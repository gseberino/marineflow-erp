// Edge Function: fiscal-emit
// Emissão de documentos fiscais via provedor ativo (Contora). Piloto: só NF-e.
// Admin-only (checado aqui além do JWT exigido pelo gateway — verify_jwt=true).
// Ações: action="create" (default) | "cancel" | "correction".
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider, readFiscalEnvironment } from "../_shared/fiscal/factory.ts";
import { applyStatusUpdate } from "../_shared/fiscal/apply-status.ts";
import { resolveIbgeCityCode } from "../_shared/fiscal/ibge.ts";
import { resolveServiceFiscal, semCodigoFiscal } from "../_shared/fiscal/service-fiscal.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import {
  buildNfeDraftPayload,
  computeCfop,
  findNatureOfOperation,
  validateNfeDraftInput,
  type BuildNfePayloadInput,
} from "../_shared/fiscal/payload-builder.ts";
import {
  resolveProductFiscal,
  type CategoryFiscalDefaults,
  type GlobalFiscalDefaults,
  type ProductFiscalInput,
} from "../_shared/fiscal/product-fiscal.ts";
// [F-NFSE-01] Builder da NFS-e — separado do da NF-e de propósito: os contratos não têm
// campo em comum, e misturá-los faria uma mudança de layout de produto mexer em serviço.
import {
  buildNfseDraftPayload,
  validateNfseDraftInput,
  type BuildNfsePayloadInput,
  type NfseStandard,
} from "../_shared/fiscal/nfse-payload-builder.ts";

// SEFAZ exige justificativa com pelo menos 15 caracteres tanto no cancelamento
// quanto na Carta de Correção Eletrônica.
const MIN_JUSTIFICATION_LENGTH = 15;
// [F-NFSE-01] Teto da justificativa de cancelamento — a doc da NFS-e define a faixa 15–255.
// A NF-e também tem limite (255), então a constante vale para as duas famílias.
const MAX_JUSTIFICATION_LENGTH = 255;
const ACTIVE_STATUSES = ["draft", "queued", "processing", "authorized"];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
async function requireAdmin(admin: any, req: Request): Promise<{ id: string } | null> {
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data: userData, error } = await admin.auth.getUser(jwt);
  if (error || !userData?.user) return null;
  const { data: profile } = await admin
    .from("app_users")
    .select("id, role, active")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (!profile || profile.role !== "admin" || profile.active === false) return null;
  return { id: profile.id };
}

/**
 * Caminho interno do agente de IA (WhatsApp/painel), alternativo ao JWT de admin.
 *
 * Só autoriza com as DUAS condições: o segredo interno (que apenas nossas edge functions
 * conhecem) e um acting_user_id que seja admin ATIVO. A confirmação humana — "sim + PIN" —
 * acontece antes, no agente, porque emitir é ação de risco alto lá.
 *
 * Trade-off assumido conscientemente: troca o portão "JWT de admin" pelo portão
 * "segredo interno + cargo revalidado + PIN a montante", que é o que torna possível emitir
 * pelo WhatsApp (onde não existe sessão de usuário).
 */
// deno-lint-ignore no-explicit-any
async function requireInternalAgentAdmin(admin: any, req: Request, body: any): Promise<{ id: string } | null> {
  const enviado = req.headers.get("x-internal-secret");
  const esperado = Deno.env.get("AI_INTERNAL_SECRET");
  if (!enviado || !esperado || enviado !== esperado) return null;

  const uid = body?.acting_user_id;
  if (!uid) return null;
  const { data: profile } = await admin
    .from("app_users")
    .select("id, role, active")
    .eq("id", uid)
    .maybeSingle();
  if (!profile || profile.role !== "admin" || profile.active === false) return null;

  console.log(`[fiscal-emit] chamada interna do agente autorizada por admin ${profile.id}`);
  return { id: profile.id };
}

/**
 * Ponte Ordem de Serviço → corpo da NF-e.
 *
 * Monta destinatário (a partir do cliente) e itens (a partir das PEÇAS da OS). A mão de
 * obra é deliberadamente SEPARADA e devolvida no resumo: NF-e é documento de produto, e
 * serviço é NFS-e — emitida pela ponte buildNfseBodyFromServiceOrder.
 *
 * SEAM PARA NFS-e: quando a NFS-e entrar, `servicos` já sai daqui pronto (descrição, qtd,
 * valor). Bastará montar o payload de serviço e emitir o segundo documento — sem mexer
 * nesta separação nem no que o agente já sabe fazer.
 */
// deno-lint-ignore no-explicit-any
async function buildBodyFromServiceOrder(admin: any, body: any): Promise<
  | { ok: true; body: Record<string, unknown>; resumo: Record<string, unknown> }
  | { ok: false; error: string; status: number }
> {
  const soId = String(body.service_order_id);
  const { data: so } = await admin
    .from("service_orders")
    .select("id, service_order_number, status, client_id, customer_po_number")
    .eq("id", soId)
    .maybeSingle();
  if (!so) return { ok: false, error: "Ordem de serviço não encontrada.", status: 404 };
  if (so.status === "cancelled") return { ok: false, error: "OS cancelada não pode gerar nota.", status: 422 };
  if (!so.client_id) return { ok: false, error: "Essa OS não tem cliente vinculado — sem destinatário não há nota.", status: 422 };

  const { data: cli } = await admin
    .from("clients")
    .select("name, cpf_cnpj, email, address_line_1, address_number, address_complement, neighborhood, city, state, postal_code, state_registration, ie_indicator")
    .eq("id", so.client_id)
    .maybeSingle();
  if (!cli) return { ok: false, error: "Cliente da OS não encontrado.", status: 404 };

  // Itens = PEÇAS com produto do catálogo (produto avulso sem cadastro não tem NCM).
  const { data: parts } = await admin
    .from("service_order_parts")
    .select("product_id, quantity, unit_sale_snapshot, products(name, sku, unit, ncm)")
    .eq("service_order_id", soId);

  const itens: Array<Record<string, unknown>> = [];
  const semProduto: string[] = [];
  for (const p of (parts as any[]) || []) {
    if (!p.product_id) {
      semProduto.push("item sem produto cadastrado");
      continue;
    }
    itens.push({
      product_id: p.product_id,
      code: p.products?.sku || "ITEM",
      name: p.products?.name || "Produto",
      unit: p.products?.unit || undefined,
      ncm: p.products?.ncm || undefined,
      quantity: Number(p.quantity) || 0,
      unit_price: Number(p.unit_sale_snapshot) || 0,
    });
  }
  if (itens.length === 0) {
    return { ok: false, error: "Essa OS não tem peças de catálogo para emitir NF-e (NF-e é documento de produto).", status: 422 };
  }

  // Mão de obra / materiais livres: NÃO entram na NF-e. Ficam prontos para a NFS-e.
  const { data: servicos } = await admin
    .from("service_order_services")
    .select("name_snapshot, quantity, unit_price_snapshot, line_total")
    .eq("service_order_id", soId);
  const listaServicos = ((servicos as any[]) || []).map((s) => ({
    descricao: s.name_snapshot,
    quantidade: Number(s.quantity) || 1,
    valor_unitario: Number(s.unit_price_snapshot) || 0,
    total: Number(s.line_total) || 0,
  }));
  const totalServicos = listaServicos.reduce((a, s) => a + s.total, 0);
  const totalPecas = itens.reduce((a, i) => a + (Number(i.quantity) || 0) * (Number(i.unit_price) || 0), 0);

  const r2 = (n: number) => Math.round(n * 100) / 100;
  return {
    ok: true,
    body: {
      origin_type: "service_order",
      origin_id: so.id,
      client_id: so.client_id,
      nature_of_operation: body.nature_of_operation ?? "venda",
      customer_po_number: body.customer_po_number ?? so.customer_po_number ?? null,
      recipient: {
        name: cli.name,
        document: cli.cpf_cnpj,
        email: cli.email,
        state_registration_indicator: cli.ie_indicator,
        state_registration: cli.state_registration,
        address: {
          street: cli.address_line_1,
          number: cli.address_number,
          complement: cli.address_complement,
          district: cli.neighborhood,
          city_name: cli.city,
          state_code: cli.state,
          postal_code: cli.postal_code,
        },
      },
      items: itens,
    },
    resumo: {
      os: so.service_order_number,
      cliente: cli.name,
      pecas_na_nota: itens.length,
      total_pecas: r2(totalPecas),
      // O que NÃO entra — o agente precisa dizer isso em voz alta ao dono.
      servicos_fora_da_nfe: listaServicos.length,
      total_servicos_fora: r2(totalServicos),
      itens_ignorados_sem_cadastro: semProduto.length,
      aviso_nfse: listaServicos.length > 0
        ? "A mão de obra NÃO entra na NF-e — ela sai na NFS-e, que o sistema também emite. Esta nota cobre só as peças."
        : null,
      servicos_para_nfse: listaServicos, // seam: pronto para a NFS-e quando existir
    },
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // O corpo é lido ANTES da autenticação porque o caminho interno (agente) precisa
  // declarar no corpo QUAL admin autorizou a operação.
  // deno-lint-ignore no-explicit-any
  const body = (await req.json().catch(() => null)) as any;
  if (!body) return jr({ error: "invalid_json" }, 400);

  // Dois caminhos de autorização:
  //  1) JWT de admin (a tela) — o de sempre.
  //  2) Chamada INTERNA do agente de IA: só passa com o AI_INTERNAL_SECRET (que apenas
  //     nossas edge functions possuem) E declarando um acting_user_id que seja admin ativo.
  //     A confirmação humana acontece ANTES, no agente: emitir é ação de risco alto, que
  //     exige o "sim + PIN" do dono. Aqui revalidamos o cargo — o PIN não viaja.
  const caller = (await requireAdmin(admin, req)) ?? (await requireInternalAgentAdmin(admin, req, body));
  if (!caller) return jr({ error: "unauthorized" }, 401);

  try {
    // [FATURAR-OS] Pré-voo CONJUNTO da OS (NFS-e + NF-e), sem emitir nada. Precisa vir ANTES
    // das pontes abaixo: elas mutam o body e retornam erro no primeiro documento com
    // problema, enquanto o pré-voo quer o retrato dos DOIS lados de uma vez.
    if (body.action === "billing_preflight") return await handleBillingPreflight(admin, body);

    // Ponte OS → payload: quando vem service_order_id e não vieram itens, montamos o
    // destinatário e os itens a partir da Ordem de Serviço (peças). Assim o agente não
    // precisa saber nada de fiscal — ele só diz "de qual OS".
    // [F-NFSE-01] Mesma ideia, outro documento: para NFS-e a ponte parte dos SERVIÇOS da OS,
    // não das peças. É a outra metade da separação que o seam `servicos_para_nfse` já
    // anunciava — peça vai na NF-e, mão de obra vai aqui.
    if (body.document_type === "nfse" && body.service_order_id && !body.service) {
      const ponte = await buildNfseBodyFromServiceOrder(admin, body);
      if (!ponte.ok) return jr({ error: ponte.error, details: ponte.details }, ponte.status);
      Object.assign(body, ponte.body);
      if (body.action === "prepare") {
        return jr({ ok: true, data: { resumo: ponte.resumo, payload_pronto: true } });
      }
      body.__resumo_os = ponte.resumo;
    }

    if (body.service_order_id && !Array.isArray(body.items)) {
      const ponte = await buildBodyFromServiceOrder(admin, body);
      if (!ponte.ok) return jr({ error: ponte.error }, ponte.status);
      Object.assign(body, ponte.body);
      if (body.action === "prepare") {
        return jr({ ok: true, data: { resumo: ponte.resumo, payload_pronto: true } });
      }
      // O resumo viaja para o preview responder "o que entrou e o que ficou de fora".
      body.__resumo_os = ponte.resumo;
    }

    // Ambiente REAL de emissão (lê o secret FISCAL_ENVIRONMENT do servidor, sem
    // chamar a Contora) — a UI usa para exibir o banner "PRODUÇÃO / nota real" e
    // evitar emissão acidental. É a fonte da verdade (o mesmo valor que handleCreate usa).
    if (body.action === "environment") {
      return jr({ ok: true, data: { environment: readFiscalEnvironment() } });
    }
    if (body.action === "cancel") return await handleCancel(admin, body);
    if (body.action === "correction") return await handleCorrection(admin, body);
    if (body.action === "diagnostics") return await handleDiagnostics();
    // [F-NFSE-01] Pré-voo: nada de emitir NFS-e antes do verde.
    if (body.action === "nfse_health") return await handleNfseHealth(admin);
    if (body.action === "enable_homolog") return await handleEnableHomolog();
    if (body.action === "artifact") return await handleArtifact(admin, body);
    if (body.action === "preview") return await handlePreview(admin, body);
    if (body.action === "homolog") return await handleHomolog(admin, body);
    // [F-NFSE-01] Serviço é NFS-e e produto é NF-e: fluxos separados porque a NFS-e não tem
    // etapa de build e usa outra numeração. O default continua NF-e — nenhum chamador
    // existente muda de comportamento.
    if (body.document_type === "nfse") return await handleCreateNfse(admin, body);
    return await handleCreate(admin, body);
  } catch (err) {
    console.error("[fiscal-emit] erro:", err);
    const message = err instanceof Error ? err.message : String(err);
    // 500 aqui = erro inesperado no servidor (não validação): é bug de verdade,
    // registrar como 'error'. `body.action` dá o contexto (create/cancel/…).
    void logEdgeError(admin, {
      context: "fiscal-emit", action: String(body?.action ?? "create"),
      message, error: err,
    });
    return jr({ error: message }, 500);
  }
});

// Lê os defaults fiscais globais de app_settings (fim da hierarquia
// produto→categoria→global). app_settings é key/value (colunas key, value) —
// mesma leitura do hook useAppSettings no front. Fallbacks seguros no resolver.
// deno-lint-ignore no-explicit-any
async function loadGlobalFiscalDefaults(admin: any): Promise<GlobalFiscalDefaults> {
  const { data } = await admin.from("app_settings").select("key, value");
  const m: Record<string, string> = {};
  for (const row of data ?? []) if (row?.key != null) m[String(row.key)] = String(row.value ?? "");
  const numOrNull = (v: string | undefined) => (v != null && v !== "" && !Number.isNaN(Number(v)) ? Number(v) : undefined);
  return {
    default_csosn: m["default_csosn"] || undefined,
    default_fiscal_origin: numOrNull(m["default_fiscal_origin"]),
    default_icms_rate: numOrNull(m["default_icms_rate"]),
    default_ipi_rate: numOrNull(m["default_ipi_rate"]),
    default_pis_rate: numOrNull(m["default_pis_rate"]),
    default_cofins_rate: numOrNull(m["default_cofins_rate"]),
    default_pis_cst: m["default_pis_cst"] || undefined,
    default_cofins_cst: m["default_cofins_cst"] || undefined,
  };
}

// Carrega em lote os produtos referenciados pelos itens (por product_id) e as
// categorias deles — para resolver os campos fiscais no servidor sem N+1.
// deno-lint-ignore no-explicit-any
async function loadItemFiscalSources(admin: any, items: Array<Record<string, unknown>>) {
  const productsById: Record<string, ProductFiscalInput & { product_category_id?: string | null }> = {};
  const categoriesById: Record<string, CategoryFiscalDefaults> = {};
  const productIds = [...new Set(items.map((it) => (it.product_id ? String(it.product_id) : "")).filter(Boolean))];
  if (!productIds.length) return { productsById, categoriesById };

  const { data: prods } = await admin
    .from("products")
    .select("id, ncm, cfop, unit, barcode, csosn, fiscal_origin, icms_rate, ipi_rate, pis_rate, cofins_rate, use_global_fiscal, product_category_id")
    .in("id", productIds);
  for (const p of prods ?? []) productsById[String(p.id)] = p;

  const catIds = [...new Set((prods ?? []).map((p: { product_category_id?: string | null }) => p.product_category_id).filter(Boolean))] as string[];
  if (catIds.length) {
    const { data: cats } = await admin
      .from("product_categories")
      .select("id, default_ncm, default_csosn, default_fiscal_origin, default_icms_rate, default_ipi_rate, default_pis_rate, default_cofins_rate")
      .in("id", catIds);
    for (const c of cats ?? []) categoriesById[String(c.id)] = c;
  }
  return { productsById, categoriesById };
}

// deno-lint-ignore no-explicit-any
async function findActiveDocument(admin: any, documentType: string, originType: string, originId: string | null, idempotencyKey: string | null) {
  let query = admin
    .from("issued_fiscal_documents")
    .select("*")
    .eq("document_type", documentType)
    .in("status", ACTIVE_STATUSES);
  query = originId
    ? query.eq("origin_type", originType).eq("origin_id", originId)
    : query.eq("idempotency_key", idempotencyKey);
  return await query.maybeSingle();
}

// Monta o payload da NF-e a partir do body: empresa emissora (+validação de UF),
// endereço/IBGE do destinatário, natureza/CFOP e impostos por item resolvidos na
// hierarquia produto→categoria→global. FONTE ÚNICA usada tanto pela emissão real
// (handleCreate) quanto pelo espelho (handlePreview) — garante que o preview seja
// idêntico ao que será emitido de fato.
// deno-lint-ignore no-explicit-any
async function prepareNfePayload(
  admin: any,
  // deno-lint-ignore no-explicit-any
  body: any,
  // deno-lint-ignore no-explicit-any
): Promise<{ ok: true; payload: Record<string, unknown>; company: any } | { ok: false; error: string; status: number }> {
  const { data: company, error: companyErr } = await admin
    .from("company_fiscal_settings")
    .select("*")
    .limit(1)
    .maybeSingle();
  if (companyErr) {
    return { ok: false, error: "Falha ao consultar empresa emissora: " + companyErr.message, status: 500 };
  }
  if (!company) {
    return { ok: false, error: "Empresa emissora não configurada. Preencha os dados fiscais da empresa antes de emitir.", status: 422 };
  }
  if (!company.state_code) {
    return {
      ok: false,
      error: "UF da empresa emissora não configurada. Complete a UF em 'Dados da Empresa' antes de emitir — ela define se o CFOP calculado é de operação interna ou interestadual.",
      status: 422,
    };
  }

  const addr = body.recipient?.address ?? {};
  let cityCode: string | null = addr.city_code || null;
  if (!cityCode && addr.state_code && addr.city_name) {
    cityCode = await resolveIbgeCityCode(addr.state_code, addr.city_name);
  }

  // Natureza de operação define o CFOP-base e se a nota é de saída (venda,
  // devolução ao fornecedor, remessas) ou de entrada (devolução recebida do
  // cliente) — o primeiro dígito do CFOP em si depende também de a UF do
  // destinatário coincidir ou não com a UF do emitente.
  const nature = findNatureOfOperation(body.nature_of_operation);
  const defaultItemCfop = computeCfop(nature.baseCfopCode, nature.operationType, company.state_code, addr.state_code);

  // Impostos por item são a fonte da verdade AQUI (não confiamos só no front):
  // resolvemos os campos fiscais efetivos a partir do produto → categoria →
  // defaults globais (mesma hierarquia da tela de produtos). Sem o bloco `taxes`
  // montado, a SEFAZ rejeita em produção (215).
  const globalDefaults = await loadGlobalFiscalDefaults(admin);
  const { productsById, categoriesById } = await loadItemFiscalSources(admin, body.items ?? []);

  const input: BuildNfePayloadInput = {
    natureOperation: nature.natureOperation,
    operationType: nature.operationType,
    purpose: nature.purpose,
    referencedAccessKey: body.referenced_access_key ?? null,
    presenceIndicator: body.presence_indicator != null ? Number(body.presence_indicator) : undefined,
    consumerFinal: typeof body.consumer_final === "boolean" ? body.consumer_final : undefined,
    additionalInfo: body.additional_info ?? null,
    purchaseOrder: body.customer_po_number ?? null,
    recipient: {
      name: body.recipient?.name,
      document: body.recipient?.document,
      email: body.recipient?.email,
      stateRegistrationIndicator: body.recipient?.state_registration_indicator != null
        ? Number(body.recipient.state_registration_indicator)
        : undefined,
      stateRegistration: body.recipient?.state_registration ?? null,
      address: {
        street: addr.street,
        number: addr.number,
        complement: addr.complement,
        district: addr.district,
        cityName: addr.city_name,
        cityCode: cityCode || "",
        stateCode: addr.state_code,
        postalCode: addr.postal_code,
      },
    },
    items: (body.items ?? []).map((it: Record<string, unknown>) => {
      const productId = it.product_id ? String(it.product_id) : null;
      const product = productId ? productsById[productId] : null;
      const category = product?.product_category_id ? categoriesById[String(product.product_category_id)] : null;
      const rf = resolveProductFiscal(product, category, globalDefaults);
      // Valor explícito enviado pelo front (usuário pode editar) tem precedência;
      // senão cai no resolvido (produto→categoria→global).
      const num = (v: unknown, fb: number) => (v != null && v !== "" && !Number.isNaN(Number(v)) ? Number(v) : fb);
      // deno-lint-ignore no-explicit-any
      const productBarcode = (product as any)?.barcode as string | undefined;
      return {
        code: String(it.code ?? it.sku ?? "ITEM"),
        name: String(it.name ?? ""),
        ncm: String(it.ncm ?? rf.ncm ?? ""),
        cfop: it.cfop ? String(it.cfop) : defaultItemCfop,
        unit: it.unit ? String(it.unit) : undefined,
        quantity: Number(it.quantity),
        unitPrice: Number(it.unit_price),
        discount: it.discount != null && it.discount !== "" ? Number(it.discount) : 0,
        otherExpenses: it.other_expenses != null && it.other_expenses !== "" ? Number(it.other_expenses) : 0,
        // IPI devolvido (devolução) → returned_ipi (impostoDevol/vIPIDevol).
        returnedIpi: (() => {
          const r = it.returned_ipi as { value?: unknown; percentage?: unknown } | null | undefined;
          const v = r && r.value != null && r.value !== "" ? Number(r.value) : 0;
          if (!(v > 0)) return null;
          const out: { value: number; percentage?: number } = { value: v };
          if (r?.percentage != null && r.percentage !== "" && !Number.isNaN(Number(r.percentage))) {
            out.percentage = Number(r.percentage);
          }
          return out;
        })(),
        barcode: it.barcode ? String(it.barcode) : (productBarcode ?? null),
        csosn: it.csosn ? String(it.csosn) : rf.csosn,
        origin: num(it.origin, rf.origin),
        icmsRate: num(it.icms_rate, rf.icmsRate),
        pisCst: it.pis_cst ? String(it.pis_cst) : rf.pisCst,
        pisRate: num(it.pis_rate, rf.pisRate),
        cofinsCst: it.cofins_cst ? String(it.cofins_cst) : rf.cofinsCst,
        cofinsRate: num(it.cofins_rate, rf.cofinsRate),
        ipiRate: num(it.ipi_rate, rf.ipiRate),
        // Referência por item à NF-e original (devolução, VC02-14).
        referencedKey: it.referenced_key ? String(it.referenced_key) : null,
        referencedItemNumber: it.referenced_item != null ? Number(it.referenced_item) : null,
      };
    }),
    paymentMethod: body.payment_method || "01",
    // Devolução e remessas não têm pagamento (tPag=90). Só "venda" tem transação.
    noPayment: !nature.hasPayment,
    // Venda a prazo (payment_terms.mode === "parcelado") → duplicatas do grupo
    // cobr. À vista / sem pagamento → sem duplicatas (pagamento único).
    installments: (() => {
      const pt = body.payment_terms;
      if (!nature.hasPayment || !pt || pt.mode !== "parcelado" || !Array.isArray(pt.installments)) return null;
      return pt.installments
        .filter((p: Record<string, unknown>) => p && p.due_date && Number(p.amount) > 0)
        .map((p: Record<string, unknown>) => ({ dueDate: String(p.due_date), amount: Number(p.amount) }));
    })(),
  };

  const errors = validateNfeDraftInput(input);
  if (errors.length) return { ok: false, error: errors.join(" "), status: 422 };

  return { ok: true, payload: buildNfeDraftPayload(input), company };
}

// Espelho (pré-visualização / pré-DANFE): devolve o MESMO payload da emissão
// real (impostos por item e CFOP já resolvidos no servidor) + os dados do
// emitente, em JSON, para o cliente RENDERIZAR o espelho "SEM VALOR FISCAL".
//
// NÃO chama a SEFAZ/Contora: a DANFE em PDF da Contora só existe depois do
// dispatch (precisa do protocolo de autorização), então um `build` sem dispatch
// devolve um pdf_danfe vazio — daí o "falha ao carregar PDF". O padrão dos ERPs
// (Omie "Pré-DANFE", Conta Azul, NF-Easy) é justamente renderizar a pré-nota a
// partir dos dados, sem tocar na SEFAZ. Assim: sem número consumido, sem cota,
// e funciona em produção (fim do erro de ambiente da chave).
// deno-lint-ignore no-explicit-any
async function handlePreview(admin: any, body: any): Promise<Response> {
  const prep = await prepareNfePayload(admin, body);
  if (!prep.ok) return jr({ error: prep.error }, prep.status);

  const c = prep.company ?? {};
  const emitter = {
    legal_name: c.legal_name ?? null,
    trade_name: c.trade_name ?? null,
    cnpj: c.cnpj ?? null,
    state_registration: c.state_registration ?? null,
    tax_regime: c.tax_regime ?? null,
    crt: c.crt ?? null,
    street: c.street ?? null,
    number: c.number ?? null,
    complement: c.complement ?? null,
    district: c.district ?? null,
    city_name: c.city_name ?? null,
    state_code: c.state_code ?? null,
    postal_code: c.postal_code ?? null,
  };
  // Número PREVISTO (peek): lemos o próximo da sequência SEM consumir. Reservar
  // já no espelho criaria LACUNA na numeração toda vez que uma pré-visualização
  // fosse abandonada — e lacuna exige inutilização de numeração junto à SEFAZ.
  // A reserva de verdade acontece só no handleCreate, na emissão.
  const environment = readFiscalEnvironment();
  const series = environment === "producao" ? (Number(c.nfe_series_producao ?? 1) || 1) : 2;
  const { data: seqRow, error: seqErr } = await admin
    .from("fiscal_document_sequences")
    .select("last_number")
    .eq("document_type", "nfe")
    .eq("series", series)
    .eq("environment", environment)
    .maybeSingle();
  if (seqErr) return jr({ error: "Falha ao consultar a numeração: " + seqErr.message }, 500);
  const number = (Number(seqRow?.last_number ?? 0) || 0) + 1;

  // resumo_os: presente quando o espelho veio de uma OS (o que entrou e o que ficou de fora).
  return jr({ ok: true, payload: prep.payload, emitter, environment, series, number, resumo_os: body.__resumo_os ?? null });
}

// Frase EXIGIDA pela SEFAZ no destinatário de qualquer NF-e de homologação
// (Rejeição 598 / NT 2011/002). Sem ela a nota de teste é rejeitada.
const HOMOLOG_DEST = "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL";

// A empresa da HBR está cadastrada em PRODUÇÃO na Contora, e a chave/empresa da
// Contora só opera no ambiente em que a empresa está cadastrada — logo ela RECUSA
// homologação com "a chave API não permite emissão neste ambiente". Detectamos
// essa recusa específica para o front cair no espelho local (em vez de dar erro),
// e para o botão passar a emitir de verdade sozinho SE a Contora habilitar
// homologação para o CNPJ no futuro.
function isHomologUnavailable(err: string): boolean {
  const e = (err || "").toLowerCase();
  return e.includes("ambiente") && (e.includes("permite") || e.includes("chave"));
}

// bytes → base64 em blocos (não estoura a pilha em PDFs grandes).
function bytesToBase64(buf: ArrayBuffer | Uint8Array): string {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

// Espelho REAL: emite a nota DE VERDADE em homologação (draft → build → dispatch
// → SEFAZ) e devolve a DANFE autorizada. Diferente do preview (que só simula), a
// SEFAZ valida imposto/estrutura — pega rejeição ANTES da emissão de produção.
// Só o nome do destinatário é mascarado (exigência da SEFAZ); valores, itens e
// impostos são reais. Numeração de homologação (série 2) é sequência separada.
// deno-lint-ignore no-explicit-any
async function handleHomolog(admin: any, body: any): Promise<Response> {
  const prep = await prepareNfePayload(admin, body);
  if (!prep.ok) return jr({ error: prep.error }, prep.status);

  const payload: Record<string, unknown> = { ...prep.payload };
  const rec = { ...(payload.recipient as Record<string, unknown>) };
  rec.name = HOMOLOG_DEST; // Rejeição 598
  payload.recipient = rec;

  const { data: number, error: seqErr } = await admin.rpc("next_fiscal_number", {
    p_document_type: "nfe", p_series: 2, p_environment: "homologacao",
  });
  if (seqErr) return jr({ error: "Falha ao reservar numeração de homologação: " + seqErr.message }, 500);

  const provider = createFiscalProvider();
  // Rota POR-EMPRESA é obrigatória para homologação: o allows_homologation é um
  // flag por empresa, e a rota GLOBAL (/nfe/drafts) valida o ambiente do TOKEN
  // (producao) e recusa. A rota /companies/{id}/nfe/drafts dá o contexto explícito
  // da empresa, onde o flag é respeitado. Resolve o id da empresa que o token usa.
  let companyId: string | undefined;
  const companies = await provider.listCompanies();
  if (companies.ok && companies.data[0]?.id) companyId = companies.data[0].id;
  if (!companyId) {
    return jr({ error: "Homologação: não consegui identificar a empresa na Contora (GET /companies não retornou id)." }, 502);
  }

  const created = await provider.createDraft({
    documentType: "nfe", environment: "homologacao", series: 2, number, payload, companyId,
  });
  if (!created.ok) {
    // Registra o erro CRU da Contora (diagnóstico do espelho de homologação) —
    // fica consultável em app_error_logs para entender por que caiu no fallback.
    void logEdgeError(admin, {
      context: "fiscal-emit", action: "homolog", level: "warn",
      message: "Homologação: createDraft recusado — " + created.error,
      details: { environment: "homologacao", provider_error: created.error, provider_details: created.details, classified_unavailable: isHomologUnavailable(created.error) },
    });
    // Conta sem homologação: sinaliza ao front para usar o espelho local (200,
    // não 422 — não é erro do usuário; é a conta Contora sem homologação).
    if (isHomologUnavailable(created.error)) {
      return jr({ homolog_unavailable: true, reason: created.error }, 200);
    }
    return jr({ error: "Homologação: falha ao criar o rascunho — " + didaticize(created.error), details: created.details }, 422);
  }
  const id = created.data.providerDocumentId;
  if (!id) return jr({ error: "Homologação: a Contora não retornou o identificador do rascunho." }, 502);

  const built = await provider.build("nfe", id, true, companyId);
  if (!built.ok) return jr({ error: "Homologação: falha no build — " + didaticize(built.error), details: built.details }, 422);

  const disp = await provider.dispatch("nfe", id, "authorize", companyId);
  if (!disp.ok) return jr({ error: "Homologação: falha ao enviar à SEFAZ — " + didaticize(disp.error), details: disp.details }, 422);

  // A autorização da SEFAZ é assíncrona — aguarda até ~24s (12 × 2s).
  let status = "processing", msg = "", code = "";
  for (let i = 0; i < 12; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    const st = await provider.getStatus("nfe", id, companyId);
    if (st.ok) {
      status = String(st.data.status ?? "processing");
      msg = String(st.data.statusMessage ?? "");
      code = String(st.data.statusCode ?? "");
      if (["authorized", "rejected", "failed", "cancelled"].includes(status)) break;
    }
  }

  if (status !== "authorized") {
    const detalhe = msg || (code ? `código ${code}` : status);
    // Registra a recusa do SEFAZ (cStat + motivo + fatos do payload) para
    // diagnóstico posterior sem precisar reproduzir.
    void logEdgeError(admin, {
      context: "fiscal-emit", action: "homolog", level: "warn",
      message: `Homologação: SEFAZ ${status} (${code}) — ${msg}`,
      details: {
        status, code, msg,
        purpose: (payload as Record<string, unknown>).purpose,
        first_cfop: ((payload as Record<string, unknown>).items as Array<Record<string, unknown>> | undefined)?.[0]?.cfop ?? null,
      },
    });
    // Rejeição 321 na DEVOLUÇÃO: a SEFAZ Virtual do RS (SVRS, que autoriza SC/ES)
    // NÃO mantém a nota referenciada na base de validação em HOMOLOGAÇÃO — então
    // recusa mesmo com o refNFe correto no XML (confirmado: o grupo NFref é gerado
    // e assinado). Em PRODUÇÃO a referência existe na base real e é aceita. Aqui o
    // espelho não consegue validar de verdade → cai no espelho LOCAL com a explicação.
    if (code === "321") {
      return jr({
        homolog_unavailable: true,
        reason: "A homologação da SVRS (SEFAZ que atende SC/ES) não valida devolução com nota referenciada — é uma limitação do ambiente de TESTE, não da sua nota. A referência à nota original está correta no XML; em PRODUÇÃO a devolução é aceita normalmente.",
      }, 200);
    }
    return jr({
      error: status === "processing"
        ? "A SEFAZ de homologação ainda está processando. Tente gerar o espelho de novo em instantes."
        : `A SEFAZ de homologação NÃO autorizou a nota: ${detalhe}. Corrija antes de emitir em produção.`,
      status_code: code, status_result: status,
    }, 422);
  }

  const arts = await provider.listArtifacts("nfe", id, companyId);
  const pick = arts.ok
    ? (arts.data.find((a) => a.type === "pdf_danfe" && a.available && a.downloadUrl)
      ?? arts.data.find((a) => a.type === "xml_authorized" && a.available && a.downloadUrl))
    : undefined;
  if (!pick?.downloadUrl) {
    return jr({ error: "Nota autorizada em homologação, mas a DANFE ainda não ficou pronta. Tente de novo em instantes." }, 502);
  }
  const fetched = await provider.fetchArtifact(pick.downloadUrl);
  if (!fetched.ok) return jr({ error: "Falha ao baixar a DANFE de homologação: " + fetched.error }, 502);

  // Devolve JSON com o NÚMERO + a DANFE em base64 (não um Blob cru): o front
  // precisa do número/série da homologação para nomear o arquivo de forma
  // padronizada (o supabase-js não expõe headers da resposta do invoke).
  const isPdf = pick.type === "pdf_danfe";
  return jr({
    ok: true,
    number,
    series: 2,
    environment: "homologacao",
    is_pdf: isPdf,
    danfe_base64: bytesToBase64(fetched.data.bytes),
  }, 200);
}

// deno-lint-ignore no-explicit-any
/**
 * [F-NFSE-01] Ponte Ordem de Serviço → corpo da NFS-e.
 *
 * A outra metade da separação que o seam `servicos_para_nfse` já anunciava: peça vai na
 * NF-e, mão de obra vem para cá. Monta o tomador a partir do cliente e o serviço a partir
 * das linhas de SERVIÇO da OS (`service_order_services`), nunca das peças.
 *
 * A CONSOLIDAÇÃO, E POR QUE ELA PODE SE RECUSAR A ACONTECER
 * O contrato da NFS-e tem UM objeto `service`, não uma lista. Uma OS com cinco linhas de
 * mão de obra vira UMA nota, com a descrição juntando as linhas e o valor somado. Isso é
 * fiel enquanto todas as linhas forem do mesmo código de tributação.
 *
 * Quando os códigos divergem, esta função PARA e explica. Escolher um dos códigos seria
 * declarar à prefeitura um serviço que não foi o prestado, e o erro sobreviveria à nota:
 * ninguém confere código de tributação depois de autorizado. Uma nota por código é a saída,
 * e quem decide isso é a pessoa, não o sistema.
 */
// deno-lint-ignore no-explicit-any
async function buildNfseBodyFromServiceOrder(admin: any, body: any): Promise<
  | { ok: true; body: Record<string, unknown>; resumo: Record<string, unknown> }
  | { ok: false; error: string; status: number; details?: unknown }
> {
  const soId = String(body.service_order_id);
  const { data: so } = await admin
    .from("service_orders")
    .select("id, service_order_number, status, client_id")
    .eq("id", soId)
    .maybeSingle();
  if (!so) return { ok: false, error: "Ordem de serviço não encontrada.", status: 404 };
  if (so.status === "cancelled") {
    return { ok: false, error: "OS cancelada não pode gerar nota.", status: 422 };
  }
  if (!so.client_id) {
    return { ok: false, error: "Essa OS não tem cliente vinculado — sem tomador não há NFS-e.", status: 422 };
  }

  const { data: cli } = await admin
    .from("clients")
    .select("name, cpf_cnpj, email, address_line_1, address_number, address_complement, neighborhood, city, state, postal_code")
    .eq("id", so.client_id)
    .maybeSingle();
  if (!cli) return { ok: false, error: "Cliente da OS não encontrado.", status: 404 };

  // Linhas de serviço COM o cadastro fiscal junto — é dele que saem código, CNAE e alíquota.
  // O verbo fiscal vem embutido porque o cadastro do serviço pode estar vazio e ainda assim
  // haver código: quem responde é o EFETIVO (próprio → verbo), não a coluna do serviço.
  const { data: linhas, error: linhasErr } = await admin
    .from("service_order_services")
    .select(
      "name_snapshot, description_snapshot, quantity, unit_price_snapshot, line_total, "
      + "services(national_tax_code, service_code, cnae, iss_rate, iss_withheld, fiscal_verb, "
      + "service_fiscal_verbs(default_national_tax_code, default_service_code, default_cnae, "
      + "default_iss_rate, default_iss_withheld))",
    )
    .eq("service_order_id", soId);
  // Sem esta checagem, um 400 do PostgREST (ex.: embed em tabela que não existe no schema
  // cache) viraria `linhas = null` → "OS sem linhas de serviço", um diagnóstico FALSO que já
  // aconteceu quando a migration dos verbos fiscais ainda não tinha sido aplicada.
  if (linhasErr) {
    return {
      ok: false,
      status: 500,
      error: "Falha ao consultar as linhas de serviço da OS: " + linhasErr.message,
    };
  }

  const lista = ((linhas as any[]) || []).filter((l) => Number(l.line_total) > 0);
  if (lista.length === 0) {
    return {
      ok: false,
      status: 422,
      error: "Essa OS não tem linhas de serviço com valor — a NFS-e é documento de serviço. "
        + "Se o que há são peças, o documento é a NF-e.",
    };
  }

  // Resolve o fiscal EFETIVO de cada linha antes de qualquer decisão. Sem isto, um serviço que
  // herda o código do verbo seria acusado de "sem cadastro fiscal" e a emissão pararia — a
  // herança existiria no banco e não valeria nada na hora que importa.
  const resolvidas = lista.map((l) => ({
    linha: l,
    fiscal: resolveServiceFiscal(l.services ?? null, l.services?.service_fiscal_verbs ?? null),
  }));

  // Sem cadastro fiscal não há nota. Dizer QUAIS faltam evita a caça ao serviço errado.
  const semCadastro = resolvidas
    .filter((r) => semCodigoFiscal(r.fiscal))
    .map((r) => r.linha);
  if (semCadastro.length > 0) {
    return {
      ok: false,
      status: 422,
      error: "Serviço sem cadastro fiscal: "
        + semCadastro.map((l) => `"${l.name_snapshot}"`).join(", ")
        + ". Preencha o código de tributação nacional (6 dígitos), o CNAE e a alíquota de ISS "
        + "no cadastro do serviço — ou no verbo fiscal dele, em Configurações → Fiscal → "
        + "Verbos, que vale para todos os serviços daquela atividade — antes de emitir.",
      details: { servicos_sem_cadastro: semCadastro.map((l) => l.name_snapshot) },
    };
  }

  const codigos = [...new Set(resolvidas.map((r) => String(r.fiscal.nationalTaxCode)))];
  if (codigos.length > 1) {
    return {
      ok: false,
      status: 422,
      error: `Esta OS tem serviços de códigos de tributação diferentes (${codigos.join(", ")}). `
        + "A NFS-e declara UM código por nota, então não dá para juntar tudo numa só — "
        + "escolher um deles declararia à prefeitura um serviço que não foi o prestado. "
        + "Emita uma nota por código, selecionando os serviços de cada uma.",
      details: { codigos_encontrados: codigos },
    };
  }

  const fiscal = resolvidas[0].fiscal;
  const total = lista.reduce((a, l) => a + (Number(l.line_total) || 0), 0);

  // Descrição: uma linha por serviço, com quantidade quando maior que 1. A prefeitura e o
  // cliente leem isto — "Serviços diversos" não serve a nenhum dos dois.
  const descricao = lista
    .map((l) => {
      const q = Number(l.quantity) || 1;
      const nome = l.name_snapshot || l.description_snapshot || "Serviço";
      return q > 1 ? `${nome} (${q}x)` : nome;
    })
    .join("; ")
    .slice(0, 500);

  const r2 = (n: number) => Math.round(n * 100) / 100;

  return {
    ok: true,
    body: {
      client_id: so.client_id,
      origin_type: "service_order",
      origin_id: so.id,
      service: {
        description: descricao,
        national_tax_code: fiscal.nationalTaxCode,
        service_code: fiscal.serviceCode ?? null,
        cnae: fiscal.cnae ?? null,
        iss_rate: fiscal.issRate ?? null,
        iss_withheld: fiscal.issWithheld,
      },
      taker: {
        name: cli.name,
        document: cli.cpf_cnpj,
        email: cli.email,
        address: {
          street: cli.address_line_1,
          number: cli.address_number,
          complement: cli.address_complement,
          district: cli.neighborhood,
          city_name: cli.city,
          state_code: cli.state,
          postal_code: cli.postal_code,
        },
      },
      amounts: { service_amount: r2(total) },
    },
    resumo: {
      os: so.service_order_number,
      cliente: cli.name,
      servicos_na_nota: lista.length,
      total_servicos: r2(total),
      codigo_de_tributacao: fiscal.nationalTaxCode,
      cnae: fiscal.cnae,
      iss_rate: fiscal.issRate,
      // De onde saiu o código: cadastro do serviço ou herdado do verbo. Quem confere a nota
      // antes de emitir precisa saber se está olhando um cadastro específico ou o padrão da
      // atividade — são responsabilidades diferentes se o código estiver errado.
      origem_do_codigo: fiscal.codeSource,
      // Simétrico ao aviso da NF-e: quem emite precisa saber o que NÃO entrou.
      aviso_nfe: "As peças da OS não entram na NFS-e — elas são NF-e, documento de produto.",
    },
  };
}

/**
 * [FATURAR-OS] Pré-voo conjunto da OS: o retrato dos DOIS documentos (NFS-e dos serviços,
 * NF-e das peças) de uma só vez, SEM emitir, SEM reservar numeração, SEM gastar cota.
 *
 * É o que alimenta o checklist do assistente "Faturar OS": para cada documento diz se ele se
 * aplica (há linhas daquele tipo com valor?), se está pronto (payload montaria e validaria?)
 * e, quando não está, QUAL é a pendência — com os mesmos textos didáticos das pontes.
 * Também devolve os documentos fiscais já emitidos desta OS, para o assistente mostrar o que
 * existe em vez de oferecer uma segunda emissão às cegas.
 *
 * Local e barato de propósito: não consulta a Contora (o verde da conta/certificado é o
 * `nfse_health`, que a tela chama separado e cacheia).
 */
// deno-lint-ignore no-explicit-any
async function handleBillingPreflight(admin: any, body: any): Promise<Response> {
  const soId = body.service_order_id ? String(body.service_order_id) : null;
  if (!soId) return jr({ error: "service_order_id é obrigatório" }, 422);

  const { data: so, error: soErr } = await admin
    .from("service_orders")
    .select("id, service_order_number, status, client_id, invoicing_status, grand_total")
    .eq("id", soId)
    .maybeSingle();
  if (soErr) return jr({ error: "Falha ao consultar a OS: " + soErr.message }, 500);
  if (!so) return jr({ error: "Ordem de serviço não encontrada." }, 404);

  const { data: docs } = await admin
    .from("issued_fiscal_documents")
    .select("id, document_type, status, number, series, environment, status_message, created_at")
    .eq("origin_type", "service_order")
    .eq("origin_id", soId)
    .order("created_at", { ascending: false });

  // ── NFS-e (serviços) ──
  const nfse: Record<string, unknown> = { aplicavel: true, pronto: false };
  const ponteNfse = await buildNfseBodyFromServiceOrder(admin, { service_order_id: soId });
  if (!ponteNfse.ok) {
    if (ponteNfse.status === 422 && ponteNfse.error.includes("não tem linhas de serviço")) {
      nfse.aplicavel = false;
      nfse.motivo = "A OS não tem linhas de serviço com valor.";
    } else {
      nfse.erro = ponteNfse.error;
      nfse.details = ponteNfse.details ?? null;
    }
  } else {
    nfse.resumo = ponteNfse.resumo;
    const prep = await prepareNfsePayload(admin, ponteNfse.body);
    if (!prep.ok) {
      nfse.erro = prep.error;
      nfse.details = prep.details ?? null;
    } else {
      nfse.pronto = true;
    }
  }

  // ── NF-e (peças) ──
  const nfe: Record<string, unknown> = { aplicavel: true, pronto: false };
  const ponteNfe = await buildBodyFromServiceOrder(admin, { service_order_id: soId });
  if (!ponteNfe.ok) {
    if (ponteNfe.status === 422 && ponteNfe.error.includes("não tem peças")) {
      nfe.aplicavel = false;
      nfe.motivo = "A OS não tem peças de catálogo.";
    } else {
      nfe.erro = ponteNfe.error;
    }
  } else {
    nfe.resumo = ponteNfe.resumo;
    const prep = await prepareNfePayload(admin, ponteNfe.body);
    if (!prep.ok) {
      nfe.erro = prep.error;
    } else {
      nfe.pronto = true;
    }
  }

  return jr({
    ok: true,
    data: {
      os: {
        id: so.id,
        numero: so.service_order_number,
        status: so.status,
        invoicing_status: so.invoicing_status,
        grand_total: so.grand_total,
      },
      ambiente: readFiscalEnvironment(),
      nfse,
      nfe,
      documentos: docs ?? [],
    },
  });
}

/**
 * [F-NFSE-01] Monta e valida o payload da NFS-e a partir do cadastro + do corpo da chamada.
 *
 * O cadastro da empresa é a FONTE dos campos fiscais que valem para toda nota (padrão,
 * percentual do Simples, situação, inscrição municipal); o corpo traz o que muda por nota
 * (serviço, tomador, valores). Quando o corpo informa um campo que também existe no
 * cadastro, o corpo vence — é o caso do serviço com alíquota própria.
 */
// deno-lint-ignore no-explicit-any
async function prepareNfsePayload(admin: any, body: any): Promise<
  | { ok: true; payload: Record<string, unknown>; company: any; series: number }
  | { ok: false; error: string; status: number; details?: unknown }
> {
  const { data: company } = await admin
    .from("company_fiscal_settings")
    .select("*")
    .maybeSingle();
  if (!company) {
    return {
      ok: false,
      status: 422,
      error: "Cadastro fiscal da empresa não encontrado. Preencha em Configurações → Fiscal "
        + "antes de emitir.",
    };
  }

  const s = body.service ?? {};
  const t = body.taker ?? {};
  const amt = body.amounts ?? {};

  // Código IBGE do tomador: resolvido a partir de UF + cidade, como na NF-e. Sem ele a
  // prefeitura não sabe de onde é o tomador, e o campo não existe no formulário de endereço.
  let cityCode = t.address?.city_code ?? null;
  if (!cityCode && t.address?.state_code && t.address?.city_name) {
    cityCode = await resolveIbgeCityCode(t.address.state_code, t.address.city_name);
  }

  const input: BuildNfsePayloadInput = {
    standard: (company.nfse_standard ?? "nacional") as NfseStandard,
    taxRegime: company.tax_regime ?? null,
    simplesNacionalOption: company.nfse_simples_nacional_option ?? null,
    municipalRegistration: company.municipal_registration ?? null,
    municipalRegistrationInCnc: company.nfse_municipal_registration_in_cnc !== false,
    service: {
      description: s.description ?? null,
      nationalTaxCode: s.national_tax_code ?? null,
      serviceCode: s.service_code ?? null,
      municipalTaxCode: s.municipal_tax_code ?? null,
      nbsCode: s.nbs_code ?? null,
      itemListCode: s.item_list_code ?? null,
      cnae: s.cnae ?? null,
      issRate: s.iss_rate ?? null,
      issWithheld: s.iss_withheld === true,
      // Percentual do Simples: o do serviço vence, mas o do cadastro é o padrão — é lá que
      // a contabilidade preenche uma vez e vale para todas as notas (E0712).
      totalTaxRateSn: s.total_tax_rate_sn ?? company.nfse_total_tax_rate_sn ?? null,
    },
    taker: {
      name: t.name ?? null,
      document: t.document ?? null,
      email: t.email ?? null,
      address: {
        street: t.address?.street ?? null,
        number: t.address?.number ?? null,
        complement: t.address?.complement ?? null,
        district: t.address?.district ?? null,
        cityCode,
        cityName: t.address?.city_name ?? null,
        stateCode: t.address?.state_code ?? null,
        postalCode: t.address?.postal_code ?? null,
      },
    },
    amounts: {
      serviceAmount: amt.service_amount ?? null,
      netAmount: amt.net_amount ?? null,
      deductions: amt.deductions ?? null,
      pisAmount: amt.pis_amount ?? null,
      cofinsAmount: amt.cofins_amount ?? null,
      inssAmount: amt.inss_amount ?? null,
      irAmount: amt.ir_amount ?? null,
      csllAmount: amt.csll_amount ?? null,
    },
  };

  // AVISO não bloqueia. O E0120 é o único que não dá para decidir daqui — só o CNC (ou a
  // própria rejeição) confirma —, e barrá-lo impediria de emitir em município que ESTÁ no
  // CNC, que é o caso comum. Ele volta no `avisos` para a tela mostrar.
  const todos = validateNfseDraftInput(input);
  const avisos = todos.filter((e) => e.startsWith("AVISO:"));
  const erros = todos.filter((e) => !e.startsWith("AVISO:"));
  if (erros.length > 0) {
    return {
      ok: false,
      status: 422,
      error: erros.join(" "),
      details: { erros, avisos },
    };
  }

  return {
    ok: true,
    company,
    series: Number(company.nfse_default_series ?? 1) || 1,
    payload: buildNfseDraftPayload(input),
  };
}

/**
 * [F-NFSE-01] Emissão de NFS-e — fluxo próprio, sem tocar no da NF-e.
 *
 * Três diferenças que impedem reaproveitar o handleCreate:
 *   1. NFS-e NÃO TEM BUILD. O dispatch é o gatilho da emissão.
 *   2. A numeração é outra série (nfse_default_series), independente da NF-e.
 *   3. Depois de um dispatch que não conclui, é preciso REFRESH antes de qualquer novo
 *      envio — a Contora reconcilia a DPS pelo RPS, e reenviar sem isso emite a mesma
 *      nota duas vezes.
 */
// deno-lint-ignore no-explicit-any
async function handleCreateNfse(admin: any, body: any): Promise<Response> {
  const documentType = "nfse";
  const environment = readFiscalEnvironment();
  const originType: string = body.origin_type ?? "manual";
  const originId: string | null = body.origin_id ?? null;
  const clientIdempotencyKey: string | null = body.idempotency_key || null;

  if (originId || clientIdempotencyKey) {
    const { data: existing, error: existingErr } = await findActiveDocument(
      admin, documentType, originType, originId, clientIdempotencyKey,
    );
    if (existingErr) {
      return jr({ error: "Falha ao checar duplicidade: " + existingErr.message }, 500);
    }
    // Documento vivo para a mesma origem: em vez de emitir outro, SINCRONIZA. É a regra da
    // Contora aplicada ao nosso lado — quem chega aqui de novo normalmente é um retry, e
    // um retry não pode virar uma segunda nota.
    if (existing) {
      if (existing.provider_document_id) {
        const provider = createFiscalProvider();
        await provider.refresh(documentType, existing.provider_document_id);
        const st = await provider.getStatus(documentType, existing.provider_document_id);
        if (st.ok) await applyStatusUpdate(admin, provider, existing, st.data);
      }
      return jr({ ok: true, data: existing, reused: true });
    }
  }

  const prep = await prepareNfsePayload(admin, body);
  if (!prep.ok) return jr({ error: prep.error, details: prep.details }, prep.status);

  const series = prep.series;
  const { data: number, error: seqErr } = await admin.rpc("next_fiscal_number", {
    p_document_type: documentType,
    p_series: series,
    p_environment: environment,
  });
  if (seqErr) {
    return jr({ error: "Falha ao reservar numeração: " + seqErr.message }, 500);
  }

  const idempotencyKey = clientIdempotencyKey || crypto.randomUUID();
  const { data: draftRow, error: insErr } = await admin
    .from("issued_fiscal_documents")
    .insert({
      document_type: documentType,
      origin_type: originType,
      origin_id: originId,
      client_id: body.client_id ?? null,
      provider: "contora",
      environment,
      series,
      number,
      status: "draft",
      idempotency_key: idempotencyKey,
      request_payload: prep.payload,
    })
    .select()
    .single();

  if (insErr) {
    if (String(insErr.code) === "23505") {
      const { data: existing } = await findActiveDocument(
        admin, documentType, originType, originId, idempotencyKey,
      );
      if (existing) return jr({ ok: true, data: existing, reused: true });
    }
    return jr({ error: "Falha ao registrar documento: " + insErr.message }, 500);
  }

  const provider = createFiscalProvider();
  const created = await provider.createDraft({
    documentType,
    environment,
    series,
    number,
    payload: prep.payload,
    // Chave ESTÁVEL derivada do nosso id: um retry de rede reaproveita o rascunho na
    // Contora em vez de criar um segundo e queimar numeração.
    idempotencyKey: `draft-nfse-${draftRow.id}`,
  });

  if (!created.ok) {
    await markFailed(admin, draftRow.id, didaticize(created.error), created.errorType, created.details);
    return jr({ error: didaticize(created.error), details: created.details }, 422);
  }
  if (!created.data.providerDocumentId) {
    const msg = "Resposta inesperada do provedor: documento criado sem identificador.";
    await markFailed(admin, draftRow.id, msg);
    return jr({ error: msg }, 502);
  }

  await admin.from("issued_fiscal_documents").update({
    provider_document_id: created.data.providerDocumentId,
    status: created.data.status,
    updated_at: new Date().toISOString(),
  }).eq("id", draftRow.id);

  // SEM BUILD. Na NFS-e o dispatch é o gatilho da emissão — chamar build aqui devolveria
  // 404, e a nota ficaria presa em draft sem motivo aparente.
  const dispatched = await provider.dispatch(documentType, created.data.providerDocumentId);

  if (!dispatched.ok) {
    // Falha TÉCNICA não é rejeição fiscal. Antes de deixar o documento como falho, sincroniza
    // com o autorizador: o dispatch pode ter chegado e só a resposta ter se perdido, e nesse
    // caso a nota existe — marcar falha aqui levaria alguém a emitir a segunda.
    await provider.refresh(documentType, created.data.providerDocumentId);
    const st = await provider.getStatus(documentType, created.data.providerDocumentId);
    if (st.ok && (st.data.status === "authorized" || st.data.status === "processing" || st.data.status === "queued")) {
      await applyStatusUpdate(admin, provider, draftRow, st.data);
      return jr({
        ok: true,
        data: { id: draftRow.id, status: st.data.status, environment },
        aviso: "O envio deu erro de comunicação, mas a nota FOI recebida pelo provedor — "
          + "situação sincronizada. Não emita de novo.",
      });
    }
    await markFailed(admin, draftRow.id, didaticize(dispatched.error), dispatched.errorType, dispatched.details);
    return jr({ error: didaticize(dispatched.error), details: dispatched.details }, 422);
  }

  await admin.from("issued_fiscal_documents").update({
    status: "queued",
    updated_at: new Date().toISOString(),
  }).eq("id", draftRow.id);

  return jr({ ok: true, data: { id: draftRow.id, status: "queued", environment } });
}

// deno-lint-ignore no-explicit-any
async function handleCreate(admin: any, body: any): Promise<Response> {
  const documentType = "nfe"; // piloto: só NF-e por ora (NFS-e fica para a Fase 3)
  const environment = readFiscalEnvironment();
  const originType: string = body.origin_type ?? "manual";
  const originId: string | null = body.origin_id ?? null;
  // Chave de idempotência: o front gera uma vez por abertura do diálogo de
  // emissão e reenvia a mesma em caso de duplo clique/retry de rede — sem
  // isso, o fluxo manual (único exposto na UI, sempre sem origin_id) não
  // tinha NENHUMA proteção contra emitir duas NF-e reais para a mesma venda.
  const clientIdempotencyKey: string | null = body.idempotency_key || null;

  if (originId || clientIdempotencyKey) {
    const { data: existing, error: existingErr } = await findActiveDocument(
      admin, documentType, originType, originId, clientIdempotencyKey,
    );
    if (existingErr) {
      return jr({ error: "Falha ao checar duplicidade: " + existingErr.message }, 500);
    }
    if (existing) return jr({ ok: true, data: existing, reused: true });
  }

  // Monta o payload (empresa + impostos por item + validação) — mesma função
  // usada pelo espelho, para o preview ser IDÊNTICO à emissão real.
  const prep = await prepareNfePayload(admin, body);
  if (!prep.ok) return jr({ error: prep.error }, prep.status);
  const { payload, company } = prep;

  // Numeração atômica. IMPORTANTE: a faixa de série 900–999 é RESERVADA pela
  // SEFAZ (contingência / NFC-e modelo 65) e gera Rejeição 244 numa NF-e normal
  // modelo 55. Por isso usamos a faixa normal (1–889) nos dois ambientes: série
  // 1 em produção e 2 em homologação (o ambiente já separa as sequências no
  // fiscal_document_sequences e na SEFAZ). Antes usávamos 900 em homologação, o
  // que a Contora vinha normalizando à força para 1 ("No-Lock Policy").
  // Série de produção é configurável (company_fiscal_settings.nfe_series_producao):
  // empresas que já emitiram em outro sistema usam uma série nova para começar a
  // numeração limpa e evitar Rejeição 539. Homologação fica sempre na série 2.
  const prodSeries = Number(company.nfe_series_producao ?? 1) || 1;
  const series = environment === "producao" ? prodSeries : 2;
  const { data: number, error: seqErr } = await admin.rpc("next_fiscal_number", {
    p_document_type: documentType,
    p_series: series,
    p_environment: environment,
  });
  if (seqErr) {
    return jr({ error: "Falha ao reservar numeração: " + seqErr.message }, 500);
  }

  // Grava o rascunho ANTES de chamar o provedor — garante rastro mesmo se a
  // chamada externa falhar, e serve de guarda contra corrida (índices únicos
  // uq_ifd_active_per_origin / uq_ifd_idempotency_key travam uma segunda
  // emissão concorrente para a mesma origem ou o mesmo envio do front).
  const idempotencyKey = clientIdempotencyKey || crypto.randomUUID();
  const { data: draftRow, error: insErr } = await admin
    .from("issued_fiscal_documents")
    .insert({
      document_type: documentType,
      origin_type: originType,
      origin_id: originId,
      client_id: body.client_id ?? null,
      provider: "contora",
      environment,
      series,
      number,
      status: "draft",
      idempotency_key: idempotencyKey,
      request_payload: payload,
      // Vínculo item→produto do catálogo (só itens com product_id), para a baixa
      // opt-in de estoque/recebível (RPC settle_nfe_stock_and_receivable). O
      // request_payload é layout SEFAZ e não guarda product_id.
      source_items: (body.items ?? [])
        .filter((it: Record<string, unknown>) => it.product_id)
        .map((it: Record<string, unknown>) => ({
          product_id: String(it.product_id),
          quantity: Number(it.quantity),
          unit_price: Number(it.unit_price),
        })),
      // Plano de pagamento escolhido na emissão (à vista/parcelado + vencimentos)
      // — reaproveitado ao gerar os recebíveis (e, futuramente, as duplicatas no XML).
      payment_terms: body.payment_terms ?? null,
      // Pedido do cliente em colunas próprias: o infCpl é texto (não dá para
      // reconstituir com segurança) — assim duplicar/reemitir restaura os campos
      // estruturados e a nota fica pesquisável pelo nº do pedido.
      customer_po_number: body.customer_po_number ?? null,
      customer_buyer_name: body.customer_buyer_name ?? null,
    })
    .select()
    .single();

  if (insErr) {
    if (String(insErr.code) === "23505") {
      const { data: existing } = await findActiveDocument(
        admin, documentType, originType, originId, idempotencyKey,
      );
      if (existing) return jr({ ok: true, data: existing, reused: true });
    }
    return jr({ error: "Falha ao registrar documento: " + insErr.message }, 500);
  }

  const provider = createFiscalProvider();
  const created = await provider.createDraft({
    documentType,
    environment,
    series,
    number,
    payload,
  });

  if (!created.ok) {
    await markFailed(admin, draftRow.id, created.error, created.errorType, created.details);
    return jr({ error: created.error, details: created.details }, 422);
  }
  if (!created.data.providerDocumentId) {
    const msg = "Resposta inesperada do provedor: documento criado sem identificador.";
    await markFailed(admin, draftRow.id, msg);
    return jr({ error: msg }, 502);
  }

  await admin.from("issued_fiscal_documents").update({
    provider_document_id: created.data.providerDocumentId,
    status: created.data.status,
    updated_at: new Date().toISOString(),
  }).eq("id", draftRow.id);

  // Build é opcional segundo a documentação da Contora ("execute o build
  // assinado se quiser revisar XML antes do envio"), mas chamamos mesmo
  // assim: não consome cota (não conta como evento fiscal) e remove qualquer
  // ambiguidade sobre a sequência exigida antes de autorizar.
  const built = await provider.build(documentType, created.data.providerDocumentId, true);
  if (!built.ok) {
    const msg = didaticize(built.error);
    await markFailed(admin, draftRow.id, msg, built.errorType, built.details);
    return jr({ error: msg, details: built.details }, 422);
  }

  const dispatched = await provider.dispatch(
    documentType,
    created.data.providerDocumentId,
    "authorize",
  );

  if (!dispatched.ok) {
    await markFailed(admin, draftRow.id, dispatched.error, dispatched.errorType, dispatched.details);
    return jr({ error: dispatched.error, details: dispatched.details }, 422);
  }

  await admin.from("issued_fiscal_documents").update({
    status: "queued",
    updated_at: new Date().toISOString(),
  }).eq("id", draftRow.id);

  return jr({ ok: true, data: { id: draftRow.id, status: "queued", environment } });
}

// Enriquece mensagens de erro cruas do provedor com orientação acionável — em
// especial o "empresa sem city_code", que NÃO se resolve neste app (a API v1 da
// Contora não expõe update de empresa): é correção no console da Contora.
function didaticize(error: string): string {
  const e = (error || "").toLowerCase();
  if (e.includes("city_code") || e.includes("código do município") || e.includes("codigo do municipio")) {
    return error +
      " — Corrija no console da Contora: Empresas → editar a empresa emissora → preencher o Município (código IBGE). " +
      "Use o botão 'Diagnóstico da conta Contora' em Dados da Empresa para confirmar.";
  }
  if (e.includes("certificate") || e.includes("certificado")) {
    return error + " — Suba/renove o certificado A1 no console da Contora (Empresas → Certificado).";
  }
  return error;
}

// Proxy autenticado de artefatos (DANFE/XML). As download_url da Contora são
// endpoints protegidos por Bearer — abrir direto no navegador dá "Bearer token
// ausente". Aqui buscamos com o token e devolvemos os bytes ao front (que está
// autenticado por JWT admin). Consultar/baixar artefato não gasta cota.
// deno-lint-ignore no-explicit-any
async function handleArtifact(admin: any, body: any): Promise<Response> {
  const documentId: string | undefined = body.document_id;
  const pediuXml = body.artifact === "xml_authorized";
  if (!documentId) return jr({ error: "document_id é obrigatório" }, 422);

  const { data: doc, error: docErr } = await admin
    .from("issued_fiscal_documents")
    .select("*")
    .eq("id", documentId)
    .maybeSingle();
  if (docErr) return jr({ error: "Falha ao consultar documento: " + docErr.message }, 500);
  if (!doc) return jr({ error: "Documento não encontrado" }, 404);
  if (!doc.provider_document_id) return jr({ error: "Documento ainda não foi enviado ao provedor" }, 422);

  const provider = createFiscalProvider();
  const artifacts = await provider.listArtifacts(doc.document_type, doc.provider_document_id);
  if (!artifacts.ok) return jr({ error: "Falha ao listar artefatos: " + artifacts.error }, 502);

  // Tipos por família (confirmado ao vivo 13/08/2026): NF-e/NFC-e = xml_authorized/
  // pdf_danfe; NFS-e = xml_nfse/pdf_nfse. Procurar só o nome da NF-e deixaria o download
  // da NFS-e sempre em 404.
  const ehNfse = doc.document_type === "nfse";
  const tiposAceitos = pediuXml
    ? (ehNfse ? ["xml_nfse", "xml_authorized"] : ["xml_authorized"])
    : (ehNfse ? ["pdf_nfse", "pdf_danfe"] : ["pdf_danfe"]);
  const kind = tiposAceitos[0];

  const art = artifacts.data.find((a) => tiposAceitos.includes(a.type) && a.available && a.downloadUrl);
  if (!art?.downloadUrl) {
    return jr({ error: `Artefato "${kind}" ainda não disponível para esta nota.` }, 404);
  }

  const fetched = await provider.fetchArtifact(art.downloadUrl);
  if (!fetched.ok) return jr({ error: "Falha ao baixar o artefato: " + fetched.error }, 502);

  const isPdf = !pediuXml;
  const contentType = isPdf ? "application/pdf" : "application/xml";
  const filename = art.filename || `${kind}-${doc.series}-${doc.number}.${isPdf ? "pdf" : "xml"}`;
  const blob = new Blob([fetched.data.bytes], { type: contentType });
  return new Response(blob, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": contentType,
      "Content-Disposition": `inline; filename="${filename}"`,
    },
  });
}

/**
 * [F-NFSE-01] Pré-voo da NFS-e — GET /companies/{id}/nfse/health.
 *
 * NADA DE EMITIR ANTES DO VERDE. A NFS-e tem dois caminhos e quem decide não é o regime da
 * empresa, é o MUNICÍPIO: onde ele aderiu ao Sistema Nacional vale o padrão nacional; onde
 * mantém layout próprio, vale o provedor municipal. Descobrir isso por tentativa e erro
 * custa numeração fiscal a cada tentativa — e em Itajaí/SC ninguém aqui sabe de antemão
 * qual dos dois está ativo.
 *
 * Read-only: não grava, não emite, não gasta cota.
 *
 * Devolve também o que o CADASTRO daqui tem, ao lado do que a Contora diz. Quando o
 * `nfse_standard` gravado divergir do caminho ativo, a tela mostra os dois e a pessoa
 * decide — em vez de o sistema "corrigir" sozinho um campo que é decisão fiscal.
 */
// deno-lint-ignore no-explicit-any
async function handleNfseHealth(admin: any): Promise<Response> {
  const provider = createFiscalProvider();

  const companies = await provider.listCompanies();
  if (!companies.ok) {
    return jr({ error: `Não deu para listar as empresas na Contora: ${companies.error}` }, 502);
  }
  const empresa = companies.data[0];
  if (!empresa?.id) {
    return jr({
      error: "Nenhuma empresa emissora cadastrada na Contora. O cadastro é feito no console "
        + "da Contora, não neste app — sem ele não há certificado nem município para emitir.",
    }, 422);
  }

  const health = await provider.nfseHealth(empresa.id);

  const { data: settings } = await admin
    .from("company_fiscal_settings")
    .select("nfse_standard, nfse_total_tax_rate_sn, nfse_simples_nacional_option, nfse_municipal_registration_in_cnc, nfse_default_series, tax_regime, municipal_registration, ibge_city_code, city_name")
    .maybeSingle();

  // Pendências que ESTE app consegue detectar sozinho, sem depender do contrato da Contora.
  // Cada uma corresponde a uma rejeição conhecida — melhor barrar aqui do que descobrir na
  // prefeitura minutos depois.
  const pendenciasLocais: string[] = [];
  const regime = String(settings?.tax_regime ?? "");
  if (regime === "simples" && settings?.nfse_total_tax_rate_sn == null) {
    pendenciasLocais.push(
      "Falta o percentual total de tributos do Simples (nfse_total_tax_rate_sn). O padrão "
      + "nacional recusa o indicador de tributos para ME/EPP e exige esse percentual — é a "
      + "rejeição E0712. Não é a alíquota de ISS: é a carga da faixa do Simples na "
      + "competência, que só a contabilidade sabe.",
    );
  }
  // LIÇÕES do incidente E0116/E0121 (13-14/08/2026, chamado Contora):
  // - A IM do prestador vem do CADASTRO da empresa na Contora, nunca do payload.
  // - O matcher do CNC é LITERAL (município+CNPJ+IM): a IM tem que estar na grafia exata
  //   do CNC — 15 posições com zeros à esquerda. "352217" ≠ "000000000352217" e a Sefin
  //   devolve E0116 dizendo que a IM "não foi informada", mesmo com a tag presente.
  const imLocal = String(settings?.municipal_registration ?? "").trim();
  if (imLocal && settings?.nfse_municipal_registration_in_cnc !== false) {
    if (imLocal !== imLocal.padStart(15, "0")) {
      pendenciasLocais.push(
        "A inscrição municipal está gravada como \"" + imLocal + "\" — o CNC NFS-e guarda o "
        + "identificador em 15 posições com zeros à esquerda (\"" + imLocal.padStart(15, "0")
        + "\") e o Ambiente Nacional compara LITERALMENTE. Grafia diferente volta como E0116 "
        + "('IM deve ser informada'), mesmo com a IM presente na DPS. Alinhe aqui e no "
        + "cadastro da empresa na Contora.",
      );
    }
    if (String(readFiscalEnvironment()) === "producao") {
      // Só até a primeira NFS-e real autorizada — depois disso o CNC de produção está
      // comprovadamente ok e o aviso viraria ruído permanente.
      const { data: jaAutorizada } = await admin
        .from("issued_fiscal_documents")
        .select("id")
        .eq("document_type", "nfse")
        .eq("environment", "producao")
        .eq("status", "authorized")
        .limit(1)
        .maybeSingle();
      if (!jaAutorizada) {
        pendenciasLocais.push(
          "AVISO: antes da PRIMEIRA NFS-e em produção, confirme com a Contora que o CNC de "
          + "produção já tem o registro complementar da HBR (em 14/08/2026 ele existia só em "
          + "homologação — a sincronização municipal entre ambientes pode atrasar). Não "
          + "desligue a flag do CNC nem mude a IM por conta própria para contornar: isso só "
          + "alterna entre E0116 e E0120.",
        );
      }
    }
  }

  return jr({
    ok: true,
    data: {
      empresa: { id: empresa.id, legal_name: empresa.legalName, document: empresa.document },
      // `pronto` exige o verde da Contora E nenhuma pendência nossa. Silêncio não é
      // autorização: se a Contora não afirmar que está pronta, não está.
      // "AVISO:" informa sem travar (mesma convenção do prepareNfsePayload) — só pendência
      // real bloqueia o pronto.
      pronto: (health.ok ? health.data.ready : false)
        && pendenciasLocais.filter((p) => !p.startsWith("AVISO:")).length === 0,
      contora: health.ok
        ? {
          ready: health.data.ready,
          standard: health.data.standard,
          city_code: health.data.cityCode,
          city_name: health.data.cityName,
          certificate_ok: health.data.certificateOk,
          certificate_valid_until: health.data.certificateValidUntil,
          pending: health.data.pending,
          raw: health.data.raw,
        }
        : { erro: health.error, retryable: health.retryable },
      cadastro: settings ?? null,
      pendencias_locais: pendenciasLocais,
      // Divergência é para a PESSOA resolver: qual padrão vale é decisão fiscal, e o
      // sistema alinhar sozinho esconderia justamente o que precisa ser conferido.
      divergencia_de_padrao: health.ok && health.data.standard && settings?.nfse_standard
          && health.data.standard !== settings.nfse_standard
        ? `A Contora diz que o caminho ativo é "${health.data.standard}", mas o cadastro daqui está como "${settings.nfse_standard}".`
        : null,
    },
  });
}

// Diagnóstico read-only da conta na Contora: token válido? empresa cadastrada
// com city_code/certificado? SEFAZ online? Não grava nada, não gasta cota.
// Serve para o usuário entender por que a emissão falha (ex.: "empresa sem
// city_code" é corrigido no console da Contora, não neste app).
async function handleDiagnostics(): Promise<Response> {
  const provider = createFiscalProvider();
  const [me, companies, sefaz] = await Promise.all([
    provider.validateToken(),
    provider.listCompanies(),
    provider.sefazStatus(),
  ]);

  const firstCompany = companies.ok ? companies.data[0] : undefined;
  const tokenName = me.ok ? (me.data.name ?? null) : null;
  const legalName = firstCompany?.legalName ?? null;
  const tradeName = firstCompany?.tradeName ?? null;
  // O verProc (versão do software emissor, máx 20) é preenchido pela Contora,
  // provavelmente a partir de um destes valores. Expor o comprimento ajuda a
  // achar qual passou de 20 caracteres — a causa do erro de schema.
  const len = (s: string | null) => (s ? s.length : 0);

  return jr({
    ok: true,
    data: {
      token_ok: me.ok,
      sefaz_ok: sefaz.ok ? sefaz.data.ok : false,
      // Candidatos ao verProc + comprimento (o que tiver > 20 é o suspeito).
      verproc_candidates: {
        token_name: tokenName,
        token_name_len: len(tokenName),
        legal_name: legalName,
        legal_name_len: len(legalName),
        trade_name: tradeName,
        trade_name_len: len(tradeName),
      },
      company: firstCompany
        ? {
          found: true,
          id: firstCompany.id ?? null,
          legal_name: legalName,
          trade_name: tradeName,
          state_code: firstCompany.stateCode ?? null,
          city_code: firstCompany.cityCode ?? null,
          has_certificate: firstCompany.hasCertificate ?? false,
          certificate_valid_until: firstCompany.certificateValidUntil ?? null,
          default_environment: firstCompany.defaultEnvironment ?? null,
          // Verdade da API (não do painel): a empresa aceita espelho de
          // homologação? undefined = a Contora não retornou o campo nesta conta.
          allows_homologation: (firstCompany.raw as Record<string, unknown> | undefined)?.["allows_homologation"] ?? null,
        }
        : { found: false },
      message: !companies.ok
        ? ("Falha ao consultar empresas na Contora: " + companies.error)
        : undefined,
    },
  });
}

// Liga allows_homologation PELA API (com o token) na(s) empresa(s) da conta —
// garante que o flag vá para a empresa EXATA que o token resolve, sem depender do
// toggle do painel. Necessário quando o painel foi ligado mas a API ainda recusa
// homologação ("A chave de API não permite operações neste ambiente").
async function handleEnableHomolog(): Promise<Response> {
  const provider = createFiscalProvider();
  const companies = await provider.listCompanies();
  if (!companies.ok) return jr({ error: "Falha ao consultar empresas na Contora: " + companies.error }, 502);
  if (!companies.data.length) return jr({ error: "Nenhuma empresa encontrada na conta Contora." }, 404);

  const results: Array<Record<string, unknown>> = [];
  for (const c of companies.data) {
    const nome = c.legalName ?? c.tradeName ?? c.id ?? "?";
    if (!c.id) {
      results.push({ company: nome, ok: false, error: "empresa sem id na resposta da Contora" });
      continue;
    }
    const before = (c.raw as Record<string, unknown> | undefined)?.["allows_homologation"] ?? null;
    // deno-lint-ignore no-explicit-any
    const res = await (provider as any).setAllowsHomologation(c.id, true) as
      { ok: true; data: { allows_homologation: boolean } } | { ok: false; error: string };
    results.push({
      company: nome,
      id: c.id,
      before,
      ok: res.ok,
      after: res.ok ? res.data.allows_homologation : null,
      error: res.ok ? null : res.error,
    });
  }
  const anyOk = results.some((r) => r.ok === true);
  return jr({ ok: anyOk, results });
}

// deno-lint-ignore no-explicit-any
async function markFailed(
  admin: any,
  documentId: string,
  error: string,
  errorType?: string,
  details?: unknown,
): Promise<void> {
  await admin.from("issued_fiscal_documents").update({
    status: "failed",
    status_message: error,
    provider_status: { error, error_type: errorType, details },
    updated_at: new Date().toISOString(),
  }).eq("id", documentId);
}

// deno-lint-ignore no-explicit-any
async function handleCancel(admin: any, body: any): Promise<Response> {
  const documentId: string | undefined = body.document_id;
  const reason: string | undefined = body.reason;
  if (!documentId || !reason?.trim()) {
    return jr({ error: "document_id e reason são obrigatórios" }, 422);
  }
  if (reason.trim().length < MIN_JUSTIFICATION_LENGTH) {
    return jr({ error: `O motivo do cancelamento precisa ter pelo menos ${MIN_JUSTIFICATION_LENGTH} caracteres.` }, 422);
  }
  // [F-NFSE-01] A NFS-e tem TETO, não só piso: a justificativa vai de 15 a 255 caracteres.
  // Sem este corte, um motivo longo só seria recusado pelo provedor — depois de a pessoa
  // ter escrito o texto inteiro e apertado o botão.
  if (reason.trim().length > MAX_JUSTIFICATION_LENGTH) {
    return jr({
      error: `O motivo do cancelamento pode ter no máximo ${MAX_JUSTIFICATION_LENGTH} `
        + `caracteres (o seu tem ${reason.trim().length}).`,
    }, 422);
  }

  const { data: doc, error: docErr } = await admin
    .from("issued_fiscal_documents")
    .select("*")
    .eq("id", documentId)
    .maybeSingle();
  if (docErr) return jr({ error: "Falha ao consultar documento: " + docErr.message }, 500);
  if (!doc) return jr({ error: "Documento não encontrado" }, 404);
  if (!doc.provider_document_id) {
    return jr({ error: "Documento ainda não foi enviado ao provedor" }, 422);
  }
  if (doc.status !== "authorized") {
    return jr({ error: `Só é possível cancelar um documento autorizado (status atual: ${doc.status}).` }, 422);
  }

  const provider = createFiscalProvider();
  const result = await provider.cancel(doc.document_type, doc.provider_document_id, reason.trim());
  if (!result.ok) {
    // [F-NFSE-01] Nem todo município cancela por webservice. Onde não oferece, o pedido volta
    // como FISCAL-NFSE-CANCEL-UNSUPPORTED — que é REJEIÇÃO DE NEGÓCIO, não falha técnica:
    // repetir não adianta, e tratar como erro faria a tela oferecer "tentar de novo" para
    // sempre. A nota continua autorizada; o cancelamento é feito no portal da prefeitura com
    // o certificado da empresa, e depois `refresh` sincroniza.
    const bruto = `${result.errorType ?? ""} ${result.error ?? ""} ${JSON.stringify(result.details ?? "")}`;
    if (bruto.includes("FISCAL-NFSE-CANCEL-UNSUPPORTED")) {
      return jr({
        ok: false,
        cancel_unsupported: true,
        error: "A prefeitura deste município não oferece cancelamento de NFS-e por sistema. "
          + "A nota continua AUTORIZADA. O cancelamento precisa ser feito no portal da "
          + "prefeitura, com o certificado digital da empresa — depois disso, use "
          + "\"Atualizar status\" aqui para sincronizar. Repetir este botão não vai adiantar.",
        details: result.details,
      }, 422);
    }
    return jr({ error: result.error, details: result.details }, 422);
  }

  // Cancelamento também é assíncrono, mas homologa em segundos. Marca
  // 'processing' e faz um curto polling para refletir "cancelada" na hora — o
  // cancelamento vive num grupo separado na Contora, então o getStatus (ajustado)
  // detecta 135/155/cancelled_at. Se não confirmar a tempo, fica 'processing' e
  // o reconcile (cron/manual "Atualizar status") fecha depois.
  await admin.from("issued_fiscal_documents").update({
    status: "processing",
    updated_at: new Date().toISOString(),
  }).eq("id", documentId);

  for (let i = 0; i < 4; i++) {
    await new Promise((r) => setTimeout(r, 1500));
    const st = await provider.getStatus(doc.document_type, doc.provider_document_id);
    if (st.ok && st.data.status === "cancelled") {
      await applyStatusUpdate(admin, provider, { ...doc, status: "processing" }, st.data);
      return jr({ ok: true, cancelled: true });
    }
  }

  return jr({ ok: true, pending: true });
}

// deno-lint-ignore no-explicit-any
async function handleCorrection(admin: any, body: any): Promise<Response> {
  const documentId: string | undefined = body.document_id;
  const text: string | undefined = body.text;
  if (!documentId || !text?.trim()) {
    return jr({ error: "document_id e text são obrigatórios" }, 422);
  }
  if (text.trim().length < MIN_JUSTIFICATION_LENGTH) {
    return jr({ error: `O texto da carta de correção precisa ter pelo menos ${MIN_JUSTIFICATION_LENGTH} caracteres.` }, 422);
  }

  const { data: doc, error: docErr } = await admin
    .from("issued_fiscal_documents")
    .select("*")
    .eq("id", documentId)
    .maybeSingle();
  if (docErr) return jr({ error: "Falha ao consultar documento: " + docErr.message }, 500);
  if (!doc) return jr({ error: "Documento não encontrado" }, 404);
  if (!doc.provider_document_id) {
    return jr({ error: "Documento ainda não foi enviado ao provedor" }, 422);
  }
  if (doc.status !== "authorized") {
    return jr({ error: `Só é possível corrigir um documento autorizado (status atual: ${doc.status}).` }, 422);
  }

  const provider = createFiscalProvider();
  const result = await provider.correct(doc.document_type, doc.provider_document_id, text.trim());
  if (!result.ok) return jr({ error: result.error, details: result.details }, 422);

  return jr({ ok: true });
}

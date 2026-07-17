// Edge Function: fiscal-emit
// Emissão de documentos fiscais via provedor ativo (Contora). Piloto: só NF-e.
// Admin-only (checado aqui além do JWT exigido pelo gateway — verify_jwt=true).
// Ações: action="create" (default) | "cancel" | "correction".
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider, readFiscalEnvironment } from "../_shared/fiscal/factory.ts";
import { resolveIbgeCityCode } from "../_shared/fiscal/ibge.ts";
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

// SEFAZ exige justificativa com pelo menos 15 caracteres tanto no cancelamento
// quanto na Carta de Correção Eletrônica.
const MIN_JUSTIFICATION_LENGTH = 15;
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const caller = await requireAdmin(admin, req);
  if (!caller) return jr({ error: "unauthorized" }, 401);

  // deno-lint-ignore no-explicit-any
  const body = (await req.json().catch(() => null)) as any;
  if (!body) return jr({ error: "invalid_json" }, 400);

  try {
    // Ambiente REAL de emissão (lê o secret FISCAL_ENVIRONMENT do servidor, sem
    // chamar a Contora) — a UI usa para exibir o banner "PRODUÇÃO / nota real" e
    // evitar emissão acidental. É a fonte da verdade (o mesmo valor que handleCreate usa).
    if (body.action === "environment") {
      return jr({ ok: true, data: { environment: readFiscalEnvironment() } });
    }
    if (body.action === "cancel") return await handleCancel(admin, body);
    if (body.action === "correction") return await handleCorrection(admin, body);
    if (body.action === "diagnostics") return await handleDiagnostics();
    if (body.action === "artifact") return await handleArtifact(admin, body);
    return await handleCreate(admin, body);
  } catch (err) {
    console.error("[fiscal-emit] erro:", err);
    const message = err instanceof Error ? err.message : String(err);
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

  const { data: company, error: companyErr } = await admin
    .from("company_fiscal_settings")
    .select("*")
    .limit(1)
    .maybeSingle();
  if (companyErr) {
    return jr({ error: "Falha ao consultar empresa emissora: " + companyErr.message }, 500);
  }
  if (!company) {
    return jr(
      { error: "Empresa emissora não configurada. Preencha os dados fiscais da empresa antes de emitir." },
      422,
    );
  }
  if (!company.state_code) {
    return jr(
      { error: "UF da empresa emissora não configurada. Complete a UF em 'Dados da Empresa' antes de emitir — ela define se o CFOP calculado é de operação interna ou interestadual." },
      422,
    );
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
  };

  const errors = validateNfeDraftInput(input);
  if (errors.length) return jr({ error: errors.join(" ") }, 422);

  const payload = buildNfeDraftPayload(input);

  // Numeração atômica. IMPORTANTE: a faixa de série 900–999 é RESERVADA pela
  // SEFAZ (contingência / NFC-e modelo 65) e gera Rejeição 244 numa NF-e normal
  // modelo 55. Por isso usamos a faixa normal (1–889) nos dois ambientes: série
  // 1 em produção e 2 em homologação (o ambiente já separa as sequências no
  // fiscal_document_sequences e na SEFAZ). Antes usávamos 900 em homologação, o
  // que a Contora vinha normalizando à força para 1 ("No-Lock Policy").
  const series = environment === "producao" ? 1 : 2;
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
  const kind: string = body.artifact === "xml_authorized" ? "xml_authorized" : "pdf_danfe";
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

  const art = artifacts.data.find((a) => a.type === kind && a.available && a.downloadUrl);
  if (!art?.downloadUrl) {
    return jr({ error: `Artefato "${kind}" ainda não disponível para esta nota.` }, 404);
  }

  const fetched = await provider.fetchArtifact(art.downloadUrl);
  if (!fetched.ok) return jr({ error: "Falha ao baixar o artefato: " + fetched.error }, 502);

  const isPdf = kind === "pdf_danfe";
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
          legal_name: legalName,
          trade_name: tradeName,
          state_code: firstCompany.stateCode ?? null,
          city_code: firstCompany.cityCode ?? null,
          has_certificate: firstCompany.hasCertificate ?? false,
          default_environment: firstCompany.defaultEnvironment ?? null,
        }
        : { found: false },
      message: !companies.ok
        ? ("Falha ao consultar empresas na Contora: " + companies.error)
        : undefined,
    },
  });
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
  if (!result.ok) return jr({ error: result.error, details: result.details }, 422);

  // Cancelamento também é assíncrono — webhook/reconcile confirmam o status final.
  await admin.from("issued_fiscal_documents").update({
    status: "processing",
    updated_at: new Date().toISOString(),
  }).eq("id", documentId);

  return jr({ ok: true });
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

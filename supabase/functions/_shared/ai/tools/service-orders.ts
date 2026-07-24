import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { dayOverloadNotice } from "./agenda.ts";

/**
 * Recalcula os totais da OS após inserir/alterar item — best-effort, não deve derrubar a
 * tool que a chama. O builder do supabase-js (.rpc()/.from()) só implementa `.then()`
 * (PromiseLike), não `.catch()`/`.finally()` como uma Promise nativa — encadear
 * `.catch()` direto nele (sem antes dar await) lança "X.catch is not a function". Bug real
 * que quebrava add_material_to_order e as demais tools desta lista (todas usavam esse
 * padrão): o INSERT já tinha sido gravado com sucesso quando o erro estourava aqui, então
 * a tool reportava falha para um item que na verdade JÁ estava na OS — levando a IA a
 * tentar de novo e duplicar a linha.
 */
async function recalcSoTotals(sb: any, soId: string | undefined | null): Promise<void> {
  if (!soId) return;
  try {
    await sb.rpc("recalc_so_totals", { so_id: soId });
  } catch {
    // Não crítico — recalcular totais é best-effort.
  }
}

// Um item de OS/orçamento vive em UMA de duas tabelas: produtos em service_order_parts,
// serviços/materiais em service_order_services. As tools de editar/remover precisam achar
// o item em qualquer das duas, por id (vindo de get_service_order) ou por descrição.
type SoItem = {
  table: "service_order_parts" | "service_order_services";
  id: string;
  label: string;
  quantity: number;
  unit_price: number;
  total: number;
  /** Só para peças (produtos) — necessário para mover estoque no editar/remover. */
  product_id?: string | null;
  unit_cost?: number;
};

async function loadSoItems(sb: any, soId: string): Promise<SoItem[]> {
  const { data: parts } = await sb
    .from("service_order_parts")
    .select("id, product_id, quantity, unit_sale_snapshot, unit_cost_snapshot, line_total_sale, products(name)")
    .eq("service_order_id", soId);
  const { data: services } = await sb
    .from("service_order_services")
    .select("id, name_snapshot, quantity, unit_price_snapshot, line_total")
    .eq("service_order_id", soId);
  const partItems: SoItem[] = (parts || []).map((p: any) => ({
    table: "service_order_parts",
    id: p.id,
    label: p.products?.name || "Produto",
    quantity: Number(p.quantity) || 0,
    unit_price: Number(p.unit_sale_snapshot) || 0,
    total: Number(p.line_total_sale) || 0,
    product_id: p.product_id ?? null,
    unit_cost: Number(p.unit_cost_snapshot) || 0,
  }));
  const svcItems: SoItem[] = (services || []).map((s: any) => ({
    table: "service_order_services",
    id: s.id,
    label: s.name_snapshot || "Serviço",
    quantity: Number(s.quantity) || 0,
    unit_price: Number(s.unit_price_snapshot) || 0,
    total: Number(s.line_total) || 0,
    product_id: null,
    unit_cost: 0,
  }));
  return [...partItems, ...svcItems];
}

// Espelha o movimento de estoque do frontend (use-service-orders.ts): baixa no add-da-peça,
// estorno no remover, ajuste no editar. `delta` = variação em products.stock_quantity
// (negativo = baixa; positivo = devolução). Só para PEÇAS (produto) — serviço/material não
// tem estoque. Segue o mesmo padrão read-then-update não-atômico da tela (sem piso em 0,
// igual ao frontend). Best-effort: não deve derrubar a tool que a chama.
export async function applyStockDelta(
  sb: any,
  productId: string | null | undefined,
  delta: number,
  soId: string,
  unitCost: number,
): Promise<void> {
  if (!productId || !delta) return;
  try {
    // Modelo de estoque v2 (flag app_settings.stock_model_v2='on'): o banco gerencia estoque
    // (reserva na OS comprometida, baixa física na conclusão). Aqui NÃO mexemos no físico —
    // senão haveria dupla contagem. Com a flag OFF, comportamento idêntico ao de hoje.
    const { data: flag } = await sb.from("app_settings").select("value").eq("key", "stock_model_v2").maybeSingle();
    if (String(flag?.value ?? "").toLowerCase() === "on") return;

    const { data: prod } = await sb.from("products").select("stock_quantity").eq("id", productId).maybeSingle();
    const current = Number(prod?.stock_quantity) || 0;
    await sb.from("products").update({ stock_quantity: current + delta }).eq("id", productId);
    await sb.from("inventory_movements").insert({
      product_id: productId,
      movement_type: delta < 0 ? "service_order_usage" : "return",
      quantity_delta: delta,
      reference_type: "service_order",
      reference_id: soId,
      unit_cost_snapshot: unitCost,
    });
  } catch (_e) {
    // Best-effort — igual ao padrão do frontend; não interrompe a tool.
  }
}

// Resolve um item por id (exato) ou por descrição (substring, case-insensitive). Retorna
// { item } quando há exatamente um; { matches } quando a descrição é ambígua (>1).
function resolveSoItem(items: SoItem[], itemId?: string, description?: string): { item?: SoItem; matches?: SoItem[] } {
  if (itemId) {
    const item = items.find((i) => i.id === itemId);
    return item ? { item } : {};
  }
  if (description) {
    const q = String(description).trim().toLowerCase();
    const matches = items.filter((i) => i.label.toLowerCase().includes(q));
    if (matches.length === 1) return { item: matches[0] };
    return { matches };
  }
  return {};
}

// Total atual (após recalc) + margem BRUTA sobre custo de peças. Serviço/mão de obra não tem
// custo registrado, então esta margem cobre só o custo de produtos — rotulada como tal.
async function soTotalsSummary(sb: any, soId: string): Promise<{ total_atual: number; custo_pecas: number; margem_bruta_pct: number | null }> {
  const { data: so } = await sb.from("service_orders").select("grand_total").eq("id", soId).maybeSingle();
  const { data: parts } = await sb.from("service_order_parts").select("line_total_cost").eq("service_order_id", soId);
  const custoPecas = (parts || []).reduce((a: number, p: any) => a + (Number(p.line_total_cost) || 0), 0);
  const grand = Number(so?.grand_total) || 0;
  const margemBrutaPct = grand > 0 ? Math.round(((grand - custoPecas) / grand) * 1000) / 10 : null;
  return { total_atual: grand, custo_pecas: Math.round(custoPecas * 100) / 100, margem_bruta_pct: margemBrutaPct };
}

// Bloqueia edição/remoção de item em OS que não deve mais mudar. Cancelada tem total
// "congelado" de propósito (ver recalc_so_totals) e faturada desincronizaria o financeiro.
async function assertEditableSo(sb: any, soId: string): Promise<{ error: string } | null> {
  const { data: so } = await sb.from("service_orders").select("status").eq("id", soId).maybeSingle();
  if (!so) return { error: "Orçamento/OS não encontrado." };
  if (so.status === "cancelled") return { error: "OS cancelada não pode ser editada." };
  if (so.status === "invoiced") return { error: "OS já faturada não pode ter itens alterados." };
  return null;
}

// Espelha QUOTE_STATUS_TRANSITIONS de src/hooks/use-service-orders.ts — ciclo de vida
// do orçamento (campo quote_status, separado do status geral da OS), válido enquanto
// converted_to_os_at é nulo.
const QUOTE_STATUS_TRANSITIONS: Record<string, string[]> = {
  draft: ["sent", "awaiting_approval", "rejected"],
  sent: ["awaiting_approval", "rejected"],
  awaiting_approval: ["approved", "rejected"],
  approved: ["awaiting_deposit", "rejected"],
  awaiting_deposit: ["rejected"],
  rejected: ["draft"],
};

const STATUS_PT_EN: Record<string, string> = {
  rascunho: "draft", orçamento: "draft", orcamento: "draft",
  aberto: "open", pendente: "pending", aprovado: "approved",
  agendado: "scheduled", "em andamento": "in_progress", "em execução": "in_progress",
  concluído: "completed", concluido: "completed",
  cancelado: "cancelled", faturado: "invoiced",
  "aguardando peças": "waiting_parts", "aguardando aprovação": "waiting_approval",
  reaberto: "reopened",
};

const STATUS_LABELS: Record<string, string> = {
  draft: "Orçamento", open: "Aberto", pending: "Pendente", approved: "Aprovado",
  scheduled: "Agendado", in_progress: "Em andamento", waiting_parts: "Aguardando peças",
  waiting_approval: "Aguardando aprovação", completed: "Concluído",
  cancelled: "Cancelado", invoiced: "Faturado", reopened: "Reaberto",
};

/**
 * Adiciona um PRODUTO (do catálogo, incl. pendente ou kit/composto) como linha de PEÇA de uma
 * OS/orçamento. Fonte ÚNICA usada por add_service_order_item e add_kit_to_order — para que a
 * regra de preço praticado e a baixa de estoque existam num lugar só.
 * Preço: unit_price explícito → último praticado a este cliente → global → catálogo.
 */
export async function adicionarPecaNaOS(
  sb: any,
  args: { service_order_id: string; product_id: string; quantity: number; unit_price?: number },
): Promise<{ ok: true; part: any; preco_unitario: number; preco_origem: string; preco_data: string | null } | { error: string }> {
  const { data: prod } = await sb
    .from("products")
    .select("cost_price, sale_price, cost_currency")
    .eq("id", args.product_id)
    .maybeSingle();
  if (!prod) return { error: "Produto não encontrado" };

  const { data: so } = await sb.from("service_orders").select("client_id").eq("id", args.service_order_id).maybeSingle();
  let precoUnit = Number(prod.sale_price) || 0;
  let precoOrigem = "catálogo";
  let precoData: string | null = null;
  const precoExplicito = args.unit_price != null && Number(args.unit_price) > 0;
  if (precoExplicito) {
    precoUnit = Number(args.unit_price);
    precoOrigem = "informado agora";
  } else {
    const { data: pr } = await sb.rpc("resolve_practiced_price", {
      p_product_id: args.product_id,
      p_client_id: so?.client_id ?? null,
    });
    const linha = Array.isArray(pr) ? pr[0] : pr;
    if (linha && linha.price != null) {
      precoUnit = Number(linha.price);
      precoOrigem = String(linha.source || "catálogo");
      precoData = linha.ref_date || null;
    }
  }

  const qty = Number(args.quantity);
  const { data, error } = await sb
    .from("service_order_parts")
    .insert({
      service_order_id: args.service_order_id,
      product_id: args.product_id,
      quantity: qty,
      unit_cost_snapshot: prod.cost_price || 0,
      unit_sale_snapshot: precoUnit,
      currency_snapshot: prod.cost_currency || "BRL",
      line_total_cost: (prod.cost_price || 0) * qty,
      line_total_sale: precoUnit * qty,
    })
    .select()
    .single();
  if (error) throw error;
  // Baixa de estoque — espelha o frontend (baixa no add-da-peça).
  await applyStockDelta(sb, args.product_id, -qty, args.service_order_id, prod.cost_price || 0);
  await recalcSoTotals(sb, args.service_order_id);
  return { ok: true, part: data, preco_unitario: precoUnit, preco_origem: precoOrigem, preco_data: precoData };
}

export const serviceOrderTools: ToolDef[] = [
  {
    name: "list_service_orders",
    description:
      "Lista orçamentos ou ordens de serviço. IMPORTANTE: orçamentos têm status='draft' (número ORÇ-XXXXX). OS têm outros status (número OS-XXXXX). Use is_quote=true para listar apenas orçamentos, is_quote=false para listar apenas OS, ou omita para listar tudo.",
    input_schema: {
      type: "object",
      properties: {
        is_quote: { type: "boolean", description: "true=apenas orçamentos (draft), false=apenas OS (non-draft), omitir=todos" },
        status: { type: "string", description: "Filtro por status específico (ex: 'approved', 'in_progress'). Ignorado se is_quote for fornecido." },
        client_id: { type: "string" },
        vessel_id: { type: "string" },
        limit: { type: "number", description: "Máximo de registros (padrão 20)" },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      let query = sb
        .from("service_orders")
        .select("id, service_order_number, status, grand_total, payment_status, scheduled_start_at, created_at, clients(name), vessels(name)")
        .order("created_at", { ascending: false })
        .limit(Math.min(Number(args.limit) || 20, 50));

      if (args.is_quote === true) {
        query = query.eq("status", "draft");
      } else if (args.is_quote === false) {
        query = query.neq("status", "draft");
      } else if (args.status) {
        const mappedStatus = STATUS_PT_EN[String(args.status).toLowerCase()] ?? args.status;
        query = query.eq("status", mappedStatus);
      }

      if (args.client_id) query = query.eq("client_id", args.client_id);
      if (args.vessel_id) query = query.eq("vessel_id", args.vessel_id);
      const { data, error } = await query;
      if (error) throw error;

      const mapped = (data || []).map((so: any) => ({
        id: so.id,
        numero: so.service_order_number,
        tipo: so.status === "draft" ? "Orçamento" : "OS",
        status: STATUS_LABELS[so.status] || so.status,
        status_raw: so.status,
        status_pagamento: so.payment_status || null,
        cliente: so.clients?.name || "—",
        ativo: so.vessels?.name || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { results: mapped };
    },
  },
  {
    name: "get_service_order",
    description: "Detalhes completos de uma OS incluindo itens e serviços.",
    input_schema: {
      type: "object",
      properties: { id: { type: "string" } },
      required: ["id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: so, error } = await sb
        .from("service_orders")
        .select("*, clients(name), vessels(name)")
        .eq("id", args.id)
        .maybeSingle();
      if (error) throw error;
      if (!so) return { error: "OS não encontrada" };
      const { data: parts } = await sb
        .from("service_order_parts")
        .select("id, quantity, line_total_sale, products(name)")
        .eq("service_order_id", args.id);
      const { data: services } = await sb
        .from("service_order_services")
        .select("id, name_snapshot, quantity, unit_price_snapshot, line_total")
        .eq("service_order_id", args.id);

      return {
        service_order: {
          ...so,
          cliente: so.clients?.name || "—",
          embarcacao: so.vessels?.name || "—",
        },
        parts: (parts || []).map((p: any) => ({
          item_id: p.id,
          tipo: "part",
          produto: p.products?.name || "Desconhecido",
          quantidade: p.quantity,
          total: p.line_total_sale,
        })),
        services: (services || []).map((s: any) => ({
          item_id: s.id,
          tipo: "service",
          servico: s.name_snapshot,
          quantidade: s.quantity,
          preco_unitario: s.unit_price_snapshot,
          total: s.line_total,
        })),
      };
    },
  },
  {
    name: "get_client_history",
    description: "Histórico de OSs de um cliente.",
    input_schema: {
      type: "object",
      properties: { client_id: { type: "string" } },
      required: ["client_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at, vessels(name)")
        .eq("client_id", args.client_id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        numero: so.service_order_number,
        status: so.status,
        embarcacao: so.vessels?.name || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { history: mapped };
    },
  },
  {
    name: "create_service_order",
    description:
      "Cria um novo orçamento (status='draft', número ORÇ-XXXXX) ou OS (outro status, número OS-XXXXX). SEMPRE pesquise o cliente e o ativo/embarcação antes de criar. Se não houver ativo cadastrado, use create_vessel primeiro (suporta Camper, Motorhome, Lancha, etc.).",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string", description: "UUID do cliente (obrigatório)" },
        vessel_id: { type: "string", description: "UUID do ativo/embarcação (obrigatório — use search_vessels ou create_vessel antes)" },
        status: { type: "string", description: "Status inicial. Use 'draft' para orçamento. Padrão: draft." },
        problem_description: { type: "string", description: "Descrição do problema ou escopo do serviço" },
        extra_notes: { type: "string", description: "Observações visíveis ao cliente no PDF (condições, ressalvas, validade)" },
        internal_notes: { type: "string", description: "Notas internas (não aparecem no PDF do cliente)" },
        scheduled_start_at: { type: "string", description: "Data/hora de início agendada (ISO)" },
        quote_validity_days: { type: "number", description: "Validade do orçamento em dias (padrão 30)" },
        payment_conditions: { type: "string", description: "Condições de pagamento (ex: '50% na aprovação, 50% na entrega')" },
        items: {
          type: "array",
          description: "Produtos do catálogo a adicionar (opcional — prefira add_service_to_order e add_material_to_order após criar)",
          items: {
            type: "object",
            properties: { product_id: { type: "string" }, quantity: { type: "number" } },
            required: ["product_id", "quantity"],
          },
        },
      },
      required: ["client_id", "vessel_id"],
    },
    risk: "low",
    async execute(args, { sb, admin, userId }) {
      const isQuote = !args.status || args.status === "draft";
      const prefix = isQuote ? "ORÇ" : "OS";
      let num: string;
      try {
        const { data: seqVal, error: seqErr } = await admin.rpc("next_document_number");
        if (seqErr || seqVal === null) throw new Error(seqErr?.message || "seq null");
        num = `${prefix}-${String(seqVal as number).padStart(5, "0")}`;
      } catch {
        num = `${prefix}-${Date.now().toString().slice(-5)}`;
      }
      const { items, ...rest } = args;
      const { data, error } = await sb
        .from("service_orders")
        .insert({ ...rest, service_order_number: num, status: rest.status || "draft", created_by: userId })
        .select()
        .single();
      if (error) throw error;

      if (Array.isArray(items) && items.length > 0) {
        const partsRows = [];
        for (const it of items) {
          const { data: prod } = await sb
            .from("products")
            .select("cost_price, sale_price, cost_currency")
            .eq("id", it.product_id)
            .maybeSingle();
          if (!prod) continue;
          partsRows.push({
            service_order_id: data.id,
            product_id: it.product_id,
            quantity: it.quantity,
            unit_cost_snapshot: prod.cost_price || 0,
            unit_sale_snapshot: prod.sale_price || 0,
            currency_snapshot: prod.cost_currency || "BRL",
            line_total_cost: (prod.cost_price || 0) * it.quantity,
            line_total_sale: (prod.sale_price || 0) * it.quantity,
          });
        }
        if (partsRows.length) {
          await sb.from("service_order_parts").insert(partsRows);
          // Baixa de estoque por peça — espelha o frontend (baixa no add).
          for (const row of partsRows) {
            await applyStockDelta(sb, row.product_id, -Number(row.quantity), data.id, row.unit_cost_snapshot);
          }
        }
      }
      await recalcSoTotals(sb, data.id);
      return { ok: true, service_order: data };
    },
  },
  {
    name: "update_service_order_status",
    description:
      "Altera o status de uma OS/orçamento. IMPORTANTE: ao aprovar um orçamento (draft → outro status), o sistema automaticamente renomeia o número de ORÇ-XXXXX para OS-XXXXX.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string", description: "UUID da OS/orçamento" },
        status: {
          type: "string",
          enum: ["draft", "open", "pending", "approved", "scheduled", "in_progress", "waiting_parts", "waiting_approval", "completed", "cancelled", "invoiced", "reopened"],
          description:
            "Novo status. 'draft'=Rascunho/Orçamento, 'open'=Aberto, 'pending'=Pendente, 'approved'=Aprovado, 'scheduled'=Agendado, 'in_progress'=Em andamento, 'waiting_parts'=Aguardando peças, 'waiting_approval'=Aguardando aprovação, 'completed'=Concluído, 'cancelled'=Cancelado, 'invoiced'=Faturado, 'reopened'=Reaberto",
        },
        cancellation_reason: { type: "string", description: "Motivo do cancelamento (quando status=cancelled)" },
      },
      required: ["id", "status"],
    },
    risk: "low",
    async execute(args, { sb, admin }) {
      const { data: current } = await sb
        .from("service_orders")
        .select("status, service_order_number")
        .eq("id", args.id)
        .maybeSingle();

      const updatePayload: Record<string, any> = { status: args.status };
      if (args.cancellation_reason) updatePayload.cancellation_reason = args.cancellation_reason;

      if (current?.status === "draft" && args.status !== "draft") {
        try {
          const { data: seqVal } = await admin.rpc("next_document_number");
          if (seqVal !== null) {
            updatePayload.service_order_number = `OS-${String(seqVal as number).padStart(5, "0")}`;
            updatePayload.converted_to_os_at = new Date().toISOString();
          }
        } catch { /* mantém número atual se RPC falhar */ }
      }

      const { data, error } = await sb.from("service_orders").update(updatePayload).eq("id", args.id).select().single();
      if (error) throw error;
      return { ok: true, service_order: data };
    },
  },
  {
    name: "add_service_order_item",
    description:
      "Adiciona um produto (do catálogo, incl. PENDENTE) a uma OS/orçamento. O preço é sugerido pelo ÚLTIMO praticado a este cliente → último praticado (global) → catálogo; a resposta diz a origem e a data. Passe unit_price só se quiser SOBREPOR essa sugestão.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        product_id: { type: "string" },
        quantity: { type: "number" },
        unit_price: { type: "number", description: "Opcional: sobrepõe o preço sugerido (praticado/catálogo)." },
      },
      required: ["service_order_id", "product_id", "quantity"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const r = await adicionarPecaNaOS(sb, {
        service_order_id: args.service_order_id,
        product_id: args.product_id,
        quantity: args.quantity,
        unit_price: args.unit_price,
      });
      if ("error" in r) return r;
      const explicito = args.unit_price != null && Number(args.unit_price) > 0;
      return {
        ...r,
        instrucao_preco: explicito
          ? null
          : `Preço sugerido de R$ ${r.preco_unitario.toFixed(2)} (${r.preco_origem}${r.preco_data ? ", " + new Date(r.preco_data).toLocaleDateString("pt-BR") : ""}). Se quiser outro valor, ajuste com edit_service_order_item.`,
      };
    },
  },
  {
    name: "add_service_to_order",
    description: "Adiciona um serviço de mão de obra a uma OS existente.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        service_name: { type: "string", description: "Nome/descrição do serviço" },
        service_id: { type: "string", description: "ID do serviço cadastrado (opcional)" },
        quantity: { type: "number", default: 1 },
        unit_price: { type: "number" },
        billing_unit: { type: "string", enum: ["hour", "visit", "day", "unit"] },
        notes: { type: "string" },
      },
      required: ["service_order_id", "service_name", "unit_price"],
    },
    risk: "low",
    async execute(args, { sb, settings }) {
      const { data: svc } = args.service_id
        ? await sb.from("services").select("name, billing_unit, default_price").eq("id", args.service_id).maybeSingle()
        : { data: null };
      const qty = Number(args.quantity) || 1;
      const defaultHourlyRate = Number(settings.default_hourly_rate) || 0;
      const price = Number(args.unit_price) || svc?.default_price || defaultHourlyRate || 0;
      const { data, error } = await sb
        .from("service_order_services")
        .insert({
          service_order_id: args.service_order_id,
          service_id: args.service_id || null,
          name_snapshot: args.service_name || svc?.name || "",
          billing_unit_snapshot: args.billing_unit || svc?.billing_unit || "visit",
          quantity: qty,
          unit_price_snapshot: price,
          line_total: qty * price,
          notes: args.notes || null,
        })
        .select()
        .single();
      if (error) throw error;
      await recalcSoTotals(sb, args.service_order_id);
      return { ok: true, service: data };
    },
  },
  {
    name: "add_material_to_order",
    description:
      "Adiciona uma linha de material/insumo de TEXTO LIVRE a uma OS (sem produto de catálogo). ATENÇÃO: esta linha aparece na seção SERVIÇOS da OS — a OS tem só duas seções, Serviços e Peças, NÃO existe uma seção 'Materiais' separada. Use para materiais ESTIMADOS em conjunto (ex.: 'R$ 4.500 em materiais elétricos'). Isto NÃO coloca o item na lista de PEÇAS/PRODUTOS — para levar um material à seção Peças, ele precisa virar produto de catálogo (create_product) e ser adicionado com add_service_order_item.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS/orçamento" },
        name: { type: "string", description: "Nome/descrição do conjunto de materiais (ex: 'Materiais e Insumos de Instalação')" },
        unit_price: { type: "number", description: "Valor total ou unitário em R$" },
        quantity: { type: "number", description: "Quantidade (padrão 1 para valor total)" },
        notes: { type: "string", description: "Detalhamento dos itens incluídos" },
      },
      required: ["service_order_id", "name", "unit_price"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const qty = Number(args.quantity) || 1;
      const price = Number(args.unit_price) || 0;
      const { data, error } = await sb
        .from("service_order_services")
        .insert({
          service_order_id: args.service_order_id,
          service_id: null,
          name_snapshot: args.name,
          billing_unit_snapshot: "unit",
          quantity: qty,
          unit_price_snapshot: price,
          line_total: qty * price,
          notes: args.notes || null,
        })
        .select()
        .single();
      if (error) throw error;
      await recalcSoTotals(sb, args.service_order_id);
      return { ok: true, material_item: data };
    },
  },
  {
    name: "remove_service_order_item",
    description:
      "Remove um item (produto OU serviço/material) de um orçamento/OS. Identifique o item por item_id (campo item_id vindo de get_service_order) ou por descrição. Se a descrição casar com vários itens, a tool retorna a lista (needs_choice) para você perguntar qual — nunca adivinhe. Recalcula total e margem. Não funciona em OS cancelada ou faturada.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento/OS" },
        item_id: { type: "string", description: "ID do item (campo item_id de get_service_order). Forma preferencial." },
        description: { type: "string", description: "Nome/descrição do item, quando não se tem o item_id." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      if (!args.item_id && !args.description) return { error: "Informe item_id ou description do item a remover." };
      const guard = await assertEditableSo(sb, args.service_order_id);
      if (guard) return guard;
      const items = await loadSoItems(sb, args.service_order_id);
      if (items.length === 0) return { error: "Este orçamento/OS não tem itens para remover." };
      const { item, matches } = resolveSoItem(items, args.item_id, args.description);
      if (!item) {
        if (matches && matches.length > 1) {
          return {
            needs_choice: true,
            message: `Encontrei ${matches.length} itens parecidos. Pergunte qual remover (passe o item_id).`,
            options: matches.map((m) => ({ item_id: m.id, descricao: m.label, quantidade: m.quantity, total: m.total })),
          };
        }
        return { error: "Item não encontrado neste orçamento/OS." };
      }
      const { error } = await sb.from(item.table).delete().eq("id", item.id).eq("service_order_id", args.service_order_id);
      if (error) throw error;
      // Estorno de estoque — espelha o frontend (devolve no remover). No-op p/ serviço (product_id nulo).
      await applyStockDelta(sb, item.product_id, item.quantity, args.service_order_id, item.unit_cost || 0);
      await recalcSoTotals(sb, args.service_order_id);
      const totais = await soTotalsSummary(sb, args.service_order_id);
      return { ok: true, removido: { descricao: item.label, quantidade: item.quantity, total: item.total }, ...totais };
    },
  },
  {
    name: "edit_service_order_item",
    description:
      "Edita a quantidade e/ou o preço unitário de um item (produto OU serviço/material) de um orçamento/OS. Identifique por item_id (de get_service_order) ou por descrição (ambígua → retorna needs_choice, pergunte qual). Recalcula total e margem. Rejeita quantidade <= 0 (para zerar, remova o item) e preço negativo. Desconto NÃO é por item: use apply_service_order_discount, que desconta no total da OS. Não funciona em OS cancelada ou faturada.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento/OS" },
        item_id: { type: "string", description: "ID do item (campo item_id de get_service_order). Forma preferencial." },
        description: { type: "string", description: "Nome/descrição do item, quando não se tem o item_id." },
        quantity: { type: "number", description: "Nova quantidade (opcional; > 0)." },
        unit_price: { type: "number", description: "Novo preço unitário em R$ (opcional; >= 0)." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      if (args.quantity == null && args.unit_price == null) return { error: "Informe ao menos quantity ou unit_price para editar." };
      if (args.quantity != null && Number(args.quantity) <= 0) return { error: "Quantidade deve ser maior que zero. Para remover o item, use remove_service_order_item." };
      if (args.unit_price != null && Number(args.unit_price) < 0) return { error: "Preço não pode ser negativo." };
      if (!args.item_id && !args.description) return { error: "Informe item_id ou description do item a editar." };
      const guard = await assertEditableSo(sb, args.service_order_id);
      if (guard) return guard;
      const items = await loadSoItems(sb, args.service_order_id);
      if (items.length === 0) return { error: "Este orçamento/OS não tem itens para editar." };
      const { item, matches } = resolveSoItem(items, args.item_id, args.description);
      if (!item) {
        if (matches && matches.length > 1) {
          return {
            needs_choice: true,
            message: `Encontrei ${matches.length} itens parecidos. Pergunte qual editar (passe o item_id).`,
            options: matches.map((m) => ({ item_id: m.id, descricao: m.label, quantidade: m.quantity, total: m.total })),
          };
        }
        return { error: "Item não encontrado neste orçamento/OS." };
      }
      const antes = { quantidade: item.quantity, preco_unitario: item.unit_price, total: item.total };
      const newQty = args.quantity != null ? Number(args.quantity) : item.quantity;
      const newPrice = args.unit_price != null ? Number(args.unit_price) : item.unit_price;

      if (item.table === "service_order_parts") {
        // Preço de custo é preservado (snapshot da compra); só recalculamos o custo da linha.
        const unitCost = Number(item.unit_cost) || 0;
        const { error } = await sb
          .from("service_order_parts")
          .update({ quantity: newQty, unit_sale_snapshot: newPrice, line_total_sale: newPrice * newQty, line_total_cost: unitCost * newQty })
          .eq("id", item.id);
        if (error) throw error;
        // Ajuste de estoque pelo delta de quantidade (old - new): +new baixa, -new devolve.
        // Espelha o frontend (mudança de qtd move estoque). Sem mudança de qtd = no-op.
        await applyStockDelta(sb, item.product_id, item.quantity - newQty, args.service_order_id, unitCost);
      } else {
        const { error } = await sb
          .from("service_order_services")
          .update({ quantity: newQty, unit_price_snapshot: newPrice, line_total: newPrice * newQty })
          .eq("id", item.id);
        if (error) throw error;
      }
      await recalcSoTotals(sb, args.service_order_id);
      const totais = await soTotalsSummary(sb, args.service_order_id);
      return {
        ok: true,
        item: item.label,
        antes,
        depois: { quantidade: newQty, preco_unitario: newPrice, total: Math.round(newPrice * newQty * 100) / 100 },
        ...totais,
      };
    },
  },
  {
    name: "schedule_service_order",
    description: "Agenda uma OS definindo data/hora de início, fim e técnico responsável.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        scheduled_start_at: { type: "string", description: "ISO datetime" },
        scheduled_end_at: { type: "string", description: "ISO datetime" },
        technician_user_id: { type: "string" },
      },
      required: ["service_order_id", "scheduled_start_at"],
    },
    risk: "low",
    async execute(args, { sb }) {
      // Conflito de agenda (tarefas + OS) via RPC única — mesma checagem da UI
      if (args.technician_user_id && args.scheduled_end_at) {
        const { data: confl } = await sb.rpc("get_agenda_conflicts", {
          p_user_id: args.technician_user_id,
          p_start: args.scheduled_start_at,
          p_end: args.scheduled_end_at,
          p_exclude_so: args.service_order_id,
        });
        if (confl && confl.length > 0) {
          return {
            conflito: true,
            mensagem: "O técnico já tem compromisso nesse horário — OS NÃO foi agendada. Proponha outro horário ou confirme com o usuário.",
            conflitos: confl.map((c: any) => ({ tipo: c.source, rotulo: c.label, inicio: c.starts_at, fim: c.ends_at })),
          };
        }
      }
      const update: any = { scheduled_start_at: args.scheduled_start_at };
      if (args.scheduled_end_at) update.scheduled_end_at = args.scheduled_end_at;
      if (args.technician_user_id) update.status = "scheduled";
      const { data, error } = await sb.from("service_orders").update(update).eq("id", args.service_order_id).select().single();
      if (error) throw error;
      if (args.technician_user_id) {
        await sb
          .from("service_order_technicians")
          .upsert({ service_order_id: args.service_order_id, user_id: args.technician_user_id }, { onConflict: "service_order_id,user_id" })
          .catch(() => null);
      }
      let aviso_carga: string | null = null;
      if (args.technician_user_id && args.scheduled_end_at) {
        aviso_carga = await dayOverloadNotice(sb, args.technician_user_id, args.scheduled_start_at, args.scheduled_end_at, { excludeSo: args.service_order_id });
      }
      return { ok: true, service_order: data, ...(aviso_carga ? { aviso_carga } : {}) };
    },
  },
  {
    name: "apply_service_order_discount",
    description: "Aplica desconto em uma OS (em valor, não percentual).",
    input_schema: {
      type: "object",
      properties: { id: { type: "string" }, discount_amount: { type: "number" } },
      required: ["id", "discount_amount"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("service_orders").update({ discount_amount: args.discount_amount }).eq("id", args.id).select().single();
      if (error) throw error;
      await recalcSoTotals(sb, args.service_order_id || args.id);
      return { ok: true, service_order: data };
    },
  },
  {
    name: "set_service_order_charges",
    description:
      "Define IMPOSTO e COMISSÃO de um orçamento/OS e recalcula o total. Use quando o usuário pedir algo como 'aplique 6% de imposto e 3% de comissão'. O imposto pode vir em % (calculado sobre o subtotal) ou em valor fixo. Recalcula e devolve o antes/depois. Não funciona em OS cancelada ou faturada.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento/OS." },
        tax_percent: { type: "number", description: "Imposto em % sobre o subtotal (ex.: 6 = 6%)." },
        tax_amount: { type: "number", description: "Imposto em R$ (alternativa ao percentual)." },
        commission_rate: { type: "number", description: "Comissão em % (ex.: 3 = 3%)." },
        commissioned_person: { type: "string", description: "Nome de quem recebe a comissão (opcional)." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const guard = await assertEditableSo(sb, args.service_order_id);
      if (guard) return guard;
      if (args.tax_percent == null && args.tax_amount == null && args.commission_rate == null) {
        return { error: "Informe ao menos tax_percent, tax_amount ou commission_rate." };
      }

      const { data: so } = await sb
        .from("service_orders")
        .select("id, service_order_number, grand_total, tax_amount, commission_rate, labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total, is_travel_billable, subcontract_cost_total, discount_amount")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (!so) return { error: "Orçamento/OS não encontrado." };

      const antes = {
        total: Number(so.grand_total) || 0,
        imposto: Number(so.tax_amount) || 0,
        comissao_pct: so.commission_rate != null ? Number(so.commission_rate) : null,
      };

      // Subtotal na MESMA fórmula do recalc_so_totals (viagem só entra se for cobrável).
      const viagem = so.is_travel_billable === false ? 0 : Number(so.travel_cost_total) || 0;
      const subtotal =
        (Number(so.labor_cost_total) || 0) + (Number(so.parts_cost_total) || 0) +
        (Number(so.operational_cost_total) || 0) + viagem + (Number(so.subcontract_cost_total) || 0);
      const baseImposto = subtotal - (Number(so.discount_amount) || 0);

      const patch: Record<string, unknown> = {};
      if (args.tax_amount != null) {
        patch.tax_amount = Math.round(Number(args.tax_amount) * 100) / 100;
      } else if (args.tax_percent != null) {
        if (Number(args.tax_percent) < 0) return { error: "Imposto não pode ser negativo." };
        patch.tax_amount = Math.round(baseImposto * (Number(args.tax_percent) / 100) * 100) / 100;
      }
      if (args.commission_rate != null) {
        if (Number(args.commission_rate) < 0) return { error: "Comissão não pode ser negativa." };
        patch.commission_rate = Number(args.commission_rate);
        // Comissão incide sobre a venda (subtotal menos desconto), não sobre o imposto.
        patch.commission_amount = Math.round(baseImposto * (Number(args.commission_rate) / 100) * 100) / 100;
      }
      if (args.commissioned_person) patch.commissioned_person = String(args.commissioned_person);

      const { error } = await sb.from("service_orders").update(patch).eq("id", so.id);
      if (error) throw error;
      await recalcSoTotals(sb, so.id);

      const { data: depois } = await sb.from("service_orders").select("grand_total, tax_amount, commission_rate, commission_amount").eq("id", so.id).maybeSingle();
      return {
        ok: true,
        os: so.service_order_number,
        antes,
        depois: {
          total: Number(depois?.grand_total) || 0,
          imposto: Number(depois?.tax_amount) || 0,
          comissao_pct: depois?.commission_rate != null ? Number(depois.commission_rate) : null,
          comissao_valor: Number(depois?.commission_amount) || 0,
        },
        base_de_calculo: Math.round(baseImposto * 100) / 100,
      };
    },
  },
  {
    name: "update_quote_status",
    description:
      "Altera o status do CICLO DE ORÇAMENTO (campo quote_status, separado do status geral da OS): draft → sent → awaiting_approval → approved → awaiting_deposit, ou rejected a qualquer momento (exceto de rejected, que só volta pra draft). Use para mover um orçamento no funil de aprovação do cliente — não confundir com update_service_order_status.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string", description: "UUID do orçamento" },
        quote_status: { type: "string", enum: ["draft", "sent", "awaiting_approval", "approved", "awaiting_deposit", "rejected"] },
      },
      required: ["id", "quote_status"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const { data: current } = await sb.from("service_orders").select("quote_status").eq("id", args.id).maybeSingle();
      const currentStatus = current?.quote_status || "draft";
      const allowed = QUOTE_STATUS_TRANSITIONS[currentStatus] || [];
      if (!allowed.includes(args.quote_status)) {
        return { error: `Transição inválida: ${currentStatus} → ${args.quote_status}. Permitidas a partir de ${currentStatus}: ${allowed.join(", ") || "nenhuma"}.` };
      }
      const { data, error } = await sb.from("service_orders").update({ quote_status: args.quote_status }).eq("id", args.id).select().single();
      if (error) throw error;
      return { ok: true, service_order: data };
    },
  },
  {
    name: "convert_external_quote_to_so",
    description: "Converte um orçamento externo (lead) em Ordem de Serviço via RPC.",
    input_schema: {
      type: "object",
      properties: { quote_id: { type: "string" } },
      required: ["quote_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.rpc("convert_external_quote_to_so", { _quote_id: args.quote_id });
      if (error) return { error: error.message };
      return { ok: true, result: data };
    },
  },
  {
    name: "cancel_service_order",
    description: "Cancela uma OS/orçamento (RPC atômica): restaura estoque de peças, cancela recebíveis e pagamentos vinculados.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        reason: { type: "string" },
      },
      required: ["service_order_id", "reason"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.rpc("cancel_service_order_cascade", {
        p_service_order_id: args.service_order_id,
        p_reason: args.reason,
      });
      if (error) return { error: error.message };
      if (!(data as any)?.success) return { error: "RPC não confirmou sucesso no cancelamento." };
      return {
        ok: true,
        parts_restored: (data as any).parts_restored,
        receivables_cancelled: (data as any).receivables_cancelled,
        payments_cancelled: (data as any).payments_cancelled,
      };
    },
  },
  {
    name: "reopen_service_order",
    description: "Reabre uma OS Concluída ou Faturada: cancela pagamentos confirmados e zera recebíveis, voltando a OS para 'completed' para reajuste.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        reason: { type: "string" },
      },
      required: ["service_order_id", "reason"],
    },
    // Destrutivo (cancela pagamentos confirmados) — mantém pendência de aprovação.
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data: so, error: soErr } = await admin.from("service_orders").select("status").eq("id", args.service_order_id).single();
      if (soErr) return { error: soErr.message };
      if (!so || !["invoiced", "completed"].includes(so.status)) {
        return { error: "Só é possível reabrir OS com status Faturada ou Concluída." };
      }

      const { data: receivables } = await admin.from("receivables").select("*").eq("service_order_id", args.service_order_id);
      for (const rec of receivables || []) {
        const { data: payments } = await admin.from("payments").select("*").eq("receivable_id", rec.id).eq("status", "confirmed");
        for (const payment of payments || []) {
          await admin.from("payments").update({ status: "cancelled", cancelled_at: new Date().toISOString(), cancellation_reason: `${args.reason} (reabertura de OS)` }).eq("id", payment.id);
          await admin.from("bank_transactions").update({ reconciled: false, reconciled_payment_id: null }).eq("reconciled_payment_id", payment.id);
        }
        await admin.from("receivables").update({ paid_amount: 0, balance_amount: rec.amount, status: "pending" }).eq("id", rec.id);
      }

      const { data: updated, error: updErr } = await admin
        .from("service_orders")
        .update({ status: "completed", reopened_at: new Date().toISOString(), reopen_reason: args.reason })
        .eq("id", args.service_order_id)
        .select()
        .single();
      if (updErr) return { error: updErr.message };
      return { ok: true, service_order: updated };
    },
  },
];

import type { ToolDef } from "./registry.ts";

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
          produto: p.products?.name || "Desconhecido",
          quantidade: p.quantity,
          total: p.line_total_sale,
        })),
        services: (services || []).map((s: any) => ({
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
    risk: "medium",
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
        if (partsRows.length) await sb.from("service_order_parts").insert(partsRows);
      }
      await sb.rpc("recalc_so_totals", { so_id: data.id }).catch(() => null);
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
    risk: "medium",
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
    description: "Adiciona um produto a uma OS.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        product_id: { type: "string" },
        quantity: { type: "number" },
      },
      required: ["service_order_id", "product_id", "quantity"],
    },
    risk: "medium",
    async execute(args, { sb }) {
      const { data: prod } = await sb
        .from("products")
        .select("cost_price, sale_price, cost_currency")
        .eq("id", args.product_id)
        .maybeSingle();
      if (!prod) return { error: "Produto não encontrado" };
      const { data, error } = await sb
        .from("service_order_parts")
        .insert({
          service_order_id: args.service_order_id,
          product_id: args.product_id,
          quantity: args.quantity,
          unit_cost_snapshot: prod.cost_price || 0,
          unit_sale_snapshot: prod.sale_price || 0,
          currency_snapshot: prod.cost_currency || "BRL",
          line_total_cost: (prod.cost_price || 0) * args.quantity,
          line_total_sale: (prod.sale_price || 0) * args.quantity,
        })
        .select()
        .single();
      if (error) throw error;
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id || args.id }).catch(() => null);
      return { ok: true, part: data };
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
    risk: "medium",
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
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id }).catch(() => null);
      return { ok: true, service: data };
    },
  },
  {
    name: "add_material_to_order",
    description:
      "Adiciona um item de material/insumo livre a uma OS sem necessitar de produto cadastrado no catálogo. Use quando o usuário descreve materiais estimados (ex: 'R$ 4.500 em materiais elétricos') sem produto específico. O item fica registrado como serviço do tipo 'material'.",
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
    risk: "medium",
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
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id }).catch(() => null);
      return { ok: true, material_item: data };
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
    risk: "medium",
    async execute(args, { sb }) {
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
      return { ok: true, service_order: data };
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
    risk: "medium",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("service_orders").update({ discount_amount: args.discount_amount }).eq("id", args.id).select().single();
      if (error) throw error;
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id || args.id }).catch(() => null);
      return { ok: true, service_order: data };
    },
  },
];

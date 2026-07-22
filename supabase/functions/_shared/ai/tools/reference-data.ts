import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

// Dados de referência e orçamentos externos (leads).
//
// POR QUE ISTO EXISTE: uma auditoria de cobertura comparou TODAS as tabelas do banco com o que
// o agente conseguia acessar. Sobraram tabelas de negócio COM DADO que ele não enxergava:
//   • external_quotes (6)            — leads/orçamentos externos. Havia convert_external_quote_to_so,
//                                      mas nenhuma forma de LISTAR: capacidade morta na prática.
//   • financial_categories (36)      — o agente criava recebível/conta a pagar sem categoria.
//   • payment_condition_presets (11) — condições de pagamento reais da empresa.
//   • cost_centers (7)               — centro de custo dos lançamentos.
//   • whatsapp_templates (5)         — textos já aprovados, em vez de improvisar.
// Tabelas de infraestrutura (logs, filas, sessões) ficaram DE FORA de propósito.

export const referenceDataTools: ToolDef[] = [
  {
    name: "list_external_quotes",
    description:
      "Lista ORÇAMENTOS EXTERNOS (leads que chegaram de fora do sistema) — pendentes de revisão, aprovados ou já convertidos em OS. Use para 'tem lead novo?', 'o que chegou pra revisar', ou antes de converter um em OS com convert_external_quote_to_so (que precisa do id daqui).",
    input_schema: {
      type: "object",
      properties: {
        status: { type: "string", description: "Filtra por status (ex.: submitted, approved, rejected)." },
        only_unconverted: { type: "boolean", description: "Só os que ainda NÃO viraram OS (padrão true)." },
        limit: { type: "number", description: "Máximo (padrão 15, teto 50)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      let q = sb
        .from("external_quotes")
        .select("id, quote_number, status, service_type, problem_description, grand_total, quote_validity_date, converted_service_order_id, submitted_at, clients(name), vessels(name)")
        .order("submitted_at", { ascending: false, nullsFirst: false })
        .limit(Math.min(Number(args.limit) || 15, 50));
      if (args.status) q = q.eq("status", String(args.status));
      if (args.only_unconverted !== false) q = q.is("converted_service_order_id", null);

      const { data, error } = await q;
      if (error) throw error;
      const results = ((data as any[]) || []).map((e) => ({
        external_quote_id: e.id,
        numero: e.quote_number,
        status: e.status,
        tipo_servico: e.service_type || null,
        problema: e.problem_description ? String(e.problem_description).slice(0, 120) : null,
        valor: Number(e.grand_total) || 0,
        validade: e.quote_validity_date || null,
        cliente: e.clients?.name || "(sem cliente)",
        ativo: e.vessels?.name || null,
        ja_convertido: !!e.converted_service_order_id,
        enviado_em: e.submitted_at || null,
      }));
      return {
        count: results.length,
        results,
        nota: results.length ? "Para transformar um destes em OS, use convert_external_quote_to_so com o external_quote_id." : null,
      };
    },
  },
  {
    name: "list_reference_data",
    description:
      "Traz as LISTAS DE REFERÊNCIA da empresa numa chamada só: categorias financeiras, centros de custo, condições de pagamento e modelos de mensagem. Use ANTES de criar recebível/conta a pagar (para escolher categoria e centro de custo reais) ou ao definir a condição de pagamento de um orçamento — em vez de inventar texto livre.",
    input_schema: {
      type: "object",
      properties: {
        which: {
          type: "array",
          items: { type: "string", enum: ["financial_categories", "cost_centers", "payment_conditions", "whatsapp_templates"] },
          description: "Quais listas trazer. Omita para trazer todas.",
        },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const pedidas: string[] = Array.isArray(args.which) && args.which.length
        ? args.which
        : ["financial_categories", "cost_centers", "payment_conditions", "whatsapp_templates"];
      const out: Record<string, unknown> = {};

      if (pedidas.includes("financial_categories")) {
        const { data } = await sb.from("financial_categories").select("id, name, type").eq("active", true).order("name");
        out.categorias_financeiras = ((data as any[]) || []).map((c) => ({ id: c.id, nome: c.name, tipo: c.type }));
      }
      if (pedidas.includes("cost_centers")) {
        const { data } = await sb.from("cost_centers").select("id, name, type").eq("active", true).order("name");
        out.centros_de_custo = ((data as any[]) || []).map((c) => ({ id: c.id, nome: c.name, tipo: c.type }));
      }
      if (pedidas.includes("payment_conditions")) {
        const { data } = await sb
          .from("payment_condition_presets")
          .select("id, label, installments, auto_generate_collections")
          .eq("active", true)
          .order("sort_order");
        out.condicoes_de_pagamento = ((data as any[]) || []).map((p) => ({
          id: p.id, texto: p.label, parcelas: p.installments ?? null, gera_cobrancas: !!p.auto_generate_collections,
        }));
      }
      if (pedidas.includes("whatsapp_templates")) {
        const { data } = await sb.from("whatsapp_templates").select("id, name, category, body").eq("active", true).order("sort_order");
        out.modelos_de_mensagem = ((data as any[]) || []).map((t) => ({
          id: t.id, nome: t.name, categoria: t.category || null, texto: t.body ? String(t.body).slice(0, 300) : null,
        }));
      }
      return out;
    },
  },
];

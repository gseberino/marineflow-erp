import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

export const reportTools: ToolDef[] = [
  {
    name: "get_financial_dre",
    description: "DRE por CENTRO DE CUSTO e pela data de VENCIMENTO de um mês. Para 'como fechou o mês?', 'estamos no lucro?', use resultado_do_periodo (por categoria e data do lançamento, o mesmo número da tela).",
    input_schema: {
      type: "object",
      properties: { year: { type: "number" }, month: { type: "number" } },
      required: ["year", "month"],
    },
    risk: "low",
    // Decisão do dono (09/08/2026): técnico não enxerga nada financeiro. O DRE lê
    // receivables e payables com service role — era a leitura financeira mais ampla
    // do agente, aberta a qualquer cargo.
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { year, month } = args;
      const start = new Date(year, month - 1, 1).toISOString();
      const end = new Date(year, month, 0, 23, 59, 59).toISOString();

      // Cancelados não são receita nem despesa. Leitura que falha lança (o assistente diz que a
      // consulta falhou): engolida, virava "receita 0 / despesa 0" e um lucro falso (02/10/2026).
      const { data: rec, error: recErr } = await admin.from("receivables").select("amount, cost_centers(name, type)").neq("status", "cancelled").gte("due_date", start).lte("due_date", end);
      if (recErr) throw recErr;
      const { data: pay, error: payErr } = await admin.from("payables").select("amount, cost_centers(name, type)").neq("status", "cancelled").gte("due_date", start).lte("due_date", end);
      if (payErr) throw payErr;

      const summary: Record<string, number> = {};
      let totalRevenue = 0;
      let totalExpense = 0;

      (rec || []).forEach((r: any) => {
        const cat = r.cost_centers?.name || "Outras Receitas";
        summary[cat] = (summary[cat] || 0) + Number(r.amount);
        totalRevenue += Number(r.amount);
      });

      (pay || []).forEach((p: any) => {
        const cat = p.cost_centers?.name || "Outras Despesas";
        summary[cat] = (summary[cat] || 0) - Number(p.amount);
        totalExpense += Number(p.amount);
      });

      return {
        periodo: `${month}/${year}`,
        receita_total: totalRevenue,
        despesa_total: totalExpense,
        lucro_liquido: totalRevenue - totalExpense,
        detalhamento: summary,
      };
    },
  },
  {
    name: "get_os_profitability",
    description: "Analisa a lucratividade detalhada de uma Ordem de Serviço: receita, custo de peças, deslocamento, despesas, comissões e mão de obra real das diárias, lucro e margem.",
    input_schema: {
      type: "object",
      properties: { service_order_id: { type: "string" } },
      required: ["service_order_id"],
    },
    risk: "low",
    // Lucratividade é margem: custo, preço e resultado da OS. Mesmo critério do DRE.
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      // Lê a MESMA view da tela "Lucro por OS" (vw_os_profitability): o assistente e a tela não
      // podem dizer margens diferentes. Até 29/09/2026 esta tool somava por conta própria, sem
      // mão de obra e com o preço de VENDA das peças no lugar do custo (parts_cost_total).
      const { data: v, error } = await ctx.admin
        .from("vw_os_profitability")
        .select("service_order_number, revenue, parts_cost, travel_cost, operational_cost, commission_cost, labor_cost_real, labor_days, labor_sold, hours_sold, net_profit, net_margin_percent")
        .eq("os_id", args.service_order_id)
        .maybeSingle();
      if (error) throw error;
      if (!v) return { error: "OS não encontrada." };
      const n = (x: unknown) => Math.round((Number(x) || 0) * 100) / 100;
      const custos = {
        pecas: n(v.parts_cost), deslocamento: n(v.travel_cost), despesas: n(v.operational_cost),
        comissoes: n(v.commission_cost), mao_de_obra_diarias: n(v.labor_cost_real),
      };
      const gestor = ctx.userRole === "admin" || ctx.userRole === "financial";
      return {
        os: v.service_order_number,
        receita: n(v.revenue),
        custos,
        custo_total: n(Object.values(custos).reduce((s, x) => s + x, 0)),
        lucro: n(v.net_profit),
        margem: n(v.net_margin_percent),
        mao_de_obra: {
          vendida: n(v.labor_sold),
          horas_vendidas: n(v.hours_sold),
          custo_real_diarias: n(v.labor_cost_real),
          // Quantos dias e quem: detalhe de pagamento de pessoa — só para quem vê as diárias.
          ...(gestor ? { dias_de_diarista: n(v.labor_days) } : {}),
        },
        observacao: Number(v.labor_days) > 0
          ? "A mão de obra do dono não é apontada e não entra no custo."
          : "Nenhuma diária de freelancer ligada a esta OS: a mão de obra não está descontada (a do dono nunca entra). Ligar os dias à OS em Financeiro › Diárias.",
      };
    },
  },
];

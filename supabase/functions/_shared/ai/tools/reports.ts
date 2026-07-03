import type { ToolDef } from "./registry.ts";

export const reportTools: ToolDef[] = [
  {
    name: "get_financial_dre",
    description: "Retorna o DRE (Demonstrativo de Resultados) de um período específico.",
    input_schema: {
      type: "object",
      properties: { year: { type: "number" }, month: { type: "number" } },
      required: ["year", "month"],
    },
    risk: "low",
    async execute(args, { admin }) {
      const { year, month } = args;
      const start = new Date(year, month - 1, 1).toISOString();
      const end = new Date(year, month, 0, 23, 59, 59).toISOString();

      const { data: rec } = await admin.from("receivables").select("amount, cost_centers(name, type)").gte("due_date", start).lte("due_date", end);
      const { data: pay } = await admin.from("payables").select("amount, cost_centers(name, type)").gte("due_date", start).lte("due_date", end);

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
    description: "Analisa a lucratividade detalhada de uma Ordem de Serviço.",
    input_schema: {
      type: "object",
      properties: { service_order_id: { type: "string" } },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { admin }) {
      const { data: so, error } = await admin
        .from("service_orders")
        .select("grand_total, labor_cost_total, parts_cost_total, travel_cost_total, operational_cost_total")
        .eq("id", args.service_order_id)
        .single();
      if (error) throw error;
      const revenue = Number(so.grand_total);
      const directCosts = Number(so.parts_cost_total) + Number(so.travel_cost_total) + Number(so.operational_cost_total);
      const grossProfit = revenue - directCosts;
      return {
        receita: revenue,
        custos_diretos: directCosts,
        lucro_bruto: grossProfit,
        margem: revenue > 0 ? (grossProfit / revenue) * 100 : 0,
      };
    },
  },
];

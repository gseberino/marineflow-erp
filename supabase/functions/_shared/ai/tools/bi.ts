import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

// Views de BI (Onda 5) — perguntas de NEGÓCIO que antes não tinham ferramenta.
// Base: RPCs bi_* (agregação em SQL, só OS reais — não orçamento/cancelada).

function sinceFromPeriod(period?: string): string | null {
  const now = new Date();
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  switch (String(period || "").toLowerCase()) {
    case "mes": return iso(new Date(now.getFullYear(), now.getMonth(), 1));
    case "ano": return iso(new Date(now.getFullYear(), 0, 1));
    case "12meses":
    case "12m": return iso(new Date(now.getTime() - 365 * 864e5));
    case "tudo":
    case "": return null;
    default: return iso(new Date(now.getTime() - 365 * 864e5)); // padrão: 12 meses
  }
}
const r2 = (n: number) => Math.round(n * 100) / 100;

export const biTools: ToolDef[] = [
  {
    name: "get_revenue_by_brand",
    description:
      "FATURAMENTO por MARCA/fabricante — responde 'quanto faturei com Victron?', 'quais marcas mais vendem?'. Se passar 'brand', traz só ela; senão, o ranking. Conta só peças de OS reais (não orçamento nem cancelada). Traz receita, custo, margem e quantidade.",
    input_schema: {
      type: "object",
      properties: {
        brand: { type: "string", description: "Marca/fabricante (ex.: Victron). Omita para o ranking geral." },
        period: { type: "string", enum: ["mes", "ano", "12meses", "tudo"], description: "Período (padrão: 12meses)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const since = sinceFromPeriod(args.period || "12meses");
      const { data, error } = await ctx.admin.rpc("bi_revenue_by_brand", { _since: since, _brand: args.brand || null });
      if (error) return { error: error.message };
      const rows = (data as any[]) || [];
      const fmt = rows.map((r) => {
        const rev = Number(r.revenue) || 0, cost = Number(r.cost) || 0;
        return { marca: r.brand, faturamento: r2(rev), custo: r2(cost), lucro_bruto: r2(rev - cost), margem_pct: rev > 0 ? r2(((rev - cost) / rev) * 100) : null, qtd: Number(r.qty) || 0 };
      });
      return {
        periodo: args.period || "12meses",
        desde: since || "todo o histórico",
        marca: args.brand || null,
        total_faturado: r2(fmt.reduce((a, x) => a + x.faturamento, 0)),
        marcas: fmt.slice(0, 20),
      };
    },
  },
  {
    name: "get_margin_by_category",
    description: "MARGEM por CATEGORIA de produto — onde a empresa ganha mais/menos. Responde 'qual categoria tem melhor margem?'. Só peças de OS reais. Traz receita, custo e margem % por categoria.",
    input_schema: {
      type: "object",
      properties: { period: { type: "string", enum: ["mes", "ano", "12meses", "tudo"], description: "Período (padrão: 12meses)." } },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const since = sinceFromPeriod(args.period || "12meses");
      const { data, error } = await ctx.admin.rpc("bi_margin_by_category", { _since: since });
      if (error) return { error: error.message };
      const rows = (data as any[]) || [];
      const fmt = rows.map((r) => {
        const rev = Number(r.revenue) || 0, cost = Number(r.cost) || 0;
        return { categoria: r.category, faturamento: r2(rev), custo: r2(cost), margem_pct: rev > 0 ? r2(((rev - cost) / rev) * 100) : null };
      });
      return { periodo: args.period || "12meses", desde: since || "todo o histórico", categorias: fmt.slice(0, 25) };
    },
  },
  {
    name: "get_top_clients",
    description: "TOP CLIENTES por faturamento — quem mais comprou. Responde 'quais meus melhores clientes?', 'top 5 do ano'. Considera OS reais (não orçamento). Traz receita e nº de OS por cliente.",
    input_schema: {
      type: "object",
      properties: {
        period: { type: "string", enum: ["mes", "ano", "12meses", "tudo"], description: "Período (padrão: ano)." },
        limit: { type: "number", description: "Quantos (padrão 10, teto 50)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const since = sinceFromPeriod(args.period || "ano");
      const limit = Math.min(Math.max(Number(args.limit) || 10, 1), 50);
      const { data, error } = await ctx.admin.rpc("bi_top_clients", { _since: since, _limit: limit });
      if (error) return { error: error.message };
      const rows = (data as any[]) || [];
      return {
        periodo: args.period || "ano",
        desde: since || "todo o histórico",
        clientes: rows.map((r) => ({ cliente: r.name || "(sem nome)", faturamento: r2(Number(r.revenue) || 0), os: Number(r.os_count) || 0 })),
      };
    },
  },
];

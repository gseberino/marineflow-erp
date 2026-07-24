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
  {
    name: "get_task_metrics",
    description:
      "MÉTRICAS de TAREFAS da agenda — produtividade e disciplina de execução. Responde 'como está a execução das tarefas?', 'quantas tarefas atrasadas por pessoa?'. Traz: vivas/atrasadas/concluídas por pessoa no período, tempo médio de resolução e distribuição por origem (manual/IA/automação/recorrência).",
    input_schema: {
      type: "object",
      properties: {
        days: { type: "number", description: "Janela em dias para as concluídas (padrão 30)." },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      const days = Math.min(Math.max(Number(args.days) || 30, 7), 365);
      const since = new Date(Date.now() - days * 86400000).toISOString();
      const startToday = new Date(new Date(Date.now() - 3 * 3600000).toISOString().slice(0, 10) + "T00:00:00-03:00").toISOString();

      const { data: live } = await ctx.admin.from("agenda_tasks")
        .select("assignee_user_id, due_at, scheduled_start_at, source, app_users:assignee_user_id(full_name)")
        .in("status", ["pending", "in_progress"]).limit(500);
      const { data: done } = await ctx.admin.from("agenda_tasks")
        .select("assignee_user_id, created_at, completed_at, source, app_users:assignee_user_id(full_name)")
        .eq("status", "done").gte("completed_at", since).limit(500);

      const anchor = (t: any) => t.due_at || t.scheduled_start_at;
      const byPerson = new Map<string, { pessoa: string; vivas: number; atrasadas: number; concluidas: number }>();
      const bump = (t: any, field: "vivas" | "atrasadas" | "concluidas") => {
        const nome = t.app_users?.full_name || "(sem responsável)";
        if (!byPerson.has(nome)) byPerson.set(nome, { pessoa: nome, vivas: 0, atrasadas: 0, concluidas: 0 });
        byPerson.get(nome)![field]++;
      };
      for (const t of (live as any[]) || []) {
        bump(t, "vivas");
        if (anchor(t) && anchor(t) < startToday) bump(t, "atrasadas");
      }
      let resolutionSumH = 0, resolutionN = 0;
      const bySource: Record<string, number> = {};
      for (const t of (done as any[]) || []) {
        bump(t, "concluidas");
        bySource[t.source] = (bySource[t.source] || 0) + 1;
        if (t.completed_at && t.created_at) {
          resolutionSumH += (new Date(t.completed_at).getTime() - new Date(t.created_at).getTime()) / 3600000;
          resolutionN++;
        }
      }
      return {
        janela_dias: days,
        por_pessoa: Array.from(byPerson.values()).sort((a, b) => b.vivas - a.vivas),
        concluidas_por_origem: bySource,
        tempo_medio_resolucao_horas: resolutionN > 0 ? r2(resolutionSumH / resolutionN) : null,
      };
    },
  },
];

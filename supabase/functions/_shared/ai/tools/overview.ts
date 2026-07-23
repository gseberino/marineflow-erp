import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

// Macro de LEITURA — "como estão as coisas?" numa chamada só.
//
// Sem esta tool, responder "e aí, como tá?" exige 4-5 chamadas separadas (vencidos +
// orçamentos parados + mensagens sem resposta + agenda + contas a pagar), cada uma um
// round-trip do LLM. Aqui o CÓDIGO executa os 5 blocos e devolve um resumo compacto; o
// LLM só orquestra e narra. Espelha as MESMAS queries do resumo matinal (ai-daily-briefing),
// que já rodam em produção. Cada bloco é best-effort: um erro nele não derruba os outros.

const r2 = (n: number) => Math.round(n * 100) / 100;
const isoDate = (d: Date) => d.toISOString().slice(0, 10);

export const overviewTools: ToolDef[] = [
  {
    name: "get_situation_overview",
    description:
      "PANORAMA do negócio agora, numa consulta só: cobranças vencidas, orçamentos parados, mensagens de cliente esperando resposta, agenda de hoje e contas a pagar da semana. Use para 'como estão as coisas?', 'e aí, como tá?', 'me dá um resumo', 'o que preciso resolver hoje?'. Só leitura — não envia nem altera nada. Devolve os totais e uma amostra do topo de cada frente; para a lista completa de uma frente, use a tool específica (get_delinquency_plan, list_service_orders, list_unanswered_messages, list_agenda).",
    input_schema: {
      type: "object",
      properties: {
        stuck_days: { type: "number", description: "Orçamento conta como 'parado' se sem mexer há ≥ N dias (padrão 2)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;

      const now = new Date();
      const hojeIso = isoDate(now);
      const diasParado = Number(args.stuck_days) > 0 ? Number(args.stuck_days) : 2;

      // ── 1. Cobranças vencidas (mesma lógica do get_delinquency_plan) ──
      let cobrancas: Record<string, unknown> = { erro: "não consultado" };
      try {
        const { data: recs } = await admin
          .from("receivables")
          .select("amount, balance_amount, due_date, clients(name)")
          .in("status", ["pending", "partially_paid"])
          .eq("is_deposit", false)
          .lt("due_date", hojeIso)
          .limit(200);
        const casos = ((recs as any[]) || [])
          .map((r) => ({
            cliente: r.clients?.name || "(sem cliente)",
            saldo: r2(Number(r.balance_amount ?? r.amount) || 0),
            dias_atraso: Math.floor((now.getTime() - new Date(`${r.due_date}T00:00:00`).getTime()) / 86400000),
          }))
          .filter((c) => c.saldo > 0)
          .sort((a, b) => b.saldo - a.saldo);
        cobrancas = {
          quantidade: casos.length,
          total_em_atraso: r2(casos.reduce((a, c) => a + c.saldo, 0)),
          topo: casos.slice(0, 5),
        };
      } catch (e) { cobrancas = { erro: (e as Error).message }; }

      // ── 2. Orçamentos parados (draft + quote_status aberto, sem mexer há ≥ N dias) ──
      let orcamentos: Record<string, unknown> = { erro: "não consultado" };
      try {
        const todayMid = new Date(`${hojeIso}T00:00:00`).getTime();
        const { data: openQuotes } = await admin
          .from("service_orders")
          .select("service_order_number, grand_total, updated_at, quote_validity_date, clients(name)")
          .eq("status", "draft")
          .in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"])
          .order("updated_at", { ascending: true })
          .limit(50);
        const flagged = ((openQuotes as any[]) || [])
          .map((q) => {
            const dias = Math.floor((now.getTime() - new Date(q.updated_at).getTime()) / 86400000);
            const vd = q.quote_validity_date ? new Date(`${q.quote_validity_date}T00:00:00`).getTime() : null;
            return {
              numero: q.service_order_number,
              cliente: q.clients?.name || "(sem cliente)",
              valor: r2(Number(q.grand_total) || 0),
              dias_parado: dias,
              expirado: vd !== null && vd < todayMid,
            };
          })
          .filter((q) => q.dias_parado >= diasParado || q.expirado);
        orcamentos = {
          quantidade: flagged.length,
          valor_total: r2(flagged.reduce((a, q) => a + q.valor, 0)),
          topo: flagged.slice(0, 5),
        };
      } catch (e) { orcamentos = { erro: (e as Error).message }; }

      // ── 3. Mensagens de cliente esperando resposta (RPC, últimos 7 dias, clientes primeiro) ──
      let mensagens: Record<string, unknown> = { erro: "não consultado" };
      try {
        const since7d = new Date(now.getTime() - 7 * 86400000).toISOString();
        const { data: waitingRows } = await admin.rpc("whatsapp_pending_inbox", { _since: since7d, _limit: 15 });
        const waiting = ((waitingRows as any[]) || []).slice();
        waiting.sort((a, b) => Number(b.is_client) - Number(a.is_client));
        mensagens = {
          quantidade: waiting.length,
          de_clientes: waiting.filter((w) => w.is_client).length,
          topo: waiting.slice(0, 5).map((w) => {
            const mins = Math.max(0, Math.round((now.getTime() - new Date(w.last_inbound_at as string).getTime()) / 60000));
            return {
              contato: w.contato,
              cliente: !!w.is_client,
              ha: mins < 60 ? `${mins} min` : mins < 1440 ? `${Math.round(mins / 60)} h` : `${Math.round(mins / 1440)} d`,
            };
          }),
        };
      } catch (e) { mensagens = { erro: (e as Error).message }; }

      // ── 4. Agenda de hoje (OS com scheduled_start_at dentro do dia) ──
      let agenda: Record<string, unknown> = { erro: "não consultado" };
      try {
        const dayStart = `${hojeIso}T00:00:00`;
        const dayEnd = `${hojeIso}T23:59:59`;
        const { data: hoje } = await admin
          .from("service_orders")
          .select("service_order_number, scheduled_start_at, status, clients(name)")
          .gte("scheduled_start_at", dayStart)
          .lte("scheduled_start_at", dayEnd)
          .order("scheduled_start_at", { ascending: true })
          .limit(30);
        agenda = {
          quantidade: (hoje as any[])?.length || 0,
          itens: ((hoje as any[]) || []).slice(0, 8).map((o) => ({
            numero: o.service_order_number,
            cliente: o.clients?.name || null,
            inicio: o.scheduled_start_at,
            status: o.status,
          })),
        };
      } catch (e) { agenda = { erro: (e as Error).message }; }

      // ── 5. Contas a pagar dos próximos 7 dias (total) ──
      let contas_a_pagar: Record<string, unknown> = { erro: "não consultado" };
      try {
        const em7 = isoDate(new Date(now.getTime() + 7 * 86400000));
        const { data: pag } = await admin
          .from("payables")
          .select("amount, balance_amount, due_date")
          .not("status", "in", "(paid,cancelled)")
          .lte("due_date", em7)
          .gt("balance_amount", 0);
        const rows = (pag as any[]) || [];
        contas_a_pagar = {
          quantidade: rows.length,
          total: r2(rows.reduce((a, p) => a + (Number(p.balance_amount ?? p.amount) || 0), 0)),
        };
      } catch (e) { contas_a_pagar = { erro: (e as Error).message }; }

      return {
        data: hojeIso,
        cobrancas_vencidas: cobrancas,
        orcamentos_parados: orcamentos,
        mensagens_esperando: mensagens,
        agenda_hoje: agenda,
        contas_a_pagar_7d: contas_a_pagar,
        nota: "Amostra do topo de cada frente. Para a lista completa, use a tool específica (get_delinquency_plan, list_service_orders, list_unanswered_messages, list_agenda).",
      };
    },
  },
];

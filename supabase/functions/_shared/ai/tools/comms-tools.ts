import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { classificarResposta } from "../comms/reply-router.ts";
import { MAX_TOQUES, podeTocarAgora } from "../comms/cadence.ts";

// Ferramentas da Camada de Inteligência de Comunicação (inbound + cadência + loop).

export const commsTools: ToolDef[] = [
  {
    name: "interpret_customer_reply",
    description:
      "Classifica a RESPOSTA que um cliente/fornecedor mandou (disputa · acordo · pergunta · cotação parcial · opt-out) e diz como manejar. Use quando chegar uma resposta a uma cobrança/cotação/follow-up — ESPECIALMENTE para não continuar cobrando quem contesta ou pediu para parar. Se passar entity_id, registra o desfecho no histórico de comunicação.",
    input_schema: {
      type: "object",
      properties: {
        text: { type: "string", description: "O texto que o contato respondeu." },
        entity_kind: { type: "string", description: "client|supplier (opcional, para registrar o desfecho)." },
        entity_id: { type: "string", description: "UUID do cliente/fornecedor (opcional)." },
      },
      required: ["text"],
    },
    risk: "low",
    async execute(args, { admin }) {
      const r = classificarResposta(String(args.text || ""));
      if (args.entity_id) {
        try {
          const { data } = await admin.from("ai_comms_log").select("id").eq("entity_id", args.entity_id).is("responded_at", null).order("created_at", { ascending: false }).limit(1);
          const id = (data as any[])?.[0]?.id;
          if (id) await admin.from("ai_comms_log").update({ responded_at: new Date().toISOString(), reply_intent: r.intencao }).eq("id", id);
        } catch { /* best-effort */ }
      }
      return { intencao: r.intencao, manejo: r.manejo, sinais: r.sinais };
    },
  },
  {
    name: "check_followup_cadence",
    description:
      "ANTES de mandar mais um follow-up/cobrança para o mesmo alvo, verifica a cadência: quantos toques já foram, se pode tocar AGORA (espaçamento e teto) e a orientação. Evita insistir cedo demais ou além do teto (repetição vira ruído e irrita). Se pode tocar, traga um GANCHO NOVO — não repita a mensagem anterior.",
    input_schema: {
      type: "object",
      properties: {
        entity_id: { type: "string", description: "UUID do alvo (OS/cobrança/cliente/fornecedor)." },
        tipo: { type: "string", description: "follow_up | cobranca | cotacao" },
      },
      required: ["entity_id", "tipo"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      let toques = 0;
      let ultimo: string | null = null;
      try {
        const { data } = await admin.from("ai_comms_log").select("created_at").eq("entity_id", args.entity_id).eq("tipo", args.tipo).eq("status", "sent").order("created_at", { ascending: false });
        const rows = (data as any[]) || [];
        toques = rows.length;
        ultimo = rows[0]?.created_at ?? null;
      } catch { /* best-effort */ }
      const d = podeTocarAgora(toques, ultimo);
      return { toques, teto: MAX_TOQUES, pode_tocar_agora: d.permitido, motivo: d.motivo, esperar_ate: d.esperarAte ?? null };
    },
  },
  {
    name: "get_comms_log",
    description:
      "Mostra 'o que o agente mandou e o que voltou' — histórico de mensagens externas (cobrança/cotação/follow-up) com status e, quando houve, a intenção da resposta. Use para 'como estão os follow-ups?', 'quem respondeu as cobranças?', 'a cotação foi respondida?'. Traz a taxa de resposta.",
    input_schema: {
      type: "object",
      properties: {
        entity_id: { type: "string", description: "Filtra por um alvo específico (opcional)." },
        days: { type: "number", description: "Janela em dias (padrão 14)." },
        limit: { type: "number", description: "Máximo de linhas (padrão 30, teto 100)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const days = Number(args.days) || 14;
      const lim = Math.min(Number(args.limit) || 30, 100);
      const desde = new Date(Date.now() - days * 86400000).toISOString();
      let q = admin.from("ai_comms_log")
        .select("created_at, tipo, audiencia, entity_kind, entity_id, status, block_code, responded_at, reply_intent, message_preview")
        .gte("created_at", desde).order("created_at", { ascending: false }).limit(lim);
      if (args.entity_id) q = q.eq("entity_id", args.entity_id);
      const { data } = await q;
      const rows = (data as any[]) || [];
      const enviados = rows.filter((r) => r.status === "sent").length;
      const responderam = rows.filter((r) => r.responded_at).length;
      return {
        total: rows.length,
        enviados,
        responderam,
        taxa_resposta_pct: enviados ? Math.round((responderam / enviados) * 100) : 0,
        itens: rows.slice(0, 20),
      };
    },
  },
  {
    name: "get_comms_metrics",
    description:
      "MÉTRICAS de comunicação do período: quantas mensagens externas saíram, taxa de resposta, e o ATRITO do destinatário (bloqueios, disputas, opt-outs) — além do desempenho por tipo. Use para 'como está a comunicação?', 'a cobrança está funcionando?', 'teve muito opt-out?'.",
    input_schema: {
      type: "object",
      properties: { days: { type: "number", description: "Janela em dias (padrão 30)." } },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const days = Number(args.days) || 30;
      const desde = new Date(Date.now() - days * 86400000).toISOString();
      const { data } = await admin.from("ai_comms_log").select("tipo, status, responded_at, reply_intent, block_code").gte("created_at", desde);
      const rows = (data as any[]) || [];
      const enviados = rows.filter((r) => r.status === "sent");
      const responderam = enviados.filter((r) => r.responded_at);
      const porTipo: Record<string, { enviados: number; responderam: number }> = {};
      for (const r of enviados) {
        const t = r.tipo || "?";
        (porTipo[t] ||= { enviados: 0, responderam: 0 }).enviados++;
        if (r.responded_at) porTipo[t].responderam++;
      }
      const intents: Record<string, number> = {};
      for (const r of rows) if (r.reply_intent) intents[r.reply_intent] = (intents[r.reply_intent] || 0) + 1;
      const bloqueios: Record<string, number> = {};
      for (const r of rows) if (r.status === "blocked") { const c = r.block_code || "?"; bloqueios[c] = (bloqueios[c] || 0) + 1; }
      return {
        periodo_dias: days,
        enviados: enviados.length,
        responderam: responderam.length,
        taxa_resposta_pct: enviados.length ? Math.round((responderam.length / enviados.length) * 100) : 0,
        atrito: { bloqueios: rows.filter((r) => r.status === "blocked").length, disputas: intents["disputa"] || 0, opt_outs: intents["opt_out"] || 0 },
        por_tipo: Object.fromEntries(Object.entries(porTipo).map(([t, v]) => [t, { enviados: v.enviados, taxa_resposta_pct: v.enviados ? Math.round((v.responderam / v.enviados) * 100) : 0 }])),
        respostas_por_intencao: intents,
        bloqueios_por_motivo: bloqueios,
      };
    },
  },
];

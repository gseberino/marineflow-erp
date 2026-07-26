import type { ToolDef } from "./registry.ts";

// Aprendizado do agente sobre o dia a dia (Fase 10-A).
// Princípio: o agente OBSERVA e REGISTRA; propõe automação só quando há repetição
// evidente; e a autonomia só muda com um "sim" explícito do dono.

export const learningTools: ToolDef[] = [
  {
    name: "record_routine",
    description:
      "Registra algo que você APRENDEU sobre como o dono trabalha: uma rotina que se repete ('toda segunda ele cobra os atrasados'), uma preferência ('prefere mensagem curta e sem emoji'), um contexto do negócio ('o técnico Felipe atende a marina X') ou um atalho ('quando ele diz \"o de sempre\" para o cliente Y, é o filtro de óleo Z'). Chame quando perceber um padrão, SEM interromper o assunto. Se o padrão já existir, ele conta +1 observação — é a repetição que justifica propor automação depois.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string", description: "O aprendizado em uma frase curta e específica." },
        pattern_key: { type: "string", description: "Chave estável em minúsculas p/ o mesmo padrão sempre cair no mesmo registro. Ex.: 'cobranca:semanal:segunda'." },
        category: { type: "string", enum: ["rotina", "preferencia", "contexto", "atalho"] },
        description: { type: "string" },
        evidence: { type: "string", description: "O que o dono disse/fez que levou a este aprendizado." },
        suggested_automation: { type: "string", description: "Se este padrão puder virar automação, descreva em uma frase o que o sistema passaria a fazer sozinho." },
      },
      required: ["title", "pattern_key", "category"],
    },
    risk: "low",
    async execute(args, { sb, userId }) {
      const { data: existing } = await sb.from("ai_learned_routines")
        .select("id, observations").eq("pattern_key", args.pattern_key)
        .eq("user_id", userId).maybeSingle();

      if (existing) {
        const { error } = await sb.from("ai_learned_routines").update({
          observations: (existing as any).observations + 1,
          last_observed_at: new Date().toISOString(),
          evidence: args.evidence ?? null,
          updated_at: new Date().toISOString(),
          ...(args.suggested_automation ? { suggested_automation: args.suggested_automation } : {}),
        }).eq("id", (existing as any).id);
        if (error) throw error;
        const n = (existing as any).observations + 1;
        return {
          ok: true, aprendizado: args.title, observacoes: n,
          nota: n >= 3 && args.suggested_automation
            ? "Já vi isso 3+ vezes — vale oferecer para automatizar (use propose_automation)."
            : "Registrado. Vou continuar observando.",
        };
      }

      const { error } = await sb.from("ai_learned_routines").insert({
        title: args.title,
        pattern_key: args.pattern_key,
        category: args.category,
        description: args.description ?? null,
        evidence: args.evidence ?? null,
        suggested_automation: args.suggested_automation ?? null,
        user_id: userId,
      });
      if (error) throw error;
      return { ok: true, aprendizado: args.title, observacoes: 1, nota: "Primeiro registro deste padrão." };
    },
  },
  {
    name: "list_routines",
    description:
      "Lista o que você já aprendeu sobre o dia a dia do dono (rotinas, preferências, contextos, atalhos), com quantas vezes cada padrão foi observado. Use para responder 'o que você já aprendeu sobre mim?' e para lembrar do jeito da casa antes de agir.",
    input_schema: {
      type: "object",
      properties: {
        category: { type: "string", enum: ["rotina", "preferencia", "contexto", "atalho"] },
        only_automatable: { type: "boolean", description: "Só as que já podem virar automação (3+ observações com sugestão)." },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      let q = sb.from("ai_learned_routines")
        .select("id, title, category, observations, suggested_automation, status, last_observed_at, evidence")
        .neq("status", "rejected")
        .order("observations", { ascending: false })
        .limit(50);
      if (args.category) q = q.eq("category", args.category);
      const { data, error } = await q;
      if (error) throw error;
      let rows = (data as any[]) || [];
      if (args.only_automatable) {
        rows = rows.filter((r) => r.observations >= 3 && r.suggested_automation && r.status !== "automated");
      }
      return {
        total: rows.length,
        aprendizados: rows.map((r) => ({
          id: r.id, o_que: r.title, tipo: r.category, vezes_observado: r.observations,
          poderia_automatizar: r.suggested_automation || null, status: r.status,
          ultima_vez: r.last_observed_at,
        })),
      };
    },
  },
  {
    name: "propose_automation",
    description:
      "OFERECE ao dono transformar uma rotina aprendida em automação (ex.: tarefa recorrente, regra do motor, lembrete fixo). Use quando um padrão já foi observado 3+ vezes. Isto NÃO liga nada: marca a rotina como proposta e devolve o texto da oferta para você apresentar. A ativação só acontece se o dono disser sim e você executar a ação correspondente (ex.: create_task com rrule).",
    input_schema: {
      type: "object",
      properties: {
        routine_id: { type: "string" },
        automation_payload: { type: "object", description: "Parâmetros prontos da automação proposta (ex.: {rrule, title, assignee})." },
      },
      required: ["routine_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: r, error } = await sb.from("ai_learned_routines")
        .select("id, title, observations, suggested_automation").eq("id", args.routine_id).maybeSingle();
      if (error) throw error;
      if (!r) return { error: "Rotina não encontrada." };
      await sb.from("ai_learned_routines").update({
        status: "proposed",
        automation_payload: args.automation_payload ?? null,
        updated_at: new Date().toISOString(),
      }).eq("id", args.routine_id);
      return {
        ok: true,
        oferta: `Notei que ${String((r as any).title).toLowerCase()} — já vi isso ${(r as any).observations} vezes. Quer que eu passe a fazer isso sozinho? (${(r as any).suggested_automation || "automação a combinar"})`,
        nota: "Apresente a oferta ao dono. Só execute a automação se ele confirmar.",
      };
    },
  },
  {
    name: "confirm_automation",
    description:
      "Marca uma rotina como APROVADA para automação, depois que o dono disse sim. Registre isso logo após criar a tarefa recorrente/regra correspondente, para não oferecer de novo.",
    input_schema: {
      type: "object",
      properties: {
        routine_id: { type: "string" },
        accepted: { type: "boolean", description: "true = dono aceitou; false = recusou (não ofereça de novo)." },
        reason: { type: "string" },
      },
      required: ["routine_id", "accepted"],
    },
    risk: "low",
    async execute(args, { sb, userId }) {
      const patch = args.accepted
        ? { status: "automated", approved_at: new Date().toISOString(), approved_by: userId }
        : { status: "rejected", rejected_reason: args.reason ?? null };
      const { error } = await sb.from("ai_learned_routines")
        .update({ ...patch, updated_at: new Date().toISOString() }).eq("id", args.routine_id);
      if (error) throw error;
      return { ok: true, status: args.accepted ? "automated" : "rejected" };
    },
  },
  {
    name: "get_autonomy_report",
    description:
      "Relatório de como está a parceria: quantas sugestões da caixa de entrada foram aceitas vs descartadas (por tipo de detector), tarefas por origem, rotinas aprendidas e o que já está maduro para virar automático. Use quando o dono perguntar 'como você está indo?', 'o que já dá pra automatizar?' ou no resumo semanal.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    async execute(_args, { sb }) {
      const since = new Date(Date.now() - 30 * 86400000).toISOString();

      const { data: sugg } = await sb.from("agenda_suggestions")
        .select("detector, status").gte("created_at", since).limit(1000);
      const porDetector: Record<string, { aceitas: number; descartadas: number; pendentes: number }> = {};
      for (const s of ((sugg as any[]) || [])) {
        const d = s.detector;
        porDetector[d] = porDetector[d] || { aceitas: 0, descartadas: 0, pendentes: 0 };
        if (s.status === "accepted") porDetector[d].aceitas++;
        else if (s.status === "dismissed") porDetector[d].descartadas++;
        else if (s.status === "pending") porDetector[d].pendentes++;
      }
      const prontosParaAutomatizar = Object.entries(porDetector)
        .filter(([, v]) => v.aceitas + v.descartadas >= 5 && v.aceitas / Math.max(1, v.aceitas + v.descartadas) >= 0.8)
        .map(([k, v]) => ({ detector: k, taxa_aceite: Math.round((v.aceitas / (v.aceitas + v.descartadas)) * 100) }));

      const { data: tasks } = await sb.from("agenda_tasks")
        .select("source, status").gte("created_at", since).limit(1000);
      const porOrigem: Record<string, number> = {};
      for (const t of ((tasks as any[]) || [])) porOrigem[t.source] = (porOrigem[t.source] || 0) + 1;

      const { data: routines } = await sb.from("ai_learned_routines")
        .select("title, observations, status, suggested_automation")
        .neq("status", "rejected").order("observations", { ascending: false }).limit(20);

      const maduras = ((routines as any[]) || [])
        .filter((r) => r.observations >= 3 && r.suggested_automation && r.status === "observed");

      return {
        periodo_dias: 30,
        caixa_de_entrada: { por_detector: porDetector, prontos_para_automatizar: prontosParaAutomatizar },
        tarefas_por_origem: porOrigem,
        rotinas_aprendidas: ((routines as any[]) || []).length,
        rotinas_maduras_para_oferecer: maduras.map((r) => ({ o_que: r.title, vezes: r.observations, automacao: r.suggested_automation })),
        leitura:
          prontosParaAutomatizar.length > 0 || maduras.length > 0
            ? "Há coisas maduras para ganhar autonomia — ofereça ao dono."
            : "Ainda coletando evidência. Continue sugerindo e registrando rotinas.",
      };
    },
  },
];

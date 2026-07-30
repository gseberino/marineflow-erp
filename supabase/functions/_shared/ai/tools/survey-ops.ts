import type { ToolDef } from "./registry.ts";

// Levantamento antes de orçar — Fase 4 do Ciclo do Serviço.
// Plano: plans/marineflow-execucao-os-roteiro.md (princípios P15 a P18)
//
// Quando o serviço exige análise técnica antes de orçar, estas tools montam o
// questionário, conduzem a entrevista e devolvem a estimativa. O ponto delicado
// não é perguntar: é saber PARAR. A literatura (MediQ) mostra que um agente que
// pergunta sem critério fica pior que um que não pergunta — 11,3% de queda. Por
// isso `assess_survey_confidence` existe e é obrigatória antes de fechar.

function formatarMinutos(min: number | null | undefined): string {
  if (min === null || min === undefined) return "—";
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m === 0 ? `${h}h` : `${h}h${String(m).padStart(2, "0")}`;
}

export const surveyOpsTools: ToolDef[] = [
  {
    name: "check_needs_survey",
    description:
      "Diz se um serviço precisa de LEVANTAMENTO TÉCNICO antes de ser orçado, e por quê. Use antes de montar orçamento de serviço que você não conhece bem, quando o cliente pedir preço de algo incomum, ou quando o dono perguntar 'preciso ir ver antes?'. Quatro dos cinco gatilhos são conta sobre o histórico; o quinto (incerteza no pedido do cliente) é leitura sua.",
    input_schema: {
      type: "object",
      properties: {
        service_id: { type: "string", description: "UUID do serviço do catálogo." },
        client_id: { type: "string", description: "UUID do cliente, se conhecido." },
        vessel_id: { type: "string", description: "UUID do ativo (embarcação/motorhome), se conhecido." },
        valor_estimado: { type: "number", description: "Valor aproximado do serviço, se já houver ideia." },
      },
      required: ["service_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.rpc("should_survey_service", {
        p_service_id: args.service_id,
        p_client_id: args.client_id ?? null,
        p_vessel_id: args.vessel_id ?? null,
        p_valor: args.valor_estimado ?? null,
      });
      if (error) throw error;

      const r = data as any;
      return {
        precisa_levantamento: r.precisa,
        motivos: r.motivos,
        casos_conhecidos: r.casos_conhecidos,
        dispersao_pct: r.dispersao_pct,
        observacao: r.precisa
          ? "Orçar sem levantar aqui é chute. Proponha a visita técnica ou peça foto ao cliente."
          : "Histórico consistente o bastante para orçar direto.",
      };
    },
  },

  {
    name: "start_service_survey",
    description:
      "Abre um levantamento técnico e traz as perguntas a fazer, já na ordem de impacto no preço. Use depois que check_needs_survey disser que precisa. O modo 'remoto' traz só as perguntas que um leigo responde com uma foto — serve para pedir ao próprio cliente e evitar a viagem.",
    input_schema: {
      type: "object",
      properties: {
        service_id: { type: "string", description: "UUID do serviço." },
        trigger_reason: { type: "string", description: "Por que está levantando (veio de check_needs_survey)." },
        service_order_id: { type: "string", description: "UUID do orçamento/OS, se já existir." },
        client_id: { type: "string" },
        vessel_id: { type: "string" },
        mode: { type: "string", enum: ["local", "remoto"], description: "'local' = técnico no local; 'remoto' = cliente responde por foto." },
      },
      required: ["service_id", "trigger_reason"],
    },
    risk: "low",
    async execute(args, { sb, userId }) {
      const modo = args.mode === "remoto" ? "remoto" : "local";

      const { data: perguntas, error: qErr } = await sb
        .from("service_survey_templates")
        .select("id, seq, question, help_text, answer_type, options, price_impact, affects, ask_remotely")
        .eq("service_id", args.service_id)
        .eq("active", true)
        .order("price_impact", { ascending: true })  // 'alto' < 'baixo' < 'medio' alfabeticamente; reordenado abaixo
        .order("seq", { ascending: true });
      if (qErr) throw qErr;

      const peso: Record<string, number> = { alto: 0, medio: 1, baixo: 2 };
      const lista = (perguntas || [])
        .filter((q: any) => (modo === "remoto" ? q.ask_remotely : true))
        .sort((a: any, b: any) => (peso[a.price_impact] ?? 1) - (peso[b.price_impact] ?? 1) || a.seq - b.seq)
        .slice(0, 9); // P2/P16: teto de 9 — acima disso ninguém responde com atenção

      if (lista.length === 0) {
        return {
          error: modo === "remoto"
            ? "Este serviço não tem nenhuma pergunta marcada como respondível pelo cliente. Faça o levantamento no local."
            : "Este serviço ainda não tem perguntas de levantamento cadastradas. Monte o questionário na tela do serviço antes.",
        };
      }

      const { data: survey, error } = await sb
        .from("service_surveys")
        .insert({
          service_id: args.service_id,
          service_order_id: args.service_order_id ?? null,
          client_id: args.client_id ?? null,
          vessel_id: args.vessel_id ?? null,
          trigger_reason: args.trigger_reason,
          mode: modo,
          status: "draft",
          questions_planned: lista.length,
          created_by: userId,
        })
        .select("id")
        .single();
      if (error) throw error;

      return {
        survey_id: survey.id,
        modo,
        total_perguntas: lista.length,
        instrucao:
          "Faça UMA pergunta por vez, na ordem. Depois de cada resposta, grave com record_survey_answer e chame assess_survey_confidence para saber se já dá para orçar — não faça todas de enfiada.",
        perguntas: lista.map((q: any, i: number) => ({
          ordem: i + 1,
          template_id: q.id,
          pergunta: q.question,
          porque: q.help_text,
          tipo: q.answer_type,
          opcoes: q.options,
          impacto_no_preco: q.price_impact,
        })),
      };
    },
  },

  {
    name: "record_survey_answer",
    description:
      "Grava a resposta de uma pergunta do levantamento. 'Não sei' e 'não consegui ver' são respostas legítimas — registre com skipped_reason em vez de insistir ou inventar.",
    input_schema: {
      type: "object",
      properties: {
        survey_id: { type: "string" },
        seq: { type: "number", description: "Ordem da pergunta (1, 2, 3...)." },
        question: { type: "string", description: "Texto da pergunta, como foi feita." },
        answer: { type: "string", description: "Resposta do técnico ou do cliente." },
        template_id: { type: "string", description: "UUID da pergunta padrão, quando veio de uma." },
        skipped_reason: { type: "string", description: "Preencha quando não foi possível responder." },
      },
      required: ["survey_id", "seq", "question"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { error } = await sb.from("service_survey_answers").upsert(
        {
          survey_id: args.survey_id,
          template_id: args.template_id ?? null,
          seq: args.seq,
          question_snapshot: args.question,
          answer_value: args.answer ?? null,
          skipped_reason: args.skipped_reason ?? null,
        },
        { onConflict: "survey_id,seq" },
      );
      if (error) throw error;

      const { count } = await sb
        .from("service_survey_answers")
        .select("id", { count: "exact", head: true })
        .eq("survey_id", args.survey_id);

      await sb.from("service_surveys")
        .update({ questions_asked: count || 0, status: "answered" })
        .eq("id", args.survey_id);

      return { ok: true, respostas_ate_agora: count || 0 };
    },
  },

  {
    name: "assess_survey_confidence",
    description:
      "REGISTRA se você já consegue orçar com o que sabe, e por quê. Chame depois de CADA resposta. Se a confiança for 'alta', pare de perguntar — perguntar além do necessário piora o resultado e cansa quem responde. A justificativa é obrigatória: dizer 'ainda não sei o suficiente' sem dizer o que falta é o que produz pergunta ruim na sequência.",
    input_schema: {
      type: "object",
      properties: {
        survey_id: { type: "string" },
        confidence: {
          type: "string", enum: ["alta", "media", "baixa"],
          description: "'alta' = dá para orçar agora; 'media' = falta algo específico; 'baixa' = ainda no escuro.",
        },
        rationale: {
          type: "string",
          description: "O que você já sabe e o que ainda falta, em uma frase. Ex.: 'sei o acesso e o suporte, não sei se há inversor no barramento'.",
        },
      },
      required: ["survey_id", "confidence", "rationale"],
    },
    risk: "low",
    async execute(args, { sb }) {
      if (!args.rationale?.trim()) {
        return { error: "A justificativa é obrigatória — diga o que sabe e o que falta." };
      }
      const { error } = await sb
        .from("service_surveys")
        .update({ confidence: args.confidence, confidence_rationale: args.rationale.trim() })
        .eq("id", args.survey_id);
      if (error) throw error;

      return {
        ok: true,
        pode_parar: args.confidence === "alta",
        orientacao: args.confidence === "alta"
          ? "Pare de perguntar e feche o levantamento com close_service_survey."
          : "Faça a PRÓXIMA pergunta que reduz justamente o que você disse que falta — não a próxima da lista por ordem.",
      };
    },
  },

  {
    name: "close_service_survey",
    description:
      "Fecha o levantamento e devolve a estimativa por analogia (P50, P80 e contingência), com os casos anteriores que a sustentam. Se não houver histórico suficiente, diz isso em vez de inventar número.",
    input_schema: {
      type: "object",
      properties: { survey_id: { type: "string" } },
      required: ["survey_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: survey } = await sb
        .from("service_surveys")
        .select("id, service_id, confidence, confidence_rationale, questions_asked, questions_planned, mode")
        .eq("id", args.survey_id)
        .maybeSingle();
      if (!survey) return { error: "Levantamento não encontrado." };
      if (!survey.confidence) {
        return { error: "Antes de fechar, registre a confiança com assess_survey_confidence." };
      }

      const { data: est, error } = await sb.rpc("estimate_from_cases", { p_service_id: survey.service_id });
      if (error) throw error;
      const e = est as any;

      const { data: respostas } = await sb
        .from("service_survey_answers")
        .select("seq, question_snapshot, answer_value, skipped_reason")
        .eq("survey_id", args.survey_id)
        .order("seq");

      // Confiança baixa engorda a contingência: é o P18 — gordura dita, não escondida.
      const ajuste = survey.confidence === "baixa" ? 10 : survey.confidence === "media" ? 5 : 0;
      const contingencia = e.tem_base ? Number(e.contingencia_pct) + ajuste : null;

      await sb.from("service_surveys").update({
        status: "closed",
        estimated_minutes_p50: e.tem_base ? e.p50_min : null,
        estimated_minutes_p80: e.tem_base ? e.p80_min : null,
        contingency_pct: contingencia,
        cases_used: e.baseado_em ?? null,
        answered_at: new Date().toISOString(),
      }).eq("id", args.survey_id);

      return {
        ok: true,
        perguntas_feitas: `${survey.questions_asked ?? 0} de ${survey.questions_planned ?? 0} planejadas`,
        confianca: survey.confidence,
        porque: survey.confidence_rationale,
        estimativa: e.tem_base
          ? {
              provavel: formatarMinutos(e.p50_min),
              pior_caso: formatarMinutos(e.p80_min),
              contingencia_pct: contingencia,
              baseado_em: e.baseado_em,
              como_dizer: `Entre ${formatarMinutos(e.p50_min)} e ${formatarMinutos(e.p80_min)}, com base em ${e.casos} execução(ões) parecida(s).`,
            }
          : { sem_base: true, mensagem: e.mensagem },
        respostas,
        proximo_passo:
          "Monte o rascunho do orçamento com esses números e escreva a condição em português (ex.: 'valor válido para acesso pelo compartimento lateral; se for preciso remover o painel, revisamos').",
      };
    },
  },
];

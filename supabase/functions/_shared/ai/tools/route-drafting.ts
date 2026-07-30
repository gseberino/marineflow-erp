import type { ToolDef } from "./registry.ts";

// IA-1 — rascunho de roteiro a partir dos serviços já lançados na OS/orçamento.
// Plano: plans/marineflow-execucao-os-roteiro.md (P14, P26)
//
// Divisão de trabalho: estas tools NÃO chamam LLM. Elas dão o contexto e
// persistem o resultado — quem redige é o próprio agente, que já é o loop de
// modelo. Chamar modelo dentro de tool seria pagar duas vezes pela mesma coisa.
//
// O rascunho nasce com origin='ai' e approved_by nulo. A tela mostra esses
// passos separados, e cada aceite/descarte vira linha em ai_suggestion_reviews —
// que é o combustível da Fase 7.

export const routeDraftingTools: ToolDef[] = [
  {
    name: "get_route_drafting_context",
    description:
      "Reúne tudo que você precisa para REDIGIR o roteiro de uma OS: os serviços lançados, as peças, o problema relatado, o tipo de ativo e — o mais importante — os passos padrão que já existem no catálogo para esses serviços. Chame SEMPRE antes de propor passos. Se um serviço já tem template, use generate_service_order_route em vez de inventar.",
    input_schema: {
      type: "object",
      properties: { service_order_id: { type: "string", description: "UUID da OS ou do orçamento." } },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: so } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, problem_description, service_type, vessels(name, asset_type, engine_brand, engine_model), clients(name)")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (!so) return { error: "OS não encontrada." };

      const { data: linhas } = await sb
        .from("service_order_services")
        .select("id, service_id, name_snapshot, description_snapshot, quantity")
        .eq("service_order_id", args.service_order_id);

      const { data: pecas } = await sb
        .from("service_order_parts")
        .select("quantity, products(name)")
        .eq("service_order_id", args.service_order_id);

      const { data: jaTem } = await sb
        .from("service_order_steps")
        .select("id")
        .eq("service_order_id", args.service_order_id)
        .limit(1);

      // Para cada linha: já existe template? E como são os passos de serviços
      // parecidos — reusar o vocabulário da casa vale mais que redigir bonito.
      const comTemplate: any[] = [];
      const semTemplate: any[] = [];
      for (const l of linhas || []) {
        if (!l.service_id) {
          semTemplate.push({ linha_id: l.id, servico: l.name_snapshot, sem_vinculo_no_catalogo: true });
          continue;
        }
        const { data: tpl } = await sb
          .from("service_step_templates")
          .select("seq, block, title, standard_minutes")
          .eq("service_id", l.service_id)
          .eq("active", true)
          .order("seq");
        if ((tpl || []).length > 0) {
          comTemplate.push({ linha_id: l.id, servico: l.name_snapshot, passos_padrao: tpl!.length });
        } else {
          semTemplate.push({ linha_id: l.id, service_id: l.service_id, servico: l.name_snapshot, descricao: l.description_snapshot });
        }
      }

      // Vocabulário da casa: exemplos de passos já aprovados, para o rascunho
      // sair no mesmo tom em vez de parecer manual genérico.
      const { data: exemplos } = await sb
        .from("service_step_templates")
        .select("title, detail, block, kind, standard_minutes, services(name)")
        .eq("active", true)
        .not("approved_by", "is", null)
        .limit(15);

      return {
        os: so.service_order_number,
        status: so.status,
        ja_tem_roteiro: (jaTem || []).length > 0,
        cliente: (so as any).clients?.name,
        ativo: (so as any).vessels
          ? { nome: (so as any).vessels.name, tipo: (so as any).vessels.asset_type,
              motor: [(so as any).vessels.engine_brand, (so as any).vessels.engine_model].filter(Boolean).join(" ") || null }
          : null,
        problema_relatado: so.problem_description,
        linhas_com_template: comTemplate,
        linhas_sem_template: semTemplate,
        pecas: (pecas || []).map((p: any) => `${p.products?.name} x${p.quantity}`),
        exemplos_de_passos_aprovados: exemplos || [],
        como_proceder:
          comTemplate.length > 0 && semTemplate.length === 0
            ? "Todas as linhas têm passos padrão: chame generate_service_order_route e NÃO redija nada."
            : "Para as linhas COM template, chame generate_service_order_route primeiro. Para as SEM template, redija os passos e grave com save_drafted_route_steps.",
        regras_para_redigir: [
          "5 a 9 passos por serviço — acima disso ninguém segue.",
          "Título é verbo no imperativo e curto; o 'como' vai no detalhe.",
          "Passo de segurança (kind='safety') só quando há risco real: energia, gás, combustível, içamento, altura.",
          "NÃO invente torque, pressão, folga, tensão ou número de fabricante. Onde precisar, escreva 'conferir no manual' e marque requires_measure.",
          "Tempo é estimativa honesta: prefira redondo (15, 30, 45, 60) a falsa precisão.",
          "Use o vocabulário dos exemplos aprovados, não o de manual genérico.",
        ],
      };
    },
  },

  {
    name: "save_drafted_route_steps",
    description:
      "Grava os passos que VOCÊ redigiu como rascunho da IA, para o dono revisar. Eles aparecem separados na tela, marcados como sugestão, e só entram em uso quando alguém aprova. Use só para linhas de serviço SEM passos padrão no catálogo — quando há template, generate_service_order_route resolve.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        service_order_service_id: { type: "string", description: "UUID da linha de serviço a que estes passos pertencem." },
        source: { type: "string", description: "De onde tirou: 'descrição do serviço', 'peças lançadas', 'serviço parecido X'." },
        confidence: { type: "number", description: "0 a 1. Abaixo de 0,5 avise o dono que é chute com pouca base." },
        steps: {
          type: "array",
          description: "5 a 9 passos, na ordem de execução.",
          items: {
            type: "object",
            properties: {
              block: { type: "string", description: "Preparação | Execução | Fechamento" },
              title: { type: "string", description: "Verbo no imperativo, curto." },
              detail: { type: "string", description: "O 'como', quando ajuda. Opcional." },
              kind: { type: "string", enum: ["do", "check", "safety", "evidence", "handoff"] },
              standard_minutes: { type: "number" },
              is_killer: { type: "boolean", description: "Passo cujo esquecimento é caro." },
              requires_photo: { type: "boolean" },
              requires_measure: { type: "string", description: "ex.: tensao_v, corrente_a, torque_nm" },
              measure_unit: { type: "string" },
            },
            required: ["title"],
          },
        },
      },
      required: ["service_order_id", "steps"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const passos = (args.steps || []) as any[];
      if (passos.length === 0) return { error: "Nenhum passo enviado." };
      if (passos.length > 12) {
        return { error: "Passos demais. Roteiro acima de 9 passos por serviço não é seguido — agrupe ou divida em blocos." };
      }

      const { data: maxSeq } = await sb
        .from("service_order_steps")
        .select("seq")
        .eq("service_order_id", args.service_order_id)
        .order("seq", { ascending: false })
        .limit(1)
        .maybeSingle();
      let seq = (maxSeq?.seq as number) ?? 0;

      const linhas = passos.map((p) => ({
        service_order_id: args.service_order_id,
        service_order_service_id: args.service_order_service_id ?? null,
        seq: ++seq,
        block: p.block ?? "Roteiro",
        title: String(p.title).slice(0, 200),
        detail: p.detail ?? null,
        kind: p.kind ?? "do",
        mode: "do_confirm",
        standard_minutes: p.standard_minutes ?? null,
        is_killer: p.is_killer ?? false,
        requires_photo: p.requires_photo ?? false,
        requires_measure: p.requires_measure ?? null,
        measure_unit: p.measure_unit ?? null,
        origin: "ai",
        ai_confidence: args.confidence ?? null,
        ai_source: args.source ?? null,
      }));

      const { error } = await sb.from("service_order_steps").insert(linhas);
      if (error) throw error;

      // Instrumentação do aprendizado (Fase 7): o que foi proposto fica gravado
      // desde já, mesmo antes de existir quem consuma.
      await sb.from("ai_suggestion_reviews").insert({
        suggestion_type: "step",
        target_table: "service_order_steps",
        target_id: null,
        suggested: { passos: linhas.map((l) => ({ title: l.title, minutes: l.standard_minutes, kind: l.kind })) },
        verdict: "accepted",       // ainda não julgado; a revisão humana atualiza
        change_summary: `${linhas.length} passo(s) rascunhados para a OS`,
      });

      return {
        ok: true,
        passos_gravados: linhas.length,
        mensagem:
          "Rascunho salvo. Ele aparece na aba Roteiro marcado como sugestão e NÃO vale até alguém aprovar. " +
          (args.confidence !== undefined && args.confidence < 0.5
            ? "Avise que a confiança é baixa e por quê."
            : ""),
      };
    },
  },
];

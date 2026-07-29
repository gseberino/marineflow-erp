import type { ToolDef } from "./registry.ts";

// Roteiro de Execução da OS — o passo a passo que o técnico segue.
// Plano: plans/marineflow-execucao-os-roteiro.md
//
// Estas tools são PARA O TÉCNICO usar pelo WhatsApp, no mesmo espírito de
// field-ops.ts: nenhuma restrição de cargo e nenhuma exposição de preço, custo
// ou margem. Sem elas o agente conversa sobre uma OS sem saber que existe um
// roteiro — e diria "não há nada pendente" com passos abertos na tela.

const STATUS_PT: Record<string, string> = {
  pending: "a fazer",
  in_progress: "em execução",
  done: "feito",
  not_applicable: "não se aplica",
  blocked: "travado",
};

/** Minutos entre started_at e agora, somados ao que já estava acumulado. */
function tempoAcumulado(step: { actual_minutes: number | null; started_at: string | null }): number | null {
  const anterior = step.actual_minutes ?? 0;
  const emCurso = step.started_at
    ? Math.max(1, Math.round((Date.now() - new Date(step.started_at).getTime()) / 60000))
    : 0;
  const total = anterior + emCurso;
  return total > 0 ? total : null;
}

function formatarMinutos(min: number | null | undefined): string {
  if (min === null || min === undefined) return "—";
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m === 0 ? `${h}h` : `${h}h${String(m).padStart(2, "0")}`;
}

const STEP_COLS =
  "id, seq, block, title, detail, kind, mode, status, standard_minutes, actual_minutes, " +
  "started_at, is_killer, requires_photo, requires_measure, measure_unit, measure_value, " +
  "na_reason, blocked_reason_code, blocked_note, service_order_service_id";

export const routeOpsTools: ToolDef[] = [
  {
    name: "get_service_order_route",
    description:
      "Mostra o ROTEIRO de execução de uma OS: os passos, em que pé está cada um, o tempo previsto e o real, e qual é o próximo passo do técnico. Use quando perguntarem 'o que falta nessa OS', 'em que passo estamos', 'qual o próximo passo', ou antes de concluir/travar um passo (para saber o número certo).",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: so } = await sb
        .from("service_orders")
        .select("id, service_order_number, status")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (!so) return { error: "OS não encontrada." };

      const { data: steps, error } = await sb
        .from("service_order_steps")
        .select(STEP_COLS)
        .eq("service_order_id", args.service_order_id)
        .order("seq", { ascending: true });
      if (error) throw error;

      const lista = steps || [];
      if (lista.length === 0) {
        return {
          os: so.service_order_number,
          tem_roteiro: false,
          mensagem:
            "Esta OS ainda não tem roteiro. Dá para gerar a partir do catálogo com generate_service_order_route, se os serviços dela tiverem passos padrão cadastrados.",
        };
      }

      const feitos = lista.filter((s: any) => s.status === "done").length;
      const na = lista.filter((s: any) => s.status === "not_applicable").length;
      const travados = lista.filter((s: any) => s.status === "blocked");
      const proximo =
        lista.find((s: any) => s.status === "in_progress") ||
        lista.find((s: any) => s.status === "pending");

      const previsto = lista.reduce((t: number, s: any) => t + (s.standard_minutes || 0), 0);
      const real = lista.reduce((t: number, s: any) => t + (s.actual_minutes || 0), 0);

      return {
        os: so.service_order_number,
        tem_roteiro: true,
        progresso: `${feitos + na} de ${lista.length}`,
        tempo_previsto: formatarMinutos(previsto),
        tempo_real: formatarMinutos(real),
        travados: travados.map((s: any) => ({
          passo: s.seq,
          titulo: s.title,
          motivo: s.blocked_note || s.blocked_reason_code,
        })),
        proximo_passo: proximo
          ? {
              passo_id: proximo.id,
              numero: proximo.seq,
              bloco: proximo.block,
              titulo: proximo.title,
              detalhe: proximo.detail,
              seguranca: proximo.kind === "safety",
              critico: proximo.is_killer,
              pede_foto: proximo.requires_photo,
              pede_medicao: proximo.requires_measure
                ? `${proximo.requires_measure}${proximo.measure_unit ? ` (${proximo.measure_unit})` : ""}`
                : null,
              previsto: formatarMinutos(proximo.standard_minutes),
              ja_em_execucao: proximo.status === "in_progress",
            }
          : null,
        passos: lista.map((s: any) => ({
          passo_id: s.id,
          numero: s.seq,
          bloco: s.block,
          titulo: s.title,
          situacao: STATUS_PT[s.status] || s.status,
          previsto: formatarMinutos(s.standard_minutes),
          real: formatarMinutos(s.actual_minutes),
          observacao: s.na_reason || s.blocked_note || null,
        })),
      };
    },
  },

  {
    name: "generate_service_order_route",
    description:
      "Gera o roteiro de execução de uma OS a partir dos passos padrão cadastrados no catálogo de serviços. Idempotente: rodar de novo não duplica nada. Use quando a OS ainda não tem roteiro e o técnico ou o dono pedir para preparar o passo a passo.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.rpc("generate_service_order_steps", {
        p_service_order_id: args.service_order_id,
      });
      if (error) throw error;
      const criados = (data as number) ?? 0;
      if (criados > 0) return { ok: true, passos_criados: criados };

      const { count } = await sb
        .from("service_order_steps")
        .select("id", { count: "exact", head: true })
        .eq("service_order_id", args.service_order_id);

      return {
        ok: true,
        passos_criados: 0,
        mensagem:
          (count || 0) > 0
            ? "O roteiro já estava gerado."
            : "Nenhum serviço desta OS tem passos padrão cadastrados ainda — o roteiro precisa ser montado à mão na aba Roteiro.",
      };
    },
  },

  {
    name: "complete_service_order_step",
    description:
      "Marca um passo do roteiro como FEITO. Use quando o técnico disser 'terminei o passo X', 'já isolei os cabos', 'pronto, próximo'. Se o passo pedir medição, informe o valor. Não conclui a OS — só o passo.",
    input_schema: {
      type: "object",
      properties: {
        step_id: { type: "string", description: "UUID do passo (vem de get_service_order_route)." },
        measure_value: { type: "number", description: "Valor medido, quando o passo pede medição (ex.: tensão em volts)." },
        note: { type: "string", description: "Observação curta do técnico sobre o passo." },
      },
      required: ["step_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: step } = await sb
        .from("service_order_steps")
        .select("id, seq, title, status, actual_minutes, started_at, requires_measure, measure_unit, service_order_id, service_orders(status)")
        .eq("id", args.step_id)
        .maybeSingle();
      if (!step) return { error: "Passo não encontrado." };
      if ((step as any).service_orders?.status === "cancelled") {
        return { error: "Esta OS está cancelada — não dá para mexer no roteiro dela." };
      }
      if (step.status === "done") {
        return { ok: true, ja_feito: true, passo: step.seq, titulo: step.title };
      }
      if (step.requires_measure && args.measure_value === undefined) {
        return {
          error: `Este passo pede a medição de ${step.requires_measure}${step.measure_unit ? ` em ${step.measure_unit}` : ""}. Pergunte o valor ao técnico antes de concluir.`,
        };
      }

      const patch: Record<string, unknown> = {
        status: "done",
        completed_at: new Date().toISOString(),
        actual_minutes: tempoAcumulado(step),
        started_at: null,
      };
      if (args.measure_value !== undefined) patch.measure_value = args.measure_value;
      if (args.note) patch.notes = args.note;

      const { error } = await sb.from("service_order_steps").update(patch).eq("id", step.id);
      if (error) throw error;

      // Qual é o próximo — é o que o técnico quer ouvir em seguida.
      const { data: proximo } = await sb
        .from("service_order_steps")
        .select("id, seq, title, detail, kind, requires_photo")
        .eq("service_order_id", step.service_order_id)
        .in("status", ["pending", "in_progress"])
        .order("seq", { ascending: true })
        .limit(1)
        .maybeSingle();

      return {
        ok: true,
        passo_concluido: `${step.seq} — ${step.title}`,
        tempo_registrado: formatarMinutos(patch.actual_minutes as number | null),
        proximo_passo: proximo
          ? {
              passo_id: proximo.id,
              numero: proximo.seq,
              titulo: proximo.title,
              detalhe: proximo.detail,
              seguranca: proximo.kind === "safety",
              pede_foto: proximo.requires_photo,
            }
          : null,
        roteiro_terminou: !proximo,
      };
    },
  },

  {
    name: "block_service_order_step",
    description:
      "Marca um passo como TRAVADO, com o motivo. Use quando o técnico disser que não consegue seguir: falta peça, cliente ausente, sem acesso ao equipamento, clima, ferramenta faltando. O escritório precisa saber na hora — travar registra o motivo em vez de deixar o passo parado sem explicação.",
    input_schema: {
      type: "object",
      properties: {
        step_id: { type: "string", description: "UUID do passo." },
        reason_code: {
          type: "string",
          description:
            "Código do motivo. Um de: falta_peca, espera_cliente, espera_aprovacao, acesso_bloqueado, deslocamento, clima, equipamento, apoio_tecnico, retrabalho, pausa, outro.",
        },
        note: { type: "string", description: "Detalhe curto — ajuda quem vai destravar." },
      },
      required: ["step_id", "reason_code"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: motivo } = await sb
        .from("work_stop_reasons")
        .select("code, label")
        .eq("code", args.reason_code)
        .eq("active", true)
        .maybeSingle();
      if (!motivo) {
        const { data: opcoes } = await sb
          .from("work_stop_reasons")
          .select("code, label")
          .eq("active", true)
          .order("sort");
        return {
          error: "Motivo inválido.",
          motivos_validos: (opcoes || []).map((o: any) => `${o.code} = ${o.label}`),
        };
      }

      const { data: step } = await sb
        .from("service_order_steps")
        .select("id, seq, title, actual_minutes, started_at, service_order_id, service_orders(status)")
        .eq("id", args.step_id)
        .maybeSingle();
      if (!step) return { error: "Passo não encontrado." };
      if ((step as any).service_orders?.status === "cancelled") {
        return { error: "Esta OS está cancelada — não dá para mexer no roteiro dela." };
      }

      const { error } = await sb
        .from("service_order_steps")
        .update({
          status: "blocked",
          blocked_reason_code: motivo.code,
          blocked_note: args.note || null,
          // Fecha o trecho em curso: o tempo até travar é trabalho; o tempo
          // travado não é.
          actual_minutes: tempoAcumulado(step),
          started_at: null,
        })
        .eq("id", step.id);
      if (error) throw error;

      return {
        ok: true,
        passo_travado: `${step.seq} — ${step.title}`,
        motivo: motivo.label,
        mensagem: "Passo travado e motivo registrado. Siga para o próximo passo do roteiro, se houver.",
      };
    },
  },
];

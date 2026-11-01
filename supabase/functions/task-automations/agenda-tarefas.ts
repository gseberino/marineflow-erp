// Passo do motor de 15 min: a rodada das etapas da Agenda de Produção (as tarefas do dia; Fase 7c, P8 — 01/11/2026).
//
// Roda DEPOIS do material e ANTES da rotina da equipe, com o MESMO instante dela: a rotina manda a ficha das 19:30 e o "como foi" das
// 17:00, e o que cada um faz no dia já tem de estar congelado quando ela monta o texto. Chama agenda_tarefas_rodar (migration
// 20261102100550), que faz tudo no banco a CADA tique: sincroniza as etapas das OS com o orçamento e o roteiro, congela o plano de
// amanhã às 19:30 e o de hoje no 1º tique, confere o dia pela conferência do dono, faz as exceções ao dono (a ação de 2 dias pendente,
// as perguntas tarefa:prazo e tarefa:quem) e, uma vez por dia a partir de agenda_config.tarefas_hora (16:20), o diário. Com
// modo_tarefas desligado o banco devolve { rodou: false } — o normal até o dono ligar. Por isso o passo chama o banco a cada tique, sem
// ler o modo nem a hora.
//
// Nenhuma mensagem a ninguém daqui: a lista vai dentro da ficha e do "como foi" que a rotina já manda, e o que é do dono vai pelo
// fechamento e pelas perguntas da agenda.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:tarefas). O passo que
// falha NO BANCO já vai a app_error_logs lá (context agenda, action tarefas:<passo>) e os outros passos rodam. O código publicado antes
// da migration (a função ainda não existe: PGRST202/42883) é pulado calado — sem 96 linhas de erro por dia.
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O resumo quando a função da rodada das etapas ainda não está no banco (a migration 20261102100550 não foi aplicada). */
export const RODADA_DAS_TAREFAS_AUSENTE = "a migration 20261102100550 ainda não está no banco";

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

export interface ResultadoDaRodadaDasTarefas {
  /** Por que não rodou: a função agenda_tarefas_rodar ainda não existe no banco (o código publicado antes da migration). */
  pulado?: string;
  rodou?: boolean;
  /** agenda_config.modo_tarefas na hora da rodada. */
  modo?: string;
  contagens?: Record<string, unknown>;
  /** A rodada gravou a linha da rotina tarefas em agenda_vigia_rodadas (algum passo fez algo, falhou, ou o diário). */
  gravou?: boolean;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action tarefas:<passo>). */
  erros?: number;
  falhas?: unknown[];
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O passo da rodada das etapas no motor. Nunca lança. */
export async function tarefasDaAgenda(db: Db, agora: Date = new Date()): Promise<ResultadoDaRodadaDasTarefas> {
  try {
    const { data, error } = await db.rpc("agenda_tarefas_rodar", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) {
      // o código publicado antes da migration 20261102100550: a função ainda não existe — cala (sem uma linha em app_error_logs a
      // cada 15 min)
      if (funcaoAusente(error)) return { pulado: RODADA_DAS_TAREFAS_AUSENTE };
      throw error;
    }
    const v = (data ?? {}) as Record<string, unknown>;
    const modo = typeof v.modo === "string" ? v.modo : undefined;
    // desligado: o normal até o dono ligar (o banco não fez nada)
    if (v.rodou !== true) {
      return { rodou: false, ...(modo ? { modo } : {}) };
    }
    return {
      rodou: true,
      modo,
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
      gravou: v.gravou === true,
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
    };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:tarefas failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:tarefas",
      message: `rodada das etapas: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

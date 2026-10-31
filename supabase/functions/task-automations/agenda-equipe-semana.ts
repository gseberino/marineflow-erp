// Passo do motor de 15 min: a rodada da semana da equipe da Agenda de Produção (Fase 7b, P3 — 31/10/2026).
//
// Roda DEPOIS da rotina da equipe (0b: a ficha, a confirmação e o "como foi" do dia já registrados — a pergunta da semana conta
// com eles no teto de 2 por dia) e ANTES do aprendizado (0b2). Chama agenda_equipe_semana (migration 20261101100200), que faz
// tudo no banco e decide sozinha o QUE e QUANDO: a regra d14 (no dia do plano), a chamada da equipe, o telefone e o contato (uma
// vez por dia a partir de agenda_config.equipe_hora_dias, 16:45), o prazo da chamada depois de vista, o fechamento da semana cujo
// prazo passou e a pergunta dos dias (da quinta até pode_perguntar_ate; ao dono só na quinta e só quando faz diferença). Com
// modo_dias e modo_cadastro desligados o banco devolve { rodou: false } — o normal até o dado de sombra (20261101100900). Por
// isso o passo chama o banco a CADA tique, sem ler o modo nem a hora.
//
// Nada sai daqui: a mensagem à equipe é registrada e enfileirada pelo banco (_agenda_equipe_registrar, na janela, no teto do dia
// e com a trava da fila), e as perguntas ao dono chegam pelo fechamento (a linha da equipe).
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:equipe-semana). O
// passo que falha NO BANCO já vai a app_error_logs lá (context agenda, action equipe_semana:<passo>) e os outros passos rodam. O
// código publicado antes da migration (a função ainda não existe: PGRST202/42883) é pulado calado — sem 96 linhas de erro por dia.
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O resumo quando a função da rodada da semana ainda não está no banco (a migration 20261101100200 não foi aplicada). */
export const RODADA_DA_SEMANA_AUSENTE = "a migration 20261101100200 ainda não está no banco";

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

export interface ResultadoDaRodadaDaSemana {
  /** Por que não rodou: a função agenda_equipe_semana ainda não existe no banco (o código publicado antes da migration). */
  pulado?: string;
  rodou?: boolean;
  /** agenda_config.modo_dias e modo_cadastro na hora da rodada. */
  modos?: Record<string, unknown>;
  contagens?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action equipe_semana:<passo>). */
  erros?: number;
  falhas?: unknown[];
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O passo da rodada da semana da equipe no motor. Nunca lança. */
export async function rodarSemanaDaEquipe(db: Db, agora: Date = new Date()): Promise<ResultadoDaRodadaDaSemana> {
  try {
    const { data, error } = await db.rpc("agenda_equipe_semana", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) {
      // o código publicado antes da migration 20261101100200: a função ainda não existe — cala (sem uma linha em
      // app_error_logs a cada 15 min)
      if (funcaoAusente(error)) return { pulado: RODADA_DA_SEMANA_AUSENTE };
      throw error;
    }
    const v = (data ?? {}) as Record<string, unknown>;
    const modos = v.modos && typeof v.modos === "object" ? (v.modos as Record<string, unknown>) : undefined;
    // os dois modos desligados: o normal (o banco não fez nada)
    if (v.rodou !== true) return { rodou: false, ...(modos ? { modos } : {}) };
    return {
      rodou: true,
      modos,
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
    };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:equipe-semana failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:equipe-semana",
      message: `rodada da semana da equipe: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

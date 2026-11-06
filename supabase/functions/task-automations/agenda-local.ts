// Passo do motor de 15 min: a rodada do local da Agenda de Produção (Fase 7d, P5 — 05/11/2026).
//
// Roda DEPOIS do aprendizado (0b2) e de quem faz o quê (0b2a) e ANTES da vigia (0c): a vigia lê, no mesmo tique, o que foi combinado. Chama
// agenda_local_vigiar (migration 20261107100400), que faz tudo no banco e decide sozinha QUANDO roda: uma vez por dia, no 1º tique a partir de
// agenda_config.local_hora (16:15). Antes disso o banco devolve { rodou: false, cedo: true }; nos tiques seguintes do mesmo dia, { rodou: false,
// ja_rodou: true }; com os 6 modos desligados, { rodou: false }: as três são o normal. Por isso o passo chama o banco a CADA tique, sem ler o modo nem a hora.
//
// O que a rodada faz (tudo no banco, IA nenhuma): tira o dia que o local não recebe (só com o calendário ligado), cobra o que falta combinar (o acesso,
// a vaga na garagem seca, a descida e a entrada no pátio) e conta o que a 7d tiraria. Com *gestor, só propor*, ela só lê e grava "Em teste". As perguntas
// chegam ao dono pelo fechamento e pela conversa. Nenhuma mensagem a ninguém daqui: nem à equipe, nem ao cliente.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:local). O passo que falha NO BANCO já vai a
// app_error_logs lá (context agenda, action local:<passo>) e os outros passos rodam. O código publicado antes da migration (a função ainda não existe:
// PGRST202/42883) é pulado calado — sem 96 linhas de erro por dia.
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O resumo quando a função da rodada do local ainda não está no banco (a migration 20261107100400 não foi aplicada). */
export const RODADA_DO_LOCAL_AUSENTE = "a migration 20261107100400 ainda não está no banco";

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

export interface ResultadoDaRodadaDoLocal {
  /** Por que não rodou: a função agenda_local_vigiar ainda não existe no banco (o código publicado antes da migration). */
  pulado?: string;
  rodou?: boolean;
  /** Antes de agenda_config.local_hora: o normal até as 16:15. */
  cedo?: boolean;
  /** A rodada de hoje já rodou: o normal depois do 1º tique das 16:15. */
  ja_rodou?: boolean;
  /** Os 6 modos do local, os efetivos (com *gestor, só propor*, ligado vale sombra). */
  modos?: Record<string, unknown>;
  contagens?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action local:<passo>). */
  erros?: number;
  falhas?: unknown[];
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O passo da rodada do local no motor. Nunca lança. */
export async function localDaAgenda(db: Db, agora: Date = new Date()): Promise<ResultadoDaRodadaDoLocal> {
  try {
    const { data, error } = await db.rpc("agenda_local_vigiar", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) {
      // o código publicado antes da migration 20261107100400: a função ainda não existe — cala (sem uma linha em app_error_logs a cada 15 min)
      if (funcaoAusente(error)) return { pulado: RODADA_DO_LOCAL_AUSENTE };
      throw error;
    }
    const v = (data ?? {}) as Record<string, unknown>;
    const modos = v.modos && typeof v.modos === "object" ? (v.modos as Record<string, unknown>) : undefined;
    // antes da hora, o 2º tique do dia e os 6 desligados: o normal (o banco não fez nada)
    if (v.rodou !== true) {
      return {
        rodou: false,
        ...(v.cedo === true ? { cedo: true } : {}),
        ...(v.ja_rodou === true ? { ja_rodou: true } : {}),
        ...(modos ? { modos } : {}),
      };
    }
    return {
      rodou: true,
      modos,
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
    };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:local failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:local",
      message: `rodada do local: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

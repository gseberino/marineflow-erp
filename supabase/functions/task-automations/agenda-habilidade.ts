// Passo do motor de 15 min: a rodada de quem faz o quê da Agenda de Produção (Fase 7c, P5 — 01/11/2026).
//
// Roda DEPOIS do aprendizado (0b2) e ANTES da vigia (0c): a vigia, o motor e o aviso do mesmo tique já leem a etiqueta que acabou de
// valer. Chama agenda_habilidade (migration 20261102100400), que faz tudo no banco e decide sozinha QUANDO roda: uma vez por dia, no
// 1º tique a partir de agenda_config.habilidade_hora (16:10, o tique das 16:15). Antes disso o banco devolve { rodou: false, cedo:
// true }; nos tiques seguintes do mesmo dia, { rodou: false, ja_rodou: true }: as duas são o normal (95 dos 96 tiques do dia). Por
// isso o passo chama o banco a CADA tique, sem ler o modo nem a hora.
//
// O que a rodada faz (tudo no banco, IA nenhuma): propõe o que cada pessoa faz pelo histórico e pelo que o dono declarou (uma pergunta
// só, que chega ao dono pela linha da equipe do fechamento), deixa valer a proposta que passou do prazo depois de vista, confere em
// teste o publicado com as regras de quem faz o quê, pergunta ao dono quando ninguém com o que o serviço pede fica livre (só ligado) e
// mede. Nenhuma mensagem a ninguém daqui: nem à equipe, nem ao cliente.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:habilidade). O passo que
// falha NO BANCO já vai a app_error_logs lá (context agenda, action habilidade:<passo>) e os outros passos rodam. O código publicado
// antes da migration (a função ainda não existe: PGRST202/42883) é pulado calado — sem 96 linhas de erro por dia.
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O resumo quando a função da rodada de quem faz o quê ainda não está no banco (a migration 20261102100400 não foi aplicada). */
export const RODADA_DA_HABILIDADE_AUSENTE = "a migration 20261102100400 ainda não está no banco";

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

export interface ResultadoDaRodadaDaHabilidade {
  /** Por que não rodou: a função agenda_habilidade ainda não existe no banco (o código publicado antes da migration). */
  pulado?: string;
  rodou?: boolean;
  /** Antes de agenda_config.habilidade_hora: o normal até as 16:10. */
  cedo?: boolean;
  /** A rodada de hoje já rodou: o normal depois do 1º tique das 16:10. */
  ja_rodou?: boolean;
  /** agenda_config.modo_habilidade, modo_lider e modo_habilidade_propor na hora da rodada. */
  modos?: Record<string, unknown>;
  contagens?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action habilidade:<passo>). */
  erros?: number;
  falhas?: unknown[];
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O passo da rodada de quem faz o quê no motor. Nunca lança. */
export async function habilidadeDaAgenda(db: Db, agora: Date = new Date()): Promise<ResultadoDaRodadaDaHabilidade> {
  try {
    const { data, error } = await db.rpc("agenda_habilidade", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) {
      // o código publicado antes da migration 20261102100400: a função ainda não existe — cala (sem uma linha em app_error_logs a
      // cada 15 min)
      if (funcaoAusente(error)) return { pulado: RODADA_DA_HABILIDADE_AUSENTE };
      throw error;
    }
    const v = (data ?? {}) as Record<string, unknown>;
    const modos = v.modos && typeof v.modos === "object" ? (v.modos as Record<string, unknown>) : undefined;
    // antes da hora e o 2º tique do dia: o normal (o banco não fez nada)
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
    console.error("agenda:habilidade failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:habilidade",
      message: `rodada de quem faz o quê: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

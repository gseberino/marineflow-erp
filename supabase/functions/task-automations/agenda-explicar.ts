// Passo do motor de 15 min: a rodada explicar da Agenda de Produção (Fase 7g, P5 — 12/11/2026).
//
// Roda DEPOIS da rodada do cliente e ANTES da rodada comunicar (spec-fase7g R9.5-21: o placar do dia do plano fica guardado antes da mensagem da quinta).
// Chama agenda_explicar_rodar (migration 20261112100400), que faz tudo no banco e decide sozinha QUANDO roda: uma vez por dia, no 1º tique a partir de
// agenda_config.explicar_hora (16:35). Antes disso o banco devolve { rodou: false, cedo: true }; nos tiques seguintes do mesmo dia, { rodou: false,
// ja_rodou: true }; no domingo, { rodou: false, domingo: true }; com os modos da etapa desligados, { rodou: false, desligado: true }: todas são o normal.
// Por isso o passo chama o banco a CADA tique, sem ler o modo nem a hora.
//
// O que a rodada faz (tudo no banco, IA nenhuma): registra as marcações que a agenda fez e decide o que aconteceu com as do gestor (o dono desfez, ajustou,
// o gestor remarcou, a OS saiu, ou o 1º dia chegou); calcula, por tipo de OS, o que o rebaixar faria (só em teste: nada muda); e, no dia do plano, o placar
// (quando existir, P6). Nenhuma mensagem a ninguém daqui.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:explicar).
// O passo que falha NO BANCO já vai a app_error_logs lá (context agenda, action explicar:<passo>) e os outros passos rodam.
// O código publicado antes da migration (a função ainda não existe: PGRST202/42883) é pulado calado — sem 96 linhas de erro por dia.
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O resumo quando a função da rodada explicar ainda não está no banco (a migration 20261112100400 não foi aplicada). */
export const RODADA_EXPLICAR_AUSENTE = "a migration 20261112100400 ainda não está no banco";

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

export interface ResultadoDaRodadaExplicar {
  /** Por que não rodou: a função agenda_explicar_rodar ainda não existe no banco (o código publicado antes da migration). */
  pulado?: string;
  rodou?: boolean;
  /** Os modos da etapa (o porquê, o rebaixar e o placar) desligados: nada a fazer. */
  desligado?: boolean;
  /** Domingo: nada. */
  domingo?: boolean;
  /** Antes de agenda_config.explicar_hora: o normal até as 16:35. */
  cedo?: boolean;
  /** A rodada de hoje já rodou: o normal depois do 1º tique das 16:35. */
  ja_rodou?: boolean;
  /** Nenhum passo a rodar hoje (só o placar ligado, fora do dia do plano). */
  nada?: boolean;
  contagens?: Record<string, unknown>;
  modos?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action explicar:<passo>). */
  erros?: number;
  falhas?: unknown[];
  /** O passo em que a rodada parou (o tempo acabou): o resto fica para amanhã. */
  parou_no?: string;
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O passo da rodada explicar no motor. Nunca lança. */
export async function explicarDaAgenda(db: Db, agora: Date = new Date()): Promise<ResultadoDaRodadaExplicar> {
  try {
    const { data, error } = await db.rpc("agenda_explicar_rodar", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) {
      // o código publicado antes da migration 20261112100400: a função ainda não existe — cala (sem uma linha em app_error_logs a cada 15 min)
      if (funcaoAusente(error)) return { pulado: RODADA_EXPLICAR_AUSENTE };
      throw error;
    }
    const v = (data ?? {}) as Record<string, unknown>;
    // desligado, domingo, antes da hora, o 2º tique do dia e nenhum passo: o normal (o banco não fez nada)
    if (v.rodou !== true) {
      return {
        rodou: false,
        ...(v.desligado === true ? { desligado: true } : {}),
        ...(v.domingo === true ? { domingo: true } : {}),
        ...(v.cedo === true ? { cedo: true } : {}),
        ...(v.ja_rodou === true ? { ja_rodou: true } : {}),
        ...(v.nada === true ? { nada: true } : {}),
      };
    }
    return {
      rodou: true,
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
      modos: (v.modos ?? undefined) as Record<string, unknown> | undefined,
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
      ...(typeof v.parou_no === "string" ? { parou_no: v.parou_no } : {}),
    };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:explicar failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:explicar",
      message: `rodada explicar: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

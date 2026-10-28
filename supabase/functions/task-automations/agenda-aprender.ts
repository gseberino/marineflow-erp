// Passo do motor de 15 min: a rodada do aprendizado da Agenda de Produção (Fase 6, P8 — 28/10/2026).
//
// Roda DEPOIS da rotina da equipe (a medida lê a conferência do dia já em dia) e ANTES da vigia (a vigia, o motor e a rodada
// do cliente leem, no mesmo tique, o que a rodada aprendeu). Chama agenda_aprender (migration 20261029100600), que faz tudo
// no banco e decide sozinha QUANDO roda: uma vez por dia, no 1º tique a partir de agenda_config.aprender_hora (16:00). Antes
// disso o banco devolve { rodou: false, cedo: true }; nos tiques seguintes do mesmo dia, { rodou: false, ja_rodou: true }:
// as duas são o normal (95 dos 96 tiques do dia). Por isso o passo chama o banco a CADA tique, sem ler o modo nem a hora.
//
// O que a rodada faz (tudo no banco, IA nenhuma): congela os dias que o dono disse no início da OS e mede a OS que concluiu
// — SEMPRE, até com modo_aprendizado desligado —; com o modo fora de desligado, calcula o fator de campo, o R$ por diária, a
// presença do dono, os fornecedores, a capacidade do dono e o cliente (e, no dia do plano, a revisão da carga e os gatilhos
// de um planejador mais forte). O que é usado só muda com o modo ligado e o item na lista (o OK do dono); a troca pequena
// vira ação no "o que mudou" (com *desfaz aprendizado*), a grande vira pergunta crítica. Nenhuma mensagem a ninguém daqui.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:aprender).
// O passo que falha NO BANCO já vai a app_error_logs lá (context agenda, action aprender:<passo>) e os outros passos rodam.
// O código publicado antes da migration (a função ainda não existe: PGRST202/42883) é pulado calado — sem 96 linhas de erro
// por dia (o molde do passo do cliente, correção C2 da Fase 5).
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O resumo quando a função da rodada do aprendizado ainda não está no banco (a migration 20261029100600 não foi aplicada). */
export const RODADA_DO_APRENDIZADO_AUSENTE = "a migration 20261029100600 ainda não está no banco";

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

export interface ResultadoDaRodadaDoAprendizado {
  /** Por que não rodou: a função agenda_aprender ainda não existe no banco (o código publicado antes da migration). */
  pulado?: string;
  rodou?: boolean;
  /** Antes de agenda_config.aprender_hora: o normal até as 16:00. */
  cedo?: boolean;
  /** A rodada de hoje já rodou: o normal depois do 1º tique das 16:00. */
  ja_rodou?: boolean;
  /** agenda_config.modo_aprendizado na hora da rodada. */
  modo?: string;
  /** agenda_config.aprendizado_ligados (os itens com o OK do dono). */
  ligados?: string[];
  /** A revisão da carga e os gatilhos rodaram (o dia do plano). */
  semanal?: boolean;
  contagens?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action aprender:<passo>). */
  erros?: number;
  falhas?: unknown[];
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O passo da rodada do aprendizado no motor. Nunca lança. */
export async function aprenderDaAgenda(db: Db, agora: Date = new Date()): Promise<ResultadoDaRodadaDoAprendizado> {
  try {
    const { data, error } = await db.rpc("agenda_aprender", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) {
      // o código publicado antes da migration 20261029100600: a função ainda não existe — cala (sem uma linha em
      // app_error_logs a cada 15 min)
      if (funcaoAusente(error)) return { pulado: RODADA_DO_APRENDIZADO_AUSENTE };
      throw error;
    }
    const v = (data ?? {}) as Record<string, unknown>;
    const modo = typeof v.modo === "string" ? v.modo : undefined;
    // antes da hora e o 2º tique do dia: o normal (o banco não fez nada)
    if (v.rodou !== true) {
      return {
        rodou: false,
        ...(v.cedo === true ? { cedo: true } : {}),
        ...(v.ja_rodou === true ? { ja_rodou: true } : {}),
        ...(modo ? { modo } : {}),
      };
    }
    return {
      rodou: true,
      modo,
      ligados: Array.isArray(v.ligados) ? v.ligados.filter((t): t is string => typeof t === "string") : undefined,
      semanal: v.semanal === true,
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
    };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:aprender failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:aprender",
      message: `rodada do aprendizado: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

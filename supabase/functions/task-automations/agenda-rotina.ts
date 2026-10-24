// Passo do motor de 15 min: a rotina da equipe e da diária da Agenda de Produção (Fase 3, P4 — 24/10/2026).
//
// Roda logo ANTES da vigia (index.ts): agenda_rotina_rodar (migration 20261026100300) manda a ficha da véspera às 19:30,
// a confirmação das 07:45 (só a quem não respondeu OK), remaneja pelo silêncio até as 9h, pergunta "como foi hoje?" às
// 17:00, lança a diária quando a resposta e o plano batem e conclui a OS quando o técnico disse que terminou no último
// dia. TUDO o que vai à equipe é decidido no banco (modo_equipe, a janela 07:30–20:00, nunca domingo, o teto de 2 por dia,
// a lista de quem recebe) e entra na fila de sempre (whatsapp_send_queue); aqui nada é enviado à equipe. Com modo_equipe
// e modo_diaria em 'desligado' (produção hoje) o banco devolve {rodou: false} e nada acontece; em 'sombra' nada sai.
//
// Os acordes ("o Roberto não respondeu até as 9h: mudei a agenda de hoje") vão ao dono pelo MESMO envio da vigia
// (enviarAcordesDaAgenda: o portão da voz única, a janela 08–20h, a chave agenda:<ação>, a cota acordes_dia_max).
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:rotina).
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { acordesValidos, type DepsDaVigia, enviarAcordesDaAgenda, type ResultadoDosAcordesDaAgenda } from "./agenda-vigia.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface ResultadoDaRotina {
  rodou?: boolean;
  modos?: { proposta?: string; vigia?: string; equipe?: string; diaria?: string };
  erros?: number;
  falhas?: unknown[];
  contagens?: Record<string, unknown>;
  acordes?: ResultadoDosAcordesDaAgenda;
  /** a rotina inteira falhou */
  erro?: string;
}

/** O passo da rotina no motor. Nunca lança. `deps` só no teste (o portão e o dono do envio dos acordes). */
export async function rodarRotinaDaAgenda(db: Db, agora: Date = new Date(), deps?: DepsDaVigia): Promise<ResultadoDaRotina> {
  try {
    const { data, error } = await db.rpc("agenda_rotina_rodar", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) throw error;
    const v = (data ?? {}) as Record<string, unknown>;
    const resultado: ResultadoDaRotina = {
      rodou: v.rodou === true,
      modos: (v.modos ?? undefined) as ResultadoDaRotina["modos"],
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
    };
    // o banco só devolve acorde com a vigia ligada e a ação executada (em sombra, nunca)
    const acordes = acordesValidos(v.acordes);
    if (acordes.length) resultado.acordes = await enviarAcordesDaAgenda(db, acordes, agora, deps);
    return resultado;
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:rotina failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:rotina",
      message: `rotina da agenda: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

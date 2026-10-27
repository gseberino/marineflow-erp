// Passo do motor de 15 min: a rodada da mensagem ao cliente da Agenda de Produção (Fase 5, P3 — 27/10/2026).
//
// Roda DEPOIS da vigia (index.ts: a rodada lê o plano já replanejado no mesmo tique) e ANTES das regras (a R15 lê o modo
// do cliente). Chama agenda_cliente_vigiar (migration 20261028100300), que faz tudo no banco: antes de tudo, em qualquer
// modo, o passo "fila" (o que ficou velho na fila do cliente não sai; o que é hora de mandar vai à fila); com
// modo_cliente fora de desligado, os passos que decidem QUAL mensagem-modelo vai a QUEM e QUANDO (a confirmação, a véspera
// ou o acesso, o material chegou, o aviso de atraso, a mudança no dia, o andamento, o "ficou pronto", o pós-serviço, o
// "não respondeu"). TUDO o que vai ao cliente é decidido no banco (o texto do modelo, o modo e as ondas, a aprovação dos 3
// primeiros dias, a janela, o feriado, o teto, o intervalo, a revalidação) e entra na fila de sempre (source
// agenda-cliente), com a trava do gatilho da fila e a do worker; aqui nada é enviado ao cliente.
//
// Por isso o passo chama o banco SEMPRE (até com tudo desligado): é o passo "fila" que faz o "parar tudo na hora" valer no
// tique seguinte (spec-fase5 §10).
//
// Os acordes ("o aviso de atraso do Nelson precisa de você hoje", "o Nelson esperava a equipe amanhã: a decisão está com
// você") vão ao dono pelo MESMO envio da vigia (enviarAcordesDaAgenda: o portão da voz única, a janela 08–20h, a chave
// agenda:<ação>, a cota acordes_dia_max) — o banco só os devolve com a vigia ligada e a ação executada.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations,
// agenda:cliente-vigia). O passo que falha NO BANCO já vai a app_error_logs lá (context agenda, action cliente:<passo>) e
// os outros passos rodam.
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { acordesValidos, type DepsDaVigia, enviarAcordesDaAgenda, type ResultadoDosAcordesDaAgenda } from "./agenda-vigia.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface ResultadoDaRodadaDoCliente {
  rodou?: boolean;
  /** agenda_config.modo_cliente na hora da rodada. */
  modo?: string;
  /** agenda_config.cliente_tipos_ligados (as ondas). */
  tipos_ligados?: string[];
  contagens?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action cliente:<passo>). */
  erros?: number;
  falhas?: unknown[];
  acordes?: ResultadoDosAcordesDaAgenda;
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O passo da rodada do cliente no motor. Nunca lança. `deps` só no teste (o portão e o dono do envio dos acordes). */
export async function vigiarClienteDaAgenda(db: Db, agora: Date = new Date(), deps?: DepsDaVigia): Promise<ResultadoDaRodadaDoCliente> {
  try {
    const { data, error } = await db.rpc("agenda_cliente_vigiar", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) throw error;
    const v = (data ?? {}) as Record<string, unknown>;
    const resultado: ResultadoDaRodadaDoCliente = {
      rodou: v.rodou === true,
      modo: typeof v.modo === "string" ? v.modo : undefined,
      tipos_ligados: Array.isArray(v.tipos_ligados) ? v.tipos_ligados.filter((t): t is string => typeof t === "string") : undefined,
      // desligado: o banco devolve só o passo "fila" (que roda sempre)
      contagens: (v.contagens ?? (v.fila !== undefined ? { fila: v.fila } : undefined)) as Record<string, unknown> | undefined,
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
    };
    // o banco só devolve acorde com a vigia ligada e a ação executada (em sombra, nunca)
    const acordes = acordesValidos(v.acordes);
    if (acordes.length) resultado.acordes = await enviarAcordesDaAgenda(db, acordes, agora, deps);
    return resultado;
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:cliente-vigia failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:cliente-vigia",
      message: `rodada do cliente: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

// Passo do motor de 15 min: o aviso do gestor da agenda ao dono (Agenda de Produção, correção de 29/10, P4).
//
// Roda logo DEPOIS da vigia (agenda-vigia.ts), com o MESMO instante dela (a rodada: uma mensagem por rodada). O dono decidiu
// (29/10) que o gestor cuida da agenda sozinho e todo dia, e ele só quer saber o que mudou: quando a vigia publica a semana,
// encaixa uma OS, promove ou solta uma reserva ou remaneja, sai UMA mensagem com o que mudou (quem vai, os dias), o que ficou
// de fora e por quê, e no fim as perguntas que destravam (a rodada de aprontar, uma vez por dia). Três RPCs da migration
// 20261030100300, nesta ordem:
//   1. agenda_aviso_conferir — o que a fila fez com os avisos anteriores: o que saiu passa a contar de verdade (a ação na hora
//      do envio, o prazo do *desfaz* a partir dali, a pergunta como mostrada); o que não saiu volta a "por contar";
//   2. agenda_aviso_pecas — o que contar (sem gravar). Fora da janela (gestor_aviso_inicio a gestor_aviso_fim, nunca no
//      domingo), no teto do dia (gestor_aviso_dia_max) ou sem nada novo, não avisa: o que mudou espera e sai junto na abertura
//      da janela. Fora de 'ligado' (a agenda automática ou a vigia), nada;
//   3. agenda_aviso_enfileirar — a 1ª trava (de novo o modo, a janela, o teto, o dono e as ações por contar) e a fila
//      (source agenda-dono). A 2ª trava é o gatilho da fila no banco; a 3ª, o worker (_shared/agenda/janela-da-fila.ts).
// O texto é montado em _shared/agenda/aviso-do-gestor.ts com as peças do banco (as datas, os nomes e os textos vêm prontos).
// Depois de enfileirar, o aviso entra no histórico da conversa do assistente (o dono responde às perguntas: "o Lenine não tem
// peça, 3 dias com o João"), como o fechamento faz.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:aviso).
import { diaBR } from "../_shared/agenda-dia.ts";
import { lerPecasDoAviso, montarAvisoDoGestor } from "../_shared/agenda/aviso-do-gestor.ts";
import { resolveOrCreateWhatsAppSession } from "../_shared/ai/whatsapp-channel.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { horaBR } from "../_shared/pdf/datas.ts";
import { lerDonoDaVoz } from "../_shared/uma-voz/registrar.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface ResultadoDoAviso {
  /** o que a fila fez com os avisos de antes */
  conferido?: { enviados: number; recusados: number; devolvidas: number };
  avisou?: boolean;
  /** por que não avisou (modo, desligado, nada_mudou, fora_da_janela, teto, sem_dono, ja_existe, mudou, recusada…) */
  motivo?: string;
  /** o que espera a janela abrir (ou o dia seguinte, no teto) */
  pendentes?: number | null;
  aviso?: {
    id: string | null;
    fila_id: string | null;
    mudancas: number;
    perguntas: number;
    caracteres: number;
    cortes: string[];
  };
  historico?: boolean;
  /** o passo inteiro falhou */
  erro?: string;
}

/** O que o passo faz fora do banco (injetável no teste). */
export interface DepsDoAviso {
  historico: (db: Db, texto: string, agora: Date) => Promise<boolean>;
}

const MARCA_DO_HISTORICO = (hora: string) =>
  `[Mensagem automática do sistema, não é do dono] Às ${hora} o gestor da agenda mandou para o WhatsApp do dono o aviso ` +
  "abaixo, com o que ele mudou sozinho na agenda (a entrega não é confirmada aqui: se ele disser que não chegou, é possível). " +
  "Se o dono responder às perguntas do fim (a peça, os dias, com quem), as respostas são deste aviso.";

/** O par do histórico do assistente (a marca do sistema + o aviso), como o fechamento grava. Nunca lança. */
export async function historicoDoAviso(db: Db, texto: string, agora: Date): Promise<boolean> {
  try {
    const dono = await lerDonoDaVoz(db);
    if (!dono) return false;
    const sessao = await resolveOrCreateWhatsAppSession(db, dono.phone, dono.id);
    const t0 = Date.now();
    const { error } = await db.from("ai_operator_messages").insert([
      { session_id: sessao, role: "user", source: "system", created_at: new Date(t0).toISOString(), content: MARCA_DO_HISTORICO(horaBR(agora)) },
      { session_id: sessao, role: "assistant", source: "system", created_at: new Date(t0 + 1).toISOString(), content: texto },
    ]);
    if (error) throw error;
    await db.from("ai_operator_sessions").update({ last_activity_at: new Date().toISOString() }).eq("id", sessao);
    return true;
  } catch (e) {
    console.warn("[agenda:aviso] aviso fora do histórico do assistente:", (e as Error)?.message ?? e);
    return false;
  }
}

const DEPS: DepsDoAviso = { historico: historicoDoAviso };

function numero(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** O passo do aviso no motor. Nunca lança. */
export async function avisarDonoDaAgenda(db: Db, agora: Date = new Date(), deps: DepsDoAviso = DEPS): Promise<ResultadoDoAviso> {
  try {
    const p_agora = agora.toISOString();
    const p_hoje = diaBR(agora.getTime());
    const c = await db.rpc("agenda_aviso_conferir", { p_agora });
    if (c.error) throw c.error;
    const cd = (c.data ?? {}) as Record<string, unknown>;
    const r: ResultadoDoAviso = {
      conferido: { enviados: numero(cd.enviados), recusados: numero(cd.recusados), devolvidas: numero(cd.devolvidas) },
    };

    const p = await db.rpc("agenda_aviso_pecas", { p_hoje, p_agora });
    if (p.error) throw p.error;
    const lidas = lerPecasDoAviso(p.data);
    if (!lidas) throw new Error("agenda_aviso_pecas devolveu um formato que o montador não conhece");
    if (!lidas.avisar) return { ...r, avisou: false, motivo: lidas.motivo, pendentes: lidas.pendentes };
    if (lidas.pecas.perguntasErro) {
      // a rodada de aprontar falhou no banco: o que mudou sai do mesmo jeito, sem as perguntas, e o erro fica consultável
      await logEdgeError(db, {
        context: "task-automations",
        action: "agenda:aviso",
        level: "warn",
        message: `aviso do gestor da agenda: saiu sem as perguntas (a rodada de aprontar falhou: ${lidas.pecas.perguntasErro})`,
      });
    }
    const m = montarAvisoDoGestor(lidas.pecas);
    if (!m) return { ...r, avisou: false, motivo: "nada_a_contar" };

    const e = await db.rpc("agenda_aviso_enfileirar", {
      p_texto: m.texto, p_acao_ids: m.acaoIds, p_pergunta_ids: m.perguntaIds, p_com_perguntas: m.comPerguntas, p_hoje, p_agora,
    });
    if (e.error) throw e.error;
    const d = (e.data ?? {}) as Record<string, unknown>;
    if (d.enfileirou !== true) return { ...r, avisou: false, motivo: typeof d.motivo === "string" ? d.motivo : "recusado" };
    return {
      ...r,
      avisou: true,
      aviso: {
        id: typeof d.id === "string" ? d.id : null,
        fila_id: typeof d.fila_id === "string" ? d.fila_id : null,
        mudancas: m.acaoIds.length,
        perguntas: m.perguntaIds.length,
        caracteres: m.texto.length,
        cortes: m.cortes,
      },
      historico: await deps.historico(db, m.texto, agora),
    };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:aviso failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:aviso",
      message: `aviso do gestor da agenda: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

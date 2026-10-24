// Passo do motor de 15 min: a vigia da Agenda de Produção (Fase 2, P3 — 24/10/2026).
//
// Roda DEPOIS do material (material-da-agenda.ts) e ANTES das regras (index.ts): a agenda_vigiar (migration
// 20261025100300) publica a semana na quinta, replaneja quando algo muda, promove e solta reservas, faz as perguntas que
// só o dono responde e devolve os acordes — a mudança que ela fez sozinha e que perde hoje ou amanhã. Com os dois modos
// em 'desligado' (produção hoje) o banco devolve {rodou: false} e nada acontece; em 'sombra' nada muda para ninguém e
// nenhum acorde volta (o banco só devolve acorde com modo_vigia = 'ligado' e a ação executada).
//
// O acorde vai ao dono (o mesmo da manhã: donoDoWhatsApp) pela regra das outras fontes (ai-business-monitor,
// whatsapp-conexao, acompanhar-conversas/acordes.ts):
//   · voz única LIGADA de verdade → pergunta ao portão ANTES: 'acordar' vai pela fila com a chave aviso:<id>; 'guardar'
//     é resolvido na hora (aviso_resolver: a linha da agenda no fechamento já conta a mudança — guardar seria dizer duas
//     vezes); 'acabar'/'repetido' não saem; portão ilegível = manda como sempre (nunca calar por erro de leitura);
//   · voz em sombra ou desligada → manda como sempre (na janela de acordar, 08–20h) e, em sombra, registra depois.
// "Como sempre" é a fila com a chave agenda:<ação>: a mesma ação nunca sai duas vezes. O que saiu é marcado em
// agenda_acoes (agenda_acorde_registrado), que é o que o banco conta no limite de acordes_dia_max por dia.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:vigia).
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { avisoDaAgenda } from "../_shared/uma-voz/fontes.ts";
import { podeAcordar, tentativasAteAs20h } from "../_shared/uma-voz/janela.ts";
import {
  enfileirarAcorde, falaDoPortao, falaPeloPortao, lerDonoDaVoz, lerPortao, type PortaoDaRodada, registrarNoPortao,
} from "../_shared/uma-voz/registrar.ts";
import type { Dono } from "../_shared/whatsapp/dono.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** Um acorde devolvido por agenda_vigiar. */
export interface AcordeDaAgenda {
  chave: string;
  assunto: string;
  texto: string;
  acao_id: string;
  os?: string | null;
  perda_em?: string | null;
}

export interface ResultadoDosAcordesDaAgenda {
  /** saíram (pela fila) */
  enviados: number;
  /** o portão guardou: resolvido na hora (o fechamento conta) */
  guardados: number;
  /** fora das 08–20h (sem portão ligado): fica para o fechamento */
  fora_da_janela: number;
  /** sem dono com WhatsApp, ou o portão disse que não (acabar/repetido), ou a fila recusou */
  nao_saiu: number;
}

export interface ResultadoDaVigia {
  rodou?: boolean;
  modos?: { proposta?: string; vigia?: string };
  erros?: number;
  falhas?: unknown[];
  contagens?: Record<string, unknown>;
  acordes?: ResultadoDosAcordesDaAgenda;
  /** a vigia inteira falhou */
  erro?: string;
}

/** O que a vigia lê de fora (injetável no teste). */
export interface DepsDaVigia {
  lerPortao: (db: Db) => Promise<PortaoDaRodada>;
  lerDono: (db: Db) => Promise<Dono | null>;
}

const DEPS: DepsDaVigia = { lerPortao, lerDono: lerDonoDaVoz };

/** O acorde que veio do banco, conferido (o que não tem a ação ou o texto não sai). */
export function acordesValidos(v: unknown): AcordeDaAgenda[] {
  if (!Array.isArray(v)) return [];
  return v.flatMap((a) => {
    const x = a as Record<string, unknown>;
    if (typeof x?.acao_id !== "string" || typeof x?.texto !== "string" || !x.texto.trim()) return [];
    return [{
      acao_id: x.acao_id,
      texto: x.texto,
      chave: typeof x.chave === "string" && x.chave ? x.chave : `agenda:${x.acao_id}`,
      assunto: typeof x.assunto === "string" && x.assunto ? x.assunto : `agenda:${x.acao_id}`,
      os: typeof x.os === "string" ? x.os : null,
      perda_em: typeof x.perda_em === "string" ? x.perda_em : null,
    }];
  });
}

/** A linha da fila do acorde que vai "como sempre" (sem o portão): uma por ação (chave agenda:<ação>). */
export function linhaDoAcordeDireto(p: { phone: string; texto: string; acaoId: string; agora: Date }): Record<string, unknown> {
  return {
    phone_normalized: p.phone,
    message: p.texto,
    source: "agenda",
    priority: 1,
    max_attempts: tentativasAteAs20h(p.agora),
    dedupe_key: `agenda:${p.acaoId}`,
    source_ref_id: p.acaoId,
  };
}

/** Enfileira o acorde direto. A mesma chave já na fila (23505) = já foi. Nunca lança. */
async function enfileirarDireto(db: Db, p: { phone: string; texto: string; acaoId: string; agora: Date }): Promise<boolean> {
  try {
    const { error } = await db.from("whatsapp_send_queue").insert(linhaDoAcordeDireto(p));
    if (!error) return true;
    if ((error as { code?: string }).code === "23505") return true;
    console.warn("[agenda:vigia] acorde fora da fila:", error.message ?? error);
  } catch (e) {
    console.warn("[agenda:vigia] acorde fora da fila:", (e as Error)?.message ?? e);
  }
  return false;
}

/** Marca a ação como contada no acorde (entra no limite do dia). Nunca lança. */
async function marcarAcorde(db: Db, acaoId: string, avisoId: string | null, agora: Date): Promise<void> {
  try {
    const { error } = await db.rpc("agenda_acorde_registrado", {
      p_acao: acaoId, p_aviso: avisoId, p_enviado: true, p_agora: agora.toISOString(),
    });
    if (error) console.warn("[agenda:vigia] acorde não marcado:", error.message ?? error);
  } catch (e) {
    console.warn("[agenda:vigia] acorde não marcado:", (e as Error)?.message ?? e);
  }
}

/** O guardado do portão some na hora: a linha da agenda no fechamento já leva a mudança. Nunca lança. */
async function resolverGuardado(db: Db, phone: string, avisoId: string): Promise<void> {
  try {
    const { error } = await db.rpc("aviso_resolver", {
      p: { phone, modo: "ligado", ids: [avisoId], motivo: "agenda_no_fechamento" },
    });
    if (error) console.warn("[agenda:vigia] guardado não resolvido:", error.message ?? error);
  } catch (e) {
    console.warn("[agenda:vigia] guardado não resolvido:", (e as Error)?.message ?? e);
  }
}

/** Manda os acordes da agenda ao dono. Nunca lança. */
export async function enviarAcordesDaAgenda(
  db: Db, acordes: AcordeDaAgenda[], agora: Date, deps: DepsDaVigia = DEPS,
): Promise<ResultadoDosAcordesDaAgenda> {
  const r: ResultadoDosAcordesDaAgenda = { enviados: 0, guardados: 0, fora_da_janela: 0, nao_saiu: 0 };
  if (!acordes.length) return r;
  const portao = await deps.lerPortao(db);
  const dono = await deps.lerDono(db);
  if (!dono) {
    r.nao_saiu += acordes.length;
    return r;
  }
  for (const a of acordes) {
    const aviso = avisoDaAgenda({ acao_id: a.acao_id, os: a.os ?? null, texto: a.texto, perda_em: a.perda_em ?? null, chave: a.chave, assunto: a.assunto });
    if (falaPeloPortao(portao, dono, dono.phone)) {
      const resp = await registrarNoPortao(db, "ligado", dono.phone, aviso, agora);
      const fala = falaDoPortao(resp);
      if (fala.decisao === "guardar" && typeof resp?.id === "string") {
        await resolverGuardado(db, dono.phone, resp.id);
        r.guardados++;
        continue;
      }
      if (fala.acordou) {
        if (await enfileirarAcorde(db, { phone: dono.phone, texto: a.texto, avisoId: fala.acordou, agora, source: "agenda" })) {
          await marcarAcorde(db, a.acao_id, fala.acordou, agora);
          r.enviados++;
        } else {
          r.nao_saiu++;
        }
        continue;
      }
      if (!fala.manda) {
        r.nao_saiu++;
        continue;
      }
      // portão ilegível (ou 'deixar'): manda como sempre, abaixo
    }
    if (!podeAcordar(agora)) {
      r.fora_da_janela++;
      continue;
    }
    if (!await enfileirarDireto(db, { phone: dono.phone, texto: a.texto, acaoId: a.acao_id, agora })) {
      r.nao_saiu++;
      continue;
    }
    await marcarAcorde(db, a.acao_id, null, agora);
    r.enviados++;
    // voz em sombra: registra depois de mandar (o que o portão faria), como as outras fontes
    if (portao.modo === "sombra") await registrarNoPortao(db, "sombra", dono.phone, aviso, agora);
  }
  return r;
}

/** O passo da vigia no motor. Nunca lança. */
export async function vigiarAgenda(db: Db, agora: Date = new Date(), deps: DepsDaVigia = DEPS): Promise<ResultadoDaVigia> {
  try {
    const { data, error } = await db.rpc("agenda_vigiar", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) throw error;
    const v = (data ?? {}) as Record<string, unknown>;
    const resultado: ResultadoDaVigia = {
      rodou: v.rodou === true,
      modos: (v.modos ?? undefined) as ResultadoDaVigia["modos"],
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
    };
    const acordes = acordesValidos(v.acordes);
    if (acordes.length) resultado.acordes = await enviarAcordesDaAgenda(db, acordes, agora, deps);
    return resultado;
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:vigia failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:vigia",
      message: `vigia da agenda: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}

// Vigia do negócio com a voz única LIGADA (secretário, Passo 4, P4.5, 20/10/2026).
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md §2 (F2) e §6.3.
//
// Com a voz ligada de verdade, o DONO não recebe mais o "🔔 Alerta…" com todos os sinais juntos: cada sinal pergunta
// ao portão ANTES (perguntarAoPortao) e só o que ele libera sai — o acorde (NF-e rejeitada por nota, certificado de 7
// dias ou menos), cada um na sua linha da fila com a chave aviso:<id> (se a fila desistir, a próxima mensagem fixa o
// leva). O resto fica com as mensagens fixas: "vence hoje" e orçamentos parados acabam (a manhã já mostra); saldo,
// estoque e cota vão para o escritório do fechamento; consentimento e certificado de 8–30 dias para a linha "Hoje".
// Portão ilegível num sinal = esse sinal vai como sempre (o "🔔 Alerta…" só com ele): nunca calar por erro.
// A equipe (os outros telefones) recebe o alerta de sempre — isto aqui é só o telefone do dono.

import type { AvisoDaFonte } from "../_shared/uma-voz/portao.ts";
import { enfileirarAcorde, type Fala, perguntarAoPortao } from "../_shared/uma-voz/registrar.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** Um sinal do vigia: o texto de sempre (a linha do "🔔 Alerta…") e o que ele pede ao portão (um ou mais avisos). */
export interface SinalDoVigia {
  texto: string;
  avisos: AvisoDaFonte[];
}

export interface PlanoDoDono {
  /** os acordes liberados: cada um sai sozinho, com o texto do acorde */
  acordes: Array<{ id: string; texto: string }>;
  /** as linhas que vão como sempre (portão ilegível, ou 'deixar') */
  comoHoje: string[];
  guardados: number;
  acabados: number;
  repetidos: number;
}

/**
 * Das falas de cada sinal ao que sai para o dono (puro). Um sinal com algum aviso sem resposta do portão vai inteiro
 * como sempre (a linha de sempre); os avisos que acordaram saem com o texto deles.
 */
export function planoDoDono(sinais: Array<{ texto: string; falas: Array<{ aviso: AvisoDaFonte; fala: Fala }> }>): PlanoDoDono {
  const plano: PlanoDoDono = { acordes: [], comoHoje: [], guardados: 0, acabados: 0, repetidos: 0 };
  for (const s of sinais) {
    let comoHoje = false;
    for (const { aviso, fala } of s.falas) {
      if (fala.decisao === "erro" || fala.decisao === "deixar") comoHoje = true;
      else if (fala.decisao === "acordar" && fala.acordou) plano.acordes.push({ id: fala.acordou, texto: aviso.texto || s.texto });
      else if (fala.decisao === "acordar") comoHoje = true; // acordou sem id (não acontece): manda como sempre
      else if (fala.decisao === "guardar") plano.guardados++;
      else if (fala.decisao === "acabar") plano.acabados++;
      else plano.repetidos++;
    }
    if (comoHoje && !plano.comoHoje.includes(s.texto)) plano.comoHoje.push(s.texto);
  }
  return plano;
}

/**
 * Os sinais desta rodada para o dono, pelo portão. `mensagem` monta o "🔔 Alerta…" de sempre com as linhas que vão
 * como sempre. Nunca lança por causa do portão; erro no insert da mensagem de sempre lança (como antes).
 */
export async function falarAoDono(admin: Db, p: {
  phone: string;
  sinais: SinalDoVigia[];
  mensagem: (linhas: string[]) => string;
  agora: Date;
}): Promise<{ acordes: number; como_hoje: number; guardados: number; acabados: number; repetidos: number; fora_da_fila: number }> {
  const comFalas: Array<{ texto: string; falas: Array<{ aviso: AvisoDaFonte; fala: Fala }> }> = [];
  for (const s of p.sinais) {
    const falas: Array<{ aviso: AvisoDaFonte; fala: Fala }> = [];
    for (const aviso of s.avisos) falas.push({ aviso, fala: await perguntarAoPortao(admin, p.phone, aviso, p.agora) });
    comFalas.push({ texto: s.texto, falas });
  }
  const plano = planoDoDono(comFalas);
  let acordes = 0;
  let foraDaFila = 0;
  for (const a of plano.acordes) {
    if (await enfileirarAcorde(admin, { phone: p.phone, texto: a.texto, avisoId: a.id, agora: p.agora, source: "ai_monitor" })) acordes++;
    else foraDaFila++;
  }
  if (plano.comoHoje.length) {
    const { error } = await admin.from("whatsapp_send_queue")
      .insert({ phone_normalized: p.phone, message: p.mensagem(plano.comoHoje), source: "ai_monitor", priority: 5 });
    if (error) throw error;
  }
  return { acordes, como_hoje: plano.comoHoje.length, guardados: plano.guardados, acabados: plano.acabados, repetidos: plano.repetidos, fora_da_fila: foraDaFila };
}

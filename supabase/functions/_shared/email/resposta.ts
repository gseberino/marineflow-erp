// Resposta a e-mail (08/10/2026, etapa 5). Regras do dono: o assistente só escreve rascunho a
// e-mail IMPORTANTE — nunca a automático, propaganda ou "não responda" — e SÓ quando ele pede; o
// envio sai só com o "sim" dele. Aqui ficam as decisões puras (testáveis): quem pode ser respondido,
// o assunto e os cabeçalhos de resposta, e a pasta de Enviados.

import { isNoReplySender } from "./normalize.ts";

export interface MensagemParaResponder {
  from_address: string;
  triage_class: string | null;
  muted: boolean;
  client_id: string | null;
  supplier_id: string | null;
}

/**
 * Endereço (ou domínio "@...") da própria HBR: o domínio hbrmarine.com.br e o Gmail antigo
 * hbr.boats@gmail.com (lido desde 12/11/2026). Nunca vira rascunho de resposta nem é silenciado.
 */
export function ehEnderecoDaHbr(endereco: string): boolean {
  const e = String(endereco ?? "").trim().toLowerCase();
  return /hbrmarine\.com\.br$/.test(e) || e === "hbr.boats@gmail.com";
}

/**
 * Por onde a resposta sai, conforme o servidor da caixa (12/11/2026, Gmail hbr.boats@).
 * Gmail: smtp.gmail.com:465 com a mesma senha de app, e o próprio Gmail já guarda o que sai por
 * SMTP em "E-mails enviados" — a cópia por IMAP APPEND duplicaria. GoDaddy/Titan: o de sempre
 * (SMTP_HOST/SMTP_PORT dos segredos) e a cópia em Enviados por APPEND.
 */
export function envioDaCaixa(
  imapHost: string | null | undefined,
  env: { host?: string | null; porta?: string | null },
): { host: string; porta: number; copiarEmEnviados: boolean } {
  if (/(^|\.)gmail\.com$/i.test(String(imapHost ?? "").trim())) return { host: "smtp.gmail.com", porta: 465, copiarEmEnviados: false };
  return { host: env.host || "smtpout.secureserver.net", porta: Number(env.porta || 465), copiarEmEnviados: true };
}

/**
 * Pode escrever rascunho? Urgente e "esperando resposta" sempre; informativo/documento só de
 * cliente ou fornecedor cadastrado; sem classificação (histórico) só de cadastrado. Filtrado,
 * silenciado e remetente automático ("não responda"), nunca.
 */
export function podeResponder(m: MensagemParaResponder): { ok: true } | { ok: false; motivo: string } {
  if (m.muted) return { ok: false, motivo: "esse remetente está silenciado" };
  if (m.triage_class === "ignore") return { ok: false, motivo: "o e-mail foi filtrado como propaganda/automático" };
  if (isNoReplySender(m.from_address)) return { ok: false, motivo: "o remetente é automático (não aceita resposta)" };
  if (ehEnderecoDaHbr(m.from_address)) return { ok: false, motivo: "é um e-mail da própria HBR" };
  const cadastrado = !!(m.client_id || m.supplier_id);
  if (m.triage_class === "urgent" || m.triage_class === "respond") return { ok: true };
  if (cadastrado) return { ok: true };
  return { ok: false, motivo: "não é de cliente ou fornecedor cadastrado e não foi marcado como importante" };
}

/** "Re: assunto" sem empilhar "Re: Re: RES:". */
export function assuntoDaResposta(original: string | null | undefined): string {
  const base = String(original ?? "").replace(/^\s*((re|res|fw|fwd|enc)\s*:\s*)+/i, "").trim();
  return `Re: ${base || "(sem assunto)"}`;
}

/** In-Reply-To e References no formato do RFC 5322 (mantém a conversa no programa de e-mail). */
export function cabecalhosDeResposta(messageId: string | null, references: string[] | null): Record<string, string> {
  if (!messageId) return {};
  const refs = [...(references ?? []), messageId].filter((r, i, a) => r && a.indexOf(r) === i).slice(-20);
  return { "In-Reply-To": `<${messageId}>`, References: refs.map((r) => `<${r}>`).join(" ") };
}

/** A pasta de Enviados: a marcada \Sent; senão, pelos nomes de costume. */
export function pastaDeEnviados(pastas: { nome: string; atributos: string[] }[]): string | null {
  const marcada = pastas.find((p) => p.atributos.some((a) => a.toLowerCase() === "\\sent"));
  if (marcada) return marcada.nome;
  for (const n of ["Sent", "INBOX.Sent", "Sent Items", "Sent Messages", "Itens Enviados", "Enviados", "INBOX.Enviados"]) {
    const p = pastas.find((x) => x.nome.toLowerCase() === n.toLowerCase());
    if (p) return p.nome;
  }
  return null;
}

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
 * Pode escrever rascunho? Urgente e "esperando resposta" sempre; informativo/documento só de
 * cliente ou fornecedor cadastrado; sem classificação (histórico) só de cadastrado. Filtrado,
 * silenciado e remetente automático ("não responda"), nunca.
 */
export function podeResponder(m: MensagemParaResponder): { ok: true } | { ok: false; motivo: string } {
  if (m.muted) return { ok: false, motivo: "esse remetente está silenciado" };
  if (m.triage_class === "ignore") return { ok: false, motivo: "o e-mail foi filtrado como propaganda/automático" };
  if (isNoReplySender(m.from_address)) return { ok: false, motivo: "o remetente é automático (não aceita resposta)" };
  if (/@hbrmarine\.com\.br$/i.test(m.from_address)) return { ok: false, motivo: "é um e-mail da própria HBR" };
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

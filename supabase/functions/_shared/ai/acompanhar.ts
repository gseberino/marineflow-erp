// Regras do vigia acompanhar-conversas (06/10/2026) — puras, para testar sem banco.
// plans/marineflow-acompanhar-conversa.md
import { dentroDaJanela } from "./promessa.ts";

const BRASILIA_MS = 3 * 60 * 60 * 1000;
export const AVISOS_POR_DIA = 3;

export interface Acompanhamento {
  id: string;
  phone_normalized: string;
  contato: string | null;
  modo: "acompanhar" | "lembrar_em" | "promessa";
  intervalo_min: number;
  ate: string;
  lembrar_em: string | null;
  promessa: string | null;
  ultimo_aviso_em: string | null;
  avisos_dia: string | null;
  avisos_no_dia: number;
  created_at: string;
}

export interface EstadoDaConversa {
  ultimaRecebida: { em: string; texto: string } | null;
  ultimaEnviadaEm: string | null;
}

/** O dia em Brasília (AAAA-MM-DD) — o teto de avisos é por dia local. */
export function diaEmBrasilia(agora: Date): string {
  return new Date(agora.getTime() - BRASILIA_MS).toISOString().slice(0, 10);
}

/** Horário de avisar o dono: 8h–20h de Brasília, seg–sáb (o mesmo de dentroDaJanela). */
export function horaDeAvisar(agora: Date): boolean {
  return dentroDaJanela(agora.getTime()) === agora.getTime();
}

/** A conversa está esperando resposta da HBR: a última mensagem é do contato. */
export function esperandoResposta(c: EstadoDaConversa): boolean {
  if (!c.ultimaRecebida) return false;
  return !c.ultimaEnviadaEm || Date.parse(c.ultimaRecebida.em) > Date.parse(c.ultimaEnviadaEm);
}

export type Decisao = { acao: "avisar" } | { acao: "encerrar"; motivo: string } | { acao: "esperar" };

/** O que fazer com um acompanhamento agora. */
export function decidir(a: Acompanhamento, c: EstadoDaConversa, agora: Date): Decisao {
  const t = agora.getTime();
  if (a.modo === "lembrar_em" || a.modo === "promessa") {
    return a.lembrar_em && Date.parse(a.lembrar_em) <= t ? { acao: "avisar" } : { acao: "esperar" };
  }
  if (Date.parse(a.ate) <= t) return { acao: "encerrar", motivo: "prazo" };
  if (!esperandoResposta(c)) return { acao: "esperar" };
  const intervalo = a.intervalo_min * 60_000;
  if (t - Date.parse(c.ultimaRecebida!.em) < intervalo) return { acao: "esperar" };
  // Desde o último aviso: ou passou o intervalo, ou chegou mensagem nova dele depois do aviso.
  if (a.ultimo_aviso_em && t - Date.parse(a.ultimo_aviso_em) < intervalo) return { acao: "esperar" };
  const hoje = diaEmBrasilia(agora);
  if (a.avisos_dia === hoje && a.avisos_no_dia >= AVISOS_POR_DIA) return { acao: "esperar" };
  return { acao: "avisar" };
}

/** "3h", "45 min", "2 dias" — quanto tempo ele espera. */
export function tempoEsperando(desde: string, agora: Date): string {
  const min = Math.max(0, Math.round((agora.getTime() - Date.parse(desde)) / 60_000));
  if (min < 60) return `${min} min`;
  const h = Math.round(min / 60);
  if (h < 48) return `${h}h`;
  return `${Math.round(h / 24)} dias`;
}

function curto(t: string, n = 300): string {
  const s = t.replace(/\s+/g, " ").trim();
  return s.length > n ? `${s.slice(0, n)}…` : s;
}

/**
 * O pedido que o vigia faz ao assistente, como se fosse o dono — o assistente lê a conversa, sugere
 * a resposta e chama send_whatsapp_message (a confirmação que o dono recebe). A marca 🤖 no começo
 * deixa claro, no histórico, que não foi o dono que escreveu.
 */
export function textoDoAviso(a: Acompanhamento, c: EstadoDaConversa, agora: Date, telefoneLegivel: string): string {
  const quem = `${a.contato || "o contato"} (${telefoneLegivel})`;
  const ler = `Leia a conversa com get_whatsapp_conversation (phone ${a.phone_normalized}, poucos dias)`;
  const sugerir = `sugira a resposta chamando send_whatsapp_message com to_phone ${a.phone_normalized} — a confirmação vai para mim. Se não houver o que responder, diga isso em uma linha.`;
  if (a.modo === "promessa") {
    return `🤖 Lembrete de promessa (detectado numa mensagem sua): você escreveu a ${quem}: "${curto(a.promessa ?? "")}". ` +
      `${ler} e veja se já foi cumprido. Se já foi, diga em uma linha. Se não, diga em uma linha o que falta e, se couber, ${sugerir}`;
  }
  const ultima = c.ultimaRecebida
    ? ` Última mensagem dele, há ${tempoEsperando(c.ultimaRecebida.em, agora)}: "${curto(c.ultimaRecebida.texto)}".`
    : "";
  const abertura = a.modo === "lembrar_em"
    ? `🤖 Lembrete que você pediu: responder ${quem}.`
    : `🤖 Acompanhamento (pedido seu): ${quem} está esperando resposta.`;
  return `${abertura}${ultima} ${ler}, me diga em uma linha o que ele quer e ${sugerir}`;
}

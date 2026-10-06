// Responder uma conversa com a ajuda do assistente (06/10/2026).
//
// Pedido do dono: "que o agente lesse o que o cliente mandou e me ajudasse a responder, com base no
// contexto da conversa — ele sugere, e com a minha confirmação envia". A leitura já existia
// (get_whatsapp_conversation) e o envio também (send_whatsapp_message, sempre com confirmação). O que
// faltava era a confirmação mostrar A QUE a resposta responde: a última mensagem da pessoa — o dono
// confere de relance que a sugestão casa com a pergunta, no número certo, antes do "sim".
import { destinoDoAgendamento, telefoneLegivel, telefoneParaEnvio } from "./agendamento.ts";

const BRASILIA_MS = 3 * 60 * 60 * 1000;

function quandoCurto(iso: string): string {
  const d = new Date(new Date(iso).getTime() - BRASILIA_MS);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getUTCDate())}/${p(d.getUTCMonth() + 1)} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`;
}

/** Mídia sem texto vira um rótulo legível em vez de "[audio]". */
function textoDaMensagem(corpo: unknown): string {
  const b = String(corpo ?? "").trim();
  const rotulos: Record<string, string> = { "[audio]": "🎤 áudio", "[image]": "📷 imagem", "[video]": "🎬 vídeo", "[document]": "📎 arquivo", "[sticker]": "figurinha" };
  if (rotulos[b]) return rotulos[b];
  return b.length > 300 ? `${b.slice(0, 300)}…` : b;
}

/** A última mensagem que a pessoa MANDOU (entrada), para mostrar a que a resposta responde. */
// deno-lint-ignore no-explicit-any
export async function ultimaMensagemRecebida(admin: any, telefone: string): Promise<{ quando: string; texto: string } | null> {
  const { data } = await admin
    .from("whatsapp_messages")
    .select("body, occurred_at")
    .eq("phone_normalized", telefone)
    .eq("direction", "inbound")
    .order("occurred_at", { ascending: false })
    .limit(1);
  const m = Array.isArray(data) ? data[0] : null;
  if (!m) return null;
  return { quando: quandoCurto(m.occurred_at), texto: textoDaMensagem(m.body) };
}

/** Resumo da confirmação de send_whatsapp_message. */
// deno-lint-ignore no-explicit-any
export async function resumirMensagem(admin: any, args: Record<string, unknown>): Promise<string> {
  const destino = await destinoDoAgendamento(admin, { client_id: args?.client_id, phone: args?.to_phone });
  const quem = destino.origem === "cliente"
    ? `*${destino.nome || "cliente"}* (cliente do cadastro)`
    : destino.origem === "conversa"
    ? `*${destino.nome || "sem nome"}* (conversa do WhatsApp)`
    : `*${destino.nome || "número sem conversa"}* — número que ainda não conversou com a HBR`;
  const linhas = [
    `Para: ${quem}`,
    destino.telefone ? `WhatsApp: ${telefoneLegivel(destino.telefone)}` : "WhatsApp: ⚠️ número inválido ou ausente — o envio será recusado",
  ];
  if (destino.telefone) {
    const ultima = await ultimaMensagemRecebida(admin, destino.telefone);
    if (ultima) linhas.push(`Última mensagem dele (${ultima.quando}): "${ultima.texto}"`);
  }
  linhas.push(`Resposta: "${String(args?.message ?? "").trim()}"`);
  return linhas.join("\n");
}

/** Antes da pendência: mensagem e número (quando não é cliente do cadastro). */
export function validarMensagem(args: Record<string, unknown> | null | undefined): { error: string } | null {
  if (!String(args?.message ?? "").trim()) return { error: "A mensagem está vazia." };
  if (!args?.client_id && !telefoneParaEnvio(args?.to_phone)) {
    return { error: `Número "${String(args?.to_phone ?? "")}" inválido. Use o número da conversa (get_whatsapp_conversation) ou peça o WhatsApp com DDD.` };
  }
  return null;
}

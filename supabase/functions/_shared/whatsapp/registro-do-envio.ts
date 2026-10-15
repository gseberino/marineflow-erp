// O que o whatsapp-send manda a um contato passa a ficar na conversa (whatsapp_messages), como já
// ficava o que sai pela caixa de mensagens (whatsapp-send-text) e o que o dono digita no celular
// (webhook, fromMe).
//
// ═══ POR QUE EXISTE (15/10/2026) ═══
//
// Todo envio do assistente (send_whatsapp_message, cobrança, orçamento/OS ao cliente) passa pelo
// whatsapp-send, e ele só gravava audit_log. Medido em 15/10: 379 envios com sucesso desde 15/09,
// NENHUM em whatsapp_messages. Daí três erros vistos pelo dono: o histórico do assistente dizia
// "nada foi enviado" ao Miguel (saíram 3 mensagens em 07/10), o "esperando resposta" do resumo
// listava como sem resposta quem já tinha sido respondido, e o vigia de promessas não via o que o
// dono aprovou pelo assistente.
//
// Fica de fora (deveRegistrarEnvio): o envio desviado pelo modo de teste (não foi ao contato) e o
// envio a quem conversa com o assistente (app_users com o canal ligado) — a conversa do dono com o
// assistente não é conversa com cliente.
import { mesmoTelefone } from "../ai/phone.ts";

export type OrigemDoEnvio = "assistente" | "tela" | "sistema";
const ORIGENS: ReadonlyArray<OrigemDoEnvio> = ["assistente", "tela", "sistema"];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** O corpo do whatsapp-send no que importa para a linha da conversa. */
export interface PedidoDeEnvio {
  kind: "text" | "link" | "document";
  message?: string;
  link_url?: string;
  document_caption?: string;
  document_filename?: string;
  service_order_id?: string;
}

/** O vínculo da conversa (da mensagem mais recente do mesmo número que tem algum). */
export interface VinculoDaConversa {
  client_id?: string | null;
  lead_id?: string | null;
  supplier_id?: string | null;
}

/**
 * Quem mandou. Chamada com o JWT de um usuário: é ele (o corpo não decide). Chamada de sistema
 * (service-role — o assistente no WhatsApp, o agendador): o `sent_by` do corpo, se for um id.
 * Campo de registro nunca derruba o envio: o que não é uuid vira null.
 */
export function quemEnviou(doCorpo: unknown, chamadaDeSistema: boolean, usuarioDoJwt: string | null): string | null {
  if (!chamadaDeSistema) return usuarioDoJwt && UUID.test(usuarioDoJwt) ? usuarioDoJwt : null;
  return typeof doCorpo === "string" && UUID.test(doCorpo) ? doCorpo : null;
}

/** De onde saiu. Sem origem válida: "tela" quando há usuário logado, "sistema" quando não. */
export function origemDoEnvio(doCorpo: unknown, chamadaDeSistema: boolean): OrigemDoEnvio {
  if (typeof doCorpo === "string" && (ORIGENS as readonly string[]).includes(doCorpo)) return doCorpo as OrigemDoEnvio;
  return chamadaDeSistema ? "sistema" : "tela";
}

/** O envio entra na conversa? Não quando foi para o número de teste nem para quem fala com o assistente. */
export function deveRegistrarEnvio(p: { desviadoPorTeste: boolean; telefone: string; telefonesDoAssistente: Array<string | null | undefined> }): boolean {
  if (p.desviadoPorTeste) return false;
  return !p.telefonesDoAssistente.some((t) => mesmoTelefone(t, p.telefone));
}

/** O texto que fica na conversa: texto como foi; link com a URL; PDF pela legenda ou "[pdf] arquivo". */
export function textoDoEnvio(p: PedidoDeEnvio): string {
  const msg = String(p.message ?? "").trim();
  if (p.kind === "document") {
    const legenda = String(p.document_caption ?? "").trim() || msg;
    return legenda || `[pdf] ${p.document_filename || "documento.pdf"}`;
  }
  if (p.kind === "link") {
    const url = String(p.link_url ?? "").trim();
    if (!url || msg.includes(url)) return msg;
    return msg ? `${msg}\n${url}` : url;
  }
  return msg;
}

/** A linha de whatsapp_messages de um envio que saiu (o webhook grava as recebidas no mesmo formato). */
export function linhaDaMensagemEnviada(
  pedido: PedidoDeEnvio,
  telefone: string,
  providerMessageId: string | null,
  sentBy: string | null,
  origem: OrigemDoEnvio,
  contexto: string | null,
  anterior?: VinculoDaConversa | null,
) {
  return {
    direction: "outbound" as const,
    phone_normalized: telefone,
    message_type: pedido.kind === "document" ? "document" : "text",
    body: textoDoEnvio(pedido).slice(0, 4000),
    wa_message_id: providerMessageId || null,
    delivery_status: "sent" as const,
    sent_by: sentBy,
    // O "esperando resposta" pega o cliente da ÚLTIMA mensagem do número: sem copiar o vínculo, a
    // saída deixaria a conversa sem cliente.
    client_id: anterior?.client_id ?? null,
    lead_id: anterior?.lead_id ?? null,
    supplier_id: anterior?.supplier_id ?? null,
    service_order_id: pedido.service_order_id && UUID.test(pedido.service_order_id) ? pedido.service_order_id : null,
    raw_payload: { origem, contexto, via: "whatsapp-send" },
  };
}

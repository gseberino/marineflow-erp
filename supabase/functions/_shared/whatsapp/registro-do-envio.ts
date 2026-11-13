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
//
// ═══ AS ORIGENS DO RETORNO (Retorno rápido, F1, 16/11/2026) ═══
//
// O recibo, a coleta e o adiamento que o retorno manda ao cliente (edge retorno-recibos) saem pelo
// whatsapp-send com origem retorno_recibo, retorno_coleta ou retorno_adiamento e o contexto
// "retorno:<id da saída>". Três regras:
//  - só valem em chamada de sistema (service-role): com o JWT de um usuário viram "tela", e
//    ninguém logado finge ser o retorno para pular o portão da tela ou ganhar o portão do banco;
//  - a linha da conversa leva via "retorno" (plano B.7): _saida_e_humana (F0b) lê todo via que não
//    é "whatsapp-send" como AUTOMÁTICO, e o recibo nunca conta como "o dono respondeu";
//  - sent_by fica nulo: o retorno não é ninguém da equipe, mesmo que o corpo mande um id.
// Quem lê via hoje: só _saida_e_humana e retorno_medidas_base (que conta o automático pelo
// audit_log, gravado em todo envio).
//
// Retorno F4 (P5.2): o texto à parceira (retorno_parceiro) e o aviso ao cliente final (retorno_aviso) saem pelo mesmo
// caminho, com as mesmas três regras. O whatsapp-send confere a saída por retorno_saida_autorizada, que passa a do
// parceiro a parceiro_saida_autorizada. A lista é compilada na edge: origem nova pede reimplantar o whatsapp-send.
//
// Retorno F5 (P5.2): o lembrete, a véspera e o encerramento do orçamento enviado, o "Fechado" e o pedido de dados da nota
// (retorno_orcamento, 17 caracteres) também, com as mesmas três regras; retorno_saida_autorizada passa a saída do orçamento a
// orcamento_saida_autorizada. Também pede reimplantar o whatsapp-send.
//
// Reverter: tirar OrigemDoRetorno de OrigemDoEnvio, ORIGENS_DO_RETORNO, ehOrigemDoRetorno,
// idDaSaidaDoRetorno e os dois ternários de linhaDaMensagemEnviada (sent_by e via). Só a F4: tirar
// retorno_parceiro e retorno_aviso das duas listas. Só a F5: tirar retorno_orcamento das duas listas.
import { mesmoTelefone } from "../ai/phone.ts";

export type OrigemDoRetorno =
  | "retorno_recibo"
  | "retorno_coleta"
  | "retorno_adiamento"
  | "retorno_modelo"
  | "retorno_parceiro"
  | "retorno_aviso"
  | "retorno_orcamento";
export type OrigemDoEnvio = "assistente" | "tela" | "sistema" | OrigemDoRetorno;
const ORIGENS: ReadonlyArray<OrigemDoEnvio> = ["assistente", "tela", "sistema"];
export const ORIGENS_DO_RETORNO: ReadonlyArray<OrigemDoRetorno> = [
  "retorno_recibo",
  "retorno_coleta",
  "retorno_adiamento",
  "retorno_modelo",
  "retorno_parceiro",
  "retorno_aviso",
  "retorno_orcamento",
];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// "retorno:<uuid da saída>", como a edge retorno-recibos monta (o uuid do banco é sempre minúsculo).
const CONTEXTO_DO_RETORNO = /^retorno:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/;

/** A origem é uma das do retorno (recibo, coleta, adiamento, modelo, as do parceiro e a do orçamento)? */
export function ehOrigemDoRetorno(o: unknown): o is OrigemDoRetorno {
  return typeof o === "string" && (ORIGENS_DO_RETORNO as readonly string[]).includes(o);
}

/** O id da saída do retorno no contexto "retorno:<uuid>", ou null (sem prefixo, uuid torto, não texto). */
export function idDaSaidaDoRetorno(contexto: unknown): string | null {
  if (typeof contexto !== "string") return null;
  const m = CONTEXTO_DO_RETORNO.exec(contexto);
  return m ? m[1] : null;
}

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

/**
 * De onde saiu. Sem origem válida: "tela" quando há usuário logado, "sistema" quando não. As
 * origens do retorno só valem em chamada de sistema; com JWT de usuário viram "tela".
 */
export function origemDoEnvio(doCorpo: unknown, chamadaDeSistema: boolean): OrigemDoEnvio {
  if (ehOrigemDoRetorno(doCorpo)) return chamadaDeSistema ? doCorpo : "tela";
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
    // O retorno não é ninguém da equipe: sent_by nulo, mesmo que o corpo traga um id.
    sent_by: ehOrigemDoRetorno(origem) ? null : sentBy,
    // O "esperando resposta" pega o cliente da ÚLTIMA mensagem do número: sem copiar o vínculo, a
    // saída deixaria a conversa sem cliente.
    client_id: anterior?.client_id ?? null,
    lead_id: anterior?.lead_id ?? null,
    supplier_id: anterior?.supplier_id ?? null,
    service_order_id: pedido.service_order_id && UUID.test(pedido.service_order_id) ? pedido.service_order_id : null,
    // via "retorno" só para as origens do retorno: _saida_e_humana lê como automático (F1, B.7).
    raw_payload: { origem, contexto, via: ehOrigemDoRetorno(origem) ? "retorno" : "whatsapp-send" },
  };
}

// ═══ A FILA TAMBÉM GRAVA (Retorno rápido, F0b, 06/11/2026) ═══
//
// O worker da fila (whatsapp_send_queue) manda direto ao provedor e não gravava nada na conversa:
// 0 de 116 envios em 31/10. A linha leva origem "fila:<fonte>" e via "whatsapp-queue-worker", e
// _saida_e_humana (SQL) a lê como automática: nunca conta como resposta do dono nem vira promessa.
//
// As linhas da AGENDA ficam de fora por enquanto: _agenda_cliente_outra_conversa conta toda enviada
// como "o dono conversou com o cliente" (só desconta as da agenda-cliente pelo id do provedor).
// Entram quando a sessão da agenda passar a usar _saida_e_humana (pedido 1 do plano).

/** A linha da fila entra na conversa? Não a da agenda (ver acima) nem a conversa com o assistente. */
export function filaGravaNaConversa(p: { fonte: string | null | undefined; telefone: string; telefonesDoAssistente: Array<string | null | undefined> }): boolean {
  if (String(p.fonte ?? "").startsWith("agenda-")) return false;
  return !p.telefonesDoAssistente.some((t) => mesmoTelefone(t, p.telefone));
}

/** A linha de whatsapp_messages de um envio da fila que saiu. */
export function linhaDaMensagemDaFila(
  item: { id: string; phone_normalized: string; message: string; source?: string | null },
  providerMessageId: string | null,
  anterior?: VinculoDaConversa | null,
) {
  return {
    direction: "outbound" as const,
    phone_normalized: item.phone_normalized,
    message_type: "text",
    body: String(item.message ?? "").slice(0, 4000),
    wa_message_id: providerMessageId || null,
    delivery_status: "sent" as const,
    sent_by: null,
    client_id: anterior?.client_id ?? null,
    lead_id: anterior?.lead_id ?? null,
    supplier_id: anterior?.supplier_id ?? null,
    service_order_id: null,
    raw_payload: { origem: `fila:${item.source || "manual"}`, contexto: null, via: "whatsapp-queue-worker", fila_id: item.id },
  };
}

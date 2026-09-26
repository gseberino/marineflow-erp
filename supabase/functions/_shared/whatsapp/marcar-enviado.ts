// Duas decisões do whatsapp-send, isoladas para teste: quando um envio marca o orçamento como
// ENVIADO AO CLIENTE, e de onde a Evolution pode baixar um documento.
import { mesmoTelefone } from "../ai/phone.ts";

export type OrdemParaMarcar = {
  status: string | null;
  quote_status: string | null;
  converted_to_os_at: string | null;
};

/**
 * O envio marca o orçamento como enviado ao cliente?
 *
 * ═══ POR QUE EXISTE ═══
 *
 * Até 26/09/2026 bastava o envio vir com context='quote' e service_order_id: o whatsapp-send
 * marcava 'sent' sem olhar PARA QUEM foi. O dono mandava o PDF para o próprio número (ou o modo
 * de teste desviava tudo para o número de teste) e o orçamento virava "enviado ao cliente". Daí
 * vinham a tarefa de follow-up de "sem resposta", o briefing, a conciliação procurando sinal —
 * e a rotina quote-reminders, que REJEITOU sozinha ORÇ-00072 e ORÇ-00078 depois de envios que
 * só foram ao número de teste.
 *
 * Agora só marca quando tudo abaixo vale:
 *   · é orçamento de verdade: status 'draft', não convertido, quote_status em draft/aguardando;
 *   · o envio não foi desviado pelo modo de teste;
 *   · o número de destino é o do cliente da ordem (casamento pelos 8 dígitos finais).
 *
 * Cliente sem telefone cadastrado nunca marca — quem mandou para um contato de fora (capitão,
 * sócio) marca à mão. Errar para menos é barato; errar para mais rejeita orçamento vivo.
 */
export function decidirMarcarEnviado(p: {
  context?: string | null;
  serviceOrderId?: string | null;
  desviadoPorTeste: boolean;
  telefoneDestino: string;
  telefonesDoCliente: Array<string | null | undefined>;
  ordem: OrdemParaMarcar | null;
}): { marcar: boolean; motivo: string } {
  if (p.context !== "quote" || !p.serviceOrderId) return { marcar: false, motivo: "não é envio de orçamento" };
  if (p.desviadoPorTeste) return { marcar: false, motivo: "modo de teste: foi para o número de teste" };
  const o = p.ordem;
  if (!o) return { marcar: false, motivo: "ordem não encontrada" };
  if (o.status !== "draft") return { marcar: false, motivo: `a ordem não é mais orçamento (${o.status})` };
  if (o.converted_to_os_at) return { marcar: false, motivo: "orçamento já convertido em OS" };
  if (!["draft", "awaiting_approval"].includes(String(o.quote_status))) {
    return { marcar: false, motivo: `o funil já está em ${o.quote_status}` };
  }
  const doCliente = p.telefonesDoCliente.some((t) => mesmoTelefone(t, p.telefoneDestino));
  if (!doCliente) return { marcar: false, motivo: "o número de destino não é o do cliente da ordem" };
  return { marcar: true, motivo: "enviado ao WhatsApp do cliente" };
}

/**
 * De onde a Evolution pode baixar um documento: só do NOSSO armazenamento.
 *
 * A Evolution roda no PC da empresa e baixa a URL que chega aqui para mandá-la como PDF. Aceitar
 * qualquer endereço deixava um usuário logado apontar para a rede interna da HBR e receber o
 * conteúdo no WhatsApp. Os três caminhos reais — tela (bucket documents), assistente (pdf-agente)
 * e DANFE (fiscal-xml) — usam URL do Storage deste projeto: assinada, ou pública enquanto o
 * bucket documents não virar privado.
 */
export function urlDeDocumentoPermitida(url: string, supabaseUrl: string): boolean {
  let alvo: URL;
  let base: URL;
  try {
    alvo = new URL(url);
    base = new URL(supabaseUrl);
  } catch {
    return false;
  }
  if (alvo.protocol !== "https:" || alvo.origin !== base.origin) return false;
  return alvo.pathname.startsWith("/storage/v1/object/sign/") ||
    alvo.pathname.startsWith("/storage/v1/object/public/");
}

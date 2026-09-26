// As decisões do whatsapp-send, isoladas para teste: se o modo de teste desvia o envio, que
// campo falta para cada tipo de envio, quando um envio marca o orçamento como ENVIADO AO
// CLIENTE, e de onde a Evolution pode baixar um documento.
import { mesmoTelefone } from "../ai/phone.ts";

/** app_settings em mapa. A edge guarda o valor cru (null fica null); o ai-agent, em texto. */
type Configuracoes = Record<string, string | null | undefined>;

/**
 * Para onde o modo de teste desvia o envio — ou null quando NÃO desvia.
 *
 * ═══ POR QUE EXISTE ═══
 *
 * A regra é da edge whatsapp-send: desvia só com o modo LIGADO **e** um número de teste
 * preenchido. Modo ligado sem número não desvia — a mensagem vai ao destino de verdade.
 *
 * As tools do assistente precisam da MESMA resposta: a chave anti-duplicado do envio ao cliente
 * leva a marca "teste" quando o envio é desviado, e o resultado diz ao dono "foi para o número
 * de teste". Até 26/09/2026 elas olhavam só o interruptor. Com o modo ligado e o número vazio,
 * o PDF ia ao cliente, a tool dizia "foi para o número de TESTE" e a chave levava ":teste" —
 * desligado o modo no mesmo dia, a chave mudava e o cliente recebia o mesmo PDF de novo. Uma
 * função só, usada pela edge e pelas tools, é o que impede as duas de divergirem.
 *
 * O cálculo é o que a edge sempre fez: nomes antigos zapi_* como reserva; o número wa_* vai
 * como está, o zapi_* só com os dígitos.
 */
export function numeroDeTesteAtivo(settings: Configuracoes): string | null {
  const modoLigado = (settings.wa_test_mode ?? settings.zapi_test_mode) === "true";
  if (!modoLigado) return null;
  const numero = settings.wa_test_number ?? settings.zapi_test_number?.replace(/\D/g, "");
  return numero ? numero : null;
}

/** O envio vai para o número de teste em vez do destino de verdade? (ver numeroDeTesteAtivo) */
export function desviadoPorTeste(settings: Configuracoes): boolean {
  return numeroDeTesteAtivo(settings) !== null;
}

/** O corpo do whatsapp-send no que importa para a validação por tipo. */
export type CorpoDoEnvio = {
  kind: "text" | "link" | "document";
  message?: string;
  link_url?: string;
  document_url?: string;
};

/**
 * O campo obrigatório que falta para o tipo de envio (a mensagem do 400), ou null.
 *
 * A edge chama ANTES de reservar a chave anti-duplicado. Até 26/09/2026 estas checagens
 * ficavam depois da reserva e devolviam 400 sem liberá-la: o pedido corrigido, com a mesma
 * chave, ouvia "já enviado" sem nada ter saído. As tools contam com a ordem certa — com
 * resposta 400 elas NÃO liberam a chave, porque "a edge recusa antes de reservar".
 */
export function campoObrigatorioFaltando(body: CorpoDoEnvio): string | null {
  if (body.kind === "text") return body.message ? null : "message é obrigatório para kind=text";
  if (body.kind === "link") {
    return body.link_url && body.message ? null : "link_url e message são obrigatórios para kind=link";
  }
  return body.document_url ? null : "document_url é obrigatório para kind=document";
}

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

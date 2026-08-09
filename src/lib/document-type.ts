/**
 * Os dois documentos que uma ordem gera por si.
 *
 * Mais estreito que `PDFDocumentType` de propósito: `invoice` e `receipt`
 * existem, mas não saem do status — a fatura depende da ordem estar concluída,
 * e o recibo nasce de um pagamento. Devolver o tipo largo aqui obrigaria quem
 * chama a tratar dois casos que esta função nunca produz.
 */
export type OrderDocumentType = 'quote' | 'service_order';

/**
 * Orçamento ou ordem de serviço?
 *
 * A mesma tabela guarda os dois, e o que os separa é o status: rascunho é
 * orçamento, o resto é ordem de serviço. É o critério que já decide as abas da
 * tela de detalhe (`isQuote = status === 'draft'`) e as duas listas
 * (/v2/quotes e /v2/service-orders).
 *
 * Ficou numa função porque a mesma pergunta passou a ser feita em três lugares
 * — o botão de imprimir, o envio por WhatsApp e o rótulo do menu — e três
 * cópias da mesma comparação é como uma delas fica para trás no dia em que
 * aparecer um status novo.
 */
export function isQuoteStatus(status: string | null | undefined): boolean {
  return status === 'draft';
}

/** O documento que esta ordem gera: `quote` para rascunho, `service_order` para o resto. */
export function documentTypeFor(status: string | null | undefined): OrderDocumentType {
  return isQuoteStatus(status) ? 'quote' : 'service_order';
}

/** Como chamar o documento numa frase ("Enviar orçamento por WhatsApp"). */
export function documentLabelFor(status: string | null | undefined): string {
  return isQuoteStatus(status) ? 'orçamento' : 'OS';
}

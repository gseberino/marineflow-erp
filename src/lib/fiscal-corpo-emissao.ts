/**
 * O corpo que a tela manda ao fiscal-emit, tanto na emissão real quanto no espelho (preview):
 * o espelho mostra exatamente o que será emitido.
 *
 * Extraído de FiscalEmission.tsx (D33, passo 3, 01/10/2026) sem mudar nada, para ter teste:
 * é o conteúdo da nota. Os campos de entrada têm os MESMOS nomes dos estados da tela, para
 * a chamada lá ser um repasse direto.
 */
import { buildEmissionItem, type EmissionDraftItem } from './fiscal-emission-item';
import { BLOCK_SEPARATOR, composeAdditionalInfo } from './nfe-info-complementar';
import { montarParcelas } from './fiscal-parcelas';

export interface EstadoDaEmissao {
  clientId: string;
  natureOfOperation: string;
  /** A natureza escolhida (findNatureOfOperation): tem pagamento? exige nota referenciada? */
  selectedNature: { hasPayment: boolean; requiresReference?: boolean };
  paymentMethod: string;
  payMode: 'avista' | 'parcelado';
  payN: number;
  payFirstDue: string;
  payInterval: number;
  /** Total LÍQUIDO dos itens incluídos: a base das parcelas. */
  total: number;
  presenceIndicator: number;
  consumerFinal: boolean;
  purchaseOrder: string;
  buyerName: string;
  /** Dados adicionais da devolução ao fornecedor ('' fora da devolução). */
  devolucaoInfo: string;
  additionalInfo: string;
  isReturn: boolean;
  referencedAccessKey: string;
  recipientName: string;
  recipientDocument: string;
  recipientEmail: string;
  recipientIeIndicator: number;
  recipientIe: string;
  address: {
    postal_code: string;
    address_line_1: string;
    address_number: string;
    address_complement: string;
    neighborhood: string;
    city: string;
    state: string;
  };
  /** Só os itens incluídos (na devolução parcial, os desmarcados ficam de fora). */
  activeItems: EmissionDraftItem[];
}

export function montarCorpoDaEmissao(e: EstadoDaEmissao) {
  const parcelado = e.selectedNature.hasPayment && e.payMode === 'parcelado' && !!e.payFirstDue;
  return {
    client_id: e.clientId || null,
    nature_of_operation: e.natureOfOperation,
    // Venda a PRAZO (parcelada) → tPag = Duplicata Mercantil (14): a Contora/SEFAZ exige o
    // método 14 quando há grupo de cobrança (fatura+duplicatas), então o método do seletor não
    // se aplica ao parcelado. À vista → o método escolhido. Enviar o método REAL da nota faz o
    // espelho mostrar o MESMO que será emitido.
    payment_method: parcelado ? '14' : e.paymentMethod,
    // Plano de pagamento (à vista/parcelado) definido na emissão: só faz sentido em naturezas
    // com pagamento (venda); vira os recebíveis depois.
    payment_terms: parcelado
      ? { mode: 'parcelado', method: '14', installments: montarParcelas(e.total, e.payN, e.payFirstDue, e.payInterval, '14') }
      : (e.selectedNature.hasPayment ? { mode: 'avista', method: e.paymentMethod, installments: null } : null),
    presence_indicator: e.presenceIndicator,
    consumer_final: e.consumerFinal,
    // Ordem garantida por contrato (ver composeAdditionalInfo): pedido/comprador →
    // devolução/texto livre → declaração obrigatória do Simples, por último.
    additional_info: composeAdditionalInfo({
      purchaseOrder: e.purchaseOrder,
      buyer: e.buyerName,
      freeText: [e.devolucaoInfo, e.additionalInfo].filter(Boolean).join(BLOCK_SEPARATOR),
      isReturn: e.isReturn, // devolução: omite a frase de crédito de IPI
    }) || undefined,
    // Guardados também em colunas próprias (restaura ao duplicar; nota pesquisável).
    customer_po_number: e.purchaseOrder.trim() || undefined,
    customer_buyer_name: e.buyerName.trim() || undefined,
    referenced_access_key: e.selectedNature.requiresReference ? (e.referencedAccessKey || undefined) : undefined,
    recipient: {
      name: e.recipientName,
      document: e.recipientDocument,
      email: e.recipientEmail || undefined,
      state_registration_indicator: e.recipientIeIndicator,
      state_registration: e.recipientIeIndicator === 1 ? (e.recipientIe || undefined) : undefined,
      address: {
        street: e.address.address_line_1,
        number: e.address.address_number,
        complement: e.address.address_complement || undefined,
        district: e.address.neighborhood,
        city_name: e.address.city,
        state_code: e.address.state,
        postal_code: e.address.postal_code,
      },
    },
    // Mapeamento item a item em função pura e testada (fiscal-emission-item): o teste é a
    // rede que pega typo de campo (foi assim que other_expenses ia zerado).
    items: e.activeItems.map((it) => buildEmissionItem(it)),
  };
}

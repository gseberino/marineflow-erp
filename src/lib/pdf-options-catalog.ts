import type { PDFDocumentType, PDFOptions } from './pdf-generator';

/**
 * Catálogo dos toggles de PDF — quais existem, em que documento aparecem e como se chamam.
 *
 * Existe porque a MESMA lista precisa ser desenhada em dois lugares desde MF-AUD-014: o
 * diálogo de Baixar/Imprimir (ajuste do documento que está sendo gerado agora) e a tela de
 * Configurações › Documentos (padrão da empresa). Duas cópias divergiriam na primeira opção
 * nova — e o sintoma seria silencioso: um toggle que o dono não consegue configurar, ou que
 * ele configura e ninguém aplica.
 *
 * `showProductImages` é o único condicional: só faz sentido oferecer quando o documento tem
 * peça com foto. No padrão da empresa ele aparece sempre, porque ali se configura a intenção,
 * não um documento específico.
 */

/** Chaves booleanas de PDFOptions — as que o usuário liga e desliga. Fora ficam `validity`
 *  e `dueDate`, que descrevem UM documento e nunca um padrão. */
export type PdfOptionKey = Exclude<keyof PDFOptions, 'validity' | 'dueDate'>;

type CatalogEntry = {
  key: PdfOptionKey;
  /**
   * Chave dentro de `t.pdf`. Obrigatória: opção nova sem tradução era como as cinco que
   * viviam com texto fixo em português dentro do componente — invisíveis para quem procura
   * dívida de i18n, porque não faltava chave nenhuma no dicionário.
   */
  i18nKey: string;
  /** rede de segurança: usado se a chave sumir do dicionário em runtime */
  fallback: string;
  docTypes: PDFDocumentType[];
  /** só entra na lista do diálogo quando o documento tem peça com foto */
  requiresProductImages?: boolean;
  /** escolha de um documento específico — não faz sentido como padrão da empresa */
  perDocumentOnly?: boolean;
  /** quando ligada, esvazia as demais: os outros toggles perdem efeito */
  overridesOthers?: boolean;
  /** Bloco do diálogo: o que decide VALOR na folha, ou o que decide o resto do conteúdo. */
  grupo: 'valores' | 'conteudo';
};

const QUOTE_LIKE: PDFDocumentType[] = ['quote', 'service_order'];

// Revisão de 14/11/2026 — cada opção oferecida tem de mudar a folha do documento em que aparece:
// - "Comissão e total líquido" saiu: nenhum gerador a lia, e comissão é dado interno — não tem por
//   que ir para o cliente. A chave continua em PDFOptions (padrões gravados seguem válidos).
// - "Impostos" passou a funcionar (linha "Impostos" no quadro de valores).
// - "Dados bancários" entrou no orçamento e na OS: o card já saía neles, sem como desligar.
// - Na fatura saíram "Preço dos serviços", "Termos" e "Fotos dos produtos": o desenho da fatura
//   não tem nenhum dos três, e a caixa não mudava nada.
export const PDF_OPTION_CATALOG: readonly CatalogEntry[] = [
  { key: 'hideFinancials',         i18nKey: 'hideFinancials',    fallback: 'Via de execução (sem valores)', docTypes: ['service_order'], perDocumentOnly: true, overridesOthers: true, grupo: 'valores' },
  { key: 'showServicePrices',      i18nKey: 'showServicePrices', fallback: 'Valores dos serviços (unitário e total)', docTypes: [...QUOTE_LIKE], grupo: 'valores' },
  { key: 'showPartsPrices',        i18nKey: 'showPartsPrices',   fallback: 'Valores das peças (unitário e total)',    docTypes: [...QUOTE_LIKE], grupo: 'valores' },
  { key: 'showDiscount',           i18nKey: 'showDiscount',      fallback: 'Descontos (por item e geral)', docTypes: [...QUOTE_LIKE, 'invoice'], grupo: 'valores' },
  { key: 'showTravelCost',         i18nKey: 'showTravelCost',    fallback: 'Deslocamento',                docTypes: [...QUOTE_LIKE, 'invoice'], grupo: 'valores' },
  { key: 'showTax',                i18nKey: 'showTax',           fallback: 'Impostos',                    docTypes: [...QUOTE_LIKE, 'invoice'], grupo: 'valores' },
  { key: 'showCardFee',            i18nKey: 'showCardFee',       fallback: 'Taxa de cartão',              docTypes: [...QUOTE_LIKE, 'invoice'], grupo: 'valores' },
  { key: 'showBankDetails',        i18nKey: 'showBankDetails',   fallback: 'Dados bancários e Pix',       docTypes: [...QUOTE_LIKE, 'invoice'], grupo: 'valores' },
  { key: 'showPaymentInstructions', i18nKey: 'showPaymentInstructions', fallback: 'Instruções de pagamento', docTypes: ['invoice'], grupo: 'valores' },
  { key: 'showExtraNotes',         i18nKey: 'showExtraNotes',    fallback: 'Observações para impressão',  docTypes: [...QUOTE_LIKE, 'invoice'], grupo: 'conteudo' },
  { key: 'showTerms',              i18nKey: 'showTerms',         fallback: 'Termos e condições',          docTypes: [...QUOTE_LIKE], grupo: 'conteudo' },
  { key: 'showSignature',          i18nKey: 'showSignature',     fallback: 'Campo de assinatura',         docTypes: [...QUOTE_LIKE], grupo: 'conteudo' },
  { key: 'showProductImages',      i18nKey: 'showProductImages', fallback: 'Fotos dos produtos',          docTypes: [...QUOTE_LIKE], requiresProductImages: true, grupo: 'conteudo' },
];

/** Todas as chaves booleanas conhecidas — usada por `resolvePdfOptions` para descartar
 *  qualquer coisa fora do contrato que esteja gravada em `app_settings`. */
export const PDF_OPTION_KEYS: readonly PdfOptionKey[] = PDF_OPTION_CATALOG.map(e => e.key);

/**
 * Itens a exibir para um tipo de documento, já com rótulo resolvido.
 *
 * `labels` é o `t.pdf` do i18n; a entrada sem `i18nKey` (ou com tradução faltando) cai no
 * texto fixo em pt-BR — que é o que o diálogo já fazia antes deste catálogo existir.
 *
 * `hasProductImages` só é considerado quando `includeConditional` é `true` (o diálogo). Na
 * tela de padrão da empresa ele não se aplica: lá se configura a intenção, não um documento.
 */
export function pdfOptionItems(
  documentType: PDFDocumentType,
  labels: Record<string, string> | undefined,
  opts?: { hasProductImages?: boolean; includeConditional?: boolean },
): Array<{ key: PdfOptionKey; label: string; overridesOthers: boolean; grupo: 'valores' | 'conteudo' }> {
  const { hasProductImages = false, includeConditional = true } = opts ?? {};
  return PDF_OPTION_CATALOG
    .filter(e => e.docTypes.includes(documentType))
    // `includeConditional: false` é a tela de padrão da empresa: lá não há documento, então
    // a opção de fotos aparece sempre e a escolha por documento (via de execução) não aparece.
    .filter(e => includeConditional ? (!e.requiresProductImages || hasProductImages) : !e.perDocumentOnly)
    .map(e => ({
      key: e.key,
      label: labels?.[e.i18nKey] || e.fallback,
      overridesOthers: !!e.overridesOthers,
      grupo: e.grupo,
    }));
}

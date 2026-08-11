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
  /** chave dentro de `t.pdf`; ausente = ainda sem tradução (MF-AUD-030), usa `fallback` */
  i18nKey?: string;
  fallback: string;
  docTypes: PDFDocumentType[];
  /** só entra na lista do diálogo quando o documento tem peça com foto */
  requiresProductImages?: boolean;
  /** escolha de um documento específico — não faz sentido como padrão da empresa */
  perDocumentOnly?: boolean;
  /** quando ligada, esvazia as demais: os outros toggles perdem efeito */
  overridesOthers?: boolean;
};

const QUOTE_LIKE: PDFDocumentType[] = ['quote', 'service_order'];

export const PDF_OPTION_CATALOG: readonly CatalogEntry[] = [
  { key: 'hideFinancials',                                       fallback: 'Via de execução (sem valores)', docTypes: ['service_order'], perDocumentOnly: true, overridesOthers: true },
  { key: 'showServicePrices',      i18nKey: 'showServicePrices', fallback: 'Preço unitário dos serviços', docTypes: [...QUOTE_LIKE, 'invoice'] },
  { key: 'showPartsPrices',        i18nKey: 'showPartsPrices',   fallback: 'Preço unitário das peças',    docTypes: [...QUOTE_LIKE] },
  { key: 'showTravelCost',         i18nKey: 'showTravelCost',    fallback: 'Custo de deslocamento',       docTypes: [...QUOTE_LIKE, 'invoice'] },
  { key: 'showDiscount',           i18nKey: 'showDiscount',      fallback: 'Desconto',                    docTypes: [...QUOTE_LIKE, 'invoice'] },
  { key: 'showTax',                i18nKey: 'showTax',           fallback: 'Impostos',                    docTypes: [...QUOTE_LIKE, 'invoice'] },
  { key: 'showCardFee',                                          fallback: 'Mostrar taxa de cartão',      docTypes: [...QUOTE_LIKE, 'invoice'] },
  { key: 'showCommission',         i18nKey: 'showCommission',    fallback: 'Comissão e total líquido',    docTypes: [...QUOTE_LIKE] },
  { key: 'showBankDetails',                                      fallback: 'Mostrar dados bancários',     docTypes: ['invoice'] },
  { key: 'showPaymentInstructions',                              fallback: 'Mostrar instruções de pagamento', docTypes: ['invoice'] },
  { key: 'showTerms',              i18nKey: 'showTerms',         fallback: 'Termos e condições',          docTypes: [...QUOTE_LIKE, 'invoice'] },
  { key: 'showSignature',          i18nKey: 'showSignature',     fallback: 'Campo de assinatura',         docTypes: [...QUOTE_LIKE] },
  { key: 'showProductImages',                                    fallback: 'Incluir fotos dos produtos',  docTypes: [...QUOTE_LIKE, 'invoice'], requiresProductImages: true },
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
): Array<{ key: PdfOptionKey; label: string; overridesOthers: boolean }> {
  const { hasProductImages = false, includeConditional = true } = opts ?? {};
  return PDF_OPTION_CATALOG
    .filter(e => e.docTypes.includes(documentType))
    // `includeConditional: false` é a tela de padrão da empresa: lá não há documento, então
    // a opção de fotos aparece sempre e a escolha por documento (via de execução) não aparece.
    .filter(e => includeConditional ? (!e.requiresProductImages || hasProductImages) : !e.perDocumentOnly)
    .map(e => ({
      key: e.key,
      label: (e.i18nKey ? labels?.[e.i18nKey] : undefined) || e.fallback,
      overridesOthers: !!e.overridesOthers,
    }));
}

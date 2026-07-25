// Estado do formulário de emissão de NF-e, persistido como rascunho
// (tabela fiscal_emission_drafts, coluna form_state jsonb).
//
// Extraído como módulo PURO e testado de propósito: o projeto não roda type-check
// no build (vite/esbuild só remove tipos; o tsc da raiz tem files:[] e não checa
// nada), então um campo esquecido no collect/apply passa batido e o rascunho
// restaura errado. normalizeDraftState() é a rede: preenche defaults para
// rascunhos antigos ou de esquema divergente, sem quebrar o applyDraftState.

// Só os campos do item que a listagem precisa (para calcular o total exibido).
// O item completo (DraftItem, definido na página) é preservado como-está em items.
export interface FiscalDraftItemLike {
  name?: string;
  quantity?: number;
  unit_price?: number;
  discount?: number; // total do item (vDesc)
  other_expenses?: number; // total do item (vOutro / IPI na devolução)
  [k: string]: unknown;
}

export interface FiscalDraftState {
  version: 1;
  emitOrigin: { type: string; id: string | null };
  natureOfOperation: string;
  clientId: string;
  recipientName: string;
  recipientDocument: string;
  recipientEmail: string;
  recipientIeIndicator: number;
  recipientIe: string;
  address: unknown;
  paymentMethod: string;
  payMode: 'avista' | 'parcelado';
  payN: number;
  payInterval: number;
  payFirstDue: string;
  presenceIndicator: number;
  consumerFinal: boolean;
  additionalInfo: string;
  purchaseOrder: string;
  buyerName: string;
  returnSource: unknown;
  referencedAccessKey: string;
  items: FiscalDraftItemLike[];
  emitIdempotencyKey: string;
}

export interface FiscalDraftMeta {
  label: string;
  nature_of_operation: string;
  recipient_name: string;
  total_amount: number;
}

// Total exibido na lista: soma de (qtd × unitário − desconto + outras despesas)
// por item — mesma composição do vNF (vProd − vDesc + vOutro).
export function computeDraftTotal(items: FiscalDraftItemLike[] | undefined): number {
  if (!Array.isArray(items)) return 0;
  return items.reduce((sum, it) => {
    const q = Number(it?.quantity) || 0;
    const u = Number(it?.unit_price) || 0;
    const d = Number(it?.discount) || 0;
    const o = Number(it?.other_expenses) || 0;
    return sum + q * u - d + o;
  }, 0);
}

const NATURE_LABELS: Record<string, string> = {
  venda: 'Venda',
  devolucao: 'Devolução',
  remessa: 'Remessa',
  retorno: 'Retorno',
};

export function natureLabel(nature: string | undefined): string {
  if (!nature) return 'NF-e';
  return NATURE_LABELS[nature] || nature;
}

// Metadados desnormalizados para a coluna da lista (barato de exibir sem abrir o
// form_state). label editável cai para "destinatário · natureza" quando vazio.
export function computeDraftMeta(state: FiscalDraftState, customLabel?: string): FiscalDraftMeta {
  const recipient = (state.recipientName || '').trim();
  const nature = natureLabel(state.natureOfOperation);
  const label = (customLabel || '').trim() || `${recipient || 'Sem destinatário'} · ${nature}`;
  return {
    label,
    nature_of_operation: state.natureOfOperation || '',
    recipient_name: recipient,
    total_amount: computeDraftTotal(state.items),
  };
}

// Preenche defaults para qualquer campo ausente — protege o applyDraftState de
// rascunhos gravados por uma versão anterior do form (schema drift). Nunca lança.
export function normalizeDraftState(raw: unknown): FiscalDraftState {
  const s = (raw && typeof raw === 'object' ? raw : {}) as Partial<FiscalDraftState>;
  return {
    version: 1,
    emitOrigin:
      s.emitOrigin && typeof s.emitOrigin === 'object'
        ? { type: String((s.emitOrigin as any).type ?? 'manual'), id: (s.emitOrigin as any).id ?? null }
        : { type: 'manual', id: null },
    natureOfOperation: s.natureOfOperation ?? 'venda',
    clientId: s.clientId ?? '',
    recipientName: s.recipientName ?? '',
    recipientDocument: s.recipientDocument ?? '',
    recipientEmail: s.recipientEmail ?? '',
    recipientIeIndicator: Number.isFinite(s.recipientIeIndicator as number) ? (s.recipientIeIndicator as number) : 9,
    recipientIe: s.recipientIe ?? '',
    address: s.address ?? null,
    paymentMethod: s.paymentMethod ?? '01',
    payMode: s.payMode === 'parcelado' ? 'parcelado' : 'avista',
    payN: Number.isFinite(s.payN as number) ? (s.payN as number) : 2,
    payInterval: Number.isFinite(s.payInterval as number) ? (s.payInterval as number) : 30,
    payFirstDue: s.payFirstDue ?? '',
    presenceIndicator: Number.isFinite(s.presenceIndicator as number) ? (s.presenceIndicator as number) : 1,
    consumerFinal: s.consumerFinal ?? true,
    additionalInfo: s.additionalInfo ?? '',
    purchaseOrder: s.purchaseOrder ?? '',
    buyerName: s.buyerName ?? '',
    returnSource: s.returnSource ?? null,
    referencedAccessKey: s.referencedAccessKey ?? '',
    items: Array.isArray(s.items) ? (s.items as FiscalDraftItemLike[]) : [],
    emitIdempotencyKey: s.emitIdempotencyKey ?? '',
  };
}

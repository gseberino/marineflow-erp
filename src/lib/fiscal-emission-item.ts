// Mapeamento DraftItem (tela) → item do corpo de emissão (fiscal-emit).
//
// Extraído como função PURA e testada de propósito: o projeto não roda type-check
// no build (vite build não checa tipos; o tsc da raiz tem files:[] e não checa
// nada — só `tsc -b` checa), então um typo de campo (ex.: it.otherExpenses em vez
// de it.other_expenses) passa batido e vaza para produção. O teste desta função é
// a rede que pega esse tipo de erro.

// Subconjunto do DraftItem que a emissão lê.
export interface EmissionDraftItem {
  productId?: string | null;
  code: string;
  name: string;
  ncm: string;
  cfop: string;
  unit: string;
  quantity: number;
  unit_price: number;
  discount?: number; // prod/vDesc
  other_expenses?: number; // prod/vOutro (outras despesas acessórias genuínas)
  ipiUnit?: number; // IPI POR UNIDADE da nota de compra (devolução) → vira returned_ipi
  csosn?: string;
  origin: number;
  icms_rate: number;
  pis_rate: number;
  cofins_rate: number;
  ipi_rate: number;
  referencedKey?: string | null; // chave da NF-e original (devolução)
  referencedItemNumber?: number | null;
}

export interface EmissionBodyItem {
  product_id?: string;
  code: string;
  name: string;
  ncm: string;
  cfop: string;
  unit: string;
  quantity: number;
  unit_price: number;
  discount: number;
  other_expenses: number;
  // IPI devolvido (devolução do Simples) → det/impostoDevol/IPI/vIPIDevol na Contora.
  // É o instrumento CORRETO (gera crédito de IPI ao fornecedor), no lugar do vOutro.
  returned_ipi?: { value: number };
  csosn?: string;
  origin: number;
  icms_rate: number;
  pis_rate: number;
  cofins_rate: number;
  ipi_rate: number;
  referenced_key?: string;
  referenced_item?: number;
}

export function buildEmissionItem(it: EmissionDraftItem): EmissionBodyItem {
  return {
    product_id: it.productId || undefined,
    code: it.code,
    name: it.name,
    ncm: it.ncm,
    cfop: it.cfop,
    unit: it.unit,
    quantity: it.quantity,
    unit_price: it.unit_price,
    discount: it.discount || 0, // vDesc por item (prod/vDesc)
    other_expenses: it.other_expenses || 0, // vOutro por item (despesas acessórias)
    // IPI da devolução: valor proporcional à quantidade devolvida (ipiUnit × qtd),
    // enviado como returned_ipi (impostoDevol/vIPIDevol) — não mais em vOutro.
    returned_ipi:
      it.ipiUnit && it.ipiUnit > 0
        ? { value: Math.round(it.ipiUnit * it.quantity * 100) / 100 }
        : undefined,
    csosn: it.csosn || undefined,
    origin: it.origin,
    icms_rate: it.icms_rate,
    pis_rate: it.pis_rate,
    cofins_rate: it.cofins_rate,
    ipi_rate: it.ipi_rate,
    referenced_key: it.referencedKey || undefined, // → referenced_documents (nível da nota)
    referenced_item: it.referencedItemNumber || undefined,
  };
}

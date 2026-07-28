/* ─────────────────────────────────────────────────────────────────────────────
   Matemática financeira da Ordem de Serviço — módulo PURO.

   Extraído 1:1 do bloco "Financial summary" do ServiceOrderForm (Fase 3,
   passo 1 do plano de UI): estas funções pinam o comportamento atual para
   que a decomposição do formulário nunca altere um centavo. Qualquer
   mudança intencional de regra deve começar pelos testes em
   os-financials.test.ts.
──────────────────────────────────────────────────────────────────────────── */

export interface InstallmentRow {
  label: string;
  services_pct: number;
  parts_pct: number;
  expenses_pct: number;
  days_after_approval: number;
  tipo?: 'aprovacao' | 'entrega' | 'prazo';
}

export interface CardFeeRate {
  installments: number;
  fee_percent: number | null;
}

export interface OsFinancialInput {
  laborCost: number;
  partsCost: number;
  operationalCost: number;
  travelCost: number;
  /** form.is_travel_billable !== false — deslocamento só entra se faturável. */
  isTravelBillable: boolean;
  subcontractCost: number;
  discountAmount: number;
  taxAmount: number;
  cardFeePassthroughEnabled: boolean;
  /** Parcelas persistidas na OS (form.card_installments), não as do simulador. */
  cardInstallments: number;
  cardFees: CardFeeRate[] | null | undefined;
}

export interface OsFinancialResult {
  billableTravelCost: number;
  expensesTotal: number;
  subtotal: number;
  /** Valor com desconto/imposto, antes de taxa de cartão repassada. */
  base: number;
  passthroughFeePercent: number;
  passthroughCardFeeAmount: number;
  grandTotal: number;
  /** Razão base/subtotal aplicada proporcionalmente às parcelas (1 se subtotal=0). */
  discountRatio: number;
}

const round2 = (v: number) => Math.round(v * 100) / 100;

export function computeOsFinancials(input: OsFinancialInput): OsFinancialResult {
  const billableTravelCost = input.isTravelBillable ? (input.travelCost || 0) : 0;
  const expensesTotal = (input.operationalCost || 0) + billableTravelCost + (input.subcontractCost || 0);
  const subtotal =
    (input.laborCost || 0) + (input.partsCost || 0) + (input.operationalCost || 0) +
    billableTravelCost + (input.subcontractCost || 0);
  const base = subtotal - (input.discountAmount || 0) + (input.taxAmount || 0);

  const passthroughFee = input.cardFees?.find((f) => f.installments === input.cardInstallments);
  const passthroughFeePercent = Number(passthroughFee?.fee_percent || 0);
  const passthroughCardFeeAmount =
    input.cardFeePassthroughEnabled && passthroughFeePercent > 0
      ? round2(base * passthroughFeePercent / (100 - passthroughFeePercent))
      : 0;

  const grandTotal = base + passthroughCardFeeAmount;
  const discountRatio = subtotal > 0 ? base / subtotal : 1;

  return {
    billableTravelCost, expensesTotal, subtotal, base,
    passthroughFeePercent, passthroughCardFeeAmount, grandTotal, discountRatio,
  };
}

/** Normaliza linhas de parcelamento vindas de preset OU customizadas
 *  (linhas antigas usam `percent` único para serviços e peças). */
export function normalizeInstallmentRows(source: unknown): InstallmentRow[] {
  if (!Array.isArray(source)) return [];
  return (source as Record<string, unknown>[]).map((r) => ({
    label: String(r.label || ''),
    services_pct: Number(r.services_pct ?? r.percent ?? 0),
    parts_pct: Number(r.parts_pct ?? r.percent ?? 0),
    expenses_pct: Number(r.expenses_pct ?? 0),
    days_after_approval: Number(r.days_after_approval ?? 0),
    tipo: r.tipo as InstallmentRow['tipo'],
  }));
}

export function calcInstallmentAmount(
  row: InstallmentRow,
  ctx: { laborCost: number; partsCost: number; expensesTotal: number; discountRatio: number },
): number {
  const gross =
    (ctx.laborCost * row.services_pct / 100) +
    (ctx.partsCost * row.parts_pct / 100) +
    (ctx.expensesTotal * row.expenses_pct / 100);
  return round2(gross * ctx.discountRatio);
}

/** Sinal (depósito): primeira linha com tipo 'aprovacao' OU days=0. */
export function findSignalRow(rows: InstallmentRow[]): InstallmentRow | undefined {
  return rows.find((r) => r.tipo === 'aprovacao' || r.days_after_approval === 0);
}

/** Simulador de Recebimento no cartão: bruto a cobrar para líquido = base. */
export function simulateCardReceipt(
  base: number,
  feePercent: number,
  installments: number,
): { cardGross: number; cardFeeAmount: number; installmentValue: number } {
  const pct = Number(feePercent || 0);
  const cardGross = pct > 0 ? base / (1 - pct / 100) : base;
  const cardFeeAmount = cardGross - base;
  const installmentValue = installments > 0 ? cardGross / installments : cardGross;
  return { cardGross, cardFeeAmount, installmentValue };
}

/** Desconto aplicado POR ITEM (serviço/peça) — separado do desconto de categoria. */
export function computeItemDiscountTotal(
  services: { quantity: number; unit_price_snapshot: number; line_total: number }[] | null | undefined,
  parts: { quantity: number; unit_sale_snapshot: number; line_total_sale: number }[] | null | undefined,
): number {
  return round2(
    (services || []).reduce((s, x) => s + (x.quantity * x.unit_price_snapshot - x.line_total), 0) +
    (parts || []).reduce((s, x) => s + (x.quantity * x.unit_sale_snapshot - x.line_total_sale), 0),
  );
}

/** Lucro de peças (só modo edição, nunca no PDF). */
export function computePartsProfit(
  parts: { line_total_sale?: number | null; line_total_cost?: number | null }[] | null | undefined,
): { partsRevenue: number; partsCostItems: number; partsProfit: number; partsMarginPct: number } {
  const partsRevenue = (parts || []).reduce((sum, p) => sum + (p.line_total_sale || 0), 0);
  const partsCostItems = (parts || []).reduce((sum, p) => sum + (p.line_total_cost || 0), 0);
  const partsProfit = partsRevenue - partsCostItems;
  const partsMarginPct = partsRevenue > 0 ? (partsProfit / partsRevenue) * 100 : 0;
  return { partsRevenue, partsCostItems, partsProfit, partsMarginPct };
}

/** Totais financeiros da OS a partir dos recebíveis reais (M1). */
export function computeReceivablesStatus(
  receivables: { amount?: number | null; paid_amount?: number | null; balance_amount?: number | null }[] | null | undefined,
): { totalCharged: number; totalPaid: number; balance: number; payStatus: 'paid' | 'partially_paid' | 'unpaid' } {
  const totalCharged = (receivables || []).reduce((s, r) => s + Number(r.amount || 0), 0);
  const totalPaid = (receivables || []).reduce((s, r) => s + Number(r.paid_amount || 0), 0);
  const balance = (receivables || []).reduce((s, r) => s + Number(r.balance_amount || 0), 0);
  const payStatus = balance <= 0 && totalCharged > 0 ? 'paid' : totalPaid > 0 ? 'partially_paid' : 'unpaid';
  return { totalCharged, totalPaid, balance, payStatus };
}

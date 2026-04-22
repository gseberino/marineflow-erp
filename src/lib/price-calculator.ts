export type PriceComponents = {
  cost_price: number
  profit_margin: number
  tax_rate: number
  commission_rate: number
}

export type PriceBreakdown = {
  cost_price: number
  profit_margin: number
  tax_rate: number
  commission_rate: number
  sale_price: number
  tax_amount: number
  commission_amount: number
  profit_amount: number
  markup: number
}

/**
 * CORRECT formula for Simples Nacional and any business where
 * taxes and commission are deducted FROM revenue (not added on top).
 *
 * sale_price = cost / (1 - margin% - tax% - commission%)
 */
/**
 * Markup mode: sale_price = cost × (1 + markup/100), with taxes and commission
 * applied as percentage of the resulting sale price (informational).
 */
export function calculateByMarkup(c: PriceComponents & { markup: number }): PriceBreakdown {
  const sale_price = c.cost_price * (1 + (c.markup || 0) / 100)
  const tax_amount = sale_price * (c.tax_rate / 100)
  const commission_amount = sale_price * (c.commission_rate / 100)
  const profit_amount = sale_price - c.cost_price - tax_amount - commission_amount
  const markup = c.cost_price > 0
    ? ((sale_price - c.cost_price) / c.cost_price) * 100
    : 0
  return {
    cost_price: round2(c.cost_price),
    profit_margin: c.profit_margin,
    tax_rate: c.tax_rate,
    commission_rate: c.commission_rate,
    sale_price: round2(sale_price),
    tax_amount: round2(tax_amount),
    commission_amount: round2(commission_amount),
    profit_amount: round2(profit_amount),
    markup: round2(markup),
  }
}

export function calculateSalePrice(c: PriceComponents): PriceBreakdown {
  const marginD = c.profit_margin / 100
  const taxD = c.tax_rate / 100
  const commD = c.commission_rate / 100
  const divisor = 1 - marginD - taxD - commD

  if (divisor <= 0) {
    return {
      cost_price: c.cost_price, profit_margin: c.profit_margin,
      tax_rate: c.tax_rate, commission_rate: c.commission_rate,
      sale_price: 0, tax_amount: 0, commission_amount: 0,
      profit_amount: 0, markup: 0,
    }
  }

  const sale_price = c.cost_price / divisor
  const tax_amount = sale_price * taxD
  const commission_amount = sale_price * commD
  const profit_amount = sale_price - c.cost_price - tax_amount - commission_amount
  const markup = c.cost_price > 0
    ? ((sale_price - c.cost_price) / c.cost_price) * 100
    : 0

  return {
    cost_price: round2(c.cost_price),
    profit_margin: c.profit_margin,
    tax_rate: c.tax_rate,
    commission_rate: c.commission_rate,
    sale_price: round2(sale_price),
    tax_amount: round2(tax_amount),
    commission_amount: round2(commission_amount),
    profit_amount: round2(profit_amount),
    markup: round2(markup),
  }
}

/**
 * Back-calculate margin from a manually entered sale price.
 */
export function calculateMarginFromPrice(
  cost_price: number,
  sale_price: number,
  tax_rate: number,
  commission_rate: number
): number {
  if (sale_price <= 0 || cost_price <= 0) return 0
  const margin = 1 - (cost_price / sale_price)
    - (tax_rate / 100) - (commission_rate / 100)
  return round2(margin * 100)
}

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

export const CSOSN_OPTIONS = [
  { value: '101', label: '101 — Tributada com permissão de crédito' },
  { value: '102', label: '102 — Tributada sem permissão de crédito' },
  { value: '103', label: '103 — Isenção do ICMS (faixa de receita)' },
  { value: '201', label: '201 — Com permissão de crédito e ST' },
  { value: '202', label: '202 — Sem permissão de crédito e com ST' },
  { value: '300', label: '300 — Imune' },
  { value: '400', label: '400 — Não tributada pelo Simples Nacional' },
  { value: '500', label: '500 — ICMS cobrado anteriormente por ST' },
  { value: '900', label: '900 — Outros' },
]

export const FISCAL_ORIGIN_OPTIONS = [
  { value: 0, label: '0 — Nacional' },
  { value: 1, label: '1 — Estrangeira (importação direta)' },
  { value: 2, label: '2 — Estrangeira (mercado interno)' },
  { value: 3, label: '3 — Nacional com > 40% conteúdo estrangeiro' },
  { value: 4, label: '4 — Nacional produção básica' },
  { value: 5, label: '5 — Nacional com < 40% conteúdo estrangeiro' },
  { value: 6, label: '6 — Estrangeira (importação direta) sem similar nacional' },
  { value: 7, label: '7 — Estrangeira (mercado interno) sem similar nacional' },
  { value: 8, label: '8 — Nacional com conteúdo de importação > 70%' },
]

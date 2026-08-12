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
  /**
   * [NOVO-009] Por que não há preço, quando não há. `null` = cálculo válido.
   *
   * Campo NOVO e opcional de propósito: os três consumidores atuais
   * (PriceCalculator, PriceCalculatorDialog, ProductFormDialog) continuam compilando e
   * funcionando sem tocar em nada. Quem quiser avisar o usuário lê daqui.
   *
   * Antes, margem+imposto+comissão ≥ 100% devolvia `sale_price: 0` calado — e zero é um
   * preço que PARECE válido: entra no campo, salva no produto, e sai numa proposta.
   */
  error: string | null
  /**
   * Aviso para o caso que é matematicamente válido mas quase certamente engano de digitação.
   * Não bloqueia nada. `null` quando não há o que avisar.
   */
  warning: string | null
}

/**
 * CORRECT formula for Simples Nacional and any business where
 * taxes and commission are deducted FROM revenue (not added on top).
 *
 * sale_price = cost / (1 - margin% - tax% - commission%)
 */
/**
 * Acima deste multiplicador o preço deixa de parecer preço. [NOVO-009]
 *
 * Com divisor 0,01 (margem+imposto+comissão = 99%) o preço é CEM VEZES o custo: um item de
 * R$ 100 vira R$ 10.000 no campo, sem uma linha de aviso. A conta está certa; o que está
 * errado é a tela aceitar isso calada, porque quem digitou 99 quase sempre queria 9.
 *
 * O corte em 20× é um AVISO, nunca um bloqueio — margem alta legítima existe (peça rara,
 * serviço especializado) e recusar seria decidir preço pelo dono. Se ele quiser outro
 * número, é esta constante. Registrado no livro do turno.
 */
export const MULTIPLICADOR_SUSPEITO = 20

export function calculateSalePrice(c: PriceComponents): PriceBreakdown {
  const vazio = (error: string | null, warning: string | null = null): PriceBreakdown => ({
    cost_price: round2(c.cost_price), profit_margin: c.profit_margin,
    tax_rate: c.tax_rate, commission_rate: c.commission_rate,
    sale_price: 0, tax_amount: 0, commission_amount: 0,
    profit_amount: 0, markup: 0, error, warning,
  })

  // Entrada inválida devolve motivo, não NaN. `Number.isFinite` pega undefined, null,
  // string vazia coagida e o próprio NaN de uma só vez.
  const numeros = [c.cost_price, c.profit_margin, c.tax_rate, c.commission_rate]
  if (!numeros.every((n) => Number.isFinite(Number(n)))) {
    return vazio('Preencha custo, margem, imposto e comissão com números.')
  }
  if (Number(c.cost_price) < 0) {
    return vazio('O custo não pode ser negativo.')
  }
  if ([c.profit_margin, c.tax_rate, c.commission_rate].some((n) => Number(n) < 0)) {
    return vazio('Margem, imposto e comissão não podem ser negativos.')
  }

  const marginD = c.profit_margin / 100
  const taxD = c.tax_rate / 100
  const commD = c.commission_rate / 100
  const divisor = 1 - marginD - taxD - commD

  // [NOVO-009] ≥ 100% não é "preço alto": é impossível. Margem, imposto e comissão saem da
  // RECEITA, então somados a 100% não sobra nada para pagar o custo — e acima disso a conta
  // vira negativa. Antes isto devolvia `sale_price: 0` em silêncio, e zero é um preço que
  // parece válido: entra no campo, salva no produto e sai numa proposta ao cliente.
  const soma = round2(c.profit_margin + c.tax_rate + c.commission_rate)
  if (divisor <= 0) {
    return vazio(
      `Margem (${c.profit_margin}%) + imposto (${c.tax_rate}%) + comissão (${c.commission_rate}%) `
      + `somam ${soma}%. Como os três saem do preço de venda, a soma precisa ficar ABAIXO de `
      + `100% — senão não sobra nada para pagar o custo. Reduza um deles.`,
    )
  }

  const sale_price = c.cost_price / divisor
  const tax_amount = sale_price * taxD
  const commission_amount = sale_price * commD
  const profit_amount = sale_price - c.cost_price - tax_amount - commission_amount
  const markup = c.cost_price > 0
    ? ((sale_price - c.cost_price) / c.cost_price) * 100
    : 0

  // Válido, mas provavelmente engano de digitação: 99 no lugar de 9.
  // Arredonda ANTES de comparar: 1/(1-0,95) dá 19.999999999999982 em ponto flutuante, e um
  // corte que depende dessa lasca decide diferente para números que a pessoa digitou iguais.
  const multiplicador = c.cost_price > 0 ? round2(sale_price / c.cost_price) : 0
  const warning = multiplicador >= MULTIPLICADOR_SUSPEITO
    ? `O preço ficou ${multiplicador}× o custo, porque margem + imposto + comissão `
      + `somam ${soma}%. A conta está certa — confira se era isso mesmo que você quis digitar.`
    : null

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
    error: null,
    warning,
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

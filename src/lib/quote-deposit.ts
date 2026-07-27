// Cálculo do SINAL (depósito) de um orçamento — FONTE ÚNICA da verdade.
//
// POR QUE ISTO EXISTE: o valor do sinal era calculado em DOIS lugares com fórmulas diferentes —
// no orçamento/PDF (ServiceOrderForm) aplicando o `discountRatio` sobre os valores brutos, e no
// botão "Receber sinal" da lista (RegisterDepositDialog) SEM o desconto. Resultado: a mesma
// condição de pagamento dava valores diferentes (ex.: ORÇ-00060 mostrava 18.505,67 na lista vs
// 18.001,04 no orçamento). Esta lib centraliza a regra para os dois usarem exatamente a mesma.
//
// A regra (idêntica à do ServiceOrderForm):
//   subtotal = mão de obra + peças + operacional + deslocamento faturável + subcontratação  (BRUTO)
//   base     = subtotal − desconto + imposto                                                (LÍQUIDO)
//   discountRatio = base / subtotal
//   valor da parcela = (labor·svc% + parts·parts% + despesas·exp%) × discountRatio

export interface DepositInstallment {
  label?: string;
  services_pct?: number;
  parts_pct?: number;
  expenses_pct?: number;
  percent?: number; // fallback antigo (mesma % p/ serviços e peças)
  days_after_approval?: number;
  tipo?: "aprovacao" | "entrega" | "prazo";
}

export interface DepositOrderLike {
  labor_cost_total?: number | null;
  parts_cost_total?: number | null;
  operational_cost_total?: number | null;
  travel_cost_total?: number | null;
  subcontract_cost_total?: number | null;
  is_travel_billable?: boolean | null;
  discount_amount?: number | null;
  tax_amount?: number | null;
}

export interface DepositComputation {
  laborCost: number;
  partsCost: number;
  expensesTotal: number;
  subtotal: number;
  base: number;
  discountRatio: number;
  /** % da parcela de sinal (parcela com tipo='aprovacao' ou days_after_approval=0). null se não houver. */
  signal: { servicesPct: number; partsPct: number; expensesPct: number } | null;
  /** valor do sinal já com desconto aplicado; null se não houver parcela de sinal. */
  amount: number | null;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

/** Deriva mão de obra, peças, despesas, subtotal, base e o discountRatio de um orçamento. */
export function depositBaseFromOrder(order: DepositOrderLike) {
  const laborCost = Number(order.labor_cost_total || 0);
  const partsCost = Number(order.parts_cost_total || 0);
  const operationalCost = Number(order.operational_cost_total || 0);
  // Deslocamento só entra no valor cobrado do cliente quando marcado como faturável.
  const billableTravelCost = order.is_travel_billable !== false ? Number(order.travel_cost_total || 0) : 0;
  const subcontractCost = Number(order.subcontract_cost_total || 0);
  const expensesTotal = operationalCost + billableTravelCost + subcontractCost;
  const subtotal = laborCost + partsCost + expensesTotal;
  const base = subtotal - Number(order.discount_amount || 0) + Number(order.tax_amount || 0);
  const discountRatio = subtotal > 0 ? base / subtotal : 1;
  return { laborCost, partsCost, expensesTotal, subtotal, base, discountRatio };
}

/** Valor de uma parcela a partir de percentuais por categoria, já com o desconto aplicado. */
export function depositAmountFromPcts(
  laborCost: number,
  partsCost: number,
  expensesTotal: number,
  discountRatio: number,
  servicesPct: number,
  partsPct: number,
  expensesPct = 0,
): number {
  const gross = laborCost * servicesPct / 100 + partsCost * partsPct / 100 + expensesTotal * expensesPct / 100;
  return round2(gross * discountRatio);
}

function normalizeInstallment(r: DepositInstallment) {
  return {
    servicesPct: Number(r.services_pct ?? r.percent ?? 0),
    partsPct: Number(r.parts_pct ?? r.percent ?? 0),
    expensesPct: Number(r.expenses_pct ?? 0),
    days: Number(r.days_after_approval ?? 0),
    tipo: r.tipo,
  };
}

/** Cálculo completo do sinal do orçamento a partir das parcelas da condição de pagamento. */
export function computeDeposit(
  order: DepositOrderLike,
  installments: DepositInstallment[] | null | undefined,
): DepositComputation {
  const b = depositBaseFromOrder(order);
  const rows = Array.isArray(installments) ? installments.map(normalizeInstallment) : [];
  const signalRow = rows.find((r) => r.tipo === "aprovacao" || r.days === 0);
  const signal = signalRow
    ? { servicesPct: signalRow.servicesPct, partsPct: signalRow.partsPct, expensesPct: signalRow.expensesPct }
    : null;
  const amount = signal
    ? depositAmountFromPcts(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, signal.servicesPct, signal.partsPct, signal.expensesPct)
    : null;
  return { ...b, signal, amount };
}

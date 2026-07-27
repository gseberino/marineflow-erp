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

/**
 * Condição praticada pela empresa quando o orçamento não define uma: o sinal cobre 100%
 * de materiais e despesas mais 50% da mão de obra, e o saldo (os outros 50% de serviço)
 * fica para a entrega.
 *
 * Existe para que o diálogo "Receber sinal" e a conciliação bancária esperem o MESMO
 * valor. Enquanto o diálogo sugeria 30% do total e a conciliação calculava 100/50, o
 * operador registrava um sinal que o motor depois não reconhecia.
 * Espelhada em `supabase/functions/_shared/banking/quote-deposit.ts` (CONDICAO_PADRAO).
 */
export const CONDICAO_PADRAO = { servicesPct: 50, partsPct: 100, expensesPct: 100 } as const;

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
    label: r.label ?? "",
    servicesPct: Number(r.services_pct ?? r.percent ?? 0),
    partsPct: Number(r.parts_pct ?? r.percent ?? 0),
    expensesPct: Number(r.expenses_pct ?? 0),
    days: Number(r.days_after_approval ?? 0),
    tipo: r.tipo,
  };
}

type NormalizedInstallment = ReturnType<typeof normalizeInstallment>;

/**
 * A parcela é o SINAL (entrada) quando é explicitamente `tipo='aprovacao'`, ou — em condições
 * antigas sem tipo (só `percent`) — quando cai no dia 0.
 *
 * ATENÇÃO: uma parcela `tipo='entrega'` pode ter `days_after_approval=0` (vence "na entrega", não
 * na aprovação) e NÃO é sinal. Por isso a checagem por tipo tem que vir ANTES do fallback por dia —
 * a heurística `days===0` sozinha classificava a parcela de entrega como sinal (bug).
 */
function isSignalInstallment(r: NormalizedInstallment): boolean {
  if (r.tipo === "aprovacao") return true;
  if (r.tipo === "entrega" || r.tipo === "prazo") return false;
  return r.days === 0;
}

/** Uma parcela do cronograma, com o valor já calculado (com desconto). */
export interface ScheduleRow {
  label: string;
  amount: number;
  /** dias após a aprovação (para dueBasis='days'). */
  days: number;
  /** vencimento: 'delivery' = na entrega prevista (scheduled_end_at); 'days' = aprovação + days. */
  dueBasis: "delivery" | "days";
}

export interface PaymentSchedule {
  /** soma das parcelas de SINAL (tipo 'aprovacao' ou dia 0), com desconto. */
  signalAmount: number;
  /** parcelas do SALDO (todas menos a entrada), cada uma já com desconto. */
  balance: ScheduleRow[];
  /** soma do saldo. */
  balanceTotal: number;
}

/**
 * Cronograma completo (sinal + saldo) a partir dos custos já derivados do orçamento e das parcelas
 * da condição de pagamento. Cada parcela usa a MESMA conta do sinal (categoria × discountRatio),
 * então sinal + saldo fecham com o valor líquido do orçamento. Base única para a prévia do saldo
 * (diálogo) e para lançar os recebíveis do saldo (RPC register_deposit_and_convert).
 */
export function computeScheduleFromParts(
  laborCost: number,
  partsCost: number,
  expensesTotal: number,
  discountRatio: number,
  installments: DepositInstallment[] | null | undefined,
): PaymentSchedule {
  const rows = Array.isArray(installments) ? installments.map(normalizeInstallment) : [];
  let signalAmount = 0;
  const balance: ScheduleRow[] = [];
  rows.forEach((r, i) => {
    const amount = depositAmountFromPcts(
      laborCost, partsCost, expensesTotal, discountRatio, r.servicesPct, r.partsPct, r.expensesPct,
    );
    if (isSignalInstallment(r)) {
      signalAmount += amount;
    } else if (amount > 0) {
      const dueBasis: "delivery" | "days" = r.tipo === "entrega" ? "delivery" : "days";
      balance.push({ label: r.label || `Parcela ${i + 1}`, amount, days: r.days, dueBasis });
    }
  });
  return {
    signalAmount: round2(signalAmount),
    balance,
    balanceTotal: round2(balance.reduce((s, b) => s + b.amount, 0)),
  };
}

/** Como computeScheduleFromParts, mas partindo direto de um orçamento. */
export function computeSchedule(
  order: DepositOrderLike,
  installments: DepositInstallment[] | null | undefined,
): PaymentSchedule {
  const b = depositBaseFromOrder(order);
  return computeScheduleFromParts(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, installments);
}

/** Cálculo completo do sinal do orçamento a partir das parcelas da condição de pagamento. */
export function computeDeposit(
  order: DepositOrderLike,
  installments: DepositInstallment[] | null | undefined,
): DepositComputation {
  const b = depositBaseFromOrder(order);
  const rows = Array.isArray(installments) ? installments.map(normalizeInstallment) : [];
  const signalRow = rows.find(isSignalInstallment);
  const signal = signalRow
    ? { servicesPct: signalRow.servicesPct, partsPct: signalRow.partsPct, expensesPct: signalRow.expensesPct }
    : null;
  const amount = signal
    ? depositAmountFromPcts(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, signal.servicesPct, signal.partsPct, signal.expensesPct)
    : null;
  return { ...b, signal, amount };
}

/**
 * Extrai os % da parcela de SINAL das parcelas de uma condição de pagamento — sem precisar dos
 * valores do orçamento. Usado pelo seletor de condição no diálogo "Receber sinal".
 */
export function signalPctsFromInstallments(
  installments: DepositInstallment[] | null | undefined,
): { servicesPct: number; partsPct: number; expensesPct: number } | null {
  const rows = Array.isArray(installments) ? installments.map(normalizeInstallment) : [];
  const s = rows.find(isSignalInstallment);
  return s ? { servicesPct: s.servicesPct, partsPct: s.partsPct, expensesPct: s.expensesPct } : null;
}

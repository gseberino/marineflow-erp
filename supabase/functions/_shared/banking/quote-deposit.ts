// Cálculo do SINAL esperado de um orçamento — espelho de `src/lib/quote-deposit.ts`.
//
// POR QUE ESPELHADO E NÃO IMPORTADO: o frontend (Vite) e as edge functions (Deno) não
// compartilham módulos neste projeto — o padrão da casa é espelhar e anotar, como em
// `src/lib/ai-whatsapp.ts` e `TaskAutomationSettings.tsx`. Para que o espelho não
// divirja em silêncio (que foi exatamente o bug que originou a lib no frontend — o PDF
// e o botão "Receber sinal" calculavam valores diferentes), existe um teste de paridade
// em `src/test/banking-quote-deposit-paridade.test.ts` que roda as duas implementações
// com as mesmas entradas e falha se os resultados diferirem. Ao mexer aqui, mexa lá.
//
// A regra:
//   subtotal = mão de obra + peças + operacional + deslocamento faturável + subcontratação
//   base     = subtotal − desconto + imposto
//   discountRatio = base / subtotal
//   valor da parcela = (labor·svc% + parts·parts% + despesas·exp%) × discountRatio

export interface DepositInstallment {
  label?: string;
  services_pct?: number;
  parts_pct?: number;
  expenses_pct?: number;
  percent?: number;
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

const round2 = (n: number) => Math.round(n * 100) / 100;

export function depositBaseFromOrder(order: DepositOrderLike) {
  const laborCost = Number(order.labor_cost_total || 0);
  const partsCost = Number(order.parts_cost_total || 0);
  const operationalCost = Number(order.operational_cost_total || 0);
  const billableTravelCost = order.is_travel_billable !== false ? Number(order.travel_cost_total || 0) : 0;
  const subcontractCost = Number(order.subcontract_cost_total || 0);
  const expensesTotal = operationalCost + billableTravelCost + subcontractCost;
  const subtotal = laborCost + partsCost + expensesTotal;
  const base = subtotal - Number(order.discount_amount || 0) + Number(order.tax_amount || 0);
  const discountRatio = subtotal > 0 ? base / subtotal : 1;
  return { laborCost, partsCost, expensesTotal, subtotal, base, discountRatio };
}

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

/**
 * A parcela é o SINAL quando é explicitamente `tipo='aprovacao'`, ou — em condições
 * antigas sem tipo — quando cai no dia 0.
 *
 * A checagem por tipo vem ANTES do fallback por dia de propósito: uma parcela
 * `tipo='entrega'` pode ter `days_after_approval=0` (vence "na entrega", não na
 * aprovação) e não é sinal. Espelha `isSignalInstallment` de `src/lib/quote-deposit.ts`.
 */
function isSignalInstallment(r: ReturnType<typeof normalizeInstallment>): boolean {
  if (r.tipo === "aprovacao") return true;
  if (r.tipo === "entrega" || r.tipo === "prazo") return false;
  return r.days === 0;
}

export function signalPctsFromInstallments(
  installments: DepositInstallment[] | null | undefined,
): { servicesPct: number; partsPct: number; expensesPct: number } | null {
  const rows = Array.isArray(installments) ? installments.map(normalizeInstallment) : [];
  const s = rows.find(isSignalInstallment);
  return s ? { servicesPct: s.servicesPct, partsPct: s.partsPct, expensesPct: s.expensesPct } : null;
}

/**
 * Condição padrão da casa, informada pelo usuário em 27/07/2026: o sinal cobre 100% de
 * materiais e despesas mais 50% da mão de obra; o saldo são os 50% restantes de serviço,
 * pagos na entrega. É a mesma regra do preset "50% mão de obra + 100% materiais
 * antecipados" já cadastrado no sistema.
 *
 * Usada quando o orçamento não tem condição definida. Antes disso o fallback era um
 * percentual liso sobre o total (30%), que não corresponde a nada praticado — e fazia a
 * conciliação esperar um valor que o cliente nunca combinou.
 */
export const CONDICAO_PADRAO = { servicesPct: 50, partsPct: 100, expensesPct: 100 } as const;

/**
 * Quanto se espera de sinal deste orçamento.
 *
 * Ordem: a condição acordada no orçamento manda; sem ela, a condição padrão da casa; e o
 * percentual liso só sobra para quando não há como decompor o orçamento em mão de obra e
 * materiais. A `source` sai junto porque a tela precisa distinguir o combinado do estimado.
 */
export function expectedDepositAmount(
  order: DepositOrderLike & { grand_total?: number | null },
  installments: DepositInstallment[] | null | undefined,
  globalPct: number,
): { amount: number; source: "condicao" | "padrao" | "percentual" } | null {
  const b = depositBaseFromOrder(order);

  const pcts = signalPctsFromInstallments(installments);
  if (pcts && (pcts.servicesPct > 0 || pcts.partsPct > 0 || pcts.expensesPct > 0)) {
    const amount = depositAmountFromPcts(
      b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio,
      pcts.servicesPct, pcts.partsPct, pcts.expensesPct,
    );
    if (amount > 0) return { amount, source: "condicao" };
  }

  if (b.subtotal > 0) {
    const amount = depositAmountFromPcts(
      b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio,
      CONDICAO_PADRAO.servicesPct, CONDICAO_PADRAO.partsPct, CONDICAO_PADRAO.expensesPct,
    );
    if (amount > 0) return { amount, source: "padrao" };
  }

  const grandTotal = Number(order.grand_total || 0);
  if (grandTotal > 0 && globalPct > 0) {
    return { amount: round2(grandTotal * globalPct / 100), source: "percentual" };
  }
  return null;
}

/**
 * Saldo que fica para a entrega: o que não entrou no sinal.
 * Com a condição padrão, são os 50% restantes de mão de obra.
 */
export function expectedBalanceAmount(
  order: DepositOrderLike & { grand_total?: number | null },
  depositAmount: number,
): number {
  const b = depositBaseFromOrder(order);
  return round2(Math.max(0, b.base - depositAmount));
}

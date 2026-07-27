import { describe, it, expect } from 'vitest';
import { computeDeposit, depositBaseFromOrder, depositAmountFromPcts, computeSchedule, computeAllInstallments } from './quote-deposit';

// Dados REAIS do ORÇ-00060 (Charline): peças 16.450,67 + serviços 4.110,00 = 20.560,67 bruto,
// desconto 560,67 → grand_total 20.000,00. Condição "100% peças + 50% serviços" no sinal.
// O orçamento/PDF mostra sinal 18.001,04; o botão da lista mostrava 18.505,67 (SEM desconto) — bug.
const ORC_00060 = {
  labor_cost_total: 4110.0,
  parts_cost_total: 16450.67,
  discount_amount: 560.67,
};
const SINAL_100P_50S = [{ tipo: 'aprovacao' as const, services_pct: 50, parts_pct: 100 }];

describe('computeDeposit — sinal com desconto (fonte única)', () => {
  it('ORÇ-00060: aplica o discountRatio → 18.001,04 (não 18.505,67)', () => {
    const r = computeDeposit(ORC_00060, SINAL_100P_50S);
    expect(r.subtotal).toBeCloseTo(20560.67, 2);
    expect(r.base).toBeCloseTo(20000.0, 2);
    expect(r.discountRatio).toBeCloseTo(20000 / 20560.67, 8);
    expect(r.signal).toEqual({ servicesPct: 50, partsPct: 100, expensesPct: 0 });
    expect(r.amount).toBeCloseTo(18001.04, 2);
    // o valor SEM desconto (bug antigo) seria 18.505,67 — garantir que NÃO é esse
    expect(r.amount).not.toBeCloseTo(18505.67, 2);
  });

  it('saldo = grand_total − sinal fecha o total', () => {
    const r = computeDeposit(ORC_00060, SINAL_100P_50S);
    const saldo = Math.round((r.base - (r.amount ?? 0)) * 100) / 100;
    expect(saldo).toBeCloseTo(1998.96, 2);
  });

  it('sem desconto: discountRatio = 1 e valor = bruto', () => {
    const r = computeDeposit({ labor_cost_total: 1000, parts_cost_total: 2000 }, [{ tipo: 'aprovacao', services_pct: 50, parts_pct: 100 }]);
    expect(r.discountRatio).toBe(1);
    expect(r.amount).toBe(2500); // 1000*0.5 + 2000*1.0
  });

  it('sem parcela de sinal → amount null', () => {
    const r = computeDeposit(ORC_00060, [{ tipo: 'prazo', days_after_approval: 30, services_pct: 100, parts_pct: 100 }]);
    expect(r.signal).toBeNull();
    expect(r.amount).toBeNull();
  });

  it('inclui despesas (expenses_pct) e respeita deslocamento não-faturável', () => {
    const order = {
      labor_cost_total: 1000, parts_cost_total: 1000,
      operational_cost_total: 500, travel_cost_total: 300, is_travel_billable: false,
      discount_amount: 0,
    };
    const b = depositBaseFromOrder(order);
    expect(b.expensesTotal).toBe(500); // travel excluído (não-faturável)
    expect(b.subtotal).toBe(2500);
    const r = computeDeposit(order, [{ tipo: 'aprovacao', services_pct: 100, parts_pct: 100, expenses_pct: 100 }]);
    expect(r.amount).toBe(2500); // 1000+1000+500, ratio 1
  });

  it('depositAmountFromPcts é a mesma conta usada no diálogo ao editar %', () => {
    const b = depositBaseFromOrder(ORC_00060);
    const v = depositAmountFromPcts(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, 50, 100, 0);
    expect(v).toBeCloseTo(18001.04, 2);
  });
});

// Condição completa do ORÇ-00060: entrada (100% peças + 50% serviços) na aprovação e o restante
// (50% serviços) em 30 dias. Base para a prévia do saldo (diálogo) e para gerar as cobranças.
const COND_00060_COMPLETA = [
  { tipo: 'aprovacao' as const, services_pct: 50, parts_pct: 100, days_after_approval: 0 },
  { tipo: 'prazo' as const, services_pct: 50, parts_pct: 0, days_after_approval: 30 },
];

describe('computeSchedule — sinal + saldo (com desconto)', () => {
  it('ORÇ-00060: sinal 18.001,04 + saldo 1.998,96 fecham o líquido (20.000)', () => {
    const s = computeSchedule(ORC_00060, COND_00060_COMPLETA);
    expect(s.signalAmount).toBeCloseTo(18001.04, 2);
    expect(s.balance).toHaveLength(1);
    expect(s.balance[0].amount).toBeCloseTo(1998.96, 2);
    expect(s.balance[0].days).toBe(30);
    expect(s.signalAmount + s.balanceTotal).toBeCloseTo(20000.0, 2);
  });

  it('exclui a parcela de entrada do saldo (só as parcelas futuras)', () => {
    const s = computeSchedule(ORC_00060, COND_00060_COMPLETA);
    // nenhuma linha do saldo pode ter days=0 (essas são entrada)
    expect(s.balance.every((r) => r.days > 0)).toBe(true);
  });

  it('condição só com entrada → saldo vazio', () => {
    const s = computeSchedule(ORC_00060, SINAL_100P_50S);
    expect(s.balance).toHaveLength(0);
    expect(s.balanceTotal).toBe(0);
    expect(s.signalAmount).toBeCloseTo(18001.04, 2);
  });

  it('parcelas de saldo com valor zero são descartadas', () => {
    const s = computeSchedule(ORC_00060, [
      { tipo: 'aprovacao', services_pct: 50, parts_pct: 100, days_after_approval: 0 },
      { tipo: 'prazo', services_pct: 0, parts_pct: 0, days_after_approval: 30 }, // 0 → descartada
    ]);
    expect(s.balance).toHaveLength(0);
  });

  it("saldo 'em X dias' tem dueBasis='days'", () => {
    const s = computeSchedule(ORC_00060, COND_00060_COMPLETA);
    expect(s.balance[0].dueBasis).toBe('days');
    expect(s.balance[0].days).toBe(30);
  });
});

// Condição REAL "na entrega": a parcela de saldo é tipo='entrega' com days_after_approval=0.
// A heurística antiga (days===0 = sinal) classificava essa parcela como SINAL → saldo sumia (bug).
const ORDER_ENTREGA = { labor_cost_total: 2000, parts_cost_total: 1000, discount_amount: 0 };
const COND_ENTREGA = [
  { tipo: 'aprovacao' as const, label: 'Sinal', services_pct: 50, parts_pct: 100, expenses_pct: 100, days_after_approval: 0 },
  { tipo: 'entrega' as const, label: 'Saldo', services_pct: 50, parts_pct: 0, expenses_pct: 0, days_after_approval: 0 },
];

describe("classificação por tipo — parcela 'na entrega' (days=0) NÃO é sinal", () => {
  it('a parcela entrega vira SALDO com dueBasis=delivery, não sinal', () => {
    const s = computeSchedule(ORDER_ENTREGA, COND_ENTREGA);
    expect(s.signalAmount).toBeCloseTo(2000, 2); // 2000*0.5 + 1000*1.0
    expect(s.balance).toHaveLength(1);
    expect(s.balance[0].amount).toBeCloseTo(1000, 2); // 2000*0.5
    expect(s.balance[0].dueBasis).toBe('delivery');
    expect(s.signalAmount + s.balanceTotal).toBeCloseTo(3000, 2);
  });

  it('computeDeposit acha a parcela de aprovação como sinal (não a de entrega)', () => {
    const r = computeDeposit(ORDER_ENTREGA, COND_ENTREGA);
    expect(r.signal).toEqual({ servicesPct: 50, partsPct: 100, expensesPct: 100 });
    expect(r.amount).toBeCloseTo(2000, 2);
  });
});

describe('computeAllInstallments — plano inteiro (conclusão sem sinal)', () => {
  it('ORÇ-00060: entrada + saldo, ambos > 0, somam o líquido', () => {
    const b = depositBaseFromOrder(ORC_00060);
    const rows = computeAllInstallments(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, COND_00060_COMPLETA);
    expect(rows).toHaveLength(2);
    expect(rows[0].isSignal).toBe(true);
    expect(rows[0].amount).toBeCloseTo(18001.04, 2);
    expect(rows[1].isSignal).toBe(false);
    expect(rows[1].amount).toBeCloseTo(1998.96, 2);
    expect(rows.reduce((s, r) => s + r.amount, 0)).toBeCloseTo(20000, 2);
  });

  it("marca dueBasis='delivery' na parcela de entrega", () => {
    const b = depositBaseFromOrder(ORDER_ENTREGA);
    const rows = computeAllInstallments(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, COND_ENTREGA);
    expect(rows).toHaveLength(2);
    expect(rows.find(r => r.isSignal)?.dueBasis).toBe('days');
    expect(rows.find(r => !r.isSignal)?.dueBasis).toBe('delivery');
  });

  it('descarta parcelas de valor zero', () => {
    const b = depositBaseFromOrder(ORC_00060);
    const rows = computeAllInstallments(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, [
      { tipo: 'aprovacao', services_pct: 50, parts_pct: 100, days_after_approval: 0 },
      { tipo: 'prazo', services_pct: 0, parts_pct: 0, days_after_approval: 30 },
    ]);
    expect(rows).toHaveLength(1);
  });
});

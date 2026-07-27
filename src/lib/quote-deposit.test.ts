import { describe, it, expect } from 'vitest';
import { computeDeposit, depositBaseFromOrder, depositAmountFromPcts } from './quote-deposit';

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

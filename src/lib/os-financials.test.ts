import { describe, expect, it } from 'vitest';
import {
  calcInstallmentAmount, computeItemDiscountTotal, computeOsFinancials,
  computePartsProfit, computeReceivablesStatus, findSignalRow,
  normalizeInstallmentRows, simulateCardReceipt,
} from './os-financials';

/* Rede de paridade da Fase 3: estes testes pinam a matemática financeira
   ATUAL da OS. Se a decomposição do formulário mudar um centavo, eles quebram. */

const baseInput = {
  laborCost: 1000,
  partsCost: 500,
  operationalCost: 100,
  travelCost: 200,
  isTravelBillable: true,
  subcontractCost: 50,
  discountAmount: 0,
  taxAmount: 0,
  cardFeePassthroughEnabled: false,
  cardInstallments: 1,
  cardFees: [
    { installments: 1, fee_percent: 3.5 },
    { installments: 3, fee_percent: 5.99 },
  ],
};

describe('computeOsFinancials', () => {
  it('soma subtotal com todas as categorias e deslocamento faturável', () => {
    const r = computeOsFinancials(baseInput);
    expect(r.billableTravelCost).toBe(200);
    expect(r.expensesTotal).toBe(350); // operacional 100 + viagem 200 + terceiros 50
    expect(r.subtotal).toBe(1850);
    expect(r.base).toBe(1850);
    expect(r.grandTotal).toBe(1850);
    expect(r.discountRatio).toBe(1);
  });

  it('exclui deslocamento quando não faturável (Onda 1D)', () => {
    const r = computeOsFinancials({ ...baseInput, isTravelBillable: false });
    expect(r.billableTravelCost).toBe(0);
    expect(r.subtotal).toBe(1650);
    expect(r.expensesTotal).toBe(150);
  });

  it('base aplica desconto e imposto; discountRatio acompanha', () => {
    const r = computeOsFinancials({ ...baseInput, discountAmount: 185, taxAmount: 35 });
    expect(r.base).toBe(1700); // 1850 - 185 + 35
    expect(r.discountRatio).toBeCloseTo(1700 / 1850, 10);
  });

  it('repasse de cartão: gross-up sobre a base com arredondamento em 2 casas (Onda 1C)', () => {
    const r = computeOsFinancials({ ...baseInput, cardFeePassthroughEnabled: true, cardInstallments: 1 });
    // 1850 * 3.5 / 96.5 = 67.0984… → 67.10
    expect(r.passthroughFeePercent).toBe(3.5);
    expect(r.passthroughCardFeeAmount).toBe(67.1);
    expect(r.grandTotal).toBe(1917.1);
  });

  it('repasse usa as parcelas persistidas, não as do simulador', () => {
    const r = computeOsFinancials({ ...baseInput, cardFeePassthroughEnabled: true, cardInstallments: 3 });
    // 1850 * 5.99 / 94.01 = 117.8757… → 117.88
    expect(r.passthroughCardFeeAmount).toBe(117.88);
  });

  it('repasse desabilitado ou sem taxa cadastrada → 0', () => {
    expect(computeOsFinancials(baseInput).passthroughCardFeeAmount).toBe(0);
    const r = computeOsFinancials({ ...baseInput, cardFeePassthroughEnabled: true, cardInstallments: 12 });
    expect(r.passthroughCardFeeAmount).toBe(0); // 12x não cadastrado
  });

  it('subtotal zero → discountRatio 1 (sem divisão por zero)', () => {
    const r = computeOsFinancials({
      ...baseInput, laborCost: 0, partsCost: 0, operationalCost: 0,
      travelCost: 0, subcontractCost: 0,
    });
    expect(r.subtotal).toBe(0);
    expect(r.discountRatio).toBe(1);
  });
});

describe('normalizeInstallmentRows', () => {
  it('linhas legadas com percent único alimentam serviços E peças', () => {
    const rows = normalizeInstallmentRows([{ label: 'Sinal', percent: 40, days_after_approval: 0 }]);
    expect(rows[0]).toMatchObject({ label: 'Sinal', services_pct: 40, parts_pct: 40, expenses_pct: 0, days_after_approval: 0 });
  });

  it('linhas novas preservam pct separados e tipo', () => {
    const rows = normalizeInstallmentRows([
      { label: 'Entrega', services_pct: 60, parts_pct: 100, expenses_pct: 50, days_after_approval: 10, tipo: 'entrega' },
    ]);
    expect(rows[0]).toMatchObject({ services_pct: 60, parts_pct: 100, expenses_pct: 50, days_after_approval: 10, tipo: 'entrega' });
  });

  it('fonte não-array → lista vazia', () => {
    expect(normalizeInstallmentRows(null)).toEqual([]);
    expect(normalizeInstallmentRows(undefined)).toEqual([]);
    expect(normalizeInstallmentRows({})).toEqual([]);
  });
});

describe('calcInstallmentAmount', () => {
  const ctx = { laborCost: 1000, partsCost: 500, expensesTotal: 350, discountRatio: 1 };

  it('rateia por categoria com pct próprios', () => {
    const v = calcInstallmentAmount(
      { label: '', services_pct: 50, parts_pct: 100, expenses_pct: 0, days_after_approval: 0 },
      ctx,
    );
    expect(v).toBe(1000); // 500 + 500
  });

  it('aplica o discountRatio proporcionalmente e arredonda em 2 casas', () => {
    const v = calcInstallmentAmount(
      { label: '', services_pct: 100, parts_pct: 0, expenses_pct: 0, days_after_approval: 0 },
      { ...ctx, discountRatio: 1700 / 1850 },
    );
    // 1000 * 0.918918… = 918.918… → 918.92
    expect(v).toBe(918.92);
  });
});

describe('findSignalRow', () => {
  it("acha por tipo='aprovacao' mesmo com days>0", () => {
    const rows = normalizeInstallmentRows([
      { label: 'x', services_pct: 50, parts_pct: 50, days_after_approval: 5, tipo: 'aprovacao' },
    ]);
    expect(findSignalRow(rows)?.label).toBe('x');
  });
  it('acha por days=0 sem tipo', () => {
    const rows = normalizeInstallmentRows([
      { label: 'a', services_pct: 50, parts_pct: 50, days_after_approval: 30 },
      { label: 'b', services_pct: 50, parts_pct: 50, days_after_approval: 0 },
    ]);
    expect(findSignalRow(rows)?.label).toBe('b');
  });
});

describe('simulateCardReceipt', () => {
  it('bruto = base / (1 - pct/100); parcela divide o bruto', () => {
    const r = simulateCardReceipt(1000, 5, 4);
    expect(r.cardGross).toBeCloseTo(1052.6315789, 6);
    expect(r.cardFeeAmount).toBeCloseTo(52.6315789, 6);
    expect(r.installmentValue).toBeCloseTo(263.1578947, 6);
  });
  it('sem taxa → bruto igual à base; 0 parcelas não divide', () => {
    const r = simulateCardReceipt(1000, 0, 0);
    expect(r.cardGross).toBe(1000);
    expect(r.installmentValue).toBe(1000);
  });
});

describe('computeItemDiscountTotal', () => {
  it('soma o desconto embutido nos itens de serviço e peça', () => {
    const v = computeItemDiscountTotal(
      [{ quantity: 2, unit_price_snapshot: 100, line_total: 180 }],   // 20 de desconto
      [{ quantity: 1, unit_sale_snapshot: 50, line_total_sale: 45 }], // 5 de desconto
    );
    expect(v).toBe(25);
  });
  it('listas vazias/nulas → 0', () => {
    expect(computeItemDiscountTotal(null, undefined)).toBe(0);
  });
});

describe('computePartsProfit', () => {
  it('lucro e margem sobre a receita de peças', () => {
    const r = computePartsProfit([
      { line_total_sale: 300, line_total_cost: 200 },
      { line_total_sale: 100, line_total_cost: 50 },
    ]);
    expect(r.partsRevenue).toBe(400);
    expect(r.partsProfit).toBe(150);
    expect(r.partsMarginPct).toBeCloseTo(37.5, 10);
  });
  it('sem receita → margem 0 (sem divisão por zero)', () => {
    expect(computePartsProfit([]).partsMarginPct).toBe(0);
  });
});

describe('computeReceivablesStatus', () => {
  it('paid: saldo ≤ 0 com cobrança > 0', () => {
    const r = computeReceivablesStatus([{ amount: 100, paid_amount: 100, balance_amount: 0 }]);
    expect(r.payStatus).toBe('paid');
  });
  it('partially_paid: pago > 0 com saldo restante', () => {
    const r = computeReceivablesStatus([{ amount: 100, paid_amount: 40, balance_amount: 60 }]);
    expect(r.payStatus).toBe('partially_paid');
  });
  it('unpaid: nada pago; e também quando não há cobranças (saldo 0 mas cobrado 0)', () => {
    expect(computeReceivablesStatus([{ amount: 100, paid_amount: 0, balance_amount: 100 }]).payStatus).toBe('unpaid');
    expect(computeReceivablesStatus([]).payStatus).toBe('unpaid');
  });
});

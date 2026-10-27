import { describe, expect, it } from 'vitest';
import { condicaoTudoNaConclusao, PARCELA_TUDO_NA_CONCLUSAO } from './condicao-na-conclusao';
import { computeDeposit, computeAllInstallments, depositBaseFromOrder } from './quote-deposit';

const tudoNaEntrega = {
  id: 'p-entrega',
  label: '100% na entrega',
  installments: [{ label: '', services_pct: 100, parts_pct: 100, expenses_pct: 100, days_after_approval: 0, tipo: 'entrega' }],
};

describe('condicaoTudoNaConclusao', () => {
  it('usa o preset que cobra tudo na entrega', () => {
    expect(condicaoTudoNaConclusao([tudoNaEntrega])).toEqual({
      payment_condition_preset_id: 'p-entrega',
      payment_conditions: '100% na entrega',
      custom_payment_installments: null,
    });
  });

  it('recusa o preset que deixa as despesas de fora (expenses_pct 0) e grava personalizada', () => {
    const semDespesas = { ...tudoNaEntrega, installments: [{ ...tudoNaEntrega.installments[0], expenses_pct: 0 }] };
    const c = condicaoTudoNaConclusao([semDespesas]);
    expect(c.payment_condition_preset_id).toBeNull();
    expect(c.custom_payment_installments).toEqual([PARCELA_TUDO_NA_CONCLUSAO]);
  });

  it('recusa presets com sinal ou com mais de uma parcela', () => {
    const comSinal = {
      id: 'p-50', label: '50/50',
      installments: [
        { services_pct: 50, parts_pct: 50, expenses_pct: 50, tipo: 'aprovacao' },
        { services_pct: 50, parts_pct: 50, expenses_pct: 50, tipo: 'entrega' },
      ],
    };
    const vazio = { id: 'p-mensal', label: 'Faturado mensalmente', installments: [] };
    expect(condicaoTudoNaConclusao([comSinal, vazio]).payment_condition_preset_id).toBeNull();
    expect(condicaoTudoNaConclusao(undefined).payment_condition_preset_id).toBeNull();
  });

  it('a parcela personalizada não tem sinal e cobra o líquido inteiro (com desconto e despesas)', () => {
    const os = {
      labor_cost_total: 1000, parts_cost_total: 500, operational_cost_total: 100,
      travel_cost_total: 200, is_travel_billable: true, discount_amount: 180,
    };
    const parcelas = [PARCELA_TUDO_NA_CONCLUSAO];
    expect(computeDeposit(os, parcelas).amount).toBeNull();
    const b = depositBaseFromOrder(os);
    const rows = computeAllInstallments(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio, parcelas);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ amount: 1620, dueBasis: 'delivery', isSignal: false });
  });
});

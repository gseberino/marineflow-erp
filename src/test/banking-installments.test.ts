// Compra parcelada: uma compra, não N despesas.
//
// Os casos vieram do extrato real: uma compra de R$ 1.024 na Coremma em 10x, uma do
// Airbnb que começa em 2/6 porque a primeira parcela é anterior ao período importado, e
// uma que ainda tem parcelas a vencer.
import { describe, it, expect } from 'vitest';
import {
  lerParcela, agruparParcelamentos, descreverParcelamento,
  type PernaDeParcelamento,
} from '../../supabase/functions/_shared/banking/installments';

let seq = 0;
const perna = (o: Partial<PernaDeParcelamento> = {}): PernaDeParcelamento => {
  seq += 1;
  return {
    id: `t${seq}`,
    transaction_date: '2026-01-26',
    description: 'COMPRA',
    amount: 102.4,
    counterparty_name: 'COREMMA',
    installment_label: null,
    ...o,
  };
};

describe('leitura do rótulo', () => {
  it('entende o formato do provedor', () => {
    expect(lerParcela('3/10')).toEqual({ numero: 3, total: 10 });
    expect(lerParcela(' 1 / 2 ')).toEqual({ numero: 1, total: 2 });
  });

  it('à vista não é parcelamento', () => {
    // "1/1" existe no extrato e não tem o que agrupar.
    expect(lerParcela('1/1')).toBeNull();
    expect(lerParcela(null)).toBeNull();
    expect(lerParcela('parcela 3')).toBeNull();
  });

  it('recusa rótulo impossível', () => {
    expect(lerParcela('7/3')).toBeNull();
    expect(lerParcela('0/3')).toBeNull();
  });
});

describe('agrupamento da compra', () => {
  it('dez parcelas viram uma compra', () => {
    const pernas = Array.from({ length: 10 }, (_, i) =>
      perna({ installment_label: `${i + 1}/10`, transaction_date: `2026-0${(i % 9) + 1}-25` }));
    const { compras, pernaDe } = agruparParcelamentos(pernas);

    expect(compras).toHaveLength(1);
    const c = compras[0];
    expect(c.totalDeParcelas).toBe(10);
    expect(c.valorDaCompra).toBe(1024);
    expect(c.pernas).toHaveLength(10);
    expect(c.jaPago).toBe(1024);
    expect(c.aVencer).toBe(0);
    // Todas as pernas apontam para a mesma compra: é o que impede dez propostas.
    expect(new Set(pernaDe.values()).size).toBe(1);
    expect(pernaDe.size).toBe(10);
  });

  it('parcela anterior ao extrato conta como paga, não como pendência', () => {
    // Airbnb real: o extrato importado começa em 2/6. A parcela 1 saiu antes — é passado
    // que o recorte não alcança, não dívida.
    const pernas = [2, 3, 4, 5, 6].map((n) =>
      perna({ counterparty_name: 'AIRBNB * HMJFDQK2EH', amount: 185.24, installment_label: `${n}/6` }));
    const [c] = agruparParcelamentos(pernas).compras;

    expect(c.valorDaCompra).toBeCloseTo(1111.44, 2);
    expect(c.anterioresForaDoExtrato).toBe(1);
    expect(c.jaPago).toBeCloseTo(1111.44, 2);
    expect(c.aVencer).toBe(0);
    expect(descreverParcelamento(c)).toContain('anteriores ao período importado');
  });

  it('parcelamento em andamento deixa saldo a vencer', () => {
    const pernas = [2, 3, 4, 5].map((n) =>
      perna({ counterparty_name: 'MERCADOLIVRE*7PRODUTOS', amount: 53.02, installment_label: `${n}/8` }));
    const [c] = agruparParcelamentos(pernas).compras;

    expect(c.valorDaCompra).toBeCloseTo(424.16, 2);
    expect(c.jaPago).toBeCloseTo(265.1, 2);
    expect(c.aVencer).toBeCloseTo(159.06, 2);
    expect(descreverParcelamento(c)).toContain('a vencer');
  });

  it('a proposta mora na parcela mais antiga', () => {
    const pernas = [
      perna({ id: 'terceira', installment_label: '3/3', transaction_date: '2026-03-25' }),
      perna({ id: 'primeira', installment_label: '1/3', transaction_date: '2026-01-25' }),
      perna({ id: 'segunda', installment_label: '2/3', transaction_date: '2026-02-25' }),
    ];
    const [c] = agruparParcelamentos(pernas).compras;
    expect(c.ancora.id).toBe('primeira');
    expect(c.pernas.map((p) => p.id)).toEqual(['primeira', 'segunda', 'terceira']);
  });

  it('compras diferentes no mesmo lugar não se misturam', () => {
    const pernas = [
      perna({ counterparty_name: 'COREMMA', amount: 102.4, installment_label: '1/3' }),
      perna({ counterparty_name: 'COREMMA', amount: 102.4, installment_label: '2/3' }),
      perna({ counterparty_name: 'COREMMA', amount: 55, installment_label: '1/3' }),
      perna({ counterparty_name: 'COREMMA', amount: 55, installment_label: '2/3' }),
    ];
    expect(agruparParcelamentos(pernas).compras).toHaveLength(2);
  });

  it('colisão indistinguível fica de fora — errar juntando é pior', () => {
    // Mesma loja, mesmo valor, mesmo plano, e DUAS parcelas "1/3": são duas compras que
    // colidiram na chave. Nem quem olha à mão consegue separá-las pelo extrato.
    const pernas = [
      perna({ installment_label: '1/3' }),
      perna({ installment_label: '1/3' }),
      perna({ installment_label: '2/3' }),
    ];
    expect(agruparParcelamentos(pernas).compras).toHaveLength(0);
  });

  it('compra à vista não entra no agrupamento', () => {
    const pernas = [perna({ installment_label: null }), perna({ installment_label: '1/1' })];
    const { compras, pernaDe } = agruparParcelamentos(pernas);
    expect(compras).toHaveLength(0);
    expect(pernaDe.size).toBe(0);
  });

  it('uma parcela sozinha ainda é uma compra parcelada', () => {
    // O rótulo é explícito: "3/6" significa que a compra foi em 6x, mesmo que só uma
    // parcela apareça no recorte.
    const [c] = agruparParcelamentos([perna({ amount: 200, installment_label: '3/6' })]).compras;
    expect(c.valorDaCompra).toBe(1200);
    expect(c.anterioresForaDoExtrato).toBe(2);
    expect(c.aVencer).toBe(600);
  });
});

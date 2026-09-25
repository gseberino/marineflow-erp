// Compra parcelada: uma compra, não N despesas.
//
// Os casos vieram do extrato real: uma compra de R$ 1.024 na Coremma em 10x, uma do
// Airbnb que começa em 2/6 porque a primeira parcela é anterior ao período importado, e
// uma que ainda tem parcelas a vencer.
import { describe, it, expect } from 'vitest';
import {
  lerParcela, agruparParcelamentos, descreverParcelamento, compraJaTratada, nomeSemParcela,
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

  it('centavo que não divide não parte a compra em duas', () => {
    // O defeito real: R$ 100,01 em 3x vira 33,34 + 33,34 + 33,33, e a chave que exigia
    // valor idêntico transformava isso em DUAS compras — 98 grupos onde havia 64.
    const pernas = [
      perna({ amount: 33.34, installment_label: '1/3' }),
      perna({ amount: 33.34, installment_label: '2/3' }),
      perna({ amount: 33.33, installment_label: '3/3' }),
    ];
    const { compras } = agruparParcelamentos(pernas);
    expect(compras).toHaveLength(1);
    // Com o parcelamento inteiro no extrato, o valor é a soma exata — sem estimativa.
    expect(compras[0].valorDaCompra).toBeCloseTo(100.01, 2);
    expect(compras[0].aVencer).toBe(0);
  });

  it('duas compras no mesmo plano se separam pelo valor', () => {
    // Números de parcela repetidos denunciam duas compras na mesma chave; aí o valor volta
    // a ser o critério que resta para separá-las.
    const pernas = [
      perna({ amount: 100, installment_label: '1/3' }),
      perna({ amount: 100, installment_label: '2/3' }),
      perna({ amount: 55, installment_label: '1/3' }),
      perna({ amount: 55, installment_label: '2/3' }),
    ];
    const { compras } = agruparParcelamentos(pernas);
    expect(compras).toHaveLength(2);
    expect(compras.map((c) => c.valorDaCompra).sort((a, b) => a - b)).toEqual([165, 300]);
  });

  it('ambiguidade que sobra fica de fora — errar juntando é pior', () => {
    // Mesma loja, mesmo valor, mesmo plano, e DUAS parcelas "1/3": nem quem olha à mão
    // separa isso pelo extrato.
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

// ── A mesma compra lançada de novo quando chega a parcela do mês seguinte ──────────────
//
// Medido em 25/09/2026: 19 compras parceladas lançadas duas vezes (R$ 12.445). Em todas, a
// original estava ancorada na parcela 1 e a cópia na parcela 2 da mesma série, porque a
// varredura só enxerga transação ainda não tratada e a parcela 1 já tinha virado
// lançamento. Os valores e datas abaixo são desses casos reais.
describe('compra já lançada a partir de outra parcela da mesma série', () => {
  const compraDe = (pernas: PernaDeParcelamento[]) => agruparParcelamentos(pernas).compras[0];
  const tratadas = (...ids: string[]) => (id: string) => ids.includes(id);

  it('Airbnb 6x: a parcela 2 chega e a 1 já foi lançada — é a mesma compra', () => {
    const p1 = perna({ counterparty_name: 'AIRBNB * HMJFDQK2EH', amount: 185.24, installment_label: '1/6', transaction_date: '2025-12-27' });
    const p2 = perna({ counterparty_name: 'AIRBNB * HMJFDQK2EH', amount: 185.24, installment_label: '2/6', transaction_date: '2026-01-26' });
    expect(compraJaTratada(compraDe([p2]), [p1], tratadas(p1.id))).toBe(p1);
  });

  it('o sentido inverso também: lançada pela 2, e a 1 aparece depois no histórico', () => {
    // AIRBNB * HMJH38CACR: a original foi ancorada na 2/4 (27/04) e a cópia na 1/4 (01/04).
    const p2 = perna({ counterparty_name: 'AIRBNB * HMJH38CACR', amount: 52.23, installment_label: '2/4', transaction_date: '2026-04-27' });
    const p1 = perna({ counterparty_name: 'AIRBNB * HMJH38CACR', amount: 52.23, installment_label: '1/4', transaction_date: '2026-04-01' });
    expect(compraJaTratada(compraDe([p1]), [p2], tratadas(p2.id))).toBe(p2);
  });

  it('parcelas com 10 dias de distância ainda são a mesma série', () => {
    // MP *ALIEXPRESS 3x: 1/3 em 15/09 e 2/3 em 25/09 — o cartão lança no fechamento.
    const p1 = perna({ counterparty_name: 'MP *ALIEXPRESS', amount: 292.32, installment_label: '1/3', transaction_date: '2025-09-15' });
    const p2 = perna({ counterparty_name: 'MP *ALIEXPRESS', amount: 292.32, installment_label: '2/3', transaction_date: '2025-09-25' });
    expect(compraJaTratada(compraDe([p2]), [p1], tratadas(p1.id))).toBe(p1);
  });

  it('o centavo que o cartão joga numa parcela só não separa a série', () => {
    const p1 = perna({ counterparty_name: 'PREMEL - ITAJAI', amount: 74.59, installment_label: '1/3', transaction_date: '2026-02-04' });
    const p2 = perna({ counterparty_name: 'PREMEL - ITAJAI', amount: 74.58, installment_label: '2/3', transaction_date: '2026-02-25' });
    expect(compraJaTratada(compraDe([p2]), [p1], tratadas(p1.id))).toBe(p1);
  });

  it('compra NOVA idêntica a uma antiga continua sendo compra nova', () => {
    // Mesma loja, mesmo plano, mesmo valor — mas a nova começa na parcela 1. As parcelas
    // 2 e 3 da compra antiga são MAIS ANTIGAS com número maior: não podem ser irmãs.
    const a1 = perna({ counterparty_name: 'PREMEL - ITAJAI', amount: 74.59, installment_label: '1/3', transaction_date: '2026-01-10' });
    const a2 = perna({ counterparty_name: 'PREMEL - ITAJAI', amount: 74.59, installment_label: '2/3', transaction_date: '2026-02-10' });
    const a3 = perna({ counterparty_name: 'PREMEL - ITAJAI', amount: 74.59, installment_label: '3/3', transaction_date: '2026-03-10' });
    const b1 = perna({ counterparty_name: 'PREMEL - ITAJAI', amount: 74.59, installment_label: '1/3', transaction_date: '2026-04-10' });
    expect(compraJaTratada(compraDe([b1]), [a1, a2, a3], tratadas(a1.id, a2.id, a3.id))).toBeNull();
  });

  it('parcela antiga ainda sem lançamento não prova nada', () => {
    const p1 = perna({ counterparty_name: 'AUTOZONE', amount: 56.79, installment_label: '1/5', transaction_date: '2026-03-03' });
    const p2 = perna({ counterparty_name: 'AUTOZONE', amount: 56.79, installment_label: '2/5', transaction_date: '2026-03-25' });
    expect(compraJaTratada(compraDe([p2]), [p1], tratadas())).toBeNull();
  });

  it('valor de parcela diferente é outra compra', () => {
    const p1 = perna({ counterparty_name: 'LOJAS TAMOYO LTDA', amount: 93.44, installment_label: '1/4', transaction_date: '2026-06-13' });
    const p2 = perna({ counterparty_name: 'LOJAS TAMOYO LTDA', amount: 132.79, installment_label: '2/4', transaction_date: '2026-06-25' });
    expect(compraJaTratada(compraDe([p2]), [p1], tratadas(p1.id))).toBeNull();
  });

  it('outra loja não conta', () => {
    const p1 = perna({ counterparty_name: 'MILIUM 64', amount: 58.74, installment_label: '1/3', transaction_date: '2026-04-09' });
    const p2 = perna({ counterparty_name: 'MILIUM 65', amount: 58.74, installment_label: '2/3', transaction_date: '2026-04-27' });
    expect(compraJaTratada(compraDe([p2]), [p1], tratadas(p1.id))).toBeNull();
  });

  it('longe demais no tempo não é a parcela vizinha', () => {
    const p1 = perna({ counterparty_name: 'FRIGELAR COMERCIO', amount: 178.26, installment_label: '1/6', transaction_date: '2025-06-05' });
    const p2 = perna({ counterparty_name: 'FRIGELAR COMERCIO', amount: 178.26, installment_label: '2/6', transaction_date: '2026-02-05' });
    expect(compraJaTratada(compraDe([p2]), [p1], tratadas(p1.id))).toBeNull();
  });
});

// ── Parcela escrita dentro do nome da loja ──────────────────────────────────────────────
//
// Alguns bancos mandam "COREMMA 2/4" como nome do estabelecimento. Sem tirar o "2/4",
// cada parcela parecia uma loja diferente e virava uma compra inteira: na fila de
// 25/09/2026, a Coremma de 4x R$ 112,29 entraria três vezes como compra de R$ 449,16.
describe('parcela no nome do estabelecimento', () => {
  it('as três parcelas da Coremma são uma compra só', () => {
    const p2 = perna({ counterparty_name: 'COREMMA 2/4', amount: 112.29, installment_label: '2/4', transaction_date: '2026-09-13' });
    const p3 = perna({ counterparty_name: 'COREMMA 3/4', amount: 112.29, installment_label: '3/4', transaction_date: '2026-10-13' });
    const p4 = perna({ counterparty_name: 'COREMMA 4/4', amount: 112.29, installment_label: '4/4', transaction_date: '2026-11-13' });
    const { compras } = agruparParcelamentos([p2, p3, p4]);
    expect(compras).toHaveLength(1);
    expect(compras[0].pernas).toHaveLength(3);
    // 4x de 112,29: a 1ª parcela ficou fora do extrato, mas entra no valor da compra.
    expect(compras[0].valorDaCompra).toBeCloseTo(449.16, 2);
    // O nome que aparece para você não carrega a parcela.
    expect(compras[0].rotulo).toBe('COREMMA');
  });

  it('e uma parcela da série já lançada cobre as novas', () => {
    const p1 = perna({ counterparty_name: 'MERCADOLIVRE*EUROTERM 1/2', amount: 89.9, installment_label: '1/2', transaction_date: '2026-08-11' });
    const p2 = perna({ counterparty_name: 'MERCADOLIVRE*EUROTERM 2/2', amount: 89.9, installment_label: '2/2', transaction_date: '2026-09-11' });
    const compra = agruparParcelamentos([p2]).compras[0];
    expect(compraJaTratada(compra, [p1], (id) => id === p1.id)).toBe(p1);
  });

  it('só tira o número do fim: nome com número no meio fica como está', () => {
    expect(nomeSemParcela({ counterparty_name: 'COREMMA 2/4', description: '' })).toBe('COREMMA');
    expect(nomeSemParcela({ counterparty_name: 'MILIUM 64', description: '' })).toBe('MILIUM 64');
    expect(nomeSemParcela({ counterparty_name: 'LOJA 24/7 CONVENIENCIA', description: '' })).toBe('LOJA 24/7 CONVENIENCIA');
  });
});

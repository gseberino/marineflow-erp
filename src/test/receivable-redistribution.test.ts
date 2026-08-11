// [MF-AUD-009] A fórmula que a tela e o agente passam a compartilhar.
//
// Dois blocos: o comportamento da regra, e a PARIDADE entre as duas cópias (frontend e edge).
// A paridade segue o padrão de `banking-quote-deposit-paridade.test.ts`: espelho que diverge
// em silêncio já causou bug real neste sistema.
import { describe, expect, it } from 'vitest';
import {
  redistribuirRecebiveis as redistFront,
  type RecebivelParaRedistribuir,
} from '@/lib/receivable-redistribution';
import { redistribuirRecebiveis as redistEdge } from '../../supabase/functions/_shared/receivables/redistribution';

const soma = (r: { amount: number }[]) => r.reduce((s, x) => s + x.amount, 0);

describe('redistribuirRecebiveis — os três pisos', () => {
  it('bloqueia quando o novo total fica abaixo do já pago', () => {
    // O cenário que a tela sempre bloqueou e o agente aceitava: cliente pagou R$ 5.000 e
    // alguém reduz a OS para R$ 3.000. O saldo viraria negativo — na prática, uma devolução
    // que ninguém decidiu fazer.
    const recebiveis: RecebivelParaRedistribuir[] = [
      { id: 'a', amount: 5000, paid_amount: 5000, status: 'paid' },
      { id: 'b', amount: 3000, paid_amount: 0, status: 'pending' },
    ];
    const r = redistFront(recebiveis, 3000);

    expect(r.bloqueado).toBe(true);
    expect(r.alteracoes).toHaveLength(0); // nada gravado
    expect(r.motivo).toMatch(/abaixo do valor já pago/i);
  });

  it('tolera 1 centavo de resíduo — arredondamento não pode travar alteração legítima', () => {
    const r = redistFront([{ id: 'a', amount: 100, paid_amount: 100, status: 'paid' }], 99.995);
    expect(r.bloqueado).toBe(false);
  });

  it('recebível já quitado não encolhe', () => {
    // Título pago é fato consumado. Redimensioná-lo reescreveria história e desencontraria
    // o financeiro do extrato.
    const recebiveis: RecebivelParaRedistribuir[] = [
      { id: 'pago', amount: 4000, paid_amount: 4000, status: 'paid' },
      { id: 'aberto', amount: 6000, paid_amount: 0, status: 'pending' },
    ];
    const r = redistFront(recebiveis, 7000);

    expect(r.alteracoes.map((a) => a.id)).toEqual(['aberto']);
    expect(r.alteracoes[0].amount).toBe(3000); // 7000 - 4000 do quitado
  });

  it('nenhum título isolado cai abaixo do que já foi pago NELE', () => {
    // O agregado permite reduzir, mas a fatia de um título parcial ficaria abaixo do que ele
    // já recebeu. Sem este piso, aquele título fica com saldo negativo enquanto a soma
    // parece saudável.
    const recebiveis: RecebivelParaRedistribuir[] = [
      { id: 'parcial', amount: 5000, paid_amount: 2000, status: 'partially_paid' },
      { id: 'aberto', amount: 5000, paid_amount: 0, status: 'pending' },
    ];
    const r = redistFront(recebiveis, 2500);

    const parcial = r.alteracoes.find((a) => a.id === 'parcial')!;
    expect(parcial.amount).toBeGreaterThanOrEqual(2000);
    expect(parcial.balance_amount).toBeGreaterThanOrEqual(0);
    for (const a of r.alteracoes) expect(a.balance_amount).toBeGreaterThanOrEqual(0);
  });

  it('redistribui proporcionalmente à participação anterior', () => {
    const recebiveis: RecebivelParaRedistribuir[] = [
      { id: 'a', amount: 3000, paid_amount: 0, status: 'pending' },
      { id: 'b', amount: 1000, paid_amount: 0, status: 'pending' },
    ];
    const r = redistFront(recebiveis, 8000); // dobra o total

    expect(r.alteracoes.find((a) => a.id === 'a')!.amount).toBe(6000);
    expect(r.alteracoes.find((a) => a.id === 'b')!.amount).toBe(2000);
    expect(soma(r.alteracoes)).toBe(8000);
  });

  it('base anterior zerada divide igual — proporção de zero não existe', () => {
    const recebiveis: RecebivelParaRedistribuir[] = [
      { id: 'a', amount: 0, paid_amount: 0, status: 'pending' },
      { id: 'b', amount: 0, paid_amount: 0, status: 'pending' },
    ];
    const r = redistFront(recebiveis, 1000);
    expect(r.alteracoes.map((a) => a.amount)).toEqual([500, 500]);
  });

  it('cancelado não entra na conta, nem como piso', () => {
    // Um recebível cancelado com paid_amount elevaria o piso e bloquearia alteração válida.
    const recebiveis: RecebivelParaRedistribuir[] = [
      { id: 'morto', amount: 9000, paid_amount: 9000, status: 'cancelled' },
      { id: 'vivo', amount: 1000, paid_amount: 0, status: 'pending' },
    ];
    const r = redistFront(recebiveis, 1000);

    expect(r.bloqueado).toBe(false);
    expect(r.alteracoes.map((a) => a.id)).toEqual(['vivo']);
  });

  it('o status acompanha o valor novo', () => {
    const r = redistFront(
      [{ id: 'a', amount: 1000, paid_amount: 400, status: 'partially_paid' }],
      400,
    );
    // O valor caiu exatamente até o que já foi pago: o título passa a estar quitado.
    expect(r.alteracoes[0].amount).toBe(400);
    expect(r.alteracoes[0].status).toBe('paid');
    expect(r.alteracoes[0].balance_amount).toBe(0);
  });

  it('sem recebíveis não faz nada e não quebra', () => {
    expect(redistFront([], 5000).alteracoes).toHaveLength(0);
    expect(redistFront([], 5000).bloqueado).toBe(false);
  });
});

describe('paridade frontend × edge function', () => {
  const cenarios: [RecebivelParaRedistribuir[], number][] = [
    [[{ id: 'a', amount: 5000, paid_amount: 5000, status: 'paid' }], 3000],
    [[{ id: 'a', amount: 3000, paid_amount: 0, status: 'pending' },
      { id: 'b', amount: 1000, paid_amount: 0, status: 'pending' }], 8000],
    [[{ id: 'a', amount: 5000, paid_amount: 2000, status: 'partially_paid' },
      { id: 'b', amount: 5000, paid_amount: 0, status: 'pending' }], 2500],
    [[{ id: 'a', amount: 4000, paid_amount: 4000, status: 'paid' },
      { id: 'b', amount: 6000, paid_amount: 0, status: 'pending' }], 7000],
    [[{ id: 'a', amount: 0, paid_amount: 0, status: 'pending' }], 1000],
    [[], 5000],
    // Frações que quebram arredondamento — o lugar clássico de duas cópias divergirem.
    [[{ id: 'a', amount: 1000, paid_amount: 0, status: 'pending' },
      { id: 'b', amount: 2000, paid_amount: 0, status: 'pending' },
      { id: 'c', amount: 3000, paid_amount: 0, status: 'pending' }], 1234.56],
  ];

  it('as duas implementações concordam em tudo, inclusive no bloqueio', () => {
    for (const [recebiveis, novoTotal] of cenarios) {
      expect(redistEdge(recebiveis, novoTotal)).toEqual(redistFront(recebiveis, novoTotal));
    }
  });
});

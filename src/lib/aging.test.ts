// A régua do aging: a mesma para quem me deve e para a quem devo.
import { describe, it, expect } from 'vitest';
import { montarAging, type ContaEmAberto } from './aging';

const HOJE = new Date(2026, 8, 26, 15, 30); // 26/09/2026, meio da tarde

const conta = (p: Partial<ContaEmAberto>): ContaEmAberto => ({
  parteId: 'c1', parteNome: 'Marina Azul', vencimento: '2026-09-26', saldo: 100, ...p,
});

describe('montarAging', () => {
  it('distribui o saldo nas faixas de atraso', () => {
    const r = montarAging([
      conta({ vencimento: '2026-10-10', saldo: 10 }),   // a vencer
      conta({ vencimento: '2026-09-20', saldo: 20 }),   // 6 dias
      conta({ vencimento: '2026-08-20', saldo: 30 }),   // 37 dias
      conta({ vencimento: '2026-07-20', saldo: 40 }),   // 68 dias
      conta({ vencimento: '2026-05-01', saldo: 50 }),   // mais de 90
    ], HOJE);
    expect(r.buckets).toHaveLength(1);
    expect(r.buckets[0]).toMatchObject({ future: 10, days_1_30: 20, days_31_60: 30, days_61_90: 40, over_90: 50, total: 150 });
    expect(r.totals.total).toBe(150);
  });

  it('limites das faixas: 30, 60 e 90 dias ainda ficam na faixa de baixo', () => {
    const r = montarAging([
      conta({ parteId: 'a', vencimento: '2026-08-27', saldo: 1 }), // 30 dias
      conta({ parteId: 'b', vencimento: '2026-07-28', saldo: 1 }), // 60 dias
      conta({ parteId: 'c', vencimento: '2026-06-28', saldo: 1 }), // 90 dias
      conta({ parteId: 'd', vencimento: '2026-06-27', saldo: 1 }), // 91 dias
    ], HOJE);
    const de = (id: string) => r.buckets.find((b) => b.client_id === id)!;
    expect(de('a').days_1_30).toBe(1);
    expect(de('b').days_31_60).toBe(1);
    expect(de('c').days_61_90).toBe(1);
    expect(de('d').over_90).toBe(1);
  });

  it('agrupa por parte e põe primeiro quem deve há mais tempo', () => {
    const r = montarAging([
      conta({ parteId: 'novo', parteNome: 'Novo', vencimento: '2026-10-01', saldo: 5000 }),
      conta({ parteId: 'velho', parteNome: 'Velho', vencimento: '2026-01-01', saldo: 100 }),
      conta({ parteId: 'velho', parteNome: 'Velho', vencimento: '2026-09-01', saldo: 50 }),
    ], HOJE);
    expect(r.buckets.map((b) => b.client_name)).toEqual(['Velho', 'Novo']);
    expect(r.buckets[0].total).toBe(150);
  });

  it('saldo zerado ou negativo não entra', () => {
    const r = montarAging([conta({ saldo: 0 }), conta({ saldo: -10 })], HOJE);
    expect(r.buckets).toEqual([]);
    expect(r.totals.total).toBe(0);
  });

  it('soma em centavos, sem sobra de ponto flutuante', () => {
    const r = montarAging(Array.from({ length: 10 }, () => conta({ saldo: 0.1 })), HOJE);
    expect(r.totals.total).toBe(1);
  });
});

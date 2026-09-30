// Parcelas da nota (duplicatas da NF-e e recebíveis da baixa da nota avulsa). Extraído de
// FiscalEmission.tsx no D33 (30/09/2026); a divisão em ponto flutuante saía torta por centavos.
import { describe, it, expect } from 'vitest';
import { montarParcelas, intervaloDasParcelas, parcelasParaLancar, type Parcela } from './fiscal-parcelas';

const valores = (ps: Parcela[]) => ps.map((p) => p.amount);
const somaEmCentavos = (ps: Parcela[]) => ps.reduce((s, p) => s + Math.round(p.amount * 100), 0);

describe('montarParcelas', () => {
  it('divide igual quando dá, e a última leva o resto', () => {
    expect(valores(montarParcelas(300, 3, '2026-10-01', 30, '14'))).toEqual([100, 100, 100]);
    expect(valores(montarParcelas(100, 3, '2026-10-01', 30, '14'))).toEqual([33.33, 33.33, 33.34]);
  });

  it('não sai torta por centavo de ponto flutuante (a conta antiga dava 0,56 + 0,58)', () => {
    expect(valores(montarParcelas(1.14, 2, '2026-10-01', 30, '14'))).toEqual([0.57, 0.57]);
    expect(valores(montarParcelas(1.14, 3, '2026-10-01', 30, '14'))).toEqual([0.38, 0.38, 0.38]);
    expect(valores(montarParcelas(1161.3, 3, '2026-10-01', 30, '14'))).toEqual([387.1, 387.1, 387.1]);
  });

  it('a soma fecha no centavo e as N−1 primeiras são o valor cheio, em qualquer combinação', () => {
    const falhas: string[] = [];
    for (let c = 100; c <= 60_000; c += 7) {
      for (const n of [1, 2, 3, 4, 5, 6, 7, 12]) {
        const ps = montarParcelas(c / 100, n, '2026-10-01', 30, '15');
        const cheia = Math.floor(c / n);
        const ok = ps.length === n && somaEmCentavos(ps) === c
          && ps.slice(0, -1).every((p) => Math.round(p.amount * 100) === cheia);
        if (!ok) falhas.push(`${c / 100} em ${n}: ${valores(ps).join(' | ')}`);
      }
    }
    expect(falhas).toEqual([]);
  });

  it('vencimentos de X em X dias a partir do primeiro, atravessando mês e ano', () => {
    const ps = montarParcelas(90, 3, '2026-12-15', 30, '14');
    expect(ps.map((p) => p.due_date)).toEqual(['2026-12-15', '2027-01-14', '2027-02-13']);
    // 31/01 + 30 dias = 02/03 (como o setDate de antes).
    expect(montarParcelas(20, 2, '2027-01-31', 30, '14').map((p) => p.due_date)).toEqual(['2027-01-31', '2027-03-02']);
  });

  it('leva a forma de pagamento em cada parcela', () => {
    expect(montarParcelas(10, 2, '2026-10-01', 30, '14').every((p) => p.method === '14')).toBe(true);
  });
});

describe('intervaloDasParcelas', () => {
  it('lê o intervalo em dias entre as duas primeiras', () => {
    expect(intervaloDasParcelas([{ due_date: '2026-10-01' }, { due_date: '2026-10-31' }])).toBe(30);
    expect(intervaloDasParcelas([{ due_date: '2026-10-01' }, { due_date: '2026-10-01' }])).toBe(1);
  });
});

describe('parcelasParaLancar', () => {
  const planoDaNota: Parcela[] = [
    { due_date: '2026-10-10', amount: 50.5, method: '15' },
    { due_date: '2026-11-10', amount: 49.5, method: '15' },
  ];
  const base = {
    modo: 'parcelado' as const, ajustado: false, parcelasDaNota: planoDaNota,
    total: 100, n: 2, primeiroVencimento: '2026-10-10', intervaloDias: 31, metodo: '15',
  };

  it('à vista não tem parcelas', () => {
    expect(parcelasParaLancar({ ...base, modo: 'avista' })).toBeNull();
  });

  it('sem ajuste vale o plano da nota, intacto (mesmo desigual)', () => {
    expect(parcelasParaLancar(base)).toBe(planoDaNota);
  });

  it('com ajuste a conta é refeita pelo que o usuário escolheu', () => {
    expect(valores(parcelasParaLancar({ ...base, ajustado: true, n: 4 })!)).toEqual([25, 25, 25, 25]);
  });

  it('sem plano da nota e sem dados suficientes, nada a lançar', () => {
    expect(parcelasParaLancar({ ...base, parcelasDaNota: null, n: 0 })).toBeNull();
    expect(parcelasParaLancar({ ...base, parcelasDaNota: null, primeiroVencimento: '' })).toBeNull();
  });
});

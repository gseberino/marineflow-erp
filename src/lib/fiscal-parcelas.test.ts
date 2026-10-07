// Parcelas da nota (duplicatas da NF-e e recebíveis da baixa da nota avulsa). Extraído de
// FiscalEmission.tsx no D33 (30/09/2026); a divisão em ponto flutuante saía torta por centavos.
import { describe, it, expect } from 'vitest';
import { metodoDoRecebimentoNaHora, montarParcelas, intervaloDasParcelas, parcelasParaLancar, planoInicialDaBaixa, type Parcela } from './fiscal-parcelas';

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

describe('planoInicialDaBaixa', () => {
  const diaLocal = (iso: string) => {
    const d = new Date(iso);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  };

  it('nota parcelada: o plano dela, intacto, mesmo desigual (NF-e 2/25)', () => {
    const doc = {
      payment_terms: {
        mode: 'parcelado', method: '14',
        installments: [
          { due_date: '2026-08-10', amount: 5237.99, method: '14' },
          { due_date: '2026-09-09', amount: 5237.99 },
          { due_date: '2026-10-09', amount: 5238.02, method: '14' },
        ],
      },
    };
    const p = planoInicialDaBaixa(doc);
    expect(p.modo).toBe('parcelado');
    expect(p.n).toBe(3);
    expect(p.primeiroVencimento).toBe('2026-08-10');
    expect(p.intervaloDias).toBe(30);
    expect(p.metodo).toBe('14');
    expect(valores(p.parcelasDaNota!)).toEqual([5237.99, 5237.99, 5238.02]);
    // parcela sem forma de pagamento herda a da nota
    expect(p.parcelasDaNota![1].method).toBe('14');
  });

  it('uma parcela só não é plano parcelado', () => {
    const doc = { payment_terms: { mode: 'parcelado', installments: [{ due_date: '2026-08-10', amount: 100 }] }, authorized_at: '2026-08-01T12:00:00-03:00' };
    const p = planoInicialDaBaixa(doc);
    expect(p.modo).toBe('avista');
    expect(p.parcelasDaNota).toBeNull();
  });

  it('nota sem plano: à vista, vencimento no dia LOCAL da nota (não no dia UTC)', () => {
    const noite = '2026-09-10T22:30:00-03:00'; // em UTC já é 11/09
    const p = planoInicialDaBaixa({ status: 'authorized', authorized_at: noite });
    expect(p).toMatchObject({ modo: 'avista', n: 2, intervaloDias: 30, parcelasDaNota: null });
    expect(p.primeiroVencimento).toBe(diaLocal(noite));
  });

  it('forma de pagamento: a do plano, senão a do pagamento declarado, senão 15', () => {
    expect(planoInicialDaBaixa({ request_payload: { payments: [{ method: '03' }] } }).metodo).toBe('03');
    expect(planoInicialDaBaixa({}).metodo).toBe('15');
  });

  it('nota sem data nenhuma: parte de agora', () => {
    const agora = new Date(2026, 9, 1, 9, 0, 0);
    expect(planoInicialDaBaixa({}, agora).primeiroVencimento).toBe('2026-10-01');
  });
});

describe('metodoDoRecebimentoNaHora', () => {
  it('dinheiro, cheque, cartões, Pix e transferência viram recebimento; boleto, crédito loja e outros não', () => {
    expect(['01', '02', '03', '04', '17', '16', '18'].map(metodoDoRecebimentoNaHora))
      .toEqual(['cash', 'check', 'credit_card', 'debit_card', 'pix', 'bank_transfer', 'bank_transfer']);
    expect(['15', '05', '99', '90', '14', '', null].map(metodoDoRecebimentoNaHora)).toEqual([null, null, null, null, null, null, null]);
  });
});

// Previsão de caixa: a fatura de cada cartão e os gastos que se repetem (27/09/2026).
import { describe, it, expect } from 'vitest';
import {
  inferirCiclo, faturasDoCartao, fechamentosEmVolta, vencimentoDaFatura, gastosQueSeRepetem,
  gastosQueSeRepetemPorDia, mesesDeReferencia, type LinhaDoCartao, type DespesaLancada,
} from './previsao-de-caixa';

const compra = (data: string, valor: number, bill: string | null = null, extra: Partial<LinhaDoCartao> = {}): LinhaDoCartao =>
  ({ transaction_date: data, amount: valor, transaction_type: 'debit', description: 'LOJA', bill_id: bill, ...extra });
const pagamento = (data: string, valor: number, descricao = 'Pagamento recebido'): LinhaDoCartao =>
  ({ transaction_date: data, amount: valor, transaction_type: 'credit', description: descricao });

/** Um cartão como o C6: ciclo do dia 18 ao 17, pago por volta do dia 25. */
function historicoC6(): LinhaDoCartao[] {
  const linhas: LinhaDoCartao[] = [];
  for (const [inicio, fim, bill] of [['2026-05-18', '2026-06-17', 'b5'], ['2026-06-18', '2026-07-17', 'b6'], ['2026-07-18', '2026-08-17', 'b7']] as const) {
    linhas.push(compra(inicio, 100, bill), compra(fim, 100, bill), compra(`${inicio.slice(0, 8)}25`, 100, bill));
  }
  linhas.push(pagamento('2026-06-25', 300), pagamento('2026-07-24', 300), pagamento('2026-08-26', 300));
  return linhas;
}

describe('ciclo do cartão', () => {
  it('fecha na véspera do dia em que as faturas começam e vence no dia do maior pagamento', () => {
    expect(inferirCiclo(historicoC6())).toEqual({ diaDeFechamento: 17, diaDePagamento: 25 });
  });

  it('cartão que começa o ciclo no dia 1 fecha no último dia do mês', () => {
    const linhas = ['b1', 'b2'].flatMap((b, i) => [compra(`2026-0${6 + i}-01`, 10, b), compra(`2026-0${6 + i}-15`, 10, b), compra(`2026-0${6 + i}-28`, 10, b)]);
    const c = inferirCiclo(linhas)!;
    expect(c.diaDeFechamento).toBe(31);
    expect(fechamentosEmVolta('2026-09-10', c)).toEqual({ anterior: '2026-07-31', ultimo: '2026-08-31', proximo: '2026-09-30' });
  });

  it('sem nenhuma fatura identificada pelo banco, não inventa ciclo', () => {
    expect(inferirCiclo([compra('2026-09-01', 50), compra('2026-09-02', 60)])).toBeNull();
  });

  it('vencimento: o primeiro dia de pagamento depois do fechamento, virando o mês e o ano', () => {
    const c = { diaDeFechamento: 17, diaDePagamento: 25 };
    expect(vencimentoDaFatura('2026-09-17', c)).toBe('2026-09-25');
    const nubank = { diaDeFechamento: 28, diaDePagamento: 5 };
    expect(vencimentoDaFatura('2026-12-28', nubank)).toBe('2027-01-05');
  });
});

describe('fatura de um cartão', () => {
  it('fechada e paga não aparece; a aberta leva as compras até hoje para o vencimento seguinte', () => {
    const linhas = [
      ...historicoC6(),
      compra('2026-08-20', 400), compra('2026-09-10', 200), // ciclo 18/08 a 17/09
      pagamento('2026-09-24', 600),                          // pagou a fechada inteira
      compra('2026-09-20', 150), compra('2026-09-26', 50),   // ciclo aberto
    ];
    const r = faturasDoCartao('C6', linhas, '2026-09-27');
    expect(r.faturas).toEqual([
      { conta: 'C6', valor: 200, vencimento: '2026-10-25', fechamento: '2026-10-17', situacao: 'aberta', vencida: false, compras: 2, pago: 0 },
    ]);
    expect(r.pagoAlemDoExtrato).toBe(0);
  });

  it('fechada sem pagamento suficiente: o que falta, o que foi pago, e vencida se o dia passou', () => {
    const linhas = [...historicoC6(), compra('2026-08-20', 400), compra('2026-09-10', 200), pagamento('2026-09-05', 100)];
    const [fechada] = faturasDoCartao('C6', linhas, '2026-09-27').faturas;
    expect(fechada).toMatchObject({ situacao: 'fechada', valor: 500, vencimento: '2026-09-25', vencida: true, compras: 2, pago: 100 });
  });

  it('o mesmo pagamento registrado duas vezes pelo cartão conta uma vez', () => {
    const linhas = [
      ...historicoC6(), compra('2026-08-20', 600),
      pagamento('2026-09-05', 300, 'Inclusao de Pagamento Ciclo Corrente'), pagamento('2026-09-05', 300, 'Pagamento recebido'),
    ];
    const [fechada] = faturasDoCartao('C6', linhas, '2026-09-27').faturas;
    expect(fechada).toMatchObject({ situacao: 'fechada', valor: 300 });
  });

  it('pago na fechada além das compras do extrato NÃO abate a aberta: vira aviso (o caso real do C6, 09/2026)', () => {
    // Extrato do cartão com R$ 362,55 de compras na fatura; pagos R$ 1.860,81. Faltam compras no
    // extrato — levar a "sobra" para a aberta zerava a fatura de outubro.
    const linhas = [
      ...historicoC6(), compra('2026-08-20', 362.55),
      pagamento('2026-09-05', 300), pagamento('2026-09-25', 1560.81),
      compra('2026-09-20', 1031.46),
    ];
    const r = faturasDoCartao('C6', linhas, '2026-09-27');
    expect(r.faturas).toEqual([expect.objectContaining({ situacao: 'aberta', valor: 1031.46, pago: 0 })]);
    expect(r.pagoAlemDoExtrato).toBe(1498.26);
    expect(r.fechada).toEqual({ fechamento: '2026-09-17', compras: 362.55, pago: 1860.81 });
  });

  it('pagamento depois do vencimento da fechada (mais 5 dias) é adiantamento da aberta', () => {
    const linhas = [
      ...historicoC6(), compra('2026-08-20', 600), pagamento('2026-09-24', 600),
      compra('2026-09-20', 150), compra('2026-09-26', 50), compra('2026-10-01', 100),
      pagamento('2026-10-03', 100),
    ];
    const r = faturasDoCartao('C6', linhas, '2026-10-05');
    expect(r.faturas).toEqual([expect.objectContaining({ situacao: 'aberta', valor: 200, pago: 100, compras: 3 })]);
    expect(r.pagoAlemDoExtrato).toBe(0);
  });

  it('parcela já lançada com data futura dentro do ciclo aberto entra na fatura aberta', () => {
    const linhas = [...historicoC6(), compra('2026-09-20', 100), compra('2026-10-10', 112.29, null, { description: 'COREMMA 3/4' }), compra('2026-10-20', 112.29)];
    // 10/10 é antes do fechamento (17/10): entra; 20/10 é do ciclo seguinte: não.
    expect(faturasDoCartao('C6', linhas, '2026-09-27').faturas).toEqual([expect.objectContaining({ situacao: 'aberta', valor: 212.29, compras: 2 })]);
  });

  it('duplicata e estorno de importação não são compra', () => {
    const linhas = [...historicoC6(), compra('2026-09-20', 300, null, { dismissed_kind: 'duplicata' }), compra('2026-09-21', 80)];
    expect(faturasDoCartao('C6', linhas, '2026-09-27').faturas).toEqual([expect.objectContaining({ situacao: 'aberta', valor: 80 })]);
  });

  it('sem ciclo conhecido, nada — e nenhum aviso inventado', () => {
    expect(faturasDoCartao('X', [compra('2026-09-01', 50)], '2026-09-27')).toEqual({ faturas: [], pagoAlemDoExtrato: 0, fechada: { fechamento: '', compras: 0, pago: 0 } });
  });
});

describe('gastos que se repetem', () => {
  const despesa = (categoria: string, data: string, valor: number, extra: Partial<DespesaLancada> = {}): DespesaLancada =>
    ({ categoria, data, valor, grupo: 'despesa_operacional', noCartao: false, ...extra });

  it('os 4 meses completos antes do mês de hoje', () => {
    expect(mesesDeReferencia('2026-01-15')).toEqual(['2025-09', '2025-10', '2025-11', '2025-12']);
  });

  it('entra a categoria de 3 dos 4 meses com valor estável; fica fora a que varia, a do cartão e a que não é despesa', () => {
    const r = gastosQueSeRepetem([
      despesa('Contabilidade', '2026-05-10', 1045.43), despesa('Contabilidade', '2026-06-10', 851.81), despesa('Contabilidade', '2026-07-10', 848.81),
      despesa('Pró-labore', '2026-05-05', 21953.15), despesa('Pró-labore', '2026-06-05', 9535.29), despesa('Pró-labore', '2026-07-05', 4130), despesa('Pró-labore', '2026-08-05', 1100),
      despesa('Assinatura', '2026-05-01', 50, { noCartao: true }), despesa('Assinatura', '2026-06-01', 50, { noCartao: true }), despesa('Assinatura', '2026-07-01', 50, { noCartao: true }),
      despesa('Pagamento de fatura de cartão', '2026-05-25', 5000, { grupo: 'nao_operacional' }), despesa('Pagamento de fatura de cartão', '2026-06-25', 5000, { grupo: 'nao_operacional' }), despesa('Pagamento de fatura de cartão', '2026-07-25', 5000, { grupo: 'nao_operacional' }),
      despesa('Energia', '2026-07-10', 300), despesa('Energia', '2026-08-10', 300),
      // Mês corrente não entra na média.
      despesa('Contabilidade', '2026-09-10', 5000),
    ], '2026-09-27');
    expect(r).toEqual([{ categoria: 'Contabilidade', mediaMensal: 915.35, meses: 3 }]);
  });

  it('espalha pelos dias da janela e desconta o que já está lançado no mês', () => {
    const porDia = gastosQueSeRepetemPorDia(
      [{ categoria: 'Contabilidade', mediaMensal: 930, meses: 3 }],
      [{ categoria: 'Contabilidade', valor: 930, vencimento: '2026-10-10' }],
      '2026-09-01', '2026-10-31',
    );
    // Setembro inteiro: 930 em 30 dias; outubro já lançado: nada.
    expect(porDia.get('2026-09-15')).toBeCloseTo(31, 5);
    expect(porDia.has('2026-10-15')).toBe(false);
    expect([...porDia.values()].reduce((s, v) => s + v, 0)).toBeCloseTo(930, 5);
  });

  it('só a parte do mês que cai na janela', () => {
    const porDia = gastosQueSeRepetemPorDia([{ categoria: 'Telefone', mediaMensal: 300, meses: 3 }], [], '2026-09-21', '2026-09-30');
    expect([...porDia.values()].reduce((s, v) => s + v, 0)).toBeCloseTo(100, 5);
    expect(porDia.size).toBe(10);
  });

  it('no mês de hoje, o que já foi pago não entra de novo (contabilidade paga no dia 2)', () => {
    const gasto = [{ categoria: 'Contabilidade', mediaMensal: 915.35, meses: 3 }];
    const soma = (m: Map<string, number>, mes: string) => [...m].filter(([d]) => d.startsWith(mes)).reduce((s, [, v]) => s + v, 0);
    // Paga inteira em 02/09: setembro não soma nada; outubro, a média inteira.
    const paga = gastosQueSeRepetemPorDia(gasto, [], '2026-09-03', '2026-10-31', new Map([['Contabilidade', 915.35]]));
    expect(soma(paga, '2026-09')).toBe(0);
    expect(soma(paga, '2026-10')).toBeCloseTo(915.35, 5);
    // Paga em parte: no máximo o que falta do mês.
    const emParte = gastosQueSeRepetemPorDia(gasto, [], '2026-09-03', '2026-09-30', new Map([['Contabilidade', 500]]));
    expect(soma(emParte, '2026-09')).toBeCloseTo(415.35, 5);
    // Nada pago: a parte dos dias que faltam, como antes (28 de 30 dias).
    const nada = gastosQueSeRepetemPorDia(gasto, [], '2026-09-03', '2026-09-30');
    expect(soma(nada, '2026-09')).toBeCloseTo(915.35 * 28 / 30, 5);
  });
});

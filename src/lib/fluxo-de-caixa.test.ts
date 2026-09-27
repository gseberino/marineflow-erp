// O fluxo de caixa pelo extrato: quais linhas contam, quais ficam à parte e quais ficam fora.
//
// Cada regra aqui é uma decisão do dono (26/09/2026) — e cada uma, errada, muda o número que
// ele usa para saber se o mês fechou no azul.
import { describe, it, expect } from 'vitest';
import {
  destinoDaLinha, montarFluxoDeCaixa, hojeEmBrasilia, ultimosMeses, limitesDosMeses,
  rotuloDoMes, nomeDoMes, somarFluxoDoPeriodo, somarDias, paresDeTransferencia,
  LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO, type LinhaDoFluxo,
} from './fluxo-de-caixa';

const HOJE = '2026-09-26';
const C6 = 'd288bc10-eff3-42c8-ae31-4c9a9b35e5c6';
const NUBANK = 'nubank-conta';
const CAIXA = 'caixa-dinheiro';
const LOTE = LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO;

function linha(p: Partial<LinhaDoFluxo>): LinhaDoFluxo {
  return {
    transaction_date: '2026-09-10', amount: 100, transaction_type: 'debit', source_type: 'bank',
    provider: 'pluggy', bank_connection_id: C6, dismissed_kind: null, tx_status: 'POSTED', ...p,
  };
}

describe('destino de cada linha do extrato', () => {
  it('Pix, boleto e débito da conta corrente contam', () => {
    expect(destinoDaLinha(linha({}), HOJE)).toBe('movimento');
    expect(destinoDaLinha(linha({ transaction_type: 'credit' }), HOJE)).toBe('movimento');
    // Linhas antigas vieram sem tx_status: continuam valendo.
    expect(destinoDaLinha(linha({ tx_status: null }), HOJE)).toBe('movimento');
  });

  it('Caixa em dinheiro conta', () => {
    expect(destinoDaLinha(linha({ source_type: 'cash', provider: 'caixa' }), HOJE)).toBe('movimento');
  });

  it('compra no cartão de crédito NÃO é saída de caixa (conta quando a fatura é paga)', () => {
    expect(destinoDaLinha(linha({ source_type: 'credit_card' }), HOJE)).toBe('fora_cartao');
    // Nem a mecânica do cartão do LADO do cartão entra: é o cartão, não a conta.
    expect(destinoDaLinha(linha({ source_type: 'credit_card', dismissed_kind: 'mecanica_cartao', transaction_type: 'credit' }), HOJE)).toBe('fora_cartao');
  });

  it('o pagamento da fatura é débito da conta corrente e conta normalmente', () => {
    expect(destinoDaLinha(linha({ transaction_type: 'debit', amount: 1560.81 }), HOJE)).toBe('movimento');
  });

  it('duplicata, estornada e a importação manual de julho ficam fora', () => {
    expect(destinoDaLinha(linha({ dismissed_kind: 'duplicata' }), HOJE)).toBe('fora_duplicata');
    expect(destinoDaLinha(linha({ dismissed_kind: 'estornada', source_type: 'cash' }), HOJE)).toBe('fora_estornada');
    // As 13 linhas da importação de 27/07 ainda sem a marca de duplicata: pelo LOTE.
    expect(destinoDaLinha(linha({ provider: 'manual', bank_connection_id: null, import_batch_id: LOTE }), HOJE)).toBe('fora_importacao_manual');
    // Extrato importado por arquivo depois daquele lote é dinheiro de verdade (revisão de 27/09/2026).
    expect(destinoDaLinha(linha({ provider: 'manual', bank_connection_id: null, import_batch_id: 'outro-lote' }), HOJE)).toBe('movimento');
    expect(destinoDaLinha(linha({ provider: 'manual', bank_connection_id: 'caixa' }), HOJE)).toBe('movimento');
  });

  it('pendente e data no futuro ficam fora', () => {
    expect(destinoDaLinha(linha({ tx_status: 'PENDING' }), HOJE)).toBe('fora_pendente');
    expect(destinoDaLinha(linha({ transaction_date: '2026-09-27' }), HOJE)).toBe('fora_futuro');
    expect(destinoDaLinha(linha({ transaction_date: HOJE }), HOJE)).toBe('movimento');
  });

  it('transferência entre contas próprias e crédito do cartão na conta ficam À PARTE', () => {
    expect(destinoDaLinha(linha({ dismissed_kind: 'transferencia' }), HOJE)).toBe('transferencia');
    expect(destinoDaLinha(linha({ dismissed_kind: 'mecanica_cartao', transaction_type: 'credit' }), HOJE)).toBe('credito_do_cartao');
  });

  it('o que fica fora ganha do balde à parte: transferência duplicada é duplicata', () => {
    expect(destinoDaLinha(linha({ dismissed_kind: 'duplicata', provider: 'manual', bank_connection_id: null }), HOJE)).toBe('fora_duplicata');
    expect(destinoDaLinha(linha({ dismissed_kind: 'transferencia', transaction_date: '2026-12-01' }), HOJE)).toBe('fora_futuro');
  });

  it('linha que tirou da fila por outro motivo (fatura, manual) continua sendo dinheiro', () => {
    expect(destinoDaLinha(linha({ dismissed_kind: 'manual' }), HOJE)).toBe('movimento');
    expect(destinoDaLinha(linha({ dismissed_kind: 'fatura_cartao' }), HOJE)).toBe('movimento');
    // Acerto da contagem do Caixa é dinheiro que entrou ou sumiu da gaveta.
    expect(destinoDaLinha(linha({ dismissed_kind: 'ajuste_caixa', source_type: 'cash' }), HOJE)).toBe('movimento');
  });

  it('sentido ou valor ilegível não entra em conta nenhuma', () => {
    expect(destinoDaLinha(linha({ transaction_type: 'estorno' }), HOJE)).toBe('fora_ilegivel');
    expect(destinoDaLinha(linha({ amount: 'abc' }), HOJE)).toBe('fora_ilegivel');
  });

  it('origem ausente vale como conta corrente (a mesma leitura das funções de saldo)', () => {
    expect(destinoDaLinha(linha({ source_type: null }), HOJE)).toBe('movimento');
  });
});

describe('montarFluxoDeCaixa', () => {
  const meses = ['2026-08', '2026-09'];

  it('soma entrou e saiu por mês, com o líquido', () => {
    const f = montarFluxoDeCaixa([
      linha({ transaction_date: '2026-08-05', transaction_type: 'credit', amount: 5237.99 }),
      linha({ transaction_date: '2026-08-06', amount: 371.73 }),
      linha({ transaction_date: '2026-09-22', transaction_type: 'credit', amount: '2025.00' }),
      linha({ transaction_date: '2026-09-23', amount: 144.21 }),
    ], meses, HOJE);
    expect(f.meses).toHaveLength(2);
    expect(f.meses[0]).toMatchObject({ mes: '2026-08', entrou: 5237.99, saiu: 371.73, liquido: 4866.26, quantidade: 2 });
    expect(f.meses[1]).toMatchObject({ mes: '2026-09', entrou: 2025, saiu: 144.21, liquido: 1880.79 });
    expect(f.total).toMatchObject({ entrou: 7262.99, saiu: 515.94, quantidade: 4 });
  });

  it('não deixa sobra de centavo ao somar muitas linhas', () => {
    const muitas = Array.from({ length: 1000 }, () => linha({ amount: 0.1 }));
    expect(montarFluxoDeCaixa(muitas, meses, HOJE).meses[1].saiu).toBe(100);
  });

  it('transferência COM as duas pernas e crédito do cartão vêm à parte, sem mexer em Entrou/Saiu', () => {
    const f = montarFluxoDeCaixa([
      linha({ id: 'a', amount: 1000 }),
      linha({ id: 't1', dismissed_kind: 'transferencia', amount: 2900, bank_connection_id: C6 }),
      linha({ id: 't2', dismissed_kind: 'transferencia', transaction_type: 'credit', amount: 2900, bank_connection_id: NUBANK, transaction_date: '2026-09-11' }),
      linha({ id: 'm', dismissed_kind: 'mecanica_cartao', transaction_type: 'credit', amount: 551.32 }),
    ], meses, HOJE);
    const set = f.meses[1];
    expect(set).toMatchObject({ entrou: 0, saiu: 1000, liquido: -1000, quantidade: 1 });
    expect(set.transferencias).toEqual({ entrou: 2900, saiu: 2900 });
    expect(set.creditoDoCartao).toEqual({ entrou: 551.32, saiu: 0 });
  });

  it('a marca transferência SEM a outra perna é dinheiro que entrou ou saiu de verdade', () => {
    // Pagamento da fatura do Nubank pela conta do C6 (a outra perna está no cartão) e as Vendas
    // que a maquininha liquida na InfinitePay: estavam marcados como transferência.
    const f = montarFluxoDeCaixa([
      linha({ id: 'fatura', dismissed_kind: 'transferencia', amount: 1593.09 }),
      linha({ id: 'lado-do-cartao', source_type: 'credit_card', transaction_type: 'credit', amount: 1593.09, bank_connection_id: NUBANK }),
      linha({ id: 'vendas', dismissed_kind: 'transferencia', transaction_type: 'credit', amount: 4105.2, bank_connection_id: 'infinitepay' }),
    ], meses, HOJE);
    expect(f.meses[1]).toMatchObject({ entrou: 4105.2, saiu: 1593.09 });
    expect(f.meses[1].transferencias).toEqual({ entrou: 0, saiu: 0 });
  });

  it('saque para o Caixa não conta duas vezes: o banco e o Caixa pareados, só o gasto conta', () => {
    const f = montarFluxoDeCaixa([
      linha({ id: 'saque-banco', amount: 500, dismissed_kind: 'manual' }),
      linha({ id: 'saque-caixa', source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 500, dismissed_kind: 'transferencia' }),
      linha({ id: 'almoco', source_type: 'cash', bank_connection_id: CAIXA, amount: 500, transaction_date: '2026-09-12' }),
    ], meses, HOJE);
    expect(f.meses[1]).toMatchObject({ entrou: 0, saiu: 500 });
    expect(f.meses[1].transferencias).toEqual({ entrou: 500, saiu: 500 });
  });

  it('par na virada do mês: cada perna fica à parte no seu mês', () => {
    const f = montarFluxoDeCaixa([
      linha({ id: 'sai', dismissed_kind: 'transferencia', amount: 800, transaction_date: '2026-08-31' }),
      linha({ id: 'entra', dismissed_kind: 'transferencia', transaction_type: 'credit', amount: 800, bank_connection_id: NUBANK, transaction_date: '2026-09-01' }),
    ], meses, HOJE);
    expect(f.meses[0].transferencias.saiu).toBe(800);
    expect(f.meses[1].transferencias.entrou).toBe(800);
    expect(f.total.entrou + f.total.saiu).toBe(0);
  });

  it('um par por linha: duas saídas iguais e uma entrada só formam um par', () => {
    const pares = paresDeTransferencia([
      linha({ id: 's1', dismissed_kind: 'transferencia', amount: 300 }),
      linha({ id: 's2', dismissed_kind: 'transferencia', amount: 300, transaction_date: '2026-09-12' }),
      linha({ id: 'e1', dismissed_kind: 'transferencia', transaction_type: 'credit', amount: 300, bank_connection_id: NUBANK }),
    ], HOJE);
    expect([...pares].sort()).toEqual(['e1', 's1']);
  });

  it('diz o que ficou fora e quanto', () => {
    const f = montarFluxoDeCaixa([
      linha({ dismissed_kind: 'duplicata', amount: 10 }),
      linha({ dismissed_kind: 'duplicata', amount: 5.5 }),
      linha({ provider: 'manual', bank_connection_id: null, import_batch_id: LOTE, amount: 66244.92 }),
      linha({ source_type: 'credit_card', amount: 20 }),
    ], meses, HOJE);
    expect(f.deFora.fora_duplicata).toEqual({ quantidade: 2, valor: 15.5 });
    expect(f.deFora.fora_importacao_manual).toEqual({ quantidade: 1, valor: 66244.92 });
    expect(f.deFora.fora_cartao).toEqual({ quantidade: 1, valor: 20 });
    expect(f.total.entrou + f.total.saiu).toBe(0);
  });

  it('mês sem movimento aparece zerado; linha fora dos meses pedidos é ignorada', () => {
    const f = montarFluxoDeCaixa([linha({ transaction_date: '2025-01-10', amount: 999 })], meses, HOJE);
    expect(f.meses.map((m) => m.mes)).toEqual(meses);
    expect(f.meses.every((m) => m.entrou === 0 && m.saiu === 0)).toBe(true);
    expect(f.deFora).toEqual({});
  });

  it('Entrou − Saiu + os baldes à parte = variação do saldo da conta (C6, 22 a 25/09/2026)', () => {
    // As linhas reais do C6 entre a conferência de 20/09 (saldo −99,53) e a de 25/09
    // (saldo 3.246,61): o banco subiu 3.346,14, e é o que a soma com sinal tem de dar.
    const reais: Array<[string, 'credit' | 'debit', number]> = [
      ['2026-09-22', 'debit', 371.73], ['2026-09-22', 'debit', 144.21], ['2026-09-22', 'debit', 300],
      ['2026-09-22', 'debit', 1560.81], ['2026-09-22', 'credit', 5237.99], ['2026-09-22', 'debit', 200],
      ['2026-09-22', 'debit', 100], ['2026-09-22', 'debit', 43], ['2026-09-22', 'debit', 372],
      ['2026-09-22', 'debit', 1500], ['2026-09-22', 'credit', 2025],
      ['2026-09-23', 'debit', 50], ['2026-09-23', 'debit', 335.1], ['2026-09-23', 'debit', 400],
      ['2026-09-23', 'debit', 250], ['2026-09-23', 'debit', 150],
      ['2026-09-24', 'debit', 100],
      ['2026-09-25', 'debit', 110], ['2026-09-25', 'credit', 2070],
    ];
    const f = montarFluxoDeCaixa(
      reais.map(([d, t, v]) => linha({ transaction_date: d, transaction_type: t, amount: v })),
      ['2026-09'], HOJE,
    );
    const m = f.meses[0];
    const variacao = m.liquido + (m.transferencias.entrou - m.transferencias.saiu) + (m.creditoDoCartao.entrou - m.creditoDoCartao.saiu);
    expect(Math.round(variacao * 100) / 100).toBe(3346.14);
    expect(Math.round((-99.53 + variacao) * 100) / 100).toBe(3246.61);
  });
});

describe('datas do fluxo', () => {
  it('hoje é o dia de Brasília, não o de Greenwich', () => {
    // 02:00 UTC de 01/10 ainda é 30/09 em Brasília.
    expect(hojeEmBrasilia(new Date('2026-10-01T02:00:00Z'))).toBe('2026-09-30');
    expect(hojeEmBrasilia(new Date('2026-10-01T12:00:00Z'))).toBe('2026-10-01');
  });

  it('últimos meses atravessam a virada do ano', () => {
    expect(ultimosMeses(3, '2026-01-15')).toEqual(['2025-11', '2025-12', '2026-01']);
    expect(ultimosMeses(1, '2026-09')).toEqual(['2026-09']);
    expect(ultimosMeses(12, '2026-09-26')).toHaveLength(12);
  });

  it('limites vão do dia 1º do primeiro mês ao último dia do último', () => {
    expect(limitesDosMeses(['2026-01', '2026-02'])).toEqual({ de: '2026-01-01', ate: '2026-02-28' });
    expect(limitesDosMeses(['2024-02'])).toEqual({ de: '2024-02-01', ate: '2024-02-29' });
  });

  it('rótulos do mês', () => {
    expect(rotuloDoMes('2026-09')).toBe('Set/26');
    expect(nomeDoMes('2026-03')).toBe('março de 2026');
  });
});

describe('fluxo de um período de dias (o fechamento do assistente)', () => {
  it('soma só os dias pedidos, com a mesma regra', () => {
    const r = somarFluxoDoPeriodo([
      linha({ id: '1', transaction_date: '2026-09-20', transaction_type: 'credit', amount: 700 }),
      linha({ id: '2', transaction_date: '2026-09-21', amount: 120 }),
      linha({ id: '3', transaction_date: '2026-09-25', amount: 999 }),
      linha({ id: '4', transaction_date: '2026-09-21', dismissed_kind: 'duplicata', amount: 50 }),
    ], '2026-09-20', '2026-09-21', HOJE);
    expect(r).toMatchObject({ entrou: 700, saiu: 120, liquido: 580 });
    expect(r.deFora.fora_duplicata).toEqual({ quantidade: 1, valor: 50 });
  });

  it('somarDias não escorrega de dia por fuso', () => {
    expect(somarDias('2026-09-01', -3)).toBe('2026-08-29');
    expect(somarDias('2026-12-30', 3)).toBe('2027-01-02');
  });
});

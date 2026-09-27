// O fluxo de caixa pelo extrato: quais linhas contam, quais ficam à parte e quais ficam fora.
//
// Cada regra aqui é uma decisão do dono (26/09/2026) — e cada uma, errada, muda o número que
// ele usa para saber se o mês fechou no azul.
import { describe, it, expect } from 'vitest';
import {
  destinoDaLinha, montarFluxoDeCaixa, hojeEmBrasilia, ultimosMeses, limitesDosMeses,
  rotuloDoMes, nomeDoMes, somarFluxoDoPeriodo, somarDias, paresDeTransferencia, transferenciaProvada,
  mesesInteirosDoPeriodo, LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO, type LinhaDoFluxo,
} from './fluxo-de-caixa';

const HOJE = '2026-09-26';
const C6 = 'd288bc10-eff3-42c8-ae31-4c9a9b35e5c6';
const NUBANK = 'nubank-conta';
const CAIXA = 'caixa-dinheiro';
const LOTE = LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO;
/** A raiz do CNPJ da HBR e uma linha de Pix com ela do outro lado. */
const OPCOES = { raizDaEmpresa: '50057049' };
const daHBR = { counterparty_document: '50.057.049/0001-00', payment_method: 'PIX' } as const;
/** O motivo que o "+ Lançar" grava nas duas pontas do saque e do depósito ligados. */
const SAQUE = { dismissed_reason: 'Saque do banco para o Caixa' } as const;
const DEPOSITO = { dismissed_reason: 'Depósito do Caixa no banco' } as const;

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
    // O acerto da contagem do Caixa fica FORA, com o nome dele na lista do que ficou de fora: a
    // primeira contagem põe o saldo inteiro do Caixa numa linha só, e contá-la como "Entrou"
    // inventaria uma receita no mês (2ª revisão de 27/09/2026).
    expect(destinoDaLinha(linha({ dismissed_kind: 'ajuste_caixa', source_type: 'cash' }), HOJE)).toBe('fora_ajuste_caixa');
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

  it('Pix entre contas da HBR na virada do mês: cada ponta fica à parte no seu mês, pela outra ponta', () => {
    const f = montarFluxoDeCaixa([
      linha({ id: 'sai', amount: 800, transaction_date: '2026-08-31', ...daHBR }),
      linha({ id: 'entra', transaction_type: 'credit', amount: 800, bank_connection_id: NUBANK, transaction_date: '2026-09-01', ...daHBR }),
    ], meses, HOJE, OPCOES);
    expect(f.meses[0].transferencias.saiu).toBe(800);
    expect(f.meses[1].transferencias.entrou).toBe(800);
    expect(f.total.entrou + f.total.saiu).toBe(0);
  });

  it('marcada sem prova na virada do mês não tem par: o par nunca atravessa o mês', () => {
    // Sem a outra ponta no extrato, só o par diria que é transferência — e o par é do mês. Conta
    // como saída num mês e entrada no outro (o líquido dos dois meses continua certo).
    const f = montarFluxoDeCaixa([
      linha({ id: 'sai', dismissed_kind: 'transferencia', amount: 800, transaction_date: '2026-08-31' }),
      linha({ id: 'entra', dismissed_kind: 'transferencia', transaction_type: 'credit', amount: 800, bank_connection_id: NUBANK, transaction_date: '2026-09-01' }),
    ], meses, HOJE);
    expect(f.meses[0]).toMatchObject({ saiu: 800 });
    expect(f.meses[1]).toMatchObject({ entrou: 800 });
    expect(f.total.liquido).toBe(0);
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

/** Todas as ordens possíveis de uma lista. */
function permutacoes<T>(xs: T[]): T[][] {
  if (xs.length <= 1) return [xs];
  return xs.flatMap((x, i) => permutacoes([...xs.slice(0, i), ...xs.slice(i + 1)]).map((resto) => [x, ...resto]));
}

describe('pareamento: o maior número de pares, e o mesmo número em qualquer tela (2ª revisão de 27/09/2026)', () => {
  it('transferência seguida de saque do mesmo valor: as quatro pernas ficam à parte, em qualquer ordem de id', () => {
    // Nubank → C6 R$ 1.000 e, no mesmo dia, saque de R$ 1.000 do C6 para o Caixa. Pegar "o
    // primeiro par" casava o Nubank com o Caixa e deixava as duas pernas do C6 órfãs.
    const pernas: Array<Partial<LinhaDoFluxo>> = [
      { transaction_type: 'debit', bank_connection_id: NUBANK },
      { transaction_type: 'credit', bank_connection_id: C6 },
      { transaction_type: 'debit', bank_connection_id: C6 },
      { transaction_type: 'credit', bank_connection_id: CAIXA, source_type: 'cash' },
    ];
    for (const ids of permutacoes(['a', 'b', 'c', 'd'])) {
      const linhas = pernas.map((p, i) => linha({ id: ids[i], amount: 1000, dismissed_kind: 'transferencia', ...p }));
      const f = montarFluxoDeCaixa(linhas, ['2026-09'], HOJE);
      expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 0 });
      expect(f.meses[0].transferencias).toEqual({ entrou: 2000, saiu: 2000 });
    }
  });

  it('o mesmo mês dá o mesmo número lendo o mês, o ano ou o período — e nenhuma perna serve a dois meses', () => {
    // Crédito marcado sem prova em 28/08; débito em 30/08; crédito em 01/09. Agosto pareia os dois
    // dele; o de setembro fica sem par em qualquer leitura.
    const linhas = [
      linha({ id: 'x', transaction_date: '2026-08-28', transaction_type: 'credit', amount: 1000, dismissed_kind: 'transferencia' }),
      linha({ id: 'd', transaction_date: '2026-08-30', amount: 1000, dismissed_kind: 'transferencia', bank_connection_id: NUBANK }),
      linha({ id: 'c', transaction_date: '2026-09-01', transaction_type: 'credit', amount: 1000, dismissed_kind: 'transferencia' }),
    ];
    const doAno = montarFluxoDeCaixa(linhas, ultimosMeses(12, '2026-12'), HOJE);
    const setembro = doAno.meses.find((m) => m.mes === '2026-09')!;
    const soSetembro = linhas.filter((l) => l.transaction_date >= '2026-09-01');
    const doMes = montarFluxoDeCaixa(soSetembro, ['2026-09'], HOJE).meses[0];
    const doPeriodo = somarFluxoDoPeriodo(soSetembro, '2026-09-01', HOJE, HOJE);
    expect(setembro).toMatchObject({ entrou: 1000, saiu: 0, transferencias: { entrou: 0, saiu: 0 } });
    for (const r of [doMes, doPeriodo]) {
      expect([r.entrou, r.saiu, r.transferencias]).toEqual([setembro.entrou, setembro.saiu, setembro.transferencias]);
    }
    // As transferências do ano fecham: cada par tem uma entrada e uma saída.
    expect(doAno.total.transferencias.entrou).toBe(doAno.total.transferencias.saiu);
  });

  it('sem perna usada em dois meses mesmo sem empate (a0, bp, a, b na virada)', () => {
    const linhas = [
      linha({ id: 'a0', transaction_date: '2026-08-29', amount: 1000, dismissed_kind: 'transferencia', bank_connection_id: 'infinitepay' }),
      linha({ id: 'bp', transaction_date: '2026-08-31', transaction_type: 'credit', amount: 1000, dismissed_kind: 'transferencia', bank_connection_id: NUBANK }),
      linha({ id: 'a', transaction_date: '2026-08-31', amount: 1000, dismissed_kind: 'transferencia' }),
      linha({ id: 'b', transaction_date: '2026-09-01', transaction_type: 'credit', amount: 1000, dismissed_kind: 'transferencia', bank_connection_id: 'infinitepay' }),
    ];
    const f = montarFluxoDeCaixa(linhas, ['2026-08', '2026-09'], HOJE);
    // Agosto: um par e uma saída sem par; setembro: a entrada sem par. Nada contado duas vezes.
    expect(f.meses[0].transferencias).toEqual({ entrou: 1000, saiu: 1000 });
    expect(f.meses[0].saiu).toBe(1000);
    expect(f.meses[1]).toMatchObject({ entrou: 1000, transferencias: { entrou: 0, saiu: 0 } });
  });

  it('a perna do Caixa não casa com o crédito do cartão na conta, qualquer que seja a ordem', () => {
    // Depósito do Caixa de R$ 500 lançado sem ligar a linha do banco; no mesmo dia, o crédito
    // do depósito no C6 e um "Pix no crédito" de R$ 500.
    for (const [idDoCartao, idDoDeposito] of [['a', 'b'], ['b', 'a']]) {
      const f = montarFluxoDeCaixa([
        linha({ id: 'cx', source_type: 'cash', bank_connection_id: CAIXA, amount: 500, dismissed_kind: 'transferencia' }),
        linha({ id: idDoDeposito, transaction_type: 'credit', amount: 500 }),
        linha({ id: idDoCartao, transaction_type: 'credit', amount: 500, dismissed_kind: 'mecanica_cartao' }),
      ], ['2026-09'], HOJE);
      expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 0 });
      expect(f.meses[0].transferencias).toEqual({ entrou: 500, saiu: 500 });
      expect(f.meses[0].creditoDoCartao).toEqual({ entrou: 500, saiu: 0 });
    }
  });

  it('a perna marcada casa antes com outra marcada do que com uma linha comum do banco', () => {
    // Saque de R$ 300 ligado à linha do banco (as duas marcadas) e, no mesmo dia, um Pix comum
    // de R$ 300 a um fornecedor: o Pix continua sendo saída.
    const f = montarFluxoDeCaixa([
      linha({ id: 'z-saque', amount: 300, dismissed_kind: 'transferencia' }),
      linha({ id: 'a-pix', amount: 300 }),
      linha({ id: 'cx', source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 300, dismissed_kind: 'transferencia' }),
    ], ['2026-09'], HOJE);
    expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 300, quantidade: 1 });
    expect(f.meses[0].transferencias).toEqual({ entrou: 300, saiu: 300 });
  });
});

describe('ajuste pela contagem do Caixa', () => {
  it('acerta o saldo, mas não é dinheiro que entrou nem saiu', () => {
    // A primeira contagem põe o saldo inteiro do Caixa numa linha só.
    const f = montarFluxoDeCaixa([
      linha({ id: 'aj', source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 3000, dismissed_kind: 'ajuste_caixa' }),
      linha({ id: 'g', source_type: 'cash', bank_connection_id: CAIXA, amount: 45 }),
    ], ['2026-09'], HOJE);
    expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 45 });
    expect(f.deFora.fora_ajuste_caixa).toEqual({ quantidade: 1, valor: 3000 });
  });
});

describe('transferência entre contas suas: a linha diz, não a marca (extrato real, 27/09/2026)', () => {
  it('Pix com o CNPJ da HBR do outro lado é transferência, marcado ou não — mesmo sem a outra perna', () => {
    // Conta da HBR em banco que não está ligado ao sistema: a outra perna nem aparece.
    const f = montarFluxoDeCaixa([
      linha({ id: 'a', transaction_type: 'credit', amount: 22230, dismissed_kind: 'transferencia', ...daHBR }),
      linha({ id: 'b', amount: 3000, ...daHBR }),
    ], ['2026-09'], HOJE, OPCOES);
    expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 0, transferencias: { entrou: 22230, saiu: 3000 } });
  });

  it('boleto ou estorno com o CNPJ da HBR registrado não é transferência: é dinheiro de verdade', () => {
    // O banco grava a própria empresa como outra ponta na cobrança por boleto e no estorno de loja.
    const cobranca = linha({ transaction_type: 'credit', dismissed_kind: 'transferencia', counterparty_document: '50057049000100', payment_method: 'BOLETO' });
    const estorno = linha({ transaction_type: 'credit', dismissed_kind: 'transferencia', counterparty_document: '50057049000100', payment_method: 'OTHER' });
    expect(transferenciaProvada(cobranca, OPCOES)).toBe(false);
    expect(transferenciaProvada(estorno, OPCOES)).toBe(false);
    const f = montarFluxoDeCaixa([{ ...cobranca, id: 'c', amount: 2700 }, { ...estorno, id: 'e', amount: 406.84 }], ['2026-09'], HOJE, OPCOES);
    expect(f.meses[0].entrou).toBe(3106.84);
  });

  it('Pix de uma pessoa (o sócio) marcado como transferência é dinheiro que entrou', () => {
    const f = montarFluxoDeCaixa([
      linha({ id: 'g', transaction_type: 'credit', amount: 1500, dismissed_kind: 'transferencia', counterparty_document: '123.456.789-00', payment_method: 'PIX' }),
    ], ['2026-09'], HOJE, OPCOES);
    expect(f.meses[0].entrou).toBe(1500);
  });

  it('aplicação e resgate de investimento ficam à parte nos dois sentidos, marcados ou não', () => {
    // No extrato real as aplicações no CDB não tinham marca e os resgates tinham.
    const f = montarFluxoDeCaixa([
      linha({ id: 'ap', amount: 30000, description: 'CDB C6 LIM.GARANT.', payment_method: 'OTHER' }),
      linha({ id: 'rs', transaction_type: 'credit', amount: 18983.64, description: 'CDB C6 LIM. GARANT.', dismissed_kind: 'transferencia' }),
      linha({ id: 'rdb', transaction_type: 'credit', amount: 1200, description: 'Resgate RDB', bank_connection_id: NUBANK, dismissed_kind: 'transferencia' }),
    ], ['2026-09'], HOJE, OPCOES);
    expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 0, transferencias: { entrou: 20183.64, saiu: 30000 } });
  });

  it('"Vendas" da maquininha é receita mesmo marcada como transferência', () => {
    const f = montarFluxoDeCaixa([
      linha({ id: 'v', transaction_type: 'credit', amount: 7184.12, description: 'Vendas', dismissed_kind: 'transferencia', bank_connection_id: 'infinitepay', ...daHBR, payment_method: 'OTHER' }),
    ], ['2026-09'], HOJE, OPCOES);
    expect(f.meses[0]).toMatchObject({ entrou: 7184.12, transferencias: { entrou: 0, saiu: 0 } });
  });

  it('sem a raiz do CNPJ, a regra segue só com a marca e o par', () => {
    const l = linha({ id: 'a', transaction_type: 'credit', amount: 500, ...daHBR });
    expect(transferenciaProvada(l, {})).toBe(false);
    expect(montarFluxoDeCaixa([l], ['2026-09'], HOJE).meses[0].entrou).toBe(500);
  });
});

describe('crédito do cartão na conta pela descrição (conferência final)', () => {
  it('"Valor adicionado... PIX no Crédito" é crédito do cartão mesmo marcado como transferência, e não rouba par', () => {
    const f = montarFluxoDeCaixa([
      linha({ id: 'cartao', transaction_date: '2026-07-26', transaction_type: 'credit', amount: 80, bank_connection_id: NUBANK, dismissed_kind: 'transferencia',
        description: 'Valor adicionado na conta por cartão de crédito | Valor adicionado para PIX no Crédito', payment_method: 'TEF' }),
      linha({ id: 'compra', transaction_date: '2026-07-26', amount: 80, dismissed_kind: 'transferencia', description: 'TICKETEXPRESS          ITAJAI        BRA', payment_method: 'OTHER' }),
    ], ['2026-07'], '2026-07-31', OPCOES);
    expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 80 });
    expect(f.meses[0].creditoDoCartao).toEqual({ entrou: 80, saiu: 0 });
    expect(f.meses[0].transferencias).toEqual({ entrou: 0, saiu: 0 });
  });
});

describe('crédito do cartão pela descrição: só o do cartão', () => {
  it('"Valor adicionado" que não fala de cartão de crédito nem de Pix no crédito continua dinheiro', () => {
    const l = linha({ transaction_type: 'credit', amount: 50, description: 'Valor adicionado via Pix - devolução de crédito' });
    expect(destinoDaLinha(l, HOJE)).toBe('movimento');
    const noBoleto = linha({ transaction_type: 'credit', amount: 50, description: 'Valor adicionado na conta por boleto' });
    expect(destinoDaLinha(noBoleto, HOJE)).toBe('movimento');
  });
});

describe('fases do pareamento (reconferência de 27/09/2026)', () => {
  it('o saque ligado ao banco casa antes; a marcada de outra conta e o Pix comum continuam dinheiro', () => {
    // Saque ligado: débito no C6 e crédito no Caixa, os dois marcados. No mesmo dia, um crédito
    // marcado sem prova em outra conta e um Pix comum a fornecedor, do mesmo valor.
    for (const ids of permutacoes(['a', 'b', 'c', 'd'])) {
      const f = montarFluxoDeCaixa([
        linha({ id: ids[0], amount: 500, dismissed_kind: 'transferencia', ...SAQUE }),
        linha({ id: ids[1], source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 500, dismissed_kind: 'transferencia', ...SAQUE }),
        linha({ id: ids[2], transaction_type: 'credit', amount: 500, dismissed_kind: 'transferencia', bank_connection_id: 'infinitepay' }),
        linha({ id: ids[3], amount: 500, bank_connection_id: NUBANK }),
      ], ['2026-09'], HOJE);
      expect(f.meses[0]).toMatchObject({ entrou: 500, saiu: 500 });
      expect(f.meses[0].transferencias).toEqual({ entrou: 500, saiu: 500 });
    }
  });

  it('depósito ligado ao banco casa antes; a fatura marcada e o Pix do cliente continuam dinheiro', () => {
    for (const ids of permutacoes(['a', 'b', 'c', 'd'])) {
      const f = montarFluxoDeCaixa([
        linha({ id: ids[0], source_type: 'cash', bank_connection_id: CAIXA, amount: 500, dismissed_kind: 'transferencia', ...DEPOSITO }),
        linha({ id: ids[1], transaction_type: 'credit', amount: 500, dismissed_kind: 'transferencia', bank_connection_id: NUBANK, ...DEPOSITO }),
        linha({ id: ids[2], amount: 500, dismissed_kind: 'transferencia' }),
        linha({ id: ids[3], transaction_type: 'credit', amount: 500 }),
      ], ['2026-09'], HOJE);
      expect(f.meses[0]).toMatchObject({ entrou: 500, saiu: 500 });
      expect(f.meses[0].transferencias).toEqual({ entrou: 500, saiu: 500 });
    }
  });

  it('o depósito ligado não é desmanchado por uma fatura e um Pix do sócio marcados (conferência final)', () => {
    // Depósito do Caixa ligado no dia 10; fatura do Nubank paga pelo C6 no dia 8 e Pix do sócio no
    // C6 no dia 12, os dois marcados como transferência e sem par de verdade. Tudo R$ 500.
    for (const ids of permutacoes(['a', 'b', 'c', 'd'])) {
      const f = montarFluxoDeCaixa([
        linha({ id: ids[0], source_type: 'cash', bank_connection_id: CAIXA, amount: 500, dismissed_kind: 'transferencia', ...DEPOSITO }),
        linha({ id: ids[1], transaction_type: 'credit', amount: 500, dismissed_kind: 'transferencia', bank_connection_id: NUBANK, ...DEPOSITO }),
        linha({ id: ids[2], transaction_date: '2026-09-08', amount: 500, dismissed_kind: 'transferencia' }),
        linha({ id: ids[3], transaction_date: '2026-09-12', transaction_type: 'credit', amount: 500, dismissed_kind: 'transferencia' }),
      ], ['2026-09'], HOJE);
      expect(f.meses[0]).toMatchObject({ entrou: 500, saiu: 500 });
      expect(f.meses[0].transferencias).toEqual({ entrou: 500, saiu: 500 });
    }
  });

  it('as pontas ligadas pelo "+ Lançar" casam entre si mesmo com outra linha igual no dia', () => {
    // Dois saques de R$ 200 no mesmo dia: um ligado ao banco, outro lançado sem ligar.
    const f = montarFluxoDeCaixa([
      linha({ id: 'b1', amount: 200, dismissed_kind: 'transferencia', ...SAQUE }),
      linha({ id: 'c1', source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 200, dismissed_kind: 'transferencia', ...SAQUE }),
      linha({ id: 'b2', amount: 200, description: 'SAQUE 24H' }),
      linha({ id: 'c2', source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 200, dismissed_kind: 'transferencia', ...SAQUE }),
    ], ['2026-09'], HOJE);
    expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 0, transferencias: { entrou: 400, saiu: 400 } });
  });

  it('dois saques ligados no mesmo dia com centavos cruzados: os dois pares fecham, em qualquer ordem', () => {
    for (const ids of permutacoes(['a', 'b', 'c', 'd'])) {
      const f = montarFluxoDeCaixa([
        linha({ id: ids[0], amount: 500.01, dismissed_kind: 'transferencia', ...SAQUE }),
        linha({ id: ids[1], amount: 500.02, dismissed_kind: 'transferencia', ...SAQUE }),
        linha({ id: ids[2], source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 500.00, dismissed_kind: 'transferencia', ...SAQUE }),
        linha({ id: ids[3], source_type: 'cash', bank_connection_id: CAIXA, transaction_type: 'credit', amount: 500.01, dismissed_kind: 'transferencia', ...SAQUE }),
      ], ['2026-09'], HOJE);
      expect(f.meses[0]).toMatchObject({ entrou: 0, saiu: 0 });
      expect(f.meses[0].transferencias).toEqual({ entrou: 1000.01, saiu: 1000.03 });
    }
  });

  it('meses inteiros de um período: é o que a leitura do assistente traz', () => {
    expect(mesesInteirosDoPeriodo('2026-08-28', '2026-09-03')).toEqual({ de: '2026-08-01', ate: '2026-09-30' });
    expect(mesesInteirosDoPeriodo('2026-09-26', '2026-09-26')).toEqual({ de: '2026-09-01', ate: '2026-09-30' });
  });
});

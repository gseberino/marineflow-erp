// "Lançados sozinhos" com a baixa pelo boleto (22/11/2026): a conta a desfazer é a casada com a linha do banco.
// 24/11/2026: a conta casada pode ser a RECEBER (recebimento baixado pelo boleto) — o lado vai junto com o id,
// porque é ele que o Desfazer manda para o banco e que separa a entrada do total das saídas.
// 24/11/2026 (revisão): a marca de RECEBER só vale com o registro da conciliação provando que a baixa é a do sistema —
// sem isso, a baixa desfeita voltava como "baixada sozinha" quando o dono casava a mesma linha à mão.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const { leituras, pedidos, fila } = vi.hoisted(() => ({
  leituras: {} as Record<string, { data: unknown; error: unknown }>,
  pedidos: [] as Array<{ tabela: string; colunas: string; filtro: string; ids: string[] }>,
  fila: { colunas: '' },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => ({
      select: (colunas: string) => {
        // A leitura da fila (useLancadosSozinhos) encadeia filtros e termina no limit; as outras terminam no in.
        const daFila = {
          not: () => daFila, eq: () => daFila, gte: () => daFila, order: () => daFila,
          limit: () => { fila.colunas = colunas; return Promise.resolve(leituras[tabela] ?? { data: [], error: null }); },
        };
        return {
          ...daFila,
          in: (filtro: string, ids: string[]) => {
            pedidos.push({ tabela, colunas, filtro, ids });
            return Promise.resolve(leituras[tabela] ?? { data: [], error: null });
          },
        };
      },
    }),
  },
}));

import {
  comContaBaixada, contasCasadasComAsLinhas, registrosDasLinhas, useLancadosSozinhos, type LancadoSozinho, type RegistroDaLinha,
} from './use-extrato-conta';

const linha = (id: string, automatica: LancadoSozinho['automatica'], tx: string | null, criada: string | null = null): LancadoSozinho => ({
  id, title: `Despesa ${id}`, suggested_amount: 10, suggested_category: null, suggested_date: '2026-11-17',
  decided_at: '2026-11-22T10:00:00Z', decision_note: null, automatica, created_payable_id: criada, created_receivable_id: null,
  bank_transaction_id: tx,
});
/** A marca de RECEBER, como a função do banco deixa: proposta de entrada ('create_receivable') aprovada com 'boleto'. */
const recebimento = (id: string, tx: string | null): LancadoSozinho => ({ ...linha(id, 'boleto', tx), kind: 'create_receivable' });
/** O único registro que a baixa sozinha deixa na linha do banco. */
const baixaSozinha = (tx: string, conta: string): RegistroDaLinha => ({
  bank_transaction_id: tx, receivable_id: conta, acao: 'conciliou', detalhe: 'Baixa automática pelo boleto · NF-e 2/25 (parcela 3/3) ↔ CLIENTE DE TESTE',
});
const registro = (tx: string, acao: string, conta: string | null, detalhe: string | null = null): RegistroDaLinha => ({
  bank_transaction_id: tx, receivable_id: conta, acao, detalhe,
});

beforeEach(() => {
  pedidos.length = 0;
  fila.colunas = '';
  for (const tabela of Object.keys(leituras)) delete leituras[tabela];
});

describe('comContaBaixada', () => {
  it('a baixa pelo boleto ganha a conta casada com a linha do banco; as outras ficam como estavam', () => {
    const r = comContaBaixada(
      [linha('q1', 'boleto', 't1'), linha('q2', 'confianca', 't2', 'p2'), linha('q3', 'regra', 't3', 'p3')],
      [{ id: 'conta-1', bank_transaction_id: 't1', tipo: 'payable' }],
    );
    expect(r.map((l) => [l.id, l.conta_baixada_id ?? null, l.created_payable_id])).toEqual([
      ['q1', 'conta-1', null], ['q2', null, 'p2'], ['q3', null, 'p3'],
    ]);
  });

  it('baixa já desfeita (nenhuma conta casada com a linha) sai da lista', () => {
    const r = comContaBaixada(
      [linha('q1', 'boleto', 't1'), linha('q2', 'boleto', 't-desfeita'), linha('q3', 'boleto', null)],
      [{ id: 'conta-1', bank_transaction_id: 't1', tipo: 'payable' }, { id: 'solta', bank_transaction_id: null, tipo: 'payable' }],
    );
    expect(r.map((l) => l.id)).toEqual(['q1']);
  });

  it('recebimento baixado pelo boleto vem com a conta a receber e o tipo "receivable"; a conta a pagar continua "payable"', () => {
    const r = comContaBaixada(
      [recebimento('q1', 't-credito'), linha('q2', 'boleto', 't-debito'), linha('q3', 'confianca', 't3', 'p3')],
      [
        { id: 'receber-1', bank_transaction_id: 't-credito', tipo: 'receivable' },
        { id: 'pagar-1', bank_transaction_id: 't-debito', tipo: 'payable' },
      ],
      [baixaSozinha('t-credito', 'receber-1')],
    );
    expect(r.map((l) => [l.id, l.conta_baixada_id ?? null, l.conta_baixada_tipo ?? null])).toEqual([
      ['q1', 'receber-1', 'receivable'], ['q2', 'pagar-1', 'payable'], ['q3', null, null],
    ]);
    // Quem não é baixa pelo boleto não ganha campo nenhum: o objeto é o mesmo que chegou.
    expect(r[2]).not.toHaveProperty('conta_baixada_tipo');
  });

  it('recebimento desfeito (a conta a receber não está mais casada com a linha) sai da lista', () => {
    const r = comContaBaixada(
      [recebimento('q1', 't-credito'), recebimento('q2', 't-credito-desfeito')],
      [{ id: 'receber-1', bank_transaction_id: 't-credito', tipo: 'receivable' }, { id: 'reaberta', bank_transaction_id: null, tipo: 'receivable' }],
      [
        baixaSozinha('t-credito', 'receber-1'),
        baixaSozinha('t-credito-desfeito', 'reaberta'), registro('t-credito-desfeito', 'desconciliou', 'reaberta'),
      ],
    );
    expect(r.map((l) => [l.id, l.conta_baixada_tipo])).toEqual([['q1', 'receivable']]);
  });
});

// 24/11/2026 (revisão): o desfazer não toca na proposta — ela fica aprovada com 'boleto' para sempre. A conta casada
// com a linha, sozinha, não prova mais nada: pode ser decisão do dono depois do desfazer.
describe('comContaBaixada — a marca de receber que revivia', () => {
  it('baixa desfeita e a mesma linha casada à mão com OUTRA conta: não volta à lista', () => {
    const r = comContaBaixada(
      [recebimento('q1', 't1')],
      [{ id: 'conta-do-cliente-b', bank_transaction_id: 't1', tipo: 'receivable' }],
      [
        baixaSozinha('t1', 'conta-do-cliente-a'),
        registro('t1', 'desconciliou', 'conta-do-cliente-a', 'Recebimento baixado pelo boleto — desfeito para revisão'),
        registro('t1', 'conciliou', 'conta-do-cliente-b', 'Saldo OS-00200 ↔ CLIENTE B'),
      ],
    );
    expect(r).toEqual([]);
  });

  it('a faxina da varredura na mesma linha (tirou_da_fila_ja_lancada) não esconde a baixa que continua de pé', () => {
    const r = comContaBaixada(
      [recebimento('q1', 't1')],
      [{ id: 'conta-do-cliente-a', bank_transaction_id: 't1', tipo: 'receivable' }],
      [baixaSozinha('t1', 'conta-do-cliente-a'), registro('t1', 'tirou_da_fila_ja_lancada', null, 'Proposta repetida fechada')],
    );
    expect(r.map((l) => [l.id, l.conta_baixada_id, l.conta_baixada_tipo])).toEqual([['q1', 'conta-do-cliente-a', 'receivable']]);
    // …mas a faxina sozinha, sem o registro da baixa, não faz a marca valer
    expect(comContaBaixada([recebimento('q1', 't1')], [{ id: 'conta-do-cliente-a', bank_transaction_id: 't1', tipo: 'receivable' }],
      [registro('t1', 'tirou_da_fila_ja_lancada', null)])).toEqual([]);
  });

  it('baixa desfeita e a linha casada à mão com a MESMA conta: também não volta — agora a decisão é do dono', () => {
    const r = comContaBaixada(
      [recebimento('q1', 't1')],
      [{ id: 'receber-1', bank_transaction_id: 't1', tipo: 'receivable' }],
      [baixaSozinha('t1', 'receber-1'), registro('t1', 'desconciliou', 'receber-1'), registro('t1', 'conciliou', 'receber-1', 'NF-e 2/25 ↔ CLIENTE')],
    );
    expect(r).toEqual([]);
  });

  it('baixa desfeita e a linha lançada como receita nova (conta nasce casada, sem registro novo): não volta', () => {
    const r = comContaBaixada(
      [recebimento('q1', 't1')],
      [{ id: 'receita-nova', bank_transaction_id: 't1', tipo: 'receivable' }],
      [baixaSozinha('t1', 'receber-1'), registro('t1', 'desconciliou', 'receber-1')],
    );
    expect(r).toEqual([]);
  });

  it('um registro só, mas que não é o da baixa sozinha (ação, detalhe ou conta diferente): não vale', () => {
    const casadas = [{ id: 'receber-1', bank_transaction_id: 't1', tipo: 'receivable' as const }];
    const tentativa = (r: RegistroDaLinha) => comContaBaixada([recebimento('q1', 't1')], casadas, [r]);
    expect(tentativa(registro('t1', 'conciliou', 'receber-1', 'NF-e 2/25 ↔ CLIENTE'))).toEqual([]);
    expect(tentativa(registro('t1', 'conciliou', 'receber-1', null))).toEqual([]);
    expect(tentativa(registro('t1', 'desconciliou', 'receber-1', 'Baixa automática pelo boleto · desfeita'))).toEqual([]);
    expect(tentativa(baixaSozinha('t1', 'outra-conta'))).toEqual([]);
    expect(tentativa({ ...baixaSozinha('t1', 'receber-1'), receivable_id: null })).toEqual([]);
    // O registro certo, para o controle: com ele a marca vale.
    expect(tentativa(baixaSozinha('t1', 'receber-1')).map((l) => l.conta_baixada_id)).toEqual(['receber-1']);
  });

  it('sem registro nenhum, ou com o registro de outra linha, a marca de receber não vale', () => {
    const casadas = [{ id: 'receber-1', bank_transaction_id: 't1', tipo: 'receivable' as const }];
    expect(comContaBaixada([recebimento('q1', 't1')], casadas)).toEqual([]);
    expect(comContaBaixada([recebimento('q1', 't1')], casadas, [baixaSozinha('t-outra', 'receber-1')])).toEqual([]);
  });

  it('a conta do registro é a que vale, mesmo com a linha casada também em contas a pagar', () => {
    const r = comContaBaixada(
      [recebimento('q1', 't1')],
      [{ id: 'receber-1', bank_transaction_id: 't1', tipo: 'receivable' }, { id: 'pagar-1', bank_transaction_id: 't1', tipo: 'payable' }],
      [baixaSozinha('t1', 'receber-1')],
    );
    expect(r.map((l) => [l.conta_baixada_id, l.conta_baixada_tipo])).toEqual([['receber-1', 'receivable']]);
  });

  // A linha de saída pode ter registro ANTIGO (cancelou, desfez) e depois uma baixa pelo boleto legítima: a trava de
  // pagar no banco é outra. Aqui a marca de conta a pagar nem olha o registro.
  it('a marca de conta a PAGAR não muda: continua valendo pela conta casada, com qualquer registro na linha', () => {
    const marcas = [linha('q1', 'boleto', 't-debito'), { ...linha('q2', 'boleto', 't-debito-2'), kind: 'create_payable' }];
    const casadas = [
      { id: 'pagar-1', bank_transaction_id: 't-debito', tipo: 'payable' as const },
      { id: 'pagar-2', bank_transaction_id: 't-debito-2', tipo: 'payable' as const },
    ];
    const esperado = [['q1', 'pagar-1', 'payable'], ['q2', 'pagar-2', 'payable']];
    const ver = (r: LancadoSozinho[]) => r.map((l) => [l.id, l.conta_baixada_id, l.conta_baixada_tipo]);
    expect(ver(comContaBaixada(marcas, casadas))).toEqual(esperado);
    expect(ver(comContaBaixada(marcas, casadas, [
      registro('t-debito', 'cancelou_lancamento', null, 'lançamento antigo cancelado'),
      registro('t-debito', 'conciliou', null, 'Baixa automática pelo boleto · Compra'),
      registro('t-debito-2', 'desfez_aprovacao', null), registro('t-debito-2', 'desconciliou', null),
    ]))).toEqual(esperado);
  });
});

describe('registrosDasLinhas', () => {
  it('lê o registro INTEIRO das linhas, sem filtro de ação — a pergunta é "tem um registro só?"', async () => {
    leituras.reconciliation_log = { data: [baixaSozinha('t1', 'receber-1'), registro('t1', 'desconciliou', 'receber-1')], error: null };
    const r = await registrosDasLinhas(['t1', 't2']);
    expect(pedidos).toEqual([
      { tabela: 'reconciliation_log', colunas: 'bank_transaction_id, receivable_id, acao, detalhe', filtro: 'bank_transaction_id', ids: ['t1', 't2'] },
    ]);
    expect(r.map((x) => x.acao)).toEqual(['conciliou', 'desconciliou']);
  });

  // Erro engolido viraria "nenhum registro" e a baixa de verdade sumiria da lista, sem Desfazer.
  it('erro na leitura do registro não é engolido', async () => {
    leituras.reconciliation_log = { data: null, error: new Error('permission denied for table reconciliation_log') };
    await expect(registrosDasLinhas(['t1'])).rejects.toThrow('permission denied for table reconciliation_log');
  });

  // Resposta cortada no teto do PostgREST: a linha desfeita poderia parecer ter só o registro da baixa.
  it('leitura que bate no teto de 1000 linhas é erro, não resposta', async () => {
    leituras.reconciliation_log = { data: Array.from({ length: 1000 }, () => baixaSozinha('t1', 'receber-1')), error: null };
    await expect(registrosDasLinhas(['t1'])).rejects.toThrow(/veio cortado/);
  });
});

describe('useLancadosSozinhos — do começo ao fim', () => {
  const proposta = (id: string, kind: string, tx: string) => ({
    id, title: `Proposta ${id}`, suggested_amount: 10, suggested_category: null, suggested_date: '2026-11-13',
    decided_at: '2026-11-24T09:00:00Z', decision_note: null, automatica: 'boleto', kind,
    created_payable_id: null, created_receivable_id: null, bank_transaction_id: tx, bank_transactions: { bank_connection_id: 'c6' },
  });
  const usar = () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: qc }, children);
    return renderHook(() => useLancadosSozinhos(), { wrapper }).result;
  };

  it('pede o kind da proposta e lê o registro só das linhas de RECEBER; a baixa desfeita e casada à mão fica fora', async () => {
    leituras.finance_review_queue = { data: [
      proposta('q-viva', 'create_receivable', 't-viva'), proposta('q-revivida', 'create_receivable', 't-revivida'),
      proposta('q-pagar', 'create_payable', 't-pagar'),
    ], error: null };
    leituras.receivables = { data: [{ id: 'r-viva', bank_transaction_id: 't-viva' }, { id: 'r-do-dono', bank_transaction_id: 't-revivida' }], error: null };
    leituras.payables = { data: [{ id: 'p-1', bank_transaction_id: 't-pagar' }], error: null };
    leituras.reconciliation_log = { data: [
      baixaSozinha('t-viva', 'r-viva'),
      baixaSozinha('t-revivida', 'r-antiga'), registro('t-revivida', 'desconciliou', 'r-antiga'), registro('t-revivida', 'conciliou', 'r-do-dono', 'à mão'),
    ], error: null };
    const r = usar();
    await waitFor(() => expect(r.current.isSuccess).toBe(true));
    expect(fila.colunas).toMatch(/automatica, kind,/);
    expect(pedidos.find((p) => p.tabela === 'reconciliation_log')?.ids).toEqual(['t-viva', 't-revivida']);
    expect(r.current.data?.map((l) => [l.id, l.conta_baixada_id, l.conta_baixada_tipo])).toEqual([
      ['q-viva', 'r-viva', 'receivable'], ['q-pagar', 'p-1', 'payable'],
    ]);
  });

  it('só conta a pagar baixada pelo boleto: o registro nem é lido', async () => {
    leituras.finance_review_queue = { data: [proposta('q-pagar', 'create_payable', 't-pagar')], error: null };
    leituras.payables = { data: [{ id: 'p-1', bank_transaction_id: 't-pagar' }], error: null };
    const r = usar();
    await waitFor(() => expect(r.current.isSuccess).toBe(true));
    expect(pedidos.map((p) => p.tabela)).toEqual(['payables', 'receivables']);
    expect(r.current.data?.map((l) => [l.id, l.conta_baixada_id])).toEqual([['q-pagar', 'p-1']]);
  });

  it('registro que não deu para ler vira ERRO da consulta — não lista vazia nem recebimento "desfeito"', async () => {
    leituras.finance_review_queue = { data: [proposta('q-viva', 'create_receivable', 't-viva')], error: null };
    leituras.receivables = { data: [{ id: 'r-viva', bank_transaction_id: 't-viva' }], error: null };
    leituras.reconciliation_log = { data: null, error: new Error('falhou a leitura do registro') };
    const r = usar();
    await waitFor(() => expect(r.current.isError).toBe(true));
    expect(r.current.data).toBeUndefined();
    expect((r.current.error as Error).message).toBe('falhou a leitura do registro');
  });
});

describe('contasCasadasComAsLinhas', () => {
  it('procura a conta casada em contas a pagar E em contas a receber, e diz de que lado cada uma veio', async () => {
    leituras.payables = { data: [{ id: 'pagar-1', bank_transaction_id: 't-debito' }], error: null };
    leituras.receivables = { data: [{ id: 'receber-1', bank_transaction_id: 't-credito' }], error: null };
    const casadas = await contasCasadasComAsLinhas(['t-debito', 't-credito']);
    expect(pedidos.map((p) => [p.tabela, p.filtro, p.ids])).toEqual([
      ['payables', 'bank_transaction_id', ['t-debito', 't-credito']],
      ['receivables', 'bank_transaction_id', ['t-debito', 't-credito']],
    ]);
    expect([...casadas].sort((a, b) => a.id.localeCompare(b.id))).toEqual([
      { id: 'pagar-1', bank_transaction_id: 't-debito', tipo: 'payable' },
      { id: 'receber-1', bank_transaction_id: 't-credito', tipo: 'receivable' },
    ]);
    // Do começo ao fim: cada item da lista sai com a conta e o lado certos.
    const r = comContaBaixada([recebimento('q1', 't-credito'), linha('q2', 'boleto', 't-debito')], casadas, [baixaSozinha('t-credito', 'receber-1')]);
    expect(r.map((l) => [l.id, l.conta_baixada_id, l.conta_baixada_tipo])).toEqual([
      ['q1', 'receber-1', 'receivable'], ['q2', 'pagar-1', 'payable'],
    ]);
  });

  it('linha casada dos dois lados: vale a conta a pagar, como era antes de existir o recebimento', async () => {
    leituras.payables = { data: [{ id: 'pagar-1', bank_transaction_id: 't1' }], error: null };
    leituras.receivables = { data: [{ id: 'receber-1', bank_transaction_id: 't1' }], error: null };
    const r = comContaBaixada([linha('q1', 'boleto', 't1')], await contasCasadasComAsLinhas(['t1']));
    expect(r.map((l) => [l.conta_baixada_id, l.conta_baixada_tipo])).toEqual([['pagar-1', 'payable']]);
  });

  // Leitura que falha calada faria a baixa parecer desfeita (o item some da lista, sem Desfazer).
  it('erro na leitura de contas a receber não é engolido', async () => {
    leituras.payables = { data: [{ id: 'pagar-1', bank_transaction_id: 't1' }], error: null };
    leituras.receivables = { data: null, error: new Error('permission denied for table receivables') };
    await expect(contasCasadasComAsLinhas(['t1'])).rejects.toThrow('permission denied for table receivables');
  });

  it('erro na leitura de contas a pagar não é engolido', async () => {
    leituras.payables = { data: null, error: new Error('falhou a leitura de payables') };
    leituras.receivables = { data: [], error: null };
    await expect(contasCasadasComAsLinhas(['t1'])).rejects.toThrow('falhou a leitura de payables');
  });
});

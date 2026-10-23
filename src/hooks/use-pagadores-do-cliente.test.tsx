// Pagadores do cliente (leva 8, 22/10/2026): as consultas só saem para admin e financeiro, erro de leitura não vira
// "ninguém paga por este cliente", e guardar/decidir invalidam as listas e o "Pago por".
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const estado = vi.hoisted(() => ({
  cargo: 'admin' as string,
  tabelas: [] as string[],
  filtros: [] as Array<[string, unknown]>,
  rpcs: [] as Array<{ nome: string; args: unknown }>,
  resposta: { data: [] as unknown, error: null as unknown },
  respostaRpc: { data: null as unknown, error: null as unknown },
  toasts: [] as Array<[string, string]>,
}));

vi.mock('@/hooks/use-auth', () => ({
  useOptionalAuth: () => ({ user: { role: estado.cargo } }),
}));
vi.mock('sonner', () => ({
  toast: {
    success: (m: string) => estado.toasts.push(['success', m]),
    warning: (m: string) => estado.toasts.push(['warning', m]),
    error: (m: string) => estado.toasts.push(['error', m]),
  },
}));
vi.mock('@/integrations/supabase/client', () => {
  const cadeia: Record<string, unknown> = {};
  for (const m of ['select', 'order', 'limit']) cadeia[m] = () => cadeia;
  cadeia.eq = (c: string, v: unknown) => { estado.filtros.push([c, v]); return cadeia; };
  cadeia.then = (ok: (v: unknown) => unknown, nok: (e: unknown) => unknown) => Promise.resolve(estado.resposta).then(ok, nok);
  return {
    supabase: {
      from: (t: string) => { estado.tabelas.push(t); return cadeia; },
      rpc: (nome: string, args: unknown) => { estado.rpcs.push({ nome, args }); return Promise.resolve(estado.respostaRpc); },
    },
  };
});

import {
  usePagadoresDoCliente, usePagadoresParaConferir, usePagamentosComPagador, useGuardarPagadores, useDecidirPagador,
  useRecusarPagadores, podeVerPagadores, documentoMascarado, mensagemDeGuardar, pedeRevisarFila,
} from './use-pagadores-do-cliente';

let qc: QueryClient;
function wrapper({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

beforeEach(() => {
  qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  Object.assign(estado, {
    cargo: 'admin', tabelas: [], filtros: [], rpcs: [], toasts: [],
    resposta: { data: [], error: null }, respostaRpc: { data: null, error: null },
  });
});

describe('usePagadoresDoCliente', () => {
  it('admin: lê a tabela do cliente, com o nome de quem confirmou, confirmados primeiro', async () => {
    estado.resposta = {
      data: [
        { id: 'p2', client_id: 'c1', documento: '04754513000149', nome: 'ZETA LTDA', relacao: 'marina', situacao: 'proposto', proposto: { full_name: 'Fin' }, confirmado: null },
        { id: 'p1', client_id: 'c1', documento: '12345678901', nome: 'BETA', relacao: 'conjuge', situacao: 'confirmado', proposto: null, confirmado: { full_name: 'Dono' } },
      ],
      error: null,
    };
    const { result } = renderHook(() => usePagadoresDoCliente('c1'), { wrapper });
    await waitFor(() => expect(result.current.data).toBeDefined());
    expect(estado.tabelas).toEqual(['pagadores_do_cliente']);
    expect(estado.filtros).toContainEqual(['client_id', 'c1']);
    expect(result.current.data!.map((p) => [p.id, p.confirmado_por_nome, p.proposto_por_nome])).toEqual([
      ['p1', 'Dono', null], ['p2', null, 'Fin'],
    ]);
    expect(result.current.data![0]).not.toHaveProperty('confirmado');
  });

  it('erro de leitura é erro, não lista vazia', async () => {
    estado.resposta = { data: null, error: { message: 'permission denied' } };
    const { result } = renderHook(() => usePagadoresDoCliente('c1'), { wrapper });
    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(result.current.data).toBeUndefined();
  });

  it.each(['technician', 'seller', 'external_seller'])('%s: a consulta nem sai', async (cargo) => {
    estado.cargo = cargo;
    const { result } = renderHook(() => usePagadoresDoCliente('c1'), { wrapper });
    await new Promise((r) => setTimeout(r, 20));
    expect(result.current.fetchStatus).toBe('idle');
    expect(estado.tabelas).toEqual([]);
  });
});

describe('usePagadoresParaConferir e usePagamentosComPagador', () => {
  it('a lista vem da função do banco, com números de verdade e aviso nulo', async () => {
    estado.respostaRpc = { data: [{ client_id: 'c1', pagador_documento: '1', vezes: '2', total: '150.50', aviso: null }], error: null };
    const { result } = renderHook(() => usePagadoresParaConferir(), { wrapper });
    await waitFor(() => expect(result.current.data).toBeDefined());
    expect(estado.rpcs).toEqual([{ nome: 'pagadores_para_conferir', args: undefined }]);
    expect(result.current.data![0]).toMatchObject({ vezes: 2, total: 150.5, aviso: null });
    // sem proposto, os campos do proposto vêm nulos (nunca undefined)
    expect(result.current.data![0]).toMatchObject({
      pagador_id: null, situacao: null, relacao_proposta: null, proposto_por_nome: null, proposto_em: null,
    });
  });

  it('o proposto pelo financeiro continua na lista, com quem e quando; a ligação duvidosa vem marcada', async () => {
    estado.respostaRpc = {
      data: [
        { client_id: 'c1', pagador_documento: '1', vezes: 1, total: 100, aviso: null,
          pagador_id: 'p9', situacao: 'proposto', relacao_proposta: 'parente', proposto_por_nome: 'Fin', proposto_em: '2026-10-23T12:00:00Z' },
        { client_id: 'c2', pagador_documento: '2', vezes: 1, total: 3000, aviso: 'ligacao_duvidosa',
          pagador_id: null, situacao: null, relacao_proposta: null, proposto_por_nome: null, proposto_em: null },
      ],
      error: null,
    };
    const { result } = renderHook(() => usePagadoresParaConferir(), { wrapper });
    await waitFor(() => expect(result.current.data).toBeDefined());
    expect(result.current.data![0]).toMatchObject({
      pagador_id: 'p9', situacao: 'proposto', relacao_proposta: 'parente', proposto_por_nome: 'Fin', proposto_em: '2026-10-23T12:00:00Z',
    });
    expect(result.current.data![1]).toMatchObject({ aviso: 'ligacao_duvidosa', situacao: null, pagador_id: null });
  });

  it('a lista com erro de leitura é erro, não "nada para conferir"', async () => {
    estado.respostaRpc = { data: null, error: { message: 'falhou' } };
    const { result } = renderHook(() => usePagadoresParaConferir(), { wrapper });
    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(result.current.data).toBeUndefined();
  });

  it('o "Pago por" lê a view pela conta a receber (sem embed payments ↔ bank_transactions)', async () => {
    estado.cargo = 'financial';
    estado.resposta = { data: [{ payment_id: 'pg1', situacao: 'terceiro', relacao: 'conjuge' }], error: null };
    const { result } = renderHook(() => usePagamentosComPagador('r1'), { wrapper });
    await waitFor(() => expect(result.current.data).toBeDefined());
    expect(estado.tabelas).toEqual(['pagamentos_com_pagador']);
    expect(estado.filtros).toContainEqual(['receivable_id', 'r1']);
  });

  it('o "Pago por" com erro de leitura é erro', async () => {
    estado.resposta = { data: null, error: { message: 'falhou' } };
    const { result } = renderHook(() => usePagamentosComPagador('r1'), { wrapper });
    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});

describe('useGuardarPagadores e useDecidirPagador', () => {
  it('guardar manda só cliente, linha e relação; invalida listas, "Pago por", regras e trilha; parcial avisa', async () => {
    const espiao = vi.spyOn(qc, 'invalidateQueries');
    estado.respostaRpc = {
      data: {
        ok: true, gravados: [{ id: 'p1' }], recusados: [{ indice: 2, client_id: 'c2', bank_transaction_id: 't2', motivo: 'É o CNPJ da própria HBR.' }],
        regras_consolidadas: [], message: '1 pagador guardado e confirmado. 1 não foi guardado: É o CNPJ da própria HBR.',
      },
      error: null,
    };
    const { result } = renderHook(() => useGuardarPagadores(), { wrapper });
    await act(async () => {
      await result.current.mutateAsync([
        { client_id: 'c1', bank_transaction_id: 't1', relacao: 'conjuge' },
        { client_id: 'c2', bank_transaction_id: 't2', relacao: 'outro' },
      ]);
    });
    expect(estado.rpcs[0]).toEqual({ nome: 'guardar_pagadores_do_cliente', args: { p_itens: [
      { client_id: 'c1', bank_transaction_id: 't1', relacao: 'conjuge' },
      { client_id: 'c2', bank_transaction_id: 't2', relacao: 'outro' },
    ] } });
    const chaves = espiao.mock.calls.map((c) => (c[0] as { queryKey: unknown[] }).queryKey);
    expect(chaves).toEqual(expect.arrayContaining([
      ['pagadores-do-cliente'], ['payments', 'com-pagador'], ['finance-rules'], ['trilha-conciliacao'],
    ]));
    expect(estado.toasts).toEqual([['warning', '1 pagador guardado e confirmado. 1 não foi guardado: É o CNPJ da própria HBR.']]);
  });

  it('nada guardado é erro na tela; erro do banco sai sem o código', async () => {
    estado.respostaRpc = { data: { ok: false, gravados: [], recusados: [{ indice: 1, motivo: 'x' }], regras_consolidadas: [], message: 'Nenhum pagador guardado. 1 não foi guardado: x' }, error: null };
    const { result } = renderHook(() => useGuardarPagadores(), { wrapper });
    await act(async () => { await result.current.mutateAsync([{ client_id: 'c1', bank_transaction_id: 't1', relacao: 'conjuge' }]); });
    expect(estado.toasts.at(-1)?.[0]).toBe('error');

    estado.respostaRpc = { data: null, error: { message: '42501: Só administrador ou financeiro pode alterar lançamentos.' } };
    await act(async () => {
      await result.current.mutateAsync([{ client_id: 'c1', bank_transaction_id: 't1', relacao: 'conjuge' }]).catch(() => {});
    });
    expect(estado.toasts.at(-1)).toEqual(['error', 'Só administrador ou financeiro pode alterar lançamentos.']);
  });

  it('decidir manda id, decisão e motivo', async () => {
    estado.respostaRpc = { data: { ok: true, id: 'p1', situacao: 'pausado', regras_consolidadas: [], message: 'BETA pausado como pagador de X.' }, error: null };
    const { result } = renderHook(() => useDecidirPagador(), { wrapper });
    await act(async () => { await result.current.mutateAsync({ id: 'p1', decisao: 'pausar', motivo: 'em dúvida' }); });
    expect(estado.rpcs[0]).toEqual({ nome: 'decidir_pagador_do_cliente', args: { p_id: 'p1', p_decisao: 'pausar', p_motivo: 'em dúvida' } });
    // sem relação, o parâmetro nem vai (o banco mantém a relação proposta)
    expect((estado.rpcs[0].args as Record<string, unknown>).p_relacao).toBeUndefined();
    expect(estado.toasts).toEqual([['success', 'BETA pausado como pagador de X.']]);
  });

  it('o administrador confirma trocando a relação proposta (p_relacao)', async () => {
    estado.respostaRpc = {
      data: { ok: true, id: 'p1', situacao: 'confirmado', relacao: 'empresa_do_cliente', regras_consolidadas: [],
        message: 'EQUIT confirmado como pagador de X (relação trocada para empresa do cliente).' },
      error: null,
    };
    const { result } = renderHook(() => useDecidirPagador(), { wrapper });
    let r: Awaited<ReturnType<typeof result.current.mutateAsync>> | undefined;
    await act(async () => { r = await result.current.mutateAsync({ id: 'p1', decisao: 'confirmar', relacao: 'empresa_do_cliente' }); });
    expect(estado.rpcs[0]).toEqual({ nome: 'decidir_pagador_do_cliente', args: {
      p_id: 'p1', p_decisao: 'confirmar', p_motivo: undefined, p_relacao: 'empresa_do_cliente',
    } });
    expect(r!.relacao).toBe('empresa_do_cliente');
    expect(estado.toasts).toEqual([['success', 'EQUIT confirmado como pagador de X (relação trocada para empresa do cliente).']]);
  });

  it('o financeiro barrado ao recusar um confirmado vê o motivo do banco, sem o código', async () => {
    estado.cargo = 'financial';
    estado.respostaRpc = { data: null, error: { message: '42501: EQUIT é pagador confirmado de X: só o administrador recusa ou pausa (é o SIM do dono).' } };
    const { result } = renderHook(() => useDecidirPagador(), { wrapper });
    await act(async () => { await result.current.mutateAsync({ id: 'p1', decisao: 'recusar' }).catch(() => {}); });
    expect(estado.toasts.at(-1)).toEqual(['error', 'EQUIT é pagador confirmado de X: só o administrador recusa ou pausa (é o SIM do dono).']);
  });

  it('regra antiga de outro cliente: guardar e confirmar dão certo, mas o aviso sai como atenção', async () => {
    const aviso = 'Atenção: uma regra antiga diz que este CPF/CNPJ é do cliente Y; as entradas de EQUIT passam a perguntar de quem é (escolha o cliente em cada uma).';
    estado.respostaRpc = {
      data: {
        ok: true, recusados: [], regras_consolidadas: [], avisos: [aviso], message: `1 pagador guardado e confirmado. ${aviso}`,
        gravados: [{ id: 'p1', situacao: 'confirmado', regra_de_outro_cliente: { finance_rule_id: 'r1', client_id: 'cy', cliente: 'Y' } }],
      },
      error: null,
    };
    const guardar = renderHook(() => useGuardarPagadores(), { wrapper });
    await act(async () => { await guardar.result.current.mutateAsync([{ client_id: 'c1', bank_transaction_id: 't1', relacao: 'empresa_do_cliente' }]); });
    expect(estado.toasts.at(-1)).toEqual(['warning', `1 pagador guardado e confirmado. ${aviso}`]);

    estado.respostaRpc = {
      data: { ok: true, id: 'p1', situacao: 'confirmado', regras_consolidadas: [], message: `EQUIT confirmado como pagador de X. ${aviso}`,
        regra_de_outro_cliente: { finance_rule_id: 'r1', client_id: 'cy', cliente: 'Y' } },
      error: null,
    };
    const decidir = renderHook(() => useDecidirPagador(), { wrapper });
    await act(async () => { await decidir.result.current.mutateAsync({ id: 'p1', decisao: 'confirmar' }); });
    expect(estado.toasts.at(-1)?.[0]).toBe('warning');
  });
});

describe('useRecusarPagadores ("não é pagador habitual")', () => {
  it('manda só cliente e linha (o documento sai da linha do banco) e o motivo; invalida as listas', async () => {
    const espiao = vi.spyOn(qc, 'invalidateQueries');
    estado.cargo = 'financial';
    estado.respostaRpc = {
      data: {
        ok: true, recusados: [], regras_consolidadas: [], avisos: [],
        gravados: [{ id: 'p1', client_id: 'c1', cliente: 'X', nome: 'COLOMBO', relacao: 'outro', situacao: 'recusado', ja_existia: false, situacao_anterior: null, regras_consolidadas: [] }],
        message: '1 pagador recusado: não volta a ser sugerido nem à lista para conferir.',
      },
      error: null,
    };
    const { result } = renderHook(() => useRecusarPagadores(), { wrapper });
    let r: Awaited<ReturnType<typeof result.current.mutateAsync>> | undefined;
    await act(async () => {
      r = await result.current.mutateAsync({ itens: [{ client_id: 'c1', bank_transaction_id: 't1' }], motivo: 'ligação errada' });
    });
    expect(estado.rpcs).toEqual([{ nome: 'recusar_pagadores_do_cliente', args: {
      p_itens: [{ client_id: 'c1', bank_transaction_id: 't1' }], p_motivo: 'ligação errada',
    } }]);
    const chaves = espiao.mock.calls.map((c) => (c[0] as { queryKey: unknown[] }).queryKey);
    expect(chaves).toEqual(expect.arrayContaining([['pagadores-do-cliente'], ['payments', 'com-pagador']]));
    expect(estado.toasts).toEqual([['success', '1 pagador recusado: não volta a ser sugerido nem à lista para conferir.']]);
    // um par novo recusado MUDA o que a fila sugere: é o veto do motor (o histórico deixa de sugerir o cliente)
    expect(pedeRevisarFila(r!)).toBe(true);
  });

  it('sem motivo, o banco usa o dele; nada recusado é erro; o financeiro barrado no confirmado vê o motivo', async () => {
    estado.respostaRpc = {
      data: {
        ok: false, gravados: [], regras_consolidadas: [], avisos: [],
        recusados: [{ indice: 1, client_id: 'c1', bank_transaction_id: 't1', motivo: 'EQUIT é pagador confirmado de X; só o administrador recusa.' }],
        message: 'Nenhum pagador recusado. 1 não foi recusado: EQUIT é pagador confirmado de X; só o administrador recusa.',
      },
      error: null,
    };
    const { result } = renderHook(() => useRecusarPagadores(), { wrapper });
    await act(async () => { await result.current.mutateAsync({ itens: [{ client_id: 'c1', bank_transaction_id: 't1' }] }); });
    expect(estado.rpcs[0]).toEqual({ nome: 'recusar_pagadores_do_cliente', args: { p_itens: [{ client_id: 'c1', bank_transaction_id: 't1' }], p_motivo: undefined } });
    expect(estado.toasts.at(-1)).toEqual(['error', 'Nenhum pagador recusado. 1 não foi recusado: EQUIT é pagador confirmado de X; só o administrador recusa.']);

    estado.respostaRpc = { data: null, error: { message: '42501: Só administrador ou financeiro recusa quem paga por um cliente.' } };
    await act(async () => {
      await result.current.mutateAsync({ itens: [{ client_id: 'c1', bank_transaction_id: 't1' }] }).catch(() => {});
    });
    expect(estado.toasts.at(-1)).toEqual(['error', 'Só administrador ou financeiro recusa quem paga por um cliente.']);
  });
});

describe('auxiliares', () => {
  it('só admin e financeiro veem; CPF mascarado; motivos curtos juntos', () => {
    expect(['admin', 'financial'].every(podeVerPagadores)).toBe(true);
    expect(['technician', 'seller', null, undefined].some(podeVerPagadores)).toBe(false);
    expect(documentoMascarado('12345678901')).toBe('***.456.789-**');
    expect(mensagemDeGuardar({ ok: true, gravados: [], regras_consolidadas: [], message: 'M.',
      recusados: [{ indice: 1, client_id: null, bank_transaction_id: null, motivo: 'a' }, { indice: 2, client_id: null, bank_transaction_id: null, motivo: 'b' }] }))
      .toBe('M. a · b');
  });

  it('revisar a fila quando um pagador passou a valer, deixou de valer ou virou veto', () => {
    const base = { ok: true, recusados: [], regras_consolidadas: [], message: '' };
    const g = (situacao: 'proposto' | 'confirmado') => ({ ...base, gravados: [{ id: 'p', client_id: 'c', cliente: 'C', nome: 'N', relacao: 'conjuge' as const, situacao, ja_existia: false, regras_consolidadas: [] }] });
    expect(pedeRevisarFila(g('confirmado'))).toBe(true);
    expect(pedeRevisarFila(g('proposto'))).toBe(false);
    expect(pedeRevisarFila({ ok: true, id: 'p', situacao: 'pausado', regras_consolidadas: [], message: '' })).toBe(true);
    // recusar: o recusado é o VETO do motor (revisão de 23/10/2026) — muda a fila sempre que o par passa a recusado
    const recusado = (situacao_anterior: 'confirmado' | 'proposto' | 'recusado' | null) => ({ ...base, gravados: [{
      id: 'p', client_id: 'c', cliente: 'C', nome: 'N', relacao: 'outro' as const, situacao: 'recusado' as const,
      ja_existia: situacao_anterior !== null, situacao_anterior, regras_consolidadas: [] }] });
    expect(pedeRevisarFila(recusado('confirmado'))).toBe(true);
    expect(pedeRevisarFila(recusado('proposto'))).toBe(true);
    expect(pedeRevisarFila(recusado(null))).toBe(true);
    // repetir a recusa não muda nada
    expect(pedeRevisarFila(recusado('recusado'))).toBe(false);
  });
});

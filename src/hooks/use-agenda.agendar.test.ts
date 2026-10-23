// Agendar OS pela Agenda (Agenda de Produção, Fase 0 — D1, D2, D4 e D5 na tela).
//
// Até 23/10/2026: a tela só passava a OS a 'scheduled' se o status fosse 'pending' — que não
// existe, então nunca (D1); o técnico era obrigatório e a lista vinha vazia (D2); a leitura da
// semana só via OS que COMEÇAVAM no período (D4); e o aviso de sobrecarga somava a janela
// corrida inteira, "72h ocupadas" num dia (D5). Aqui o supabase é falso e grava o que foi pedido.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => {
  const estado = {
    status: 'open' as string,
    conflitos: [] as any[],
    usuarios: [] as any[],
    chamadas: [] as { tabela: string; ops: any[][] }[],
  };
  const builder = (tabela: string): any => {
    const reg = { tabela, ops: [] as any[][] };
    estado.chamadas.push(reg);
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'or', 'order', 'limit', 'is',
      'update', 'upsert', 'insert', 'delete']) {
      o[k] = (...args: any[]) => { reg.ops.push([k, ...args]); return o; };
    }
    o.single = async () => ({ data: { status: estado.status }, error: null });
    o.then = (ok: any, erro: any) =>
      Promise.resolve({ data: tabela === 'app_users' ? estado.usuarios : [], error: null }).then(ok, erro);
    return o;
  };
  const rpc = vi.fn(async (_nome: string, _args: any) => ({ data: estado.conflitos, error: null }));
  return { estado, builder, rpc };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: (t: string) => h.builder(t), rpc: h.rpc },
}));

import {
  mensagemAoAgendar,
  overloadWarning,
  responsaveisDaOs,
  useAgendaOrders,
  useQuickSchedule,
  useResponsaveisDaOs,
} from './use-agenda';
import { filtroQueCruza } from '../../supabase/functions/_shared/agenda-dia';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return createElement(QueryClientProvider, { client: qc }, children);
}

const updates = () => h.estado.chamadas
  .filter((c) => c.tabela === 'service_orders')
  .flatMap((c) => c.ops.filter((op) => op[0] === 'update').map((op) => op[1]));
const upserts = () => h.estado.chamadas
  .filter((c) => c.tabela === 'service_order_technicians')
  .flatMap((c) => c.ops.filter((op) => op[0] === 'upsert'));
const chamouConflito = () => h.rpc.mock.calls.some((c) => c[0] === 'get_agenda_conflicts');

async function agendar(status: string, tecnico: string | null = 'tec-1') {
  h.estado.status = status;
  const { result } = renderHook(() => useQuickSchedule(), { wrapper });
  return result.current.mutateAsync({
    service_order_id: 'os-1',
    technician_user_id: tecnico,
    scheduled_start_at: '2026-10-27T09:00:00-03:00',
    scheduled_end_at: '2026-10-27T11:00:00-03:00',
  });
}

beforeEach(() => {
  h.estado.chamadas.length = 0;
  h.estado.conflitos = [];
  h.estado.usuarios = [];
  h.rpc.mockClear();
});

describe('useQuickSchedule — o status vem de statusAoAgendar', () => {
  it("OS 'open' (o caminho normal: 13 de 19 conversões) vira 'scheduled'", async () => {
    const r = await agendar('open');
    expect(updates()).toEqual([{
      scheduled_start_at: '2026-10-27T09:00:00-03:00',
      scheduled_end_at: '2026-10-27T11:00:00-03:00',
      status: 'scheduled',
    }]);
    expect(r.mensagem).toBe('OS agendada');
    expect(r.status).toBe('scheduled');
  });

  it("OS 'approved' vira 'scheduled'", async () => {
    await agendar('approved');
    expect(updates()[0].status).toBe('scheduled');
  });

  it("'awaiting_parts' ganha a data e NÃO regride: o update vai sem status", async () => {
    const r = await agendar('awaiting_parts');
    expect(updates()).toHaveLength(1);
    expect('status' in updates()[0]).toBe(false);
    expect(updates()[0].scheduled_start_at).toBe('2026-10-27T09:00:00-03:00');
    expect(r.mensagem).toBe('Data gravada; a OS continua aguardando peças');
    expect(r.status).toBe('awaiting_parts');
  });

  it("'in_progress' também não regride", async () => {
    await agendar('in_progress');
    expect('status' in updates()[0]).toBe(false);
  });

  it("'draft' (orçamento) ganha data sem virar OS", async () => {
    const r = await agendar('draft');
    expect('status' in updates()[0]).toBe(false);
    expect(r.mensagem).toMatch(/continua como orçamento/);
  });

  it("'completed' lança e não grava nada", async () => {
    await expect(agendar('completed')).rejects.toThrow(/OS encerrada não se agenda/);
    expect(updates()).toHaveLength(0);
    expect(upserts()).toHaveLength(0);
    expect(chamouConflito()).toBe(false);
  });

  it('cancelada e faturada também lançam', async () => {
    await expect(agendar('cancelled')).rejects.toThrow(/OS encerrada não se agenda/);
    await expect(agendar('invoiced')).rejects.toThrow(/OS encerrada não se agenda/);
    expect(updates()).toHaveLength(0);
  });
});

describe('useQuickSchedule — técnico opcional (D2)', () => {
  it('sem técnico: não checa conflito, não faz upsert, e mesmo assim agenda', async () => {
    const r = await agendar('open', null);
    expect(chamouConflito()).toBe(false);
    expect(upserts()).toHaveLength(0);
    expect(updates()[0].status).toBe('scheduled');
    expect(r.warning).toBeNull();
  });

  it('com técnico: checa conflito e vincula o técnico', async () => {
    await agendar('open', 'tec-1');
    expect(chamouConflito()).toBe(true);
    expect(upserts()).toHaveLength(1);
    expect(upserts()[0][1]).toEqual({ service_order_id: 'os-1', user_id: 'tec-1', role_in_order: 'technician' });
  });

  it('com conflito: recusa antes de gravar', async () => {
    h.estado.conflitos = [{ source: 'service_order', label: 'OS-00060',
      starts_at: '2026-10-27T08:00:00-03:00', ends_at: '2026-10-27T12:00:00-03:00' }];
    await expect(agendar('open', 'tec-1')).rejects.toThrow(/Conflito de agenda/);
    expect(updates()).toHaveLength(0);
  });
});

describe('overloadWarning — carga do dia com teto na jornada (D5)', () => {
  it('uma OS de 72 h no dia não avisa (antes: "o dia fica com 72h ocupadas")', async () => {
    h.estado.conflitos = [];
    const aviso = await overloadWarning('tec-1', '2026-10-06T08:00:00-03:00', '2026-10-09T08:00:00-03:00');
    expect(aviso).toBeNull();
  });

  it('uma OS de 72 h já no dia + 2 h novas passa da jornada: avisa com 10h, não 74h', async () => {
    h.estado.conflitos = [{ source: 'service_order', label: 'OS-00104',
      starts_at: '2026-10-05T08:00:00-03:00', ends_at: '2026-10-08T08:00:00-03:00' }];
    const aviso = await overloadWarning('tec-1', '2026-10-06T09:00:00-03:00', '2026-10-06T11:00:00-03:00');
    expect(aviso).toBe('Atenção: com este agendamento o dia fica com 10h ocupadas.');
  });

  it('pergunta o dia de Brasília: 22 h do dia 06 consulta 06/10, não 07/10', async () => {
    await overloadWarning('tec-1', '2026-10-06T22:00:00-03:00', '2026-10-06T23:00:00-03:00');
    const args = h.rpc.mock.calls[0][1];
    expect(args.p_start).toBe('2026-10-06T03:00:00.000Z');
    expect(args.p_end).toBe('2026-10-07T03:00:00.000Z');
  });
});

describe('useAgendaOrders — interseção com o período (D4)', () => {
  it('monta .lt(scheduled_start_at, até) + .or(filtroQueCruza(de)), sem o gte/lte do início', async () => {
    const de = '2026-10-05T03:00:00.000Z';
    const ate = '2026-10-12T03:00:00.000Z';
    const { result } = renderHook(() => useAgendaOrders(de, ate), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const ops = h.estado.chamadas.find((c) => c.tabela === 'service_orders')!.ops;
    expect(ops).toContainEqual(['lt', 'scheduled_start_at', ate]);
    expect(ops).toContainEqual(['or', filtroQueCruza(de)]);
    expect(ops.some((op) => op[0] === 'gte' || op[0] === 'lte')).toBe(false);
  });
});

describe('responsáveis da OS (D2)', () => {
  const usuarios = [
    { id: 'g', full_name: 'Gustavo', role: 'admin', active: true, payees: [] },
    // Login inativo, mas segue na equipe como favorecido ativo (recebe diária).
    { id: 'r', full_name: 'Roberto', role: 'technician', active: false, payees: [{ id: 'p-r', active: true }] },
    { id: 'f', full_name: 'Felipe', role: 'technician', active: false, payees: [] },
    { id: 'x', full_name: 'Fulano de Teste', role: 'admin', active: false, payees: null },
    { id: 'd', full_name: 'Usuário Demo', role: 'financial', active: true, payees: [] },
    { id: 'm', full_name: 'Ex-técnico', role: 'technician', active: false, payees: [{ id: 'p-m', active: false }] },
  ];

  it('admin/técnico ativo ou com favorecido ativo; nem financeiro, nem inativo sem favorecido', () => {
    expect(responsaveisDaOs(usuarios)).toEqual([
      { id: 'g', full_name: 'Gustavo' },
      { id: 'r', full_name: 'Roberto' },
    ]);
  });

  it('o hook usa o embed com a dica do FK de payees e só os cargos admin/técnico', async () => {
    h.estado.usuarios = usuarios;
    const { result } = renderHook(() => useResponsaveisDaOs(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.map((u) => u.id)).toEqual(['g', 'r']);
    const ops = h.estado.chamadas.find((c) => c.tabela === 'app_users')!.ops;
    expect(ops.find((op) => op[0] === 'select')![1]).toContain('payees!payees_app_user_id_fkey(id, active)');
    expect(ops).toContainEqual(['in', 'role', ['admin', 'technician']]);
  });
});

describe('mensagemAoAgendar — o toast diz o status resultante', () => {
  it.each([
    ['open', 'scheduled', 'OS agendada'],
    ['approved', 'scheduled', 'OS agendada'],
    ['scheduled', null, 'Agendamento atualizado'],
    ['awaiting_parts', null, 'Data gravada; a OS continua aguardando peças'],
    ['awaiting_client', null, 'Data gravada; a OS continua aguardando cliente'],
    ['in_progress', null, 'Data gravada; a OS continua em andamento'],
  ] as const)('%s → %s', (anterior, novo, texto) => {
    expect(mensagemAoAgendar(anterior, novo)).toBe(texto);
  });
});

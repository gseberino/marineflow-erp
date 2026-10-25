// Agendar OS pela Agenda (Agenda de Produção, Fase 0 — D1, D2, D4 e D5 na tela; Fase 2, P4 — a porta única).
//
// Até 23/10/2026: a tela só passava a OS a 'scheduled' se o status fosse 'pending' — que não
// existe, então nunca (D1); o técnico era obrigatório e a lista vinha vazia (D2); a leitura da
// semana só via OS que COMEÇAVAM no período (D4); e o aviso de sobrecarga somava a janela
// corrida inteira, "72h ocupadas" num dia (D5).
//
// Desde a Fase 2 (P4, 24/10/2026) a tela não escreve status: fora da agenda automática grava só a data
// (scheduled_*) e o status vai pela porta do banco (os_transicionar_status, via tela_agendar), que decide;
// com a agenda automática ligada, só agenda_marcar_os (via tela), nenhum update direto. Aqui o supabase é
// falso e grava o que foi pedido.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => {
  const estado = {
    status: 'open' as string,
    conflitos: [] as any[],
    usuarios: [] as any[],
    /** os técnicos já vinculados à OS (service_order_technicians) e se a leitura deles falha */
    vinculos: [] as any[],
    erroVinculos: null as { message: string } | null,
    /** agenda_config.modo_proposta */
    modo: 'desligado' as string,
    /** a função agenda_modo_da_proposta ainda não está no banco (o modo vem da tabela, como antes) */
    semFuncaoDoModo: false,
    /** os favorecidos (payees) do login do técnico */
    favorecidos: [] as any[],
    /** a resposta da porta e a de agenda_marcar_os */
    porta: { ok: true, mudou: true, de: 'open', para: 'scheduled', texto: 'x' } as any,
    erroPorta: null as { message: string } | null,
    marcar: { ok: true, texto: 'Mudei: Lenine (OS-00074): qui 29/10, Roberto o dia todo.' } as any,
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
    o.maybeSingle = async () => (tabela === 'agenda_config'
      ? { data: { modo_proposta: estado.modo }, error: null }
      : { data: null, error: null });
    o.then = (ok: any, erro: any) => {
      const leVinculos = tabela === 'service_order_technicians' && reg.ops.some((op) => op[0] === 'select');
      if (leVinculos) return Promise.resolve({ data: estado.erroVinculos ? null : estado.vinculos, error: estado.erroVinculos }).then(ok, erro);
      if (tabela === 'payees') return Promise.resolve({ data: estado.favorecidos, error: null }).then(ok, erro);
      // o UPDATE do status do plano B (statusSemAPorta): devolve a OS quando o filtro .in('status') a pega
      const doIn = reg.ops.find((op) => op[0] === 'in' && op[1] === 'status');
      if (tabela === 'service_orders' && doIn) {
        return Promise.resolve({ data: doIn[2].includes(estado.status) ? [{ id: 'os-1' }] : [], error: null }).then(ok, erro);
      }
      return Promise.resolve({ data: tabela === 'app_users' ? estado.usuarios : [], error: null }).then(ok, erro);
    };
    return o;
  };
  const rpc = vi.fn(async (nome: string, _args: any) => {
    if (nome === 'os_transicionar_status') return { data: estado.erroPorta ? null : estado.porta, error: estado.erroPorta };
    if (nome === 'agenda_marcar_os') return { data: estado.marcar, error: null };
    // revisão da Fase 3 (R3): o modo pela função que todo login lê; sem ela (PGRST202), a tabela de antes
    if (nome === 'agenda_modo_da_proposta') {
      return estado.semFuncaoDoModo ? { data: null, error: { code: 'PGRST202', message: 'sem a função' } } : { data: estado.modo, error: null };
    }
    return { data: estado.conflitos, error: null };
  });
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
const chamadasDa = (nome: string) => h.rpc.mock.calls.filter((c) => c[0] === nome).map((c) => c[1]);

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
  h.estado.vinculos = [];
  h.estado.erroVinculos = null;
  h.estado.modo = 'desligado';
  h.estado.semFuncaoDoModo = false;
  h.estado.favorecidos = [];
  h.estado.porta = { ok: true, mudou: true, de: 'open', para: 'scheduled', texto: 'Lenine (OS-00074): de aberta para agendada.' };
  h.estado.erroPorta = null;
  h.estado.marcar = { ok: true, texto: 'Mudei: Lenine (OS-00074): ter 27/10, Roberto o dia todo.' };
  h.rpc.mockClear();
});

describe('useQuickSchedule fora da agenda automática — só a data no update, o status pela porta', () => {
  it("OS 'open': o update leva só scheduled_*, a porta é chamada (scheduled, tela_agendar) e o toast diz 'OS agendada'", async () => {
    const r = await agendar('open');
    expect(updates()).toEqual([{
      scheduled_start_at: '2026-10-27T09:00:00-03:00',
      scheduled_end_at: '2026-10-27T11:00:00-03:00',
    }]);
    expect(chamadasDa('os_transicionar_status')).toEqual([{ p_os: 'os-1', p_para: 'scheduled', p_via: 'tela_agendar' }]);
    expect(r.mensagem).toBe('OS agendada');
    expect(r.status).toBe('scheduled');
  });

  it("'awaiting_parts' sem a peça: a porta não muda e o toast traz a frase dela", async () => {
    h.estado.porta = { ok: true, mudou: false, de: 'awaiting_parts', para: 'awaiting_parts',
      texto: 'Ainda falta "Compressor 12V" na mão: a OS continua aguardando peças.' };
    const r = await agendar('awaiting_parts');
    expect(updates()).toHaveLength(1);
    expect('status' in updates()[0]).toBe(false);
    expect(updates()[0].scheduled_start_at).toBe('2026-10-27T09:00:00-03:00');
    expect(r.mensagem).toBe('Data gravada. Ainda falta "Compressor 12V" na mão: a OS continua aguardando peças.');
    expect(r.status).toBe('awaiting_parts');
  });

  it("'in_progress' não regride: o update vai sem status e a porta diz por quê", async () => {
    h.estado.porta = { ok: true, mudou: false, de: 'in_progress', para: 'in_progress', texto: 'A OS já começou: não volta para agendada.' };
    const r = await agendar('in_progress');
    expect('status' in updates()[0]).toBe(false);
    expect(r.mensagem).toBe('Data gravada. A OS já começou: não volta para agendada.');
  });

  it("'draft' (orçamento) ganha data sem virar OS", async () => {
    h.estado.porta = { ok: false, mudou: false, de: 'draft', para: 'draft', texto: 'Isso ainda é orçamento: converta antes.' };
    const r = await agendar('draft');
    expect('status' in updates()[0]).toBe(false);
    expect(r.mensagem).toMatch(/continua como orçamento/);
  });

  it("'completed' lança e não grava nada (nem pergunta à porta)", async () => {
    await expect(agendar('completed')).rejects.toThrow(/OS encerrada não se agenda/);
    expect(updates()).toHaveLength(0);
    expect(upserts()).toHaveLength(0);
    expect(chamouConflito()).toBe(false);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it('cancelada e faturada também lançam', async () => {
    await expect(agendar('cancelled')).rejects.toThrow(/OS encerrada não se agenda/);
    await expect(agendar('invoiced')).rejects.toThrow(/OS encerrada não se agenda/);
    expect(updates()).toHaveLength(0);
  });

  it('erro da porta vira o erro do toast (nunca "OS agendada" calado)', async () => {
    h.estado.erroPorta = { message: 'Você não pode mudar o status desta OS.' };
    await expect(agendar('open')).rejects.toMatchObject({ message: 'Você não pode mudar o status desta OS.' });
  });

  // Revisão da Fase 2: a tela publicada antes da migration da porta (20261025100100) volta ao caminho de antes; e quem
  // agenda sem poder mudar o status (vendedor, técnico fora da OS) fica com a data gravada e a frase, sem erro.
  it.each(['PGRST202', '42883'])("porta ausente (%s): o caminho de antes — 'open' vira agendada pelo UPDATE do status", async (code) => {
    h.estado.erroPorta = { code, message: 'Could not find the function public.os_transicionar_status' } as any;
    const r = await agendar('open');
    expect(updates()).toEqual([
      { scheduled_start_at: '2026-10-27T09:00:00-03:00', scheduled_end_at: '2026-10-27T11:00:00-03:00' },
      { status: 'scheduled' },
    ]);
    expect(r.mensagem).toBe('OS agendada');
    expect(r.status).toBe('scheduled');
  });

  it("porta ausente: 'awaiting_parts' só ganha a data (o caminho de antes não a mexia)", async () => {
    h.estado.erroPorta = { code: 'PGRST202', message: 'x' } as any;
    const r = await agendar('awaiting_parts');
    expect(updates()).toHaveLength(1);
    expect(r.status).toBe('awaiting_parts');
    expect(r.mensagem).toBe('Data gravada; a OS continua aguardando peças');
  });

  it('quem não pode mudar o status (42501): a data fica e o toast diz que o status é do administrador', async () => {
    h.estado.erroPorta = { code: '42501', message: 'Você não pode mudar o status desta OS.' } as any;
    const r = await agendar('open');
    expect(updates()).toHaveLength(1);
    expect(r.mensagem).toBe('Data gravada. O status quem muda é o administrador.');
    expect(r.status).toBe('open');
  });
});

describe('useQuickSchedule com a agenda automática ligada — só agenda_marcar_os', () => {
  it('nenhum update em service_orders, nem conferência de conflito: agenda_marcar_os com o dia de Brasília e via tela', async () => {
    h.estado.modo = 'ligado';
    const r = await agendar('approved', null);
    expect(updates()).toEqual([]);
    expect(chamouConflito()).toBe(false);
    expect(chamadasDa('os_transicionar_status')).toEqual([]);
    expect(chamadasDa('agenda_marcar_os')).toEqual([{
      p_autor: null, p_os: 'os-1', p_de: '2026-10-27', p_ate: '2026-10-27', p_pessoa: null, p_via: 'tela',
    }]);
    expect(r.mensagem).toBe('Mudei: Lenine (OS-00074): ter 27/10, Roberto o dia todo.');
    expect(r.agendaAutomatica).toBe(true);
  });

  it('o técnico escolhido vai como a pessoa (o favorecido do login) e fica vinculado à OS', async () => {
    h.estado.modo = 'ligado';
    h.estado.favorecidos = [{ id: 'payee-roberto' }];
    await agendar('open', 'tec-1');
    expect(chamadasDa('agenda_marcar_os')[0].p_pessoa).toBe('payee-roberto');
    const leitura = h.estado.chamadas.find((c) => c.tabela === 'payees')!.ops;
    expect(leitura).toContainEqual(['eq', 'app_user_id', 'tec-1']);
    expect(upserts()).toHaveLength(1);
    expect(updates()).toEqual([]);
  });

  it('não cabe: o erro é a frase do banco e nada é gravado', async () => {
    h.estado.modo = 'ligado';
    h.estado.marcar = { ok: false, texto: 'Não cabe ter 27/10: o Roberto já está no Vanderlei. O primeiro dia que dá é qua 28/10.' };
    await expect(agendar('open', null)).rejects.toThrow('Não cabe ter 27/10: o Roberto já está no Vanderlei. O primeiro dia que dá é qua 28/10.');
    expect(updates()).toEqual([]);
    expect(upserts()).toHaveLength(0);
  });

  // Revisão da Fase 3 (R3): o modo vem de agenda_modo_da_proposta (todo login lê); a tabela agenda_config é fechada ao
  // técnico e ao vendedor, e para eles a agenda parecia desligada.
  it('o modo vem da função que todo login lê (agenda_modo_da_proposta), não da tabela', async () => {
    h.estado.modo = 'ligado';
    await agendar('approved', null);
    expect(chamadasDa('agenda_modo_da_proposta')).toHaveLength(1);
    expect(h.estado.chamadas.some((c) => c.tabela === 'agenda_config')).toBe(false);
    expect(chamadasDa('agenda_marcar_os')).toHaveLength(1);
  });

  it('sem a função ainda no banco (PGRST202), o modo vem da tabela, como antes', async () => {
    h.estado.modo = 'ligado';
    h.estado.semFuncaoDoModo = true;
    await agendar('approved', null);
    expect(h.estado.chamadas.some((c) => c.tabela === 'agenda_config')).toBe(true);
    expect(chamadasDa('agenda_marcar_os')).toHaveLength(1);
  });

  it('a encerrada recusa antes de perguntar à agenda', async () => {
    h.estado.modo = 'ligado';
    await expect(agendar('completed')).rejects.toThrow(/OS encerrada não se agenda/);
    expect(h.rpc).not.toHaveBeenCalled();
  });
});

describe('useQuickSchedule — técnico opcional (D2)', () => {
  it('sem técnico e sem vínculo na OS: não checa conflito, não faz upsert, e mesmo assim agenda', async () => {
    const r = await agendar('open', null);
    expect(chamouConflito()).toBe(false);
    expect(upserts()).toHaveLength(0);
    expect(chamadasDa('os_transicionar_status')).toHaveLength(1);
    expect(r.warning).toBeNull();
    expect(r.semResponsavel).toBe(true);
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
    expect(chamadasDa('os_transicionar_status')).toHaveLength(0);
  });

  it('com técnico escolhido: diz que tem responsável', async () => {
    const r = await agendar('open', 'tec-1');
    expect(r.semResponsavel).toBe(false);
  });
});

// Revisão de 23/10/2026: reagendar a OS-00104 (técnico Roberto) com o campo vazio pulava o conflito e a
// sobrecarga do técnico que CONTINUA vinculado, e o toast dizia "(sem responsável)".
describe('useQuickSchedule — campo vazio com técnico já vinculado à OS', () => {
  it('confere a agenda de cada técnico vinculado, não faz upsert e não diz "sem responsável"', async () => {
    h.estado.vinculos = [{ user_id: 'roberto' }, { user_id: 'mickael' }, { user_id: 'roberto' }];
    h.estado.porta = { ok: true, mudou: false, de: 'awaiting_parts', para: 'awaiting_parts', texto: 'x' };
    const r = await agendar('awaiting_parts', null);
    const leitura = h.estado.chamadas.find((c) => c.tabela === 'service_order_technicians')!.ops;
    expect(leitura).toContainEqual(['eq', 'service_order_id', 'os-1']);
    const pessoas = h.rpc.mock.calls
      .filter((c) => c[0] === 'get_agenda_conflicts')
      .map((c) => c[1].p_user_id);
    // conflito (janela pedida) + sobrecarga (o dia) para cada um, sem repetir o Roberto
    expect([...new Set(pessoas)]).toEqual(['roberto', 'mickael']);
    expect(pessoas.filter((p) => p === 'roberto')).toHaveLength(2);
    expect(upserts()).toHaveLength(0);
    expect(r.semResponsavel).toBe(false);
  });

  it('conflito do técnico vinculado recusa antes de gravar', async () => {
    h.estado.vinculos = [{ user_id: 'roberto' }];
    h.estado.conflitos = [{ source: 'service_order', label: 'OS-00112',
      starts_at: '2026-10-27T08:00:00-03:00', ends_at: '2026-10-27T12:00:00-03:00' }];
    await expect(agendar('awaiting_parts', null)).rejects.toThrow(/Conflito de agenda: o responsável já tem OS-00112/);
    expect(updates()).toHaveLength(0);
  });

  it('a alocação da agenda de produção no conflito (source alocacao) cita o número da OS sem aspas', async () => {
    h.estado.vinculos = [{ user_id: 'roberto' }];
    h.estado.conflitos = [{ source: 'alocacao', label: 'OS-00069',
      starts_at: '2026-10-27T08:00:00-03:00', ends_at: '2026-10-27T12:00:00-03:00' }];
    await expect(agendar('open', null)).rejects.toThrow('Conflito de agenda: o responsável já tem OS-00069 nesse horário.');
  });

  it('erro ao ler os vínculos lança (não agenda sem conferir)', async () => {
    h.estado.erroVinculos = { message: 'falha nos vínculos' };
    await expect(agendar('open', null)).rejects.toMatchObject({ message: 'falha nos vínculos' });
    expect(updates()).toHaveLength(0);
  });

  it('com técnico escolhido, os vínculos nem são lidos (o escolhido é o conferido)', async () => {
    h.estado.vinculos = [{ user_id: 'roberto' }];
    await agendar('open', 'tec-1');
    const leuVinculos = h.estado.chamadas.some((c) => c.tabela === 'service_order_technicians'
      && c.ops.some((op) => op[0] === 'select'));
    expect(leuVinculos).toBe(false);
    expect(h.rpc.mock.calls.filter((c) => c[0] === 'get_agenda_conflicts').every((c) => c[1].p_user_id === 'tec-1')).toBe(true);
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

describe('mensagemAoAgendar — o toast diz o status resultante (o que a porta fez)', () => {
  it.each([
    ['open', { ok: true, mudou: true, para: 'scheduled' }, 'OS agendada'],
    ['awaiting_client', { ok: true, mudou: true, para: 'scheduled' }, 'OS agendada'],
    ['scheduled', { ok: true, mudou: false, para: 'scheduled', texto: 'Lenine (OS-00074) já está agendada.' }, 'Agendamento atualizado'],
    ['awaiting_parts', { ok: true, mudou: false, para: 'awaiting_parts', texto: 'Ainda falta "Cabo" na mão: a OS continua aguardando peças.' },
      'Data gravada. Ainda falta "Cabo" na mão: a OS continua aguardando peças.'],
    ['in_progress', { ok: true, mudou: false, para: 'in_progress', texto: 'A OS já começou: não volta para agendada.' },
      'Data gravada. A OS já começou: não volta para agendada.'],
    ['draft', { ok: false, mudou: false, para: 'draft', texto: 'Isso ainda é orçamento: converta antes.' },
      'Data gravada; continua como orçamento (ainda não é OS)'],
    ['awaiting_parts', null, 'Data gravada; a OS continua aguardando peças'],
  ] as const)('%s → %j', (anterior, porta, texto) => {
    expect(mensagemAoAgendar(anterior, porta as any)).toBe(texto);
  });
});

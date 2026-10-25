// As leituras das telas de produção (Agenda de Produção, Fase 3, P7a): o plano B (a tabela ou a função ainda não aplicada
// = a tela de antes, sem erro), o erro de verdade que LANÇA (nunca vira "nada marcado"), a jornada de agenda_config com o
// padrão só como reserva, e o que a porta aceita pela tela (a lista rápida e os kanbans escondem o resto).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => ({
  rpc: vi.fn(),
  linha: { data: null as unknown, error: null as unknown },
}));

vi.mock('@/integrations/supabase/client', () => {
  const builder: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'limit']) builder[m] = () => builder;
  builder.maybeSingle = async () => h.linha;
  return { supabase: { from: () => builder, rpc: (...a: unknown[]) => h.rpc(...a) } };
});

import { supabase } from '@/integrations/supabase/client';
import {
  CONFIG_DE_ANTES, jornadaDaAgenda, lerAgendaConfig, lerEquipeDaGrade, useSemanaProducao, usePlanoDaOs,
} from './use-agenda-producao';
import { lerStatusQueAPortaAceita, motivoQueAPortaPede, opcoesQueAPortaAceita } from './use-status-da-porta';
import { JORNADA_PADRAO_HORAS } from '../../supabase/functions/_shared/agenda-dia';

function envoltorio() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return { qc, wrapper: ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: qc }, children) };
}

beforeEach(() => {
  h.rpc.mockReset();
  h.linha = { data: null, error: null };
});

describe('agenda_config para a tela', () => {
  it('a tabela ainda não aplicada (PGRST205 ou 42P01) = a tela de antes: jornada padrão e agenda desligada', async () => {
    for (const code of ['PGRST205', '42P01']) {
      h.linha = { data: null, error: { code, message: 'relation does not exist' } };
      expect(await lerAgendaConfig(supabase)).toEqual(CONFIG_DE_ANTES);
    }
    expect(CONFIG_DE_ANTES.jornada_horas).toBe(JORNADA_PADRAO_HORAS);
    expect(CONFIG_DE_ANTES.modo_leitura).toBe('desligado');
  });

  it('sem linha (o técnico: a RLS é de admin/financeiro) = a tela de antes', async () => {
    h.linha = { data: null, error: null };
    expect(await lerAgendaConfig(supabase)).toEqual(CONFIG_DE_ANTES);
  });

  it('com a linha, a jornada e os modos vêm do banco (o TS não tem o número)', async () => {
    h.linha = { data: { jornada_horas: '9.00', carga_max: '0.80', modo_leitura: 'sombra', modo_proposta: 'ligado' }, error: null };
    const c = await lerAgendaConfig(supabase);
    expect(c).toMatchObject({ jornada_horas: 9, modo_leitura: 'sombra', modo_proposta: 'ligado', doBanco: true });
    expect(c.carga_max).toBeCloseTo(Number('0.80'));
  });

  it('outro erro lança (não vira "desligado" calado)', async () => {
    h.linha = { data: null, error: { code: '57014', message: 'tempo esgotado' } };
    await expect(lerAgendaConfig(supabase)).rejects.toMatchObject({ code: '57014' });
  });

  it('jornadaDaAgenda (as mutações): a do banco; com erro, a padrão', async () => {
    const { qc } = envoltorio();
    h.linha = { data: { jornada_horas: 10, carga_max: null, modo_leitura: 'ligado', modo_proposta: 'ligado' }, error: null };
    expect(await jornadaDaAgenda(qc)).toBe(10);
    const outro = envoltorio().qc;
    h.linha = { data: null, error: { code: '57014', message: 'tempo esgotado' } };
    expect(await jornadaDaAgenda(outro)).toBe(JORNADA_PADRAO_HORAS);
  });
});

describe('as leituras das telas', () => {
  it('a função ainda não aplicada (PGRST202) = null: a tela de antes, sem erro', async () => {
    h.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } });
    const { wrapper } = envoltorio();
    const { result } = renderHook(() => useSemanaProducao('2026-11-02'), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toBeNull();
    expect(h.rpc).toHaveBeenCalledWith('agenda_tela_semana', { p_de: '2026-11-02' });
  });

  it('erro de verdade LANÇA com a frase do banco (a tela mostra o erro, nunca "nada marcado")', async () => {
    h.rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'O plano da OS é com o administrador.' } });
    const { wrapper } = envoltorio();
    const { result } = renderHook(() => usePlanoDaOs('os-1'), { wrapper });
    await waitFor(() => expect(result.current.isError).toBe(true));
    expect((result.current.error as Error).message).toBe('O plano da OS é com o administrador.');
  });

  it('a equipe da grade: ausente ou sem direito = null (as linhas de antes); erro de verdade lança', async () => {
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: '42883', message: 'function does not exist' } });
    expect(await lerEquipeDaGrade(supabase)).toBeNull();
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'A agenda de produção é com o administrador.' } });
    expect(await lerEquipeDaGrade(supabase)).toBeNull();
    h.rpc.mockResolvedValueOnce({ data: [{ payee_id: 'p1', nome: 'Gustavo', nome_curto: 'Gustavo', eh_dono: true, app_user_id: 'u1' }], error: null });
    expect(await lerEquipeDaGrade(supabase)).toHaveLength(1);
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: '57014', message: 'tempo esgotado' } });
    await expect(lerEquipeDaGrade(supabase)).rejects.toThrow('tempo esgotado');
  });
});

describe('o que a porta aceita pela tela', () => {
  it('revisão da Fase 3 (R2): o que a porta só aceita com o motivo vem em "<id>:motivo"; sem resposta, nenhum', () => {
    const aceitos = { 'os-1': ['awaiting_parts', 'completed'], 'os-1:motivo': ['awaiting_parts'] };
    expect(motivoQueAPortaPede(aceitos, 'os-1')).toEqual(['awaiting_parts']);
    expect(opcoesQueAPortaAceita(['awaiting_parts', 'open'], aceitos, 'os-1')).toEqual(['awaiting_parts']);
    expect(motivoQueAPortaPede({ 'os-1': ['completed'] }, 'os-1')).toEqual([]);
    expect(motivoQueAPortaPede(null, 'os-1')).toEqual([]);
  });
  it('sem resposta do banco, todas as opções (como antes); com resposta, só as aceitas — e Cancelar fica', () => {
    const lista = ['in_progress', 'completed', 'cancelled'];
    expect(opcoesQueAPortaAceita(lista, null, 'os-1')).toEqual(lista);
    expect(opcoesQueAPortaAceita(lista, undefined, 'os-1')).toEqual(lista);
    expect(opcoesQueAPortaAceita(lista, { 'os-1': ['in_progress'] }, 'os-1')).toEqual(['in_progress', 'cancelled']);
    // a OS que o banco não devolveu fica como antes
    expect(opcoesQueAPortaAceita(lista, { 'os-2': [] }, 'os-1')).toEqual(lista);
  });

  it('a função ausente = null (a tela mostra tudo); outro erro lança; lista vazia nem pergunta', async () => {
    expect(await lerStatusQueAPortaAceita([])).toEqual({});
    expect(h.rpc).not.toHaveBeenCalled();
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } });
    expect(await lerStatusQueAPortaAceita(['os-1'])).toBeNull();
    h.rpc.mockResolvedValueOnce({ data: { 'os-1': ['completed'] }, error: null });
    expect(await lerStatusQueAPortaAceita(['os-1'])).toEqual({ 'os-1': ['completed'] });
    expect(h.rpc).toHaveBeenLastCalledWith('os_status_da_tela', { p_os: ['os-1'] });
    h.rpc.mockResolvedValueOnce({ data: null, error: { code: '57014', message: 'tempo esgotado' } });
    await expect(lerStatusQueAPortaAceita(['os-1'])).rejects.toThrow('tempo esgotado');
  });
});

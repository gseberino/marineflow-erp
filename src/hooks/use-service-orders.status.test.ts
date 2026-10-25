// A mudança de status pela tela pela porta única (Agenda de Produção, Fase 3, P3 — 24/10/2026).
//
// Até aqui useUpdateServiceOrderStatus (StatusQuickChange, kanbans, listas, formulário) fazia o UPDATE dele: a conversão,
// o início, a saída e as cobranças da conclusão com o erro engolido. Agora é os_transicionar_status (via 'tela', com
// p_check_out para só a porta da Fase 3 servir). O supabase aqui é falso e grava o que foi pedido:
//   · a RPC certa e nenhum UPDATE; a porta que não muda nada volta em semMudanca (aviso, não erro); a recusa e o 42501
//     viram erro com a frase da porta; cancelar continua recusado antes de tudo;
//   · o PLANO B (a porta completa ausente: PGRST202/42883) volta ao caminho de antes — a conversão mantendo o número, o
//     início, a saída e as cobranças —, e só nesse caso: outro erro continua erro.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => {
  const estado = {
    porta: { ok: true, mudou: true, de: 'in_progress', para: 'completed', texto: 'Lenine (OS-00074): concluída — saída qui 29/10 16:30. Cobrança: Saldo R$ 2.280,00 (vence hoje).' } as any,
    erroPorta: null as { message: string; code?: string } | null,
    os: { status: 'draft', converted_to_os_at: null, service_order_number: 'ORÇ-00119', grand_total: 9608.96, original_quote_amount: null, check_in_at: null, check_out_at: null } as any,
    chamadas: [] as { tabela: string; ops: any[][] }[],
  };
  const builder = (tabela: string): any => {
    const reg = { tabela, ops: [] as any[][] };
    estado.chamadas.push(reg);
    const o: any = {};
    for (const k of ['select', 'eq', 'in', 'update', 'insert']) {
      o[k] = (...args: any[]) => { reg.ops.push([k, ...args]); return o; };
    }
    o.maybeSingle = async () => ({ data: tabela === 'service_orders' ? estado.os : null, error: null });
    o.single = async () => {
      const upd = reg.ops.find((op) => op[0] === 'update');
      return { data: upd ? { id: 'os-1', ...estado.os, ...upd[1] } : estado.os, error: null };
    };
    o.then = (ok: any, erro: any) => Promise.resolve({ data: null, error: null }).then(ok, erro);
    return o;
  };
  const rpc = vi.fn(async (_nome: string, _args: any) => ({ data: estado.erroPorta ? null : estado.porta, error: estado.erroPorta }));
  const auditoria = vi.fn(async () => undefined);
  const cobrancas = vi.fn(async () => ({ created: 2 }));
  const toast = Object.assign(vi.fn(), { success: vi.fn(), warning: vi.fn(), error: vi.fn() });
  return { estado, builder, rpc, auditoria, cobrancas, toast };
});

vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: (t: string) => h.builder(t), rpc: h.rpc } }));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: h.auditoria }));
vi.mock('@/lib/completion-receivables', () => ({ ensureCompletionReceivables: h.cobrancas }));
vi.mock('sonner', () => ({ toast: h.toast }));

import { mudarStatusPelaTela, useUpdateServiceOrderStatus } from './use-service-orders';
import { avisarSeNaoMudou, ehPortaPedeMotivo, motivoDaParada } from '@/lib/status-pela-tela';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return createElement(QueryClientProvider, { client: qc }, children);
}

const updates = () => h.estado.chamadas.filter((c) => c.tabela === 'service_orders').flatMap((c) => c.ops.filter((op) => op[0] === 'update'));
const portas = () => h.rpc.mock.calls.filter((c) => c[0] === 'os_transicionar_status').map((c) => c[1]);

beforeEach(() => {
  h.estado.chamadas.length = 0;
  h.estado.porta = { ok: true, mudou: true, de: 'in_progress', para: 'completed', texto: 'Lenine (OS-00074): concluída — saída qui 29/10 16:30. Cobrança: Saldo R$ 2.280,00 (vence hoje).' };
  h.estado.erroPorta = null;
  h.estado.os = { status: 'draft', converted_to_os_at: null, service_order_number: 'ORÇ-00119', grand_total: 9608.96, original_quote_amount: null, check_in_at: null, check_out_at: null };
  h.rpc.mockClear();
  h.auditoria.mockClear();
  h.cobrancas.mockClear();
  h.toast.mockClear();
});

describe('useUpdateServiceOrderStatus — pela porta (via tela)', () => {
  it('concluir: chama os_transicionar_status com via tela e p_check_out (só a porta da Fase 3 serve), nenhum UPDATE, a frase volta', async () => {
    const { result } = renderHook(() => useUpdateServiceOrderStatus(), { wrapper });
    const r = await result.current.mutateAsync({ id: 'os-1', status: 'completed' });
    expect(portas()).toEqual([{ p_os: 'os-1', p_para: 'completed', p_via: 'tela', p_check_out: null }]);
    expect(updates()).toEqual([]);
    expect(h.cobrancas).not.toHaveBeenCalled();
    expect(r).toMatchObject({ mudou: true, status: 'completed', justConverted: false });
    expect(r.texto).toContain('Cobrança: Saldo R$ 2.280,00');
    expect(r.semMudanca).toBeUndefined();
    expect(h.auditoria).toHaveBeenCalledWith(expect.objectContaining({ record_id: 'os-1', new_value: { status: 'completed', via: 'tela' } }));
  });

  it('a conversão é da porta: justConverted e o número com o prefixo trocado vêm dela', async () => {
    h.estado.porta = { ok: true, mudou: true, de: 'draft', para: 'approved', convertido: true, numero: 'OS-00119', texto: 'Orçamento ORÇ-00119 virou a OS-00119 (aprovada).' };
    const r = await mudarStatusPelaTela('os-1', 'approved');
    expect(r).toMatchObject({ mudou: true, status: 'approved', justConverted: true, numero: 'OS-00119' });
    expect(updates()).toEqual([]);
  });

  it('a porta que não muda nada: semMudanca com a frase dela (aviso, não erro), sem auditoria', async () => {
    h.estado.porta = { ok: true, mudou: false, de: 'in_progress', para: 'in_progress', texto: 'A OS já começou: não volta para aprovada.' };
    const { result } = renderHook(() => useUpdateServiceOrderStatus(), { wrapper });
    const r = await result.current.mutateAsync({ id: 'os-1', status: 'approved' });
    expect(r).toMatchObject({ mudou: false, status: 'in_progress', semMudanca: 'A OS já começou: não volta para aprovada.' });
    expect(h.auditoria).not.toHaveBeenCalled();
    expect(updates()).toEqual([]);
  });

  it('a recusa da porta (ok = false) vira erro com a frase dela; nada é escrito', async () => {
    h.estado.porta = { ok: false, mudou: false, de: 'completed', para: 'completed', texto: 'Não concluí: o período de outubro está fechado no financeiro (as cobranças da conclusão entrariam nele). Reabra o período e conclua de novo.' };
    await expect(mudarStatusPelaTela('os-1', 'completed')).rejects.toThrow('Não concluí: o período de outubro está fechado');
    expect(updates()).toEqual([]);
  });

  it('quem não pode (42501: o vendedor concluindo, o técnico fora da OS) recebe a frase da porta e o plano B não roda', async () => {
    h.estado.erroPorta = { code: '42501', message: 'Concluir é com o administrador ou o técnico da OS.' };
    await expect(mudarStatusPelaTela('os-1', 'completed')).rejects.toThrow('Concluir é com o administrador ou o técnico da OS.');
    expect(updates()).toEqual([]);
    expect(h.cobrancas).not.toHaveBeenCalled();
  });

  it('cancelar continua recusado antes de tudo (o botão Cancelar OS estorna)', async () => {
    await expect(mudarStatusPelaTela('os-1', 'cancelled')).rejects.toThrow('Cancelar OS');
    expect(h.rpc).not.toHaveBeenCalled();
  });
});

describe('useUpdateServiceOrderStatus — PLANO B (a porta da Fase 3 ainda não aplicada)', () => {
  it.each(['PGRST202', '42883'])('%s: o caminho de antes — a conversão troca só o prefixo e guarda o valor orçado', async (code) => {
    h.estado.erroPorta = { code, message: 'Could not find the function public.os_transicionar_status(p_check_out, p_os, p_para, p_via)' };
    const r = await mudarStatusPelaTela('os-1', 'approved');
    const [upd] = updates();
    expect(upd[1]).toMatchObject({ status: 'approved', service_order_number: 'OS-00119', original_quote_amount: 9608.96 });
    expect(typeof upd[1].converted_to_os_at).toBe('string');
    expect(r).toMatchObject({ mudou: true, justConverted: true, numero: 'OS-00119', semAPorta: true });
  });

  it('concluir pelo plano B: a saída e as cobranças da tela (ensureCompletionReceivables), como antes', async () => {
    h.estado.erroPorta = { code: 'PGRST202', message: 'função ausente' };
    h.estado.os = { ...h.estado.os, status: 'in_progress', converted_to_os_at: '2026-10-01T12:00:00Z', service_order_number: 'OS-00074', check_in_at: '2026-10-27T11:00:00Z' };
    const r = await mudarStatusPelaTela('os-1', 'completed');
    const [upd] = updates();
    expect(upd[1]).toMatchObject({ status: 'completed' });
    expect(typeof upd[1].check_out_at).toBe('string');
    expect(upd[1].service_order_number).toBeUndefined();
    expect(h.cobrancas).toHaveBeenCalledWith(expect.objectContaining({ serviceOrderId: 'os-1' }));
    expect(r).toMatchObject({ mudou: true, justConverted: false, semAPorta: true });
  });

  it('a cobrança que falha no plano B não impede concluir (era assim antes da porta)', async () => {
    h.estado.erroPorta = { code: 'PGRST202', message: 'função ausente' };
    h.estado.os = { ...h.estado.os, status: 'in_progress', converted_to_os_at: '2026-10-01T12:00:00Z' };
    h.cobrancas.mockRejectedValueOnce(new Error('RLS'));
    const erro = vi.spyOn(console, 'error').mockImplementation(() => {});
    await expect(mudarStatusPelaTela('os-1', 'completed')).resolves.toMatchObject({ mudou: true });
    erro.mockRestore();
  });

  it('outro erro da porta (não é "função ausente") continua erro: nada de caminho de antes', async () => {
    h.estado.erroPorta = { code: '23514', message: 'violates check constraint' };
    await expect(mudarStatusPelaTela('os-1', 'approved')).rejects.toThrow('violates check constraint');
    expect(updates()).toEqual([]);
  });
});

describe('avisarSeNaoMudou', () => {
  it('a porta que não mudou nada: a frase dela num aviso, e true (quem chama não diz "Status atualizado")', () => {
    expect(avisarSeNaoMudou({ semMudanca: 'A OS já começou: não volta para aprovada.' })).toBe(true);
    expect(h.toast).toHaveBeenCalledWith('A OS já começou: não volta para aprovada.');
  });
  it('mudou (ou nada veio): false, sem aviso', () => {
    expect(avisarSeNaoMudou({})).toBe(false);
    expect(avisarSeNaoMudou(undefined)).toBe(false);
    expect(h.toast).not.toHaveBeenCalled();
  });
});

// Revisão da Fase 3 (R2): a OS em andamento volta a aguardar pela tela com o motivo; a recusa só por falta dele é PortaPedeMotivo.
describe('o motivo da parada pela tela', () => {
  it('com o motivo: vai à porta em p_motivo (via tela) e fica na auditoria', async () => {
    h.estado.porta = { ok: true, mudou: true, de: 'in_progress', para: 'awaiting_parts', texto: 'Lenine (OS-00074): de em andamento para aguardando peças — falta material.' };
    const { result } = renderHook(() => useUpdateServiceOrderStatus(), { wrapper });
    await result.current.mutateAsync({ id: 'os-1', status: 'awaiting_parts', motivo: ' falta material ' });
    expect(portas()).toEqual([{ p_os: 'os-1', p_para: 'awaiting_parts', p_via: 'tela', p_check_out: null, p_motivo: 'falta material' }]);
    expect(h.auditoria).toHaveBeenCalledWith(expect.objectContaining({ new_value: { status: 'awaiting_parts', via: 'tela', motivo: 'falta material' } }));
  });

  it('a porta recusa só por falta do motivo (pede_motivo): PortaPedeMotivo com a frase e o status pedido', async () => {
    h.estado.porta = { ok: false, mudou: false, de: 'in_progress', para: 'in_progress', pede_motivo: true,
      texto: 'A OS já começou: só volta a aguardar quando você diz que parou e por quê.' };
    const erro = await mudarStatusPelaTela('os-1', 'awaiting_client').catch((e) => e);
    expect(ehPortaPedeMotivo(erro)).toBe(true);
    expect(erro).toMatchObject({ para: 'awaiting_client', message: 'A OS já começou: só volta a aguardar quando você diz que parou e por quê.' });
  });

  it('a recusa sem pede_motivo continua erro comum', async () => {
    h.estado.porta = { ok: false, mudou: false, de: 'in_progress', para: 'in_progress', texto: 'A OS já começou: só volta a aguardar quando você diz que parou e por quê.' };
    const erro = await mudarStatusPelaTela('os-1', 'awaiting_parts').catch((e) => e);
    expect(ehPortaPedeMotivo(erro)).toBe(false);
    expect(erro).toBeInstanceOf(Error);
  });

  it('o texto do motivo: o porquê e o que aconteceu, sem espaço sobrando', () => {
    expect(motivoDaParada('awaiting_parts', '')).toBe('falta material');
    expect(motivoDaParada('awaiting_client', '  a cor   do estofado ')).toBe('esperando o cliente: a cor do estofado');
  });
});

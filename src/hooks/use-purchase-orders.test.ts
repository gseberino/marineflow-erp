// A OC criada a partir da OS e o status da OS (Agenda de Produção, Fase 2, P4 — NOVO-agenda-10).
//
// Até 24/10/2026 os dois caminhos da tela (useCreatePOFromOS, no alerta de estoque, e
// useCreatePOsFromShortages, nas necessidades de compra) faziam UPDATE do status direto, de
// aberta/aprovada/agendada E de em andamento para "aguardando peças": a OC regredia a OS que já tinha
// começado. Agora o status vai pela porta única do banco (os_transicionar_status, via 'oc'), que mantém em
// andamento; a OC é criada do mesmo jeito, e erro na porta vira aviso (a OC já existe). Aqui o supabase é
// falso e grava o que foi pedido.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => {
  const estado = {
    statusDaOs: 'open' as string,
    porta: { ok: true, mudou: true, de: 'open', para: 'awaiting_parts', texto: 'Lenine (OS-00074): de aberta para aguardando peças.' } as any,
    erroPorta: null as { message: string } | null,
    chamadas: [] as { tabela: string; ops: any[][] }[],
  };
  const builder = (tabela: string): any => {
    const reg = { tabela, ops: [] as any[][] };
    estado.chamadas.push(reg);
    const o: any = {};
    for (const k of ['select', 'eq', 'in', 'order', 'limit', 'update', 'insert']) {
      o[k] = (...args: any[]) => { reg.ops.push([k, ...args]); return o; };
    }
    o.single = async () => ({ data: { id: 'po-1', po_number: 'OC-00010' }, error: null });
    o.maybeSingle = async () => ({ data: tabela === 'service_orders' ? { status: estado.statusDaOs } : null, error: null });
    o.then = (ok: any, erro: any) => {
      if (tabela === 'purchase_orders') return Promise.resolve({ data: [{ po_number: 'OC-00009' }], error: null }).then(ok, erro);
      if (tabela === 'products') return Promise.resolve({ data: [{ id: 'p1', supplier_id: 's1' }], error: null }).then(ok, erro);
      return Promise.resolve({ data: null, error: null }).then(ok, erro);
    };
    return o;
  };
  const rpc = vi.fn(async (_nome: string, _args: any) => ({ data: estado.erroPorta ? null : estado.porta, error: estado.erroPorta }));
  const toast = { success: vi.fn(), warning: vi.fn(), error: vi.fn() };
  return { estado, builder, rpc, toast };
});

vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: (t: string) => h.builder(t), rpc: h.rpc } }));
vi.mock('sonner', () => ({ toast: h.toast }));

import { mensagemDaOC, useCreatePOFromOS, useCreatePOsFromShortages } from './use-purchase-orders';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return createElement(QueryClientProvider, { client: qc }, children);
}

const updatesNaOs = () => h.estado.chamadas
  .filter((c) => c.tabela === 'service_orders')
  .flatMap((c) => c.ops.filter((op) => op[0] === 'update'));
const portas = () => h.rpc.mock.calls.filter((c) => c[0] === 'os_transicionar_status').map((c) => c[1]);

async function criarDaOs() {
  const { result } = renderHook(() => useCreatePOFromOS(), { wrapper });
  return result.current.mutateAsync({ serviceOrderId: 'os-1', productId: 'p1', productName: 'Bateria', quantity: 1, unitCost: 900 });
}
async function criarDasFaltas() {
  const { result } = renderHook(() => useCreatePOsFromShortages(), { wrapper });
  return result.current.mutateAsync({
    serviceOrderId: 'os-1',
    items: [{ productId: 'p1', description: 'Bateria', quantity: 1, unitCost: 900 }],
  });
}

beforeEach(() => {
  h.estado.chamadas.length = 0;
  h.estado.statusDaOs = 'open';
  h.estado.porta = { ok: true, mudou: true, de: 'open', para: 'awaiting_parts', texto: 'Lenine (OS-00074): de aberta para aguardando peças.' };
  h.estado.erroPorta = null;
  h.rpc.mockClear();
  h.toast.success.mockClear();
  h.toast.warning.mockClear();
  h.toast.error.mockClear();
});

describe.each([
  ['useCreatePOFromOS', criarDaOs, 'Ordem de compra criada.'],
  ['useCreatePOsFromShortages', criarDasFaltas, 'Ordem de compra OC-00010 criada.'],
] as const)('%s — o status da OS pela porta, via oc', (_nome, criar, base) => {
  it('OS aberta: a porta é chamada (awaiting_parts, oc), nenhum UPDATE de status, e o toast diz que ela foi para aguardando peças', async () => {
    const r: any = await criar();
    expect(portas()).toEqual([{ p_os: 'os-1', p_para: 'awaiting_parts', p_via: 'oc' }]);
    expect(updatesNaOs()).toEqual([]);
    expect(r.os).toEqual({ mudou: true, texto: 'Lenine (OS-00074): de aberta para aguardando peças.', aviso: null });
    expect(h.toast.success).toHaveBeenCalledWith(`${base} OS movida para "Aguardando Peças".`);
  });

  it('OS em andamento: a porta mantém (NOVO-agenda-10) e o toast diz que ela segue em andamento', async () => {
    h.estado.statusDaOs = 'in_progress';
    h.estado.porta = { ok: true, mudou: false, de: 'in_progress', para: 'in_progress', texto: 'A OS segue em andamento; a compra foi registrada.' };
    await criar();
    expect(portas()).toHaveLength(1);
    expect(updatesNaOs()).toEqual([]);
    expect(h.toast.success).toHaveBeenCalledWith(`${base} A OS segue em andamento; a compra foi registrada.`);
  });

  it('OS aguardando o cliente: fica como estava (a porta nem é chamada), a OC sai', async () => {
    h.estado.statusDaOs = 'awaiting_client';
    await criar();
    expect(portas()).toEqual([]);
    expect(h.toast.success).toHaveBeenCalledWith(base);
  });

  it('erro na porta: a OC fica criada (sucesso) e o aviso diz que a OS não mudou', async () => {
    h.estado.erroPorta = { message: 'Você não pode mudar o status desta OS.' };
    await criar();
    expect(h.toast.success).toHaveBeenCalledWith(base);
    expect(h.toast.warning).toHaveBeenCalledWith(
      'A ordem de compra foi criada, mas a OS não mudou de status: Você não pode mudar o status desta OS.');
    expect(h.toast.error).not.toHaveBeenCalled();
  });
});

describe('mensagemDaOC', () => {
  it('com aviso, só a base (o aviso vai em outro toast)', () => {
    expect(mensagemDaOC('Ordem de compra criada.', { mudou: false, texto: 'x', aviso: 'erro' })).toBe('Ordem de compra criada.');
  });
});

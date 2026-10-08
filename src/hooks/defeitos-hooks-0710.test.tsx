// Gravações dos defeitos de tela de 07/10/2026: marcar cobrança paga (2), aceitar/descartar
// sugestão da agenda (6) e excluir/mudar a situação da ordem de compra (4).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

type Resposta = { data: unknown; error: { message: string } | null };

const banco = vi.hoisted(() => ({
  /** Resposta por "tabela.operação" (select/update/insert/delete) ou "rpc.nome". */
  respostas: {} as Record<string, Resposta | Resposta[]>,
  chamadas: [] as Array<{ alvo: string; op: string; valores?: unknown; filtros: unknown[][] }>,
}));

function responder(chave: string): Resposta {
  const r = banco.respostas[chave];
  if (Array.isArray(r)) return r.length > 1 ? r.shift()! : r[0];
  return r ?? { data: null, error: null };
}

vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn(), warning: vi.fn() }) }));
vi.mock('@/integrations/supabase/client', () => {
  const consulta = (tabela: string) => {
    const registro = { alvo: tabela, op: 'select', valores: undefined as unknown, filtros: [] as unknown[][] };
    // deno-lint-ignore no-explicit-any
    const q: any = {};
    for (const m of ['select', 'eq', 'in', 'neq', 'limit', 'order']) {
      q[m] = (...a: unknown[]) => { registro.filtros.push([m, ...a]); return q; };
    }
    q.update = (v: unknown) => { registro.op = 'update'; registro.valores = v; return q; };
    q.insert = (v: unknown) => { registro.op = 'insert'; registro.valores = v; return q; };
    q.delete = () => { registro.op = 'delete'; return q; };
    q.single = () => q;
    q.maybeSingle = () => q;
    // deno-lint-ignore no-explicit-any
    q.then = (ok: any, erro: any) => {
      banco.chamadas.push(registro);
      return Promise.resolve(responder(`${tabela}.${registro.op}`)).then(ok, erro);
    };
    return q;
  };
  return {
    supabase: {
      from: (t: string) => consulta(t),
      rpc: (nome: string, args: unknown) => {
        banco.chamadas.push({ alvo: `rpc.${nome}`, op: 'rpc', valores: args, filtros: [] });
        return Promise.resolve(responder(`rpc.${nome}`));
      },
      auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
    },
  };
});

import { useMarkCollectionPaid } from './use-collections';
import { useAcceptSuggestion, useDismissSuggestion } from './use-agenda';
import { useDeletePurchaseOrder, useUpdatePurchaseOrder } from './use-purchase-orders';

const ok = (data: unknown): Resposta => ({ data, error: null });
const falha = (message: string): Resposta => ({ data: null, error: { message } });
const ops = (alvo: string, op: string) => banco.chamadas.filter((c) => c.alvo === alvo && c.op === op);

function hook<T>(usar: () => T): T {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
  return renderHook(usar, { wrapper }).result.current;
}

beforeEach(() => {
  banco.respostas = {};
  banco.chamadas = [];
});

describe('useMarkCollectionPaid (2)', () => {
  const PAGO = { id: 'c1', paid_amount: 500, paid_method: 'pix', payment_date: '2026-10-07', confirmed_by: 'manual' as const };

  it('pagamento recusado pelo banco: a cobrança NÃO fica paga (antes o erro era ignorado)', async () => {
    banco.respostas['collections.select'] = ok({ receivable_id: 'r1' });
    banco.respostas['rpc.register_payment_and_update_balance'] = falha('O mês 09/2026 está fechado');
    const m = hook(() => useMarkCollectionPaid());
    await expect(m.mutateAsync(PAGO)).rejects.toMatchObject({ message: 'O mês 09/2026 está fechado' });
    expect(ops('collections', 'update')).toEqual([]);
    expect(ops('collection_contacts', 'insert')).toEqual([]);
  });

  it('caminho feliz: pagamento na conta primeiro, depois a cobrança e o contato', async () => {
    banco.respostas['collections.select'] = ok({ receivable_id: 'r1' });
    banco.respostas['rpc.register_payment_and_update_balance'] = ok({ ok: true });
    const m = hook(() => useMarkCollectionPaid());
    await m.mutateAsync(PAGO);
    const ordem = banco.chamadas.filter((c) => c.op !== 'select').map((c) => `${c.alvo}.${c.op}`);
    expect(ordem).toEqual(['rpc.register_payment_and_update_balance.rpc', 'collections.update', 'collection_contacts.insert']);
  });

  it('leitura da cobrança que falha pára antes de gravar', async () => {
    banco.respostas['collections.select'] = falha('timeout');
    const m = hook(() => useMarkCollectionPaid());
    await expect(m.mutateAsync(PAGO)).rejects.toMatchObject({ message: 'timeout' });
    expect(banco.chamadas.filter((c) => c.op !== 'select')).toEqual([]);
  });
});

describe('useAcceptSuggestion / useDismissSuggestion (6)', () => {
  const SUG = { id: 's1', title: 'Ligar para o Miguel', kind: 'task', origin: 'whatsapp', evidence: 'me liga amanhã', priority: 'normal' };

  it('só aceita sugestão ainda pendente (update condicional)', async () => {
    banco.respostas['agenda_tasks.insert'] = ok({ id: 't1' });
    banco.respostas['agenda_suggestions.update'] = ok([{ id: 's1' }]);
    const m = hook(() => useAcceptSuggestion());
    expect(await m.mutateAsync({ suggestion: SUG })).toBe('t1');
    const upd = ops('agenda_suggestions', 'update')[0];
    expect(upd.filtros).toContainEqual(['eq', 'status', 'pending']);
    expect(ops('agenda_tasks', 'delete')).toEqual([]);
  });

  it('aceitar 2x: a segunda não acha pendente e APAGA a tarefa que acabou de criar', async () => {
    banco.respostas['agenda_tasks.insert'] = ok({ id: 't2' });
    banco.respostas['agenda_suggestions.update'] = ok([]);
    const m = hook(() => useAcceptSuggestion());
    await expect(m.mutateAsync({ suggestion: SUG })).rejects.toThrow('já foi decidida');
    const del = ops('agenda_tasks', 'delete');
    expect(del).toHaveLength(1);
    expect(del[0].filtros).toContainEqual(['eq', 'id', 't2']);
  });

  it('marcação que falha: a tarefa órfã é apagada', async () => {
    banco.respostas['agenda_tasks.insert'] = ok({ id: 't3' });
    banco.respostas['agenda_suggestions.update'] = falha('RLS');
    const m = hook(() => useAcceptSuggestion());
    await expect(m.mutateAsync({ suggestion: SUG })).rejects.toThrow('Não consegui marcar a sugestão como aceita (RLS). Nada foi criado.');
    expect(ops('agenda_tasks', 'delete')).toHaveLength(1);
  });

  it('descartar grava o motivo e só mexe na pendente', async () => {
    const m = hook(() => useDismissSuggestion());
    await m.mutateAsync({ id: 's1', reason: '  Já resolvido ' });
    const upd = ops('agenda_suggestions', 'update')[0];
    expect(upd.valores).toMatchObject({ status: 'dismissed', dismiss_reason: 'Já resolvido' });
    expect(upd.filtros).toContainEqual(['eq', 'status', 'pending']);
  });
});

describe('ordem de compra (4)', () => {
  it('excluir só rascunho: a gravação confere status = draft e recusa o que não apagou', async () => {
    banco.respostas['purchase_order_items.select'] = ok([{ received_qty: 0 }]);
    banco.respostas['purchase_orders.delete'] = ok([]);
    const m = hook(() => useDeletePurchaseOrder());
    await expect(m.mutateAsync('oc1')).rejects.toThrow('Só rascunho se exclui');
    expect(ops('purchase_orders', 'delete')[0].filtros).toContainEqual(['eq', 'status', 'draft']);
  });

  it('excluir com item recebido: nem tenta apagar', async () => {
    banco.respostas['purchase_order_items.select'] = ok([{ received_qty: 2 }]);
    const m = hook(() => useDeletePurchaseOrder());
    await expect(m.mutateAsync('oc1')).rejects.toThrow('já tem item recebido');
    expect(ops('purchase_orders', 'delete')).toEqual([]);
  });

  it('mudar a situação confere a situação que a tela viu', async () => {
    banco.respostas['purchase_orders.update'] = ok([]);
    const m = hook(() => useUpdatePurchaseOrder());
    await expect(m.mutateAsync({ id: 'oc1', status: 'cancelled', statusEsperado: 'sent' })).rejects.toThrow('mudou de situação');
    const upd = ops('purchase_orders', 'update')[0];
    expect(upd.valores).toEqual({ status: 'cancelled' });
    expect(upd.filtros).toContainEqual(['eq', 'status', 'sent']);
  });
});

// Achados laterais do histórico de documentos (audit/novos-achados.md), corrigidos em 20/11/2026 — a parte da tela:
//   NOVO-historico-01: aplicar o preço do fornecedor (useApplyQuotePrice) num material de texto livre grava o total da linha
//                      LÍQUIDO do desconto dela (preço × qtd − desconto), a conta de useUpdateServiceOrderService.
//   NOVO-historico-06: a remoção de peça/serviço recusada (total abaixo do já pago) devolve a linha com o MESMO id.
// (O NOVO-historico-05, duplicar, está em use-service-orders.duplicar.test.tsx.) Banco falso; dado sintético.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const h = vi.hoisted(() => {
  const estado = {
    /** O que cada tabela devolve no select(...).eq(...).single() */
    linha: {} as Record<string, Record<string, unknown>>,
    inserts: [] as Array<[string, unknown]>,
    updates: [] as Array<[string, unknown]>,
    deletes: [] as string[],
  };
  const from = (tabela: string) => {
    const q: any = {};
    q.select = () => q;
    q.eq = () => q;
    q.single = async () => ({ data: estado.linha[tabela] ?? null, error: null });
    q.maybeSingle = async () => ({ data: tabela === 'app_settings' ? { value: 'on' } : null, error: null });
    q.update = (v: unknown) => { estado.updates.push([tabela, v]); return { eq: async () => ({ error: null }) }; };
    q.delete = () => { estado.deletes.push(tabela); return { eq: async () => ({ error: null }) }; };
    q.insert = async (v: unknown) => { estado.inserts.push([tabela, v]); return { data: null, error: null }; };
    return q;
  };
  const cascata = { bloqueiaUmaVez: true };
  return { estado, from, cascata };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (t: string) => h.from(t),
    rpc: async (nome: string) => (nome === 'calc_so_totals' ? { data: [{ grand_total: 100 }], error: null } : { data: null, error: null }),
  },
}));
vi.mock('@/lib/cascade-updates', () => ({
  cancelServiceOrderCascade: vi.fn(),
  reopenServiceOrder: vi.fn(),
  // A 1ª chamada recusa (o novo total ficaria abaixo do que o cliente já pagou); a do "desfazer" passa.
  updateReceivableFromSO: vi.fn(async () => {
    if (h.cascata.bloqueiaUmaVez) { h.cascata.bloqueiaUmaVez = false; throw new Error('O novo total fica abaixo do já pago'); }
  }),
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: vi.fn(async () => {}) }));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn(), warning: vi.fn() }) }));

import { useApplyQuotePrice } from './use-quote-requests';
import { useRemoveServiceOrderPart, useRemoveServiceOrderService } from './use-service-orders';

const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>{children}</QueryClientProvider>
);

beforeEach(() => {
  h.estado.linha = {};
  h.estado.inserts = [];
  h.estado.updates = [];
  h.estado.deletes = [];
  h.cascata.bloqueiaUmaVez = true;
});

describe('NOVO-historico-01: aplicar o preço do fornecedor num material de texto livre', () => {
  it('grava preço × qtd − desconto da linha (antes: preço × qtd)', async () => {
    h.estado.linha.service_order_services = { quantity: 2, discount_amount: 25 };
    const { result } = renderHook(() => useApplyQuotePrice(), { wrapper });
    result.current.mutate({ itemId: 'qi-1', unitPrice: 140, serviceOrderServiceId: 'svc-1', asSalePrice: true });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(h.estado.updates).toEqual([['service_order_services', { unit_price_snapshot: 140, line_total: 255 }]]);
  });

  it('sem desconto na linha: preço × qtd, arredondado a centavos', async () => {
    h.estado.linha.service_order_services = { quantity: 3, discount_amount: 0 };
    const { result } = renderHook(() => useApplyQuotePrice(), { wrapper });
    result.current.mutate({ itemId: 'qi-1', unitPrice: 33.333, serviceOrderServiceId: 'svc-1', asSalePrice: true });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(h.estado.updates[0][1]).toMatchObject({ line_total: 100 });
  });

  it('desconto maior que o novo bruto: recusa e não grava', async () => {
    h.estado.linha.service_order_services = { quantity: 1, discount_amount: 80 };
    const { result } = renderHook(() => useApplyQuotePrice(), { wrapper });
    result.current.mutate({ itemId: 'qi-1', unitPrice: 50, serviceOrderServiceId: 'svc-1', asSalePrice: true });
    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(h.estado.updates).toEqual([]);
  });
});

describe('NOVO-historico-06: remoção recusada devolve a linha com o mesmo id', () => {
  it('peça', async () => {
    const linha = { id: 'peca-original', service_order_id: 'os1', product_id: 'p1', quantity: 2, unit_cost_snapshot: 10,
      unit_sale_snapshot: 30, line_total_cost: 20, line_total_sale: 50, discount_pct: 16.67, discount_amount: 10 };
    h.estado.linha.service_order_parts = linha;
    const { result } = renderHook(() => useRemoveServiceOrderPart(), { wrapper });
    result.current.mutate({ id: 'peca-original', service_order_id: 'os1', product_id: 'p1', quantity: 2, unit_cost_snapshot: 10 });
    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(h.estado.deletes).toEqual(['service_order_parts']);
    expect(h.estado.inserts).toEqual([['service_order_parts', linha]]);
  });

  it('serviço', async () => {
    const linha = { id: 'serv-original', service_order_id: 'os1', name_snapshot: 'Instalação', quantity: 1, unit_price_snapshot: 800,
      line_total: 720, discount_pct: 10, discount_amount: 80 };
    h.estado.linha.service_order_services = linha;
    const { result } = renderHook(() => useRemoveServiceOrderService(), { wrapper });
    result.current.mutate({ id: 'serv-original', service_order_id: 'os1' });
    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(h.estado.inserts).toEqual([['service_order_services', linha]]);
  });
});

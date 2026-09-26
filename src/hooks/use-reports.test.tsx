// O defeito da antiga "Gerenciais" (26/09/2026): em 30 dias, R$ 223 mil de orçamentos em
// rascunho entravam no "Top 10 clientes" e na margem. Agora só conta OS aprovada.
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const { tabelas } = vi.hoisted(() => ({
  tabelas: {
    payments: [] as unknown[],
    service_orders: [
      { id: 'os1', grand_total: 1000, parts_cost_total: 0, status: 'completed', payment_status: 'paid', client_id: 'c1', created_at: '2026-09-20', clients: { name: 'Marina Azul' } },
      { id: 'os2', grand_total: 500, parts_cost_total: 0, status: 'open', payment_status: 'unpaid', client_id: 'c2', created_at: '2026-09-21', clients: { name: 'Iate Clube' } },
      // Orçamento em rascunho (inclusive recusado) e OS cancelada: não são venda.
      { id: 'q1', grand_total: 221116.76, parts_cost_total: 0, status: 'draft', payment_status: 'unpaid', client_id: 'c3', created_at: '2026-09-22', clients: { name: 'Orçamento Grande' } },
      { id: 'x1', grand_total: 22463.63, parts_cost_total: 0, status: 'cancelled', payment_status: 'unpaid', client_id: 'c4', created_at: '2026-09-23', clients: { name: 'Cancelado' } },
    ],
    service_order_parts: [
      { line_total_cost: 100, service_order_id: 'os1', service_orders: { created_at: '2026-09-20', status: 'completed' } },
      { line_total_cost: 9000, service_order_id: 'q1', service_orders: { created_at: '2026-09-22', status: 'draft' } },
    ],
  } as Record<string, unknown[]>,
}));

vi.mock('@/integrations/supabase/client', () => {
  const builder = (tabela: string): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'gte', 'lte', 'order', 'in', 'is', 'not', 'limit', 'neq']) o[k] = () => o;
    o.then = (res: any) => Promise.resolve({ data: tabelas[tabela] ?? [], error: null }).then(res);
    return o;
  };
  return { supabase: { from: (t: string) => builder(t) } };
});

import { osAprovada, useRevenueReport } from './use-reports';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('critério da Operação: só OS aprovada', () => {
  it('rascunho e cancelada ficam fora; o resto do ciclo da OS conta', () => {
    expect(osAprovada('draft')).toBe(false);
    expect(osAprovada('cancelled')).toBe(false);
    expect(osAprovada(null)).toBe(false);
    for (const s of ['approved', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'completed', 'invoiced']) {
      expect(osAprovada(s), s).toBe(true);
    }
  });

  it('Top 10 clientes e margem não somam orçamento em rascunho nem OS cancelada', async () => {
    const { result } = renderHook(() => useRevenueReport(30), { wrapper });
    await waitFor(() => expect(result.current.data).toBeDefined());
    const d = result.current.data!;
    expect(d.topClients.map((c) => c.name)).toEqual(['Marina Azul', 'Iate Clube']);
    // 1.000 + 500 de OS aprovadas, menos só as peças delas (100) — a peça do rascunho não conta.
    expect(d.margin).toBe(1400);
  });
});

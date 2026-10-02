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
  // Aplica os filtros de igualdade e de "não é nulo": é por eles que o relatório separa
  // recebimento de baixa de conta a pagar. Os de data passam direto.
  const builder = (tabela: string): any => {
    const filtros: Array<(l: Record<string, unknown>) => boolean> = [];
    const o: any = {};
    for (const k of ['select', 'gte', 'lte', 'order', 'in', 'is', 'limit', 'neq']) o[k] = () => o;
    o.eq = (col: string, v: unknown) => { filtros.push((l) => l[col] === v); return o; };
    o.not = (col: string, op: string, v: unknown) => {
      if (op === 'is' && v === null) filtros.push((l) => l[col] != null);
      return o;
    };
    o.then = (res: any) => Promise.resolve({
      data: ((tabelas[tabela] ?? []) as Record<string, unknown>[]).filter((l) => filtros.every((f) => f(l))),
      error: null,
    }).then(res);
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

describe('recebimentos registrados: só baixa de conta a receber', () => {
  it('a baixa de uma conta a pagar não entra no recebido nem no gráfico do mês', async () => {
    // Antes de 02/10/2026 o relatório somava os dois: setembro mostrava R$ 16.952,19 com
    // R$ 13.447,99 recebidos e R$ 3.504,20 pagos a fornecedores.
    const hoje = new Date();
    const dia = `${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, '0')}-01`;
    tabelas.payments = [
      { amount: 300, payment_date: dia, status: 'confirmed', receivable_id: 'r1', payable_id: null },
      { amount: 200, payment_date: dia, status: 'confirmed', receivable_id: null, payable_id: 'p1' },
      { amount: 50, payment_date: dia, status: 'cancelled', receivable_id: 'r2', payable_id: null },
    ];
    try {
      const { result } = renderHook(() => useRevenueReport(30), { wrapper });
      await waitFor(() => expect(result.current.data).toBeDefined());
      const d = result.current.data!;
      expect(d.totalReceived).toBe(300);
      expect(d.monthlyRevenue.reduce((s, m) => s + m.value, 0)).toBe(300);
    } finally {
      tabelas.payments = [];
    }
  });
});

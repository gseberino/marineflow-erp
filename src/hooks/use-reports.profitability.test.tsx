// "Lucro por OS": desde 29/09/2026 o lucro da view desconta a mão de obra real das diárias, e desde
// 11/10/2026 o custo da HBR (hbr_cost); o custo da tela tem de somar as mesmas parcelas, senão
// custo + lucro deixa de fechar com o faturamento.
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { useProfitabilityReport } from './use-reports';

vi.mock('@/integrations/supabase/client', () => {
  const linhas = [
    { os_id: 'a', service_order_number: 'OS-1', client_name: 'Cliente', status: 'completed', created_at: '2026-09-20',
      revenue: 1000, parts_cost: 200, travel_cost: 50, operational_cost: 30, commission_cost: 20, labor_cost_real: 170,
      net_profit: 530, net_margin_percent: 53 },
    { os_id: 'b', service_order_number: 'OS-2', client_name: 'Cliente', status: 'invoiced', created_at: '2026-10-10',
      revenue: 1000, parts_cost: 200, travel_cost: 50, operational_cost: 30, commission_cost: 20, labor_cost_real: 170,
      hbr_cost: 40, net_profit: 490, net_margin_percent: 49 },
  ];
  const q: any = { select: () => q, gte: () => q, order: () => Promise.resolve({ data: linhas, error: null }) };
  return { supabase: { from: () => q } };
});

describe('useProfitabilityReport', () => {
  it('o custo inclui a mão de obra das diárias e fecha com faturamento − lucro', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
    const { result } = renderHook(() => useProfitabilityReport(30), { wrapper });
    await waitFor(() => expect(result.current.data).toBeDefined());
    const [linha] = result.current.data!.rows as Array<{ cost: number; labor: number; revenue: number; profit: number }>;
    expect(linha.labor).toBe(170);
    expect(linha.cost).toBe(470);
    expect(linha.revenue - linha.cost).toBe(linha.profit);
  });

  it('o custo inclui o custo da HBR (despesa não cobrada do cliente) e continua fechando', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
    const { result } = renderHook(() => useProfitabilityReport(30), { wrapper });
    await waitFor(() => expect(result.current.data).toBeDefined());
    const rows = result.current.data!.rows as Array<{ id: string; cost: number; hbr: number; revenue: number; profit: number }>;
    const semHbr = rows.find((r) => r.id === 'a')!;
    const comHbr = rows.find((r) => r.id === 'b')!;
    expect(semHbr.hbr).toBe(0);
    expect(comHbr.hbr).toBe(40);
    expect(comHbr.cost).toBe(510);
    expect(comHbr.revenue - comHbr.cost).toBe(comHbr.profit);
  });
});

// Duplicar OS: a despesa que nasceu de um comprovante do WhatsApp (origem_codigo "CMP-…", resposta 2 do
// dono, 11/10/2026) é o custo interno daquela OS — não é composição de outra e não se copia (copiada,
// nasceria faturável e viraria cobrança na OS nova). As lançadas à mão continuam sendo copiadas.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { useDuplicateServiceOrder } from './use-service-orders';

/** O que cada tabela recebeu em insert, na ordem. */
let gravacoes: Record<string, unknown[]> = {};
let fonte: Record<string, unknown> = {};

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: async () => ({ data: 42, error: null }),
    from: (tabela: string) => ({
      select: () => ({ eq: () => ({ single: async () => ({ data: fonte, error: null }) }) }),
      insert: (linhas: unknown) => {
        (gravacoes[tabela] ??= []).push(linhas);
        return Object.assign(Promise.resolve({ data: null, error: null }), {
          select: () => ({ single: async () => ({ data: { id: 'nova' }, error: null }) }),
        });
      },
    }),
  },
}));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) }));

const despesa = (o: Record<string, unknown>) => ({
  id: 'e', service_order_id: 'os1', category: 'Combustível e deslocamento', description: 'Gasolina', amount: 62,
  currency: 'BRL', paid_by: 'company', supplier_id: null, notes: null, billable_to_client: true, origem_codigo: null, ...o,
});

beforeEach(() => {
  gravacoes = {};
  fonte = {
    id: 'os1', service_order_number: 'OS-00112', status: 'completed', priority: 'normal', client_id: 'c1',
    service_order_parts: [], service_order_services: [],
    service_order_expenses: [
      despesa({ id: 'cmp', description: 'Posto Shell', billable_to_client: false, origem_codigo: 'CMP-00124' }),
      despesa({ id: 'manual', description: 'Frete da peça' }),
    ],
  };
});

const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>{children}</QueryClientProvider>
);

describe('duplicar OS', () => {
  it('copia a despesa lançada à mão e deixa de fora a que nasceu de comprovante', async () => {
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'order' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const copiadas = (gravacoes.service_order_expenses ?? []).flat() as Array<Record<string, unknown>>;
    expect(copiadas.map((e) => e.description)).toEqual(['Frete da peça']);
    expect(copiadas[0]).toMatchObject({ service_order_id: 'nova' });
  });

  it('só despesa de comprovante: nenhuma despesa é gravada na OS nova', async () => {
    fonte.service_order_expenses = [despesa({ id: 'cmp', billable_to_client: false, origem_codigo: 'CMP-00124' })];
    const { result } = renderHook(() => useDuplicateServiceOrder(), { wrapper });
    result.current.mutate({ sourceId: 'os1', mode: 'quote' });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(gravacoes.service_order_expenses).toBeUndefined();
    expect(gravacoes.service_orders).toHaveLength(1);
  });
});

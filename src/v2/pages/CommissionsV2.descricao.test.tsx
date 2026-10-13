// Aprovar a comissão GRAVA uma conta a pagar, e a descrição dela cita a OS pelo número, que já
// traz o prefixo ("OS-00060"). Até 12/10/2026 a descrição gravada seria "Comissão OS #OS-00060 -
// Roberto" (nenhuma foi gravada assim: não há comissão aprovada com esse texto no banco).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const banco = vi.hoisted(() => ({
  contasAPagar: [] as Array<Record<string, unknown>>,
  comissao: {
    id: 'com-1',
    amount: 120,
    percentage: 10,
    status: 'pending',
    created_at: '2026-10-10T12:00:00Z',
    app_users: { full_name: 'Roberto' },
    service_orders: { service_order_number: 'OS-00060', grand_total: 1200, status: 'completed' },
  },
}));

vi.mock('@/integrations/supabase/client', () => {
  const from = (tabela: string) => {
    if (tabela === 'payables') {
      return {
        insert: (linha: Record<string, unknown>) => {
          banco.contasAPagar.push(linha);
          return { select: () => ({ single: async () => ({ data: { id: 'pay-1' }, error: null }) }) };
        },
      };
    }
    // commissions: a lista e o update do status
    return {
      select: () => ({ order: async () => ({ data: [banco.comissao], error: null }) }),
      update: () => ({ eq: async () => ({ error: null }) }),
    };
  };
  return { supabase: { from } };
});
vi.mock('@/i18n', () => ({
  useI18n: () => ({ formatCurrency: (n: number) => `R$ ${n}`, formatDate: (d: string) => d }),
}));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {} } }));

import { PainelDeComissoes } from './CommissionsV2';

beforeEach(() => {
  banco.contasAPagar = [];
});

describe('PainelDeComissoes — descrição da conta a pagar sem "OS #" repetido', () => {
  it('aprovar grava "Comissão OS-00060 - Roberto"', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <PainelDeComissoes />
      </QueryClientProvider>,
    );
    const [aprovar] = await screen.findAllByRole('button', { name: /Aprovar/ });
    fireEvent.click(aprovar);
    await waitFor(() => expect(banco.contasAPagar).toHaveLength(1));
    expect(banco.contasAPagar[0].description).toBe('Comissão OS-00060 - Roberto');
    expect(String(banco.contasAPagar[0].description)).not.toContain('OS #');
  });
});

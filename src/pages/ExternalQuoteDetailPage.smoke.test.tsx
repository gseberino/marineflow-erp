// Detalhe do orçamento externo: nenhum botão morto. O "Falar com Financeiro" não tinha onClick
// (nem destino definido: contato ou fila do financeiro) — clicar não fazia nada.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import ExternalQuoteDetailPage from './ExternalQuoteDetailPage';

const orcamento = {
  id: 'abcdef12-0000-0000-0000-000000000000', status: 'approved', created_at: '2026-10-01T12:00:00Z',
  parts: [{ id: 'p1', name_snapshot: 'Impelidor', quantity: 1, line_total_sale: 120, unit_sale_snapshot: 120, product_id: 'x' }],
  services: [], discount_amount: 0, grand_total: 120, rejection_reason: null,
  client: { name: 'Marcelo', phone: '1199' }, lead: null, vessel: null, converted_service_order_id: null,
};

vi.mock('@/hooks/use-external-quotes', () => ({
  useExternalQuote: () => ({ data: orcamento, isLoading: false, refetch: vi.fn() }),
  useUpdateExternalQuoteStatus: () => ({ mutate: vi.fn(), isPending: false }),
}));
vi.mock('@/components/agenda/EntityTasksPanel', () => ({ EntityTasksPanel: () => null }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: vi.fn() } }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn() } }));

describe('ExternalQuoteDetailPage', () => {
  it('sem o "Falar com Financeiro" que não fazia nada; o "Gerar Ordem de Serviço" continua', () => {
    render(
      <MemoryRouter initialEntries={[`/v2/external-quotes/${orcamento.id}`]}>
        <Routes><Route path="/v2/external-quotes/:id" element={<ExternalQuoteDetailPage />} /></Routes>
      </MemoryRouter>,
    );
    expect(screen.getByText('Impelidor')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Falar com Financeiro/ })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Gerar Ordem de Serviço/ })).toBeEnabled();
  });
});

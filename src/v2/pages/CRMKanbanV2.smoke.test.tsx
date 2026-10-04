// Smoke do funil do CRM (04/10/2026): o botão que avança a etapa do cartão agia num clique —
// "Converter em OS" troca ORÇ→OS e "Concluir" lança as contas a receber. Agora pergunta antes,
// dizendo o que o passo faz, e só muda o status no "Confirmar".
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import CRMKanbanV2 from './CRMKanbanV2';

const { mudarStatus, ordens } = vi.hoisted(() => ({
  mudarStatus: vi.fn(),
  ordens: [
    {
      id: 'os1', service_order_number: 'OS-00050', status: 'in_progress', grand_total: 1500,
      scheduled_start_at: null, created_at: '2026-10-01T12:00:00Z', share_token: null,
      clients: { id: 'c1', name: 'Marina Azul', phone: null, whatsapp: null }, vessels: { name: 'Veleiro Sol' },
    },
  ],
}));

vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrders: () => ({ data: ordens, isLoading: false }),
  useUpdateServiceOrderStatus: () => ({ mutateAsync: mudarStatus, isPending: false }),
}));
vi.mock('@/components/SendViaWhatsAppDialog', () => ({ SendViaWhatsAppDialog: () => null }));

function renderFunil() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={['/v2/crm']}>
          <CRMKanbanV2 />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('CRMKanbanV2 — avançar etapa', () => {
  beforeEach(() => mudarStatus.mockReset());

  it('"Concluir" pergunta antes e diz que lança as contas a receber', async () => {
    renderFunil();
    await userEvent.click(screen.getByRole('button', { name: /Concluir/ }));
    expect(await screen.findByText('Concluir — #OS-00050?')).toBeInTheDocument();
    expect(screen.getByText(/contas a receber das parcelas são lançadas/)).toBeInTheDocument();
    expect(mudarStatus).not.toHaveBeenCalled();

    await userEvent.click(screen.getByRole('button', { name: 'Voltar' }));
    expect(mudarStatus).not.toHaveBeenCalled();
  });

  it('só muda o status no confirmar', async () => {
    renderFunil();
    await userEvent.click(screen.getByRole('button', { name: /Concluir/ }));
    await userEvent.click(await screen.findByRole('button', { name: 'Concluir' }));
    expect(mudarStatus).toHaveBeenCalledWith({ id: 'os1', status: 'completed' });
  });
});

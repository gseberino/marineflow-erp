import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import ServiceOrderList from './ServiceOrderList';

// --- Mocks ---
const mockOrders = [
  {
    id: 'so-1',
    service_order_number: 'OS-001',
    status: 'open',
    priority: 'normal',
    service_type: 'maintenance',
    grand_total: 1500,
    share_token: 'token-abc-123',
    scheduled_start_at: null,
    clients: { name: 'Cliente Alpha', phone: '11999998888', whatsapp: '' },
    vessels: { name: 'Barco Alpha' },
  },
  {
    id: 'so-2',
    service_order_number: 'OS-002',
    status: 'in_progress',
    priority: 'high',
    service_type: 'repair',
    grand_total: 3200,
    share_token: 'token-def-456',
    scheduled_start_at: null,
    clients: { name: 'Cliente Beta', phone: '', whatsapp: '11977776666' },
    vessels: { name: 'Barco Beta' },
  },
  {
    id: 'so-3',
    service_order_number: 'OS-003',
    status: 'open',
    priority: 'low',
    service_type: 'inspection',
    grand_total: 500,
    share_token: null, // sem token => itens Z-API + wa.me desabilitados
    scheduled_start_at: null,
    clients: { name: 'Cliente Gama', phone: '11955554444', whatsapp: '' },
    vessels: { name: 'Barco Gama' },
  },
];

vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrders: () => ({ data: mockOrders, isLoading: false, error: null }),
}));

vi.mock('@/hooks/use-pdf', () => ({
  usePDFData: () => ({ data: null }),
}));

vi.mock('@/hooks/use-whatsapp-send-log', () => ({
  useWhatsAppSendStatusMap: () => ({ data: new Map() }),
  useWhatsAppSendHistory: () => ({ data: [], isLoading: false }),
}));

vi.mock('@/hooks/use-audit-log', () => ({
  writeAuditLog: vi.fn().mockResolvedValue(undefined),
}));

const recordWhatsAppEventMock = vi.fn();
vi.mock('@/lib/diagnostics', () => ({
  recordWhatsAppEvent: (...args: any[]) => recordWhatsAppEventMock(...args),
}));

vi.mock('sonner', () => ({
  toast: { error: vi.fn(), success: vi.fn() },
}));

vi.mock('@/i18n', () => ({
  useI18n: () => ({
    t: {
      serviceOrders: {
        title: 'OS', description: '', newOrder: 'Nova', searchPlaceholder: 'Buscar',
        allStatuses: 'Todos', orderNumber: 'Nº', client: 'Cliente', vessel: 'Embarcação',
        priority: 'Prioridade', scheduled: 'Agendado',
      },
      common: { status: 'Status', type: 'Tipo', total: 'Total', noResults: 'Sem resultados' },
      status: { open: 'Aberto', in_progress: 'Em andamento' },
      priority: { normal: 'Normal', high: 'Alta', low: 'Baixa' },
      serviceType: { maintenance: 'Manutenção', repair: 'Reparo', inspection: 'Inspeção' },
    },
    formatCurrency: (n: number) => `R$ ${n}`,
    formatDate: (d: string) => d,
  }),
}));

vi.mock('@/components/PDFOptionsDialog', () => ({
  PDFOptionsDialog: () => null,
}));

vi.mock('@/components/WhatsAppSendHistoryDialog', () => ({
  WhatsAppSendHistoryDialog: () => null,
}));

vi.mock('@/components/SendViaZAPIDialog', () => ({
  SendViaZAPIDialog: () => null,
}));

function renderList() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <ServiceOrderList />
      </MemoryRouter>
    </QueryClientProvider>
  );
}

describe('ServiceOrderList — Envio via WhatsApp / Z-API', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('exibe os itens de envio (wa.me, OS Z-API, Orçamento Z-API) habilitados quando há share_token e desabilitados quando não há', async () => {
    const user = userEvent.setup();
    renderList();

    for (const so of mockOrders) {
      const numberCell = await screen.findByText(so.service_order_number);
      const row = numberCell.closest('tr')!;
      // O último botão da linha é o trigger do dropdown (MoreHorizontal)
      const buttons = within(row).getAllByRole('button');
      const trigger = buttons[buttons.length - 1];
      await user.click(trigger);

      const waItem = await screen.findByRole('menuitem', { name: /Enviar via wa\.me/i });
      const osZapiItem = await screen.findByRole('menuitem', { name: /Enviar OS via Z-API/i });
      const quoteZapiItem = await screen.findByRole('menuitem', { name: /Enviar Orçamento via Z-API/i });

      if (so.share_token) {
        expect(waItem).not.toHaveAttribute('data-disabled');
        expect(osZapiItem).not.toHaveAttribute('data-disabled');
        expect(quoteZapiItem).not.toHaveAttribute('data-disabled');
      } else {
        expect(waItem).toHaveAttribute('data-disabled');
        expect(osZapiItem).toHaveAttribute('data-disabled');
        expect(quoteZapiItem).toHaveAttribute('data-disabled');
      }

      await user.keyboard('{Escape}');
      await waitFor(() =>
        expect(screen.queryByRole('menuitem', { name: /Enviar OS via Z-API/i })).not.toBeInTheDocument()
      );
    }
  });

  it('abre wa.me com telefone normalizado e URL pública ao clicar em "Enviar via wa.me"', async () => {
    const user = userEvent.setup();
    const openSpy = vi.spyOn(window, 'open').mockReturnValue({} as Window);

    renderList();

    const numberCell = await screen.findByText('OS-001');
    const row = numberCell.closest('tr')!;
    const buttons = within(row).getAllByRole('button');
    await user.click(buttons[buttons.length - 1]);

    const item = await screen.findByRole('menuitem', { name: /Enviar via wa\.me/i });
    await user.click(item);

    expect(openSpy).toHaveBeenCalledTimes(1);
    const [url, target] = openSpy.mock.calls[0];
    expect(target).toBe('_blank');
    expect(url).toMatch(/^https:\/\/wa\.me\/5511999998888\?text=/);
    expect(decodeURIComponent(String(url))).toContain('/view/token-abc-123');
    expect(decodeURIComponent(String(url))).toContain('OS-001');

    openSpy.mockRestore();
  });

  it('prefere whatsapp ao invés de phone quando ambos existem', async () => {
    const user = userEvent.setup();
    const openSpy = vi.spyOn(window, 'open').mockReturnValue({} as Window);

    renderList();

    const numberCell = await screen.findByText('OS-002');
    const row = numberCell.closest('tr')!;
    const buttons = within(row).getAllByRole('button');
    await user.click(buttons[buttons.length - 1]);

    const item = await screen.findByRole('menuitem', { name: /Enviar via wa\.me/i });
    await user.click(item);

    const [url] = openSpy.mock.calls[0];
    expect(url).toMatch(/^https:\/\/wa\.me\/5511977776666\?text=/);

    openSpy.mockRestore();
  });
});

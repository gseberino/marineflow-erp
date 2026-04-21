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
    clients: { full_name_or_company_name: 'Cliente Alpha', phone: '11999998888', whatsapp: '' },
    vessels: { boat_name: 'Barco Alpha' },
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
    clients: { full_name_or_company_name: 'Cliente Beta', phone: '', whatsapp: '11977776666' },
    vessels: { boat_name: 'Barco Beta' },
  },
  {
    id: 'so-3',
    service_order_number: 'OS-003',
    status: 'open',
    priority: 'low',
    service_type: 'inspection',
    grand_total: 500,
    share_token: null, // no token => disabled
    scheduled_start_at: null,
    clients: { full_name_or_company_name: 'Cliente Gama', phone: '11955554444', whatsapp: '' },
    vessels: { boat_name: 'Barco Gama' },
  },
];

vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrders: () => ({ data: mockOrders, isLoading: false, error: null }),
}));

vi.mock('@/hooks/use-pdf', () => ({
  usePDFData: () => ({ data: null }),
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

describe('ServiceOrderList — Enviar por WhatsApp', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows the WhatsApp item enabled for every OS with a share_token and disabled when missing', async () => {
    const user = userEvent.setup();
    renderList();

    // Iterate through each order row and open its dropdown
    for (const so of mockOrders) {
      const numberCell = await screen.findByText(so.service_order_number);
      const row = numberCell.closest('tr')!;
      const trigger = within(row).getByRole('button');
      await user.click(trigger);

      const item = await screen.findByRole('menuitem', { name: /Enviar por WhatsApp/i });
      expect(item).toBeInTheDocument();

      if (so.share_token) {
        expect(item).not.toHaveAttribute('data-disabled');
      } else {
        expect(item).toHaveAttribute('data-disabled');
      }

      // Close menu before next iteration
      await user.keyboard('{Escape}');
      await waitFor(() =>
        expect(screen.queryByRole('menuitem', { name: /Enviar por WhatsApp/i })).not.toBeInTheDocument()
      );
    }
  });

  it('opens the correct wa.me link with normalized phone and public URL on click', async () => {
    const user = userEvent.setup();
    const openSpy = vi.spyOn(window, 'open').mockReturnValue({} as Window);

    renderList();

    const numberCell = await screen.findByText('OS-001');
    const row = numberCell.closest('tr')!;
    await user.click(within(row).getByRole('button'));

    const item = await screen.findByRole('menuitem', { name: /Enviar por WhatsApp/i });
    await user.click(item);

    expect(openSpy).toHaveBeenCalledTimes(1);
    const [url, target] = openSpy.mock.calls[0];
    expect(target).toBe('_blank');
    expect(url).toMatch(/^https:\/\/wa\.me\/5511999998888\?text=/);
    expect(decodeURIComponent(String(url))).toContain('/view/token-abc-123');
    expect(decodeURIComponent(String(url))).toContain('OS-001');

    expect(recordWhatsAppEventMock).toHaveBeenCalledWith(
      expect.objectContaining({
        source: 'list_dropdown',
        action: 'send',
        serviceOrderId: 'so-1',
        serviceOrderNumber: 'OS-001',
        shareToken: 'token-abc-123',
        opened: true,
      })
    );

    openSpy.mockRestore();
  });

  it('prefers whatsapp over phone when both are available', async () => {
    const user = userEvent.setup();
    const openSpy = vi.spyOn(window, 'open').mockReturnValue({} as Window);

    renderList();

    const numberCell = await screen.findByText('OS-002');
    const row = numberCell.closest('tr')!;
    await user.click(within(row).getByRole('button'));

    const item = await screen.findByRole('menuitem', { name: /Enviar por WhatsApp/i });
    await user.click(item);

    const [url] = openSpy.mock.calls[0];
    expect(url).toMatch(/^https:\/\/wa\.me\/5511977776666\?text=/);

    openSpy.mockRestore();
  });
});

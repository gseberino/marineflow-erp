// Aba Cobranças (dono, 26/11/2026: "1. A"): o WhatsApp da linha ENVIAVA no clique, sem prévia nem trava. Agora abre a
// cobrança do cliente com a conferência da ficha; cobrança sem cliente do cadastro, paga ou cancelada não cobra; e a
// "Régua" (que gravava configurações que nenhuma rotina lê) saiu, com o texto que prometia lembrete automático.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { PainelDeCobrancas } from './CollectionsV2';

const cobranca = (id: string, extra: Record<string, unknown> = {}) => ({
  id, client_id: `cli-${id}`, status: 'overdue', amount: 1000, due_date: '2026-10-10', created_at: '2026-10-01T12:00:00Z',
  client: { name: `Cliente ${id}`, phone: null, whatsapp: '47999990000' }, service_order: { service_order_number: `OS-000${id}` },
  service_order_id: null, receivable_id: null, phone: null, contact_whatsapp: null, last_contact_at: null, ...extra,
});

vi.mock('@/hooks/use-collections', () => ({
  useCollections: () => ({
    isLoading: false,
    data: [
      cobranca('1'),
      cobranca('2', { client_id: null, client: null, contact_name: 'Contato avulso' }),
      cobranca('3', { status: 'paid' }),
    ],
  }),
  useMarkOverdueCollections: () => ({ mutate: vi.fn() }),
  useCancelCollection: () => ({ mutate: vi.fn(), isPending: false }),
}));
vi.mock('@/hooks/use-clients', () => ({ useClients: () => ({ data: [] }) }));
vi.mock('@/components/collections/CreateCollectionDialog', () => ({ CreateCollectionDialog: () => null }));
vi.mock('@/components/collections/PaymentConfirmDialog', () => ({ PaymentConfirmDialog: () => null }));
vi.mock('@/components/collections/AddContactDialog', () => ({ AddContactDialog: () => null }));
vi.mock('@/components/collections/EditContactDialog', () => ({ EditContactDialog: () => null }));
vi.mock('@/components/collections/CollectionDetailSheet', () => ({ CollectionDetailSheet: () => null }));
vi.mock('@/components/client/CobrarClienteDialog', () => ({
  CobrarClienteDialog: ({ clienteId }: { clienteId: string | null }) => (clienteId ? <div data-testid="cobrar-cliente">cobrar {clienteId}</div> : null),
}));

describe('Aba Cobranças — cobrar com a conferência da ficha', () => {
  it('o ícone da linha abre a cobrança do cliente (não envia); sem cliente do cadastro ou paga, o botão fica travado', async () => {
    const user = userEvent.setup();
    render(<PainelDeCobrancas />);
    const icones = screen.getAllByRole('button', { name: 'Cobrar o cliente pelo WhatsApp' });
    expect(icones).toHaveLength(3);
    expect(icones[0]).toBeEnabled();
    expect(icones[1]).toBeDisabled();
    expect(icones[1]).toHaveAttribute('title', expect.stringContaining('não está ligada a um cliente do cadastro'));
    expect(icones[2]).toBeDisabled();
    await user.click(icones[0]);
    expect(screen.getByTestId('cobrar-cliente')).toHaveTextContent('cobrar cli-1');
  });

  it('no celular, "Cobrar" só aparece na cobrança que dá para cobrar', () => {
    render(<PainelDeCobrancas />);
    expect(screen.getAllByRole('button', { name: /^Cobrar$/ })).toHaveLength(1);
  });

  it('sem "Régua" e sem a promessa de lembrete automático', () => {
    render(<PainelDeCobrancas />);
    expect(screen.queryByRole('button', { name: /Régua/ })).toBeNull();
    expect(screen.queryByText(/régua automática/)).toBeNull();
    expect(screen.getByText(/cobrar abre a mensagem e as travas antes de enviar/)).toBeInTheDocument();
  });
});

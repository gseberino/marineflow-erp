// Smoke test de RENDER da entrada de mercadoria por XML.
//
// Existe por duas lições caras deste repo, ambas de erro que passa por tsc e build:
//  - 24/07: TDZ derrubou a AgendaPage em produção;
//  - 04/08: React #310 derrubou a tela de cotação, porque um hook foi declarado
//    depois de um `return` antecipado. O smoke daquela tela existia e NÃO pegou,
//    porque o mock entregava os dados prontos e a transição carregando→carregado
//    nunca acontecia. Aqui ela é exercitada de propósito.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import ImportFiscalXML from './ImportFiscalXML';

const { ctrl, notas, ordensServico } = vi.hoisted(() => {
  const ctrl = { loading: false };
  const notas = [
    {
      id: 'n1', nfe_number: '34395', nfe_key: '4'.repeat(44),
      issuer_name: 'KAMELL COMERCIO GLOBAL LTDA', total_value: 11638.67,
      status: 'confirmed', confirmed_at: '2026-07-23T13:18:43Z',
      created_at: '2026-07-23T13:00:00Z', issue_date: '2026-07-20T00:00:00Z',
      supplier_id: 's1', purchase_order_id: null, items: [],
    },
  ];
  const ordensServico = [
    { id: 'so1', number: 'OS-00051', status: 'awaiting_parts', clientName: 'Cliente Alpha' },
    { id: 'so2', number: 'OS-00060', status: 'in_progress', clientName: 'Cliente Beta' },
  ];
  return { ctrl, notas, ordensServico };
});

vi.mock('@/hooks/use-suppliers', () => ({
  useSuppliers: () => ({ data: [{ id: 's1', name: 'Kamell', cnpj: '123' }] }),
}));
vi.mock('@/hooks/use-products', () => ({
  useProducts: () => ({ data: [{ id: 'p1', name: 'Cabo 70mm', sku: 'C70', active: true }] }),
}));
vi.mock('@/hooks/use-purchase-orders', () => ({
  usePurchaseOrders: () => ({ data: [] }),
  usePurchaseOrder: () => ({ data: null }),
  PO_STATUS_LABELS: { draft: 'Rascunho', sent: 'Enviada ao fornecedor', partial: 'Parcial', received: 'Recebida', cancelled: 'Cancelada' },
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: async () => {} }));

// O vínculo com a OS — o que esta alteração acrescentou à tela.
vi.mock('@/hooks/use-note-service-orders', () => ({
  useServiceOrdersForLinking: () => ({ data: ordensServico }),
  useNfeServiceOrderSuggestions: () => ({ data: {} }),
  useLinkNoteItemsToServiceOrders: () => ({ mutateAsync: async () => ({ vinculados: 0 }), isPending: false }),
}));

vi.mock('@/integrations/supabase/client', () => {
  const builder = () => {
    const o: any = {};
    for (const m of ['select', 'eq', 'in', 'order', 'limit', 'update', 'insert', 'is', 'not']) {
      o[m] = () => o;
    }
    o.maybeSingle = async () => ({ data: null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: any) =>
      Promise.resolve({ data: ctrl.loading ? [] : notas, error: null }).then(res);
    return o;
  };
  return {
    supabase: {
      from: () => builder(),
      rpc: async () => ({ data: {}, error: null }),
      auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
      storage: { from: () => ({ upload: async () => ({ data: null, error: null }) }) },
    },
  };
});

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={['/inventory/import-xml']}>
          <ImportFiscalXML />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('entrada de mercadoria por XML', () => {
  it('renderiza a tela sem derrubar a árvore', async () => {
    wrap();
    expect((await screen.findAllByText(/Entrada de Mercadoria|Importar XML|XML/i)).length).toBeGreaterThan(0);
  });

  it('sobrevive à transição de carregando para carregado (React #310)', async () => {
    ctrl.loading = true;
    try {
      const { rerender } = wrap();
      ctrl.loading = false;
      rerender(
        <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
          <I18nProvider>
            <MemoryRouter initialEntries={['/inventory/import-xml']}>
              <ImportFiscalXML />
            </MemoryRouter>
          </I18nProvider>
        </QueryClientProvider>,
      );
      expect((await screen.findAllByText(/Entrada de Mercadoria|Importar XML|XML/i)).length).toBeGreaterThan(0);
    } finally {
      ctrl.loading = false;
    }
  });
});

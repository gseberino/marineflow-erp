// Smoke de render do detalhe da Ordem de Compra.
//
// Protege três coisas que só aparecem no render (tsc e build passam com elas quebradas):
// 1. As abas TROCAM DE PAINEL, não de rota — foi exatamente esse o bug que sumiu com a
//    tela inteira no Financeiro v2 e virou o teste vizinho.
// 2. O aviso de "recebida sem entrada" aparece quando o status mente. Duas OCs reais
//    estavam assim em 29/08/2026 (status 'received', zero itens recebidos, zero
//    movimento de estoque), por causa do menu de status da lista.
// 3. Nenhum hook depois dos returns antecipados (React #310): a tela em branco só
//    reproduz montando de verdade, e o contador do histórico é o candidato natural.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import PurchaseOrderDetailV2 from './PurchaseOrderDetailV2';

const { navigateMock } = vi.hoisted(() => ({ navigateMock: vi.fn() }));

vi.mock('react-router-dom', async (importOriginal) => {
  const real = await importOriginal<typeof import('react-router-dom')>();
  return { ...real, useNavigate: () => navigateMock, useParams: () => ({ id: 'po-1' }) };
});

const ocBase = {
  id: 'po-1',
  po_number: 'OC-00042',
  status: 'sent' as const,
  supplier_id: 's-1',
  service_order_id: 'so-1',
  expected_date: '2026-09-10',
  received_date: null,
  notes: null,
  total_amount: 1500,
  created_by: 'sistema',
  created_at: '2026-08-01T12:00:00Z',
  updated_at: '2026-08-01T12:00:00Z',
  suppliers: { name: 'Fornecedor Teste' },
  service_orders: { service_order_number: 'OS-00013' },
  purchase_order_items: [
    { id: 'i-1', purchase_order_id: 'po-1', product_id: 'p-1', description: 'Bateria 220Ah',
      quantity: 3, unit_cost: 500, received_qty: 0, created_at: '2026-08-01T12:00:00Z',
      products: { name: 'Bateria 220Ah', sku: 'BAT-220' } },
  ],
};

const poMock = vi.hoisted(() => ({ current: null as any }));

vi.mock('@/hooks/use-purchase-orders', () => ({
  usePurchaseOrder: () => ({ data: poMock.current, isLoading: false }),
  useReceivePO: () => ({ mutateAsync: vi.fn(), isPending: false }),
  PO_STATUS_LABELS: { draft: 'Rascunho', sent: 'Enviada', partial: 'Parcial', received: 'Recebida', cancelled: 'Cancelada' },
  PO_STATUS_COLORS: { draft: '', sent: '', partial: '', received: '', cancelled: '' },
}));

vi.mock('@/hooks/use-audit-log', () => ({ useRecordHistory: () => ({ data: [] }) }));
vi.mock('@/components/agenda/EntityTasksPanel', () => ({
  EntityTasksPanel: () => <div>painel-de-tarefas</div>,
}));
vi.mock('@/components/RecordHistory', () => ({ RecordHistory: () => <div>historico</div> }));

const wrap = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <I18nProvider>
        <MemoryRouter><PurchaseOrderDetailV2 /></MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );

describe('PurchaseOrderDetailV2 — smoke de render', () => {
  it('mostra a OC, o fornecedor e o progresso de recebimento', () => {
    poMock.current = ocBase;
    wrap();
    expect(screen.getAllByText('OC-00042').length).toBeGreaterThan(0);
    expect(screen.getByText(/Fornecedor Teste/)).toBeTruthy();
    expect(screen.getByText('0 de 3')).toBeTruthy();
    // com item faltando e OC não cancelada, o caminho honesto de recebimento existe
    expect(screen.getByRole('button', { name: /Receber/ })).toBeTruthy();
  });

  it('as abas trocam de painel, não de rota', async () => {
    poMock.current = ocBase;
    wrap();
    navigateMock.mockClear();
    await userEvent.click(screen.getByRole('tab', { name: /Tarefas/ }));
    expect(screen.getByText('painel-de-tarefas')).toBeTruthy();
    await userEvent.click(screen.getByRole('tab', { name: /Histórico/ }));
    expect(screen.getByText('historico')).toBeTruthy();
    expect(navigateMock).not.toHaveBeenCalled();
  });

  it('denuncia OC marcada como recebida sem nenhuma entrada', () => {
    poMock.current = { ...ocBase, status: 'received' as const };
    wrap();
    expect(screen.getByText(/Marcada como recebida, mas nada foi dado como entrada/)).toBeTruthy();
  });

  it('não denuncia quando o recebimento é real', () => {
    poMock.current = {
      ...ocBase,
      status: 'received' as const,
      purchase_order_items: [{ ...ocBase.purchase_order_items[0], received_qty: 3 }],
    };
    wrap();
    expect(screen.queryByText(/nada foi dado como entrada/)).toBeNull();
    expect(screen.getByText('3 de 3')).toBeTruthy();
  });

  it('OC inexistente não quebra a tela', () => {
    poMock.current = null;
    wrap();
    expect(screen.getByText(/Ordem de compra não encontrada/)).toBeTruthy();
  });
});

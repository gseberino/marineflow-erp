// Smoke test de RENDER das telas de compras.
// Existe pela lição de 24/07/2026: um erro de TDZ derrubou uma página inteira em
// produção e passou por tsc + vite build. Compilar não basta — renderizar pega.
// Aqui também valida o que o comparativo deve MOSTRAR: melhor pacote, desvio da
// média e o total da cesta dividida entre fornecedores.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import QuoteRequestsPage from './QuoteRequestsPage';
import QuoteRequestDetailPage from './QuoteRequestDetailPage';
import PurchasingHubPage from './PurchasingHubPage';

const SUP_A = 'sup-a';
const SUP_B = 'sup-b';

const { quote, suppliers, mut } = vi.hoisted(() => {
  const daysAgo = (n: number) => new Date(Date.now() - n * 86400000).toISOString();
  const items = [
    { id: 'i1', quote_request_id: 'q1', position: 1, description: 'Fusível MIDI 200A', quantity: 6, product_id: 'p1', service_order_part_id: 'part-1', service_order_service_id: null },
    { id: 'i2', quote_request_id: 'q1', position: 2, description: 'Cabo 70mm² vermelho', quantity: 2, product_id: null, service_order_part_id: null, service_order_service_id: null },
  ];
  const responses = [
    { id: 'r1', quote_request_id: 'q1', supplier_id: 'sup-a', quote_request_item_id: 'i1', unit_price: 100, lead_time_days: 3, source: 'text', source_excerpt: null, confirmed: false, created_at: daysAgo(1) },
    { id: 'r2', quote_request_id: 'q1', supplier_id: 'sup-b', quote_request_item_id: 'i1', unit_price: 200, lead_time_days: 7, source: 'manual', source_excerpt: null, confirmed: false, created_at: daysAgo(1) },
    { id: 'r3', quote_request_id: 'q1', supplier_id: 'sup-a', quote_request_item_id: 'i2', unit_price: 300, lead_time_days: 5, source: 'text', source_excerpt: null, confirmed: false, created_at: daysAgo(1) },
    { id: 'r4', quote_request_id: 'q1', supplier_id: 'sup-b', quote_request_item_id: 'i2', unit_price: 150, lead_time_days: 4, source: 'text', source_excerpt: null, confirmed: false, created_at: daysAgo(1) },
  ];
  const quote = {
    id: 'q1', code: 'COT-00001', service_order_id: 'so-1', status: 'open',
    sent_supplier_ids: ['sup-a', 'sup-b'], notes: 'Sistema elétrico LiFePO4',
    created_at: daysAgo(10), updated_at: daysAgo(1), closed_at: null,
    service_orders: { service_order_number: 'OS-00061', clients: { name: 'Cliente Alpha' } },
    quote_request_items: items,
    quote_responses: responses,
  };
  const suppliers = [
    { id: 'sup-a', name: 'Anderson Eletrônica', phone: '11999999999' },
    { id: 'sup-b', name: 'Souper Peças', phone: '11888888888' },
  ];
  const mut = () => ({ mutate: () => {}, mutateAsync: async () => ({}), isPending: false });
  return { quote, suppliers, mut };
});

vi.mock('@/hooks/use-quote-requests', () => ({
  useQuoteRequests: () => ({ data: [quote], isLoading: false }),
  useQuoteRequest: () => ({ data: quote, isLoading: false }),
  useSOLinkedQuotes: () => ({ data: [quote], isLoading: false }),
  useCreateQuoteRequest: mut,
  useRecordQuoteResponse: mut,
  useApplyQuotePrice: mut,
  useCreatePOsFromQuote: mut,
  useCloseQuoteRequest: mut,
  useReopenQuoteRequest: mut,
  QUOTE_STATUS_LABELS: { open: 'Aberta', closed: 'Fechada', cancelled: 'Cancelada' },
}));

vi.mock('@/hooks/use-suppliers', () => ({ useSuppliers: () => ({ data: suppliers }) }));

vi.mock('@/hooks/use-purchase-orders', () => ({
  usePurchaseOrders: () => ({ data: [], isLoading: false }),
  usePurchaseOrder: () => ({ data: null }),
  useCreatePOsFromShortages: mut,
  PO_STATUS_LABELS: { draft: 'Rascunho', sent: 'Enviada ao fornecedor', partial: 'Parcial', received: 'Recebida', cancelled: 'Cancelada' },
}));

vi.mock('@/integrations/supabase/client', () => {
  const builder = (): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'in', 'is', 'order', 'limit', 'gte', 'lte', 'not', 'filter']) {
      o[k] = () => o;
    }
    o.maybeSingle = async () => ({ data: null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: any) => Promise.resolve({ data: [], error: null }).then(res);
    return o;
  };
  return { supabase: { from: () => builder() } };
});

function wrap(ui: React.ReactNode, path = '/') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[path]}>{ui}</MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('lista de cotações', () => {
  it('renderiza a cotação com aging em dias úteis e contagem de respostas', async () => {
    wrap(<QuoteRequestsPage />);
    expect(await screen.findByText('COT-00001')).toBeInTheDocument();
    expect(screen.getByText(/OS-00061/)).toBeInTheDocument();
    // 10 dias corridos ⇒ 5+ dias úteis ⇒ atrasada
    expect(screen.getByText(/dias úteis — atrasada/)).toBeInTheDocument();
    expect(screen.getByText(/2 de 2 responderam/)).toBeInTheDocument();
  });

  it('mostra os indicadores do topo', async () => {
    wrap(<QuoteRequestsPage />);
    expect(await screen.findByText('Cotações abertas')).toBeInTheDocument();
    expect(screen.getByText('Sem resposta há 3+ dias')).toBeInTheDocument();
    expect(screen.getByText('Em negociação')).toBeInTheDocument();
  });
});

describe('mapa de cotação', () => {
  function renderDetail() {
    return wrap(
      <Routes>
        <Route path="/purchasing/quotes/:id" element={<QuoteRequestDetailPage />} />
      </Routes>,
      '/purchasing/quotes/q1',
    );
  }

  it('renderiza pacotes por fornecedor e marca o melhor', async () => {
    renderDetail();
    expect(await screen.findByText('COT-00001')).toBeInTheDocument();
    // O nome aparece no card do pacote E em cada oferta — por isso getAllByText.
    expect(screen.getAllByText('Anderson Eletrônica').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Souper Peças').length).toBeGreaterThan(0);
    // A: 100×6 + 300×2 = 1200 · B: 200×6 + 150×2 = 1500 ⇒ A é o melhor pacote
    expect(screen.getByText('melhor pacote')).toBeInTheDocument();
    expect(screen.getAllByText(/1\.200,00/).length).toBeGreaterThan(0);
  });

  it('mostra a economia de dividir a compra entre fornecedores', async () => {
    renderDetail();
    // melhor por linha: 100×6 + 150×2 = 900 ⇒ economiza 300 sobre o pacote único
    expect(await screen.findByText(/Dividindo a compra entre fornecedores/)).toBeInTheDocument();
    expect(screen.getAllByText(/900,00/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/300,00/).length).toBeGreaterThan(0);
  });

  it('sinaliza a oferta que desvia da média da linha', async () => {
    renderDetail();
    // Uma marca por linha, cada uma em um fornecedor diferente:
    //   item 1 → média de 100 e 200 = 150, o de 200 está 33% acima (Souper);
    //   item 2 → média de 300 e 150 = 225, o de 300 está 33% acima (Anderson).
    // Isso prova que o desvio é calculado POR LINHA e não no total do fornecedor.
    const marks = await screen.findAllByText(/33% acima da média/);
    expect(marks).toHaveLength(2);
  });

  it('escolher um item abre a barra de decisão com o total da cesta', async () => {
    renderDetail();
    const buttons = await screen.findAllByRole('button', { name: /escolher/i });
    await userEvent.click(buttons[0]);
    expect(await screen.findByText(/1 de 2 itens escolhidos/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Gerar ordem de compra/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Compra direta/i })).toBeInTheDocument();
  });

  it('mostra os itens do pedido, inclusive o de texto livre', async () => {
    renderDetail();
    expect(await screen.findByText(/Fusível MIDI 200A/)).toBeInTheDocument();
    expect(screen.getByText(/Cabo 70mm² vermelho/)).toBeInTheDocument();
    expect(screen.getAllByText(/texto livre/).length).toBeGreaterThan(0);
  });
});

describe('Central de Compras', () => {
  it('renderiza a fila com a cotação que precisa de decisão', async () => {
    wrap(<PurchasingHubPage />);
    expect(await screen.findByText('Central de Compras')).toBeInTheDocument();
    expect(screen.getByText('Precisa de você')).toBeInTheDocument();
    expect(await screen.findByText(/Decidir a COT-00001/)).toBeInTheDocument();
  });

  it('mostra os quatro indicadores da operação', async () => {
    wrap(<PurchasingHubPage />);
    expect(await screen.findByText('Cotações abertas')).toBeInTheDocument();
    expect(screen.getByText('Cotações paradas')).toBeInTheDocument();
    expect(screen.getByText('OS esperando peça')).toBeInTheDocument();
    expect(screen.getByText('Aguardando entrega')).toBeInTheDocument();
  });
});

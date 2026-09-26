// Contas a Receber com a aba Cobranças (26/09/2026). Cobranças saiu do menu e virou aba daqui:
// perseguir quem deve é a mesma conversa de quem deve. O que se guarda: as duas abas, a rota
// de cada uma, aba desconhecida voltando para a padrão e o número do mês vindo do extrato.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import ReceivablesV2 from './ReceivablesV2';

const rotaAtual = { caminho: '' };
function EspiaoDeRota() {
  const l = useLocation();
  rotaAtual.caminho = l.pathname + l.search;
  return null;
}

vi.mock('@/hooks/use-financial', () => ({
  useReceivables: () => ({
    isLoading: false, error: null,
    data: [{
      id: 'r1', description: 'OS 25/0042', due_date: '2026-09-01', status: 'pending', amount: 1200, balance_amount: 1200,
      paid_amount: 0, client_id: 'c1', clients: { id: 'c1', name: 'Marina Azul' }, service_orders: null, service_order_id: null,
    }, {
      id: 'r2', description: 'OS 99/0001', due_date: '2099-01-10', status: 'pending', amount: 800, balance_amount: 800,
      paid_amount: 0, client_id: 'c2', clients: { id: 'c2', name: 'Veleiro do Futuro' }, service_orders: null, service_order_id: null,
    }],
  }),
  useFinancialSummary: () => ({ data: { total_receivable: 1200, overdue_receivable: 1200, entrou_no_mes: 12367.99, collected_this_month: 0 } }),
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: vi.fn() }));
vi.mock('@/components/FinancialFilterPanel', () => ({
  FinancialFilterPanel: () => <div>filtros</div>,
  applyFilters: (rows: unknown[]) => rows,
  defaultFilters: {},
}));
vi.mock('@/components/PaymentDialog', () => ({ PaymentDialog: () => null }));
vi.mock('@/components/ReceivableFormDialog', () => ({ ReceivableFormDialog: () => null }));
vi.mock('@/components/CorrigirLancamentoDialog', () => ({ CorrigirLancamentoDialog: () => null }));
vi.mock('@/components/DesfazerOuCancelarDialog', () => ({ DesfazerOuCancelarDialog: () => null }));
vi.mock('@/components/SendViaWhatsAppDialog', () => ({ SendViaWhatsAppDialog: () => null }));
vi.mock('@/components/BulkBillingReminderDialog', () => ({ BulkBillingReminderDialog: () => null }));
vi.mock('@/v2/lib/receipt', () => ({ generateReceivableReceipt: vi.fn() }));
// O painel de cobranças tem as próprias consultas; aqui importa que a aba o alcança.
vi.mock('@/v2/pages/CollectionsV2', () => ({ PainelDeCobrancas: () => <div>painel de cobranças</div> }));

function renderReceber(inicio = '/v2/receivables') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[inicio]}>
          <EspiaoDeRota />
          <Routes>
            <Route path="/v2/receivables/:aba?" element={<ReceivablesV2 />} />
          </Routes>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('Contas a Receber — abas Contas · Cobranças', () => {
  it('tem o nome do menu e as duas abas', async () => {
    renderReceber();
    expect(await screen.findByRole('heading', { level: 1, name: /Contas a Receber/ })).toBeInTheDocument();
    expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['Contas', 'Cobranças']);
    expect(screen.getByRole('tab', { selected: true })).toHaveTextContent('Contas');
    expect(screen.getAllByText('Marina Azul').length).toBeGreaterThan(0);
  });

  it('o recebido do mês vem do extrato, com o "?"', async () => {
    renderReceber();
    expect(await screen.findByText('Entrou no mês (extrato)')).toBeInTheDocument();
    expect(screen.getByText('R$ 12.367,99')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'De onde vem o Entrou no mês' })).toBeInTheDocument();
  });

  it('clicar em Cobranças troca a rota e mostra o painel; as ações das contas saem do topo', async () => {
    const user = userEvent.setup();
    renderReceber();
    expect(await screen.findByRole('button', { name: /Novo recebível/ })).toBeInTheDocument();
    await user.click(screen.getByRole('tab', { name: 'Cobranças' }));
    expect(rotaAtual.caminho).toBe('/v2/receivables/cobrancas');
    expect(await screen.findByText('painel de cobranças')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Novo recebível/ })).not.toBeInTheDocument();
  });

  it('o link /v2/receivables/cobrancas abre direto na aba', async () => {
    renderReceber('/v2/receivables/cobrancas');
    expect(await screen.findByText('painel de cobranças')).toBeInTheDocument();
    expect(screen.getByRole('tab', { selected: true })).toHaveTextContent('Cobranças');
  });

  it('aba desconhecida volta para Contas', async () => {
    renderReceber('/v2/receivables/xyz');
    expect(await screen.findByRole('tab', { name: 'Contas', selected: true })).toBeInTheDocument();
    expect(rotaAtual.caminho).toBe('/v2/receivables');
  });

  it('o filtro ?view= da notificação de atraso continua valendo', async () => {
    renderReceber('/v2/receivables?view=overdue');
    // Só o vencido: a conta que vence em 2099 fica de fora do recorte.
    expect((await screen.findAllByText('Marina Azul')).length).toBeGreaterThan(0);
    expect(screen.queryByText('Veleiro do Futuro')).not.toBeInTheDocument();
  });

  it('sem ?view=, abre no que está em aberto (vencido e a vencer)', async () => {
    renderReceber('/v2/receivables');
    expect((await screen.findAllByText('Veleiro do Futuro')).length).toBeGreaterThan(0);
  });
});

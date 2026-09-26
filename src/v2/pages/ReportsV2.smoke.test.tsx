// Smoke de render da Central de relatórios (26/09/2026): uma porta só para tudo o que é
// demonstrativo. Guarda: as seis seções como abas (um nível só), cada uma com o seu conteúdo,
// os números do Resumo dizendo de onde vêm, e os links antigos (/v2/reports?tab=parts) caindo
// no lugar certo.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import { hojeEmBrasilia, ultimosMeses } from '@/lib/fluxo-de-caixa';
import ReportsV2 from './ReportsV2';

const rotaAtual = { caminho: '' };
function EspiaoDeRota() {
  const l = useLocation();
  rotaAtual.caminho = l.pathname + l.search;
  return null;
}

// O mês corrente, para o teste não depender do dia em que roda.
const MES = hojeEmBrasilia().slice(0, 7);
const SEIS = ultimosMeses(6, MES);

const mesDoFluxo = {
  mes: MES, entrou: 12367.99, saiu: 8873.35, liquido: 3494.64, quantidade: 33,
  transferencias: { entrou: 0, saiu: 153 }, creditoDoCartao: { entrou: 0, saiu: 0 },
};

vi.mock('@/hooks/use-auth', () => ({ useAuth: () => ({ user: { id: 'u1', role: 'admin' } }) }));
vi.mock('@/hooks/use-fluxo-de-caixa', () => ({
  useFluxoDeCaixa: () => ({
    isLoading: false, error: null,
    data: { meses: [mesDoFluxo], total: mesDoFluxo, deFora: { fora_duplicata: { quantidade: 2, valor: 15.5 } } },
  }),
}));
vi.mock('@/hooks/use-dre', () => ({
  useLancamentosDRE: () => ({
    isLoading: false, error: null,
    data: [
      { data: `${MES}-05`, valor: 5000, categoria: 'Serviços', grupo: 'receita', tipo: 'receita' },
      { data: `${MES}-06`, valor: 2000, categoria: 'Aluguel', grupo: 'despesa_operacional', tipo: 'despesa' },
    ],
  }),
}));
vi.mock('@/hooks/use-saldo-das-contas', () => ({
  useSaldoDasContas: () => ({
    isLoading: false, error: null,
    data: {
      disponivel: 3246.61,
      contas: [
        { id: 'c6', nome: 'C6 - Conta PJ HBR', ehCaixa: false, saldo: 3246.61, conferidoEm: null, confere: true, diferenca: 0, contado: true },
        { id: 'nu', nome: 'Nubank PJ HBR', ehCaixa: false, saldo: null, conferidoEm: null, confere: null, diferenca: null, contado: true },
      ],
    },
  }),
}));
vi.mock('@/hooks/use-financial', () => ({
  useCashForecast: () => ({
    isLoading: false,
    data: {
      weeks: [
        { inicio: '2026-09-21', rotulo: 'Esta semana', entradas: 1000, saidas: 5000, liquido: -4000, acumulado: -4000, contemAtrasados: true },
        { inicio: '2026-09-28', rotulo: 'Próxima semana', entradas: 3000, saidas: 0, liquido: 3000, acumulado: -1000, contemAtrasados: false },
      ],
      totalEntradas: 4000, totalSaidas: 5000, semanasNegativas: 1,
    },
  }),
  useDuplicatePayables: () => ({ data: [] }),
  useAgingReport: () => ({
    isLoading: false, error: null,
    data: {
      buckets: [{ client_id: 'cl1', client_name: 'Marina Azul', future: 0, days_1_30: 100, days_31_60: 0, days_61_90: 0, over_90: 0, total: 100 }],
      totals: { future: 0, days_1_30: 100, days_31_60: 0, days_61_90: 0, over_90: 0, total: 100 },
      generated_at: '',
    },
  }),
  useAgingAPagar: () => ({
    isLoading: false, error: null,
    data: {
      buckets: [{ client_id: 's1', client_name: 'Toli Distribuidora', future: 1500, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 1500 }],
      totals: { future: 1500, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 1500 },
      generated_at: '',
    },
  }),
}));
vi.mock('@/hooks/use-despesas-por-categoria', () => ({
  useDespesasDosMeses: () => ({
    isLoading: false, error: null,
    data: {
      meses: SEIS,
      grupoDe: new Map([['Combustível e deslocamento', 'despesa_operacional'], ['Pagamento de fatura de cartão', 'nao_operacional']]),
      linhas: [
        { issue_date: `${MES}-02`, amount: 180.5, expense_category: 'Combustível e deslocamento' },
        { issue_date: `${MES}-03`, amount: 1560.81, expense_category: 'Pagamento de fatura de cartão' },
      ],
    },
  }),
}));
vi.mock('@/hooks/use-reports', () => ({
  useRevenueReport: () => ({ isLoading: false, error: null, data: { totalReceived: 0, avgTicket: 0, invoicedCount: 0, margin: 0, monthlyRevenue: [], topClients: [] } }),
  useOsPerformanceReport: () => ({ isLoading: false, error: null, data: { openCount: 2, completedCount: 1, avgCompletionHours: 1, conversionRate: 50, overdueCount: 0, statusDistribution: [{ name: 'open', value: 2 }], staleOrders: [] } }),
  usePartsUsageReport: () => ({ isLoading: false, error: null, data: { rows: [{ name: 'Bomba de porão', qty: 3, revenue: 300, avg_price: 100 }], top10: [{ name: 'Bomba de porão', qty: 3 }] } }),
  useTechnicianProductivityReport: () => ({ isLoading: false, error: null, data: { rows: [] } }),
  useProfitabilityReport: () => ({ isLoading: false, error: null, data: { totalRevenue: 0, totalProfit: 0, avgMargin: 0, rows: [], topOS: [] } }),
}));
vi.mock('@/components/DREPanel', () => ({ DREPanel: () => <div>painel dre</div> }));
vi.mock('@/components/AIConsultantDashboard', () => ({ AIConsultantDashboard: () => <div>consultor ia</div> }));

function renderCentral(inicio = '/v2/reports') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[inicio]}>
          <EspiaoDeRota />
          <Routes>
            <Route path="/v2/reports/:secao?" element={<ReportsV2 />} />
            <Route path="*" element={<div>fora da central</div>} />
          </Routes>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

const SECOES = ['Resumo do mês', 'Fluxo de caixa', 'Resultado (DRE)', 'Para onde foi o dinheiro', 'Quem deve e a quem devo', 'Operação'];

describe('Central de relatórios', () => {
  it('o link antigo /v2/reports abre o Resumo do mês, com as seis seções como abas', async () => {
    renderCentral('/v2/reports');
    expect(await screen.findByRole('heading', { level: 1, name: 'Central de relatórios' })).toBeInTheDocument();
    expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(SECOES);
    expect(screen.getByRole('tab', { selected: true })).toHaveTextContent('Resumo do mês');
    expect(screen.getByText('As abas mudaram de lugar.')).toBeInTheDocument();
  });

  it('Resumo do mês: quatro números, cada um dizendo de onde vem', async () => {
    renderCentral('/v2/reports');
    expect(await screen.findByText('Entrou (extrato)')).toBeInTheDocument();
    expect(screen.getByText('R$ 12.367,99')).toBeInTheDocument();
    expect(screen.getByText('R$ 8.873,35')).toBeInTheDocument();
    expect(screen.getByText('Vendido')).toBeInTheDocument();
    expect(screen.getByText('R$ 5.000,00')).toBeInTheDocument();
    expect(screen.getByText('Resultado')).toBeInTheDocument();
    expect(screen.getByText('R$ 3.000,00')).toBeInTheDocument();
    expect(screen.getByText(/pela data do extrato. Sem transferência entre contas suas/)).toBeInTheDocument();
    expect(screen.getByText(/a mesma do DRE/)).toBeInTheDocument();
    expect(screen.getByText(/Vendido menos custos e despesas do mês/)).toBeInTheDocument();
    // O que ficou à parte é dito.
    expect(screen.getByText(/Ficaram à parte, sem somar em Entrou e Saiu/)).toBeInTheDocument();
    // Vendido 5.000 de 12.367,99 que entrou: 40% — o Resultado parece pior do que é, e a tela diz.
    expect(screen.getByText(/O vendido lançado é 40% do que entrou no banco/)).toBeInTheDocument();
  });

  it('cada seção alcança o seu conteúdo e troca a rota', async () => {
    const user = userEvent.setup();
    const { container } = renderCentral('/v2/reports');
    for (const [aba, rota] of [
      ['Fluxo de caixa', '/v2/reports/fluxo'],
      ['Resultado (DRE)', '/v2/reports/dre'],
      ['Para onde foi o dinheiro', '/v2/reports/categorias'],
      ['Quem deve e a quem devo', '/v2/reports/aging'],
      ['Operação', '/v2/reports/operacao'],
      ['Resumo do mês', '/v2/reports'],
    ] as const) {
      await user.click(await screen.findByRole('tab', { name: aba }));
      expect(rotaAtual.caminho).toBe(rota);
      const painel = container.querySelector('[role="tabpanel"][data-state="active"]');
      expect(painel?.textContent?.trim().length, `"${aba}" abre vazia`).toBeGreaterThan(0);
    }
  });

  it('Fluxo de caixa: mês a mês pelo extrato e as 8 semanas partindo do saldo de hoje', async () => {
    renderCentral('/v2/reports/fluxo');
    expect(await screen.findByText(/Mês a mês, pelo extrato/)).toBeInTheDocument();
    expect(screen.getByText('Próximas 8 semanas')).toBeInTheDocument();
    expect(screen.getAllByText('R$ 3.246,61').length).toBeGreaterThan(0);
    expect(screen.getByText(/Sem saldo informado ainda, fica de fora do ponto de partida: Nubank PJ HBR/)).toBeInTheDocument();
    // Saldo de hoje 3.246,61 − 4.000 na primeira semana: fica negativo, e a tela avisa.
    expect(screen.getByText(/O saldo previsto fica negativo em 1 das próximas 8 semanas/)).toBeInTheDocument();
    expect(screen.getByText('O que a previsão não inclui')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /O que não entrou em conta nenhuma/ })).toBeInTheDocument();
  });

  it('Para onde foi o dinheiro: por categoria, e o que fica fora do resultado só com a opção', async () => {
    const user = userEvent.setup();
    renderCentral('/v2/reports/categorias');
    expect(await screen.findByText('Combustível e deslocamento')).toBeInTheDocument();
    expect(screen.queryByText('Pagamento de fatura de cartão')).not.toBeInTheDocument();
    await user.click(screen.getByRole('switch'));
    expect(screen.getByText('Pagamento de fatura de cartão')).toBeInTheDocument();
  });

  it('Quem deve e a quem devo: alterna entre A receber e A pagar, com as mesmas faixas', async () => {
    const user = userEvent.setup();
    renderCentral('/v2/reports/aging');
    expect(await screen.findByText('Marina Azul')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'A pagar' }));
    expect(await screen.findByText('Toli Distribuidora')).toBeInTheDocument();
    expect(screen.queryByText('Marina Azul')).not.toBeInTheDocument();
    for (const faixa of ['A vencer', '1–30 dias', '31–60 dias', '61–90 dias', '+90 dias']) {
      expect(screen.getByText(faixa)).toBeInTheDocument();
    }
  });

  it('Operação diz o critério: só OS aprovada', async () => {
    renderCentral('/v2/reports/operacao');
    expect(await screen.findByText(/aqui só conta ordem de serviço aprovada/)).toBeInTheDocument();
    expect(screen.getByText('Receita e clientes')).toBeInTheDocument();
    expect(screen.getByText('Lucro por OS')).toBeInTheDocument();
  });

  it('link antigo da "Gerenciais" com ?tab= abre Operação já na parte certa', async () => {
    renderCentral('/v2/reports?tab=parts');
    expect(await screen.findByText('Top 10 peças por quantidade')).toBeInTheDocument();
    expect(rotaAtual.caminho).toBe('/v2/reports/operacao?tab=parts');
  });

  it('seção desconhecida volta para o Resumo', async () => {
    renderCentral('/v2/reports/nao-existe');
    expect(await screen.findByText('Entrou (extrato)')).toBeInTheDocument();
    expect(rotaAtual.caminho).toBe('/v2/reports');
  });
});

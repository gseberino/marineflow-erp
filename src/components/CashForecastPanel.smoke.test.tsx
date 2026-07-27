// Smoke de render da programação de pagamentos. Mesmo motivo dos outros: montar JSX a
// partir de dados calculados só se prova renderizando.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { CashForecastPanel } from './CashForecastPanel';

const { forecast, duplicadas } = vi.hoisted(() => ({
  forecast: {
    weeks: [
      { inicio: '2026-07-27', rotulo: 'Esta semana', entradas: 5000, saidas: 12000, liquido: -7000, acumulado: -7000, contemAtrasados: true },
      { inicio: '2026-08-03', rotulo: 'Próxima semana', entradas: 9000, saidas: 2000, liquido: 7000, acumulado: 0, contemAtrasados: false },
      { inicio: '2026-08-10', rotulo: '10/08 a 16/08', entradas: 0, saidas: 0, liquido: 0, acumulado: 0, contemAtrasados: false },
    ],
    totalEntradas: 14000,
    totalSaidas: 14000,
    semanasNegativas: 1,
  },
  duplicadas: [
    {
      fornecedor: 'Distribuidora Náutica',
      valor: 1200,
      mesmoMes: true,
      contas: [
        { id: 'p1', description: 'Peças motor', due_date: '2026-08-05' },
        { id: 'p2', description: 'Peças motor', due_date: '2026-08-20' },
      ],
    },
  ],
}));

vi.mock('@/hooks/use-financial', () => ({
  useCashForecast: () => ({ data: forecast, isLoading: false }),
  useDuplicatePayables: () => ({ data: duplicadas }),
}));

function renderPainel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <CashForecastPanel />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('CashForecastPanel', () => {
  it('mostra os totais do período', async () => {
    renderPainel();
    expect(await screen.findByText(/A receber \(8 semanas\)/)).toBeInTheDocument();
    expect(screen.getByText(/A pagar \(8 semanas\)/)).toBeInTheDocument();
    expect(screen.getByText(/Resultado do período/)).toBeInTheDocument();
  });

  it('lista as semanas com o resultado de cada uma', async () => {
    renderPainel();
    expect(await screen.findByText('Esta semana')).toBeInTheDocument();
    expect(screen.getByText('Próxima semana')).toBeInTheDocument();
    expect(screen.getByText(/inclui vencidas/)).toBeInTheDocument();
  });

  it('alerta quando sai mais do que entra em alguma semana', async () => {
    renderPainel();
    expect(await screen.findByText(/sai mais do que entra/)).toBeInTheDocument();
  });

  it('aponta possível duplicidade sem afirmar que é erro', async () => {
    renderPainel();
    expect(await screen.findByText(/Possível lançamento em duplicidade/)).toBeInTheDocument();
    expect(screen.getByText(/Distribuidora Náutica/)).toBeInTheDocument();
    expect(screen.getByText(/Podem ser parcelas legítimas/)).toBeInTheDocument();
  });
});

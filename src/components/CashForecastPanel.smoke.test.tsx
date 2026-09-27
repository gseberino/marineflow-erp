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
      { inicio: '2026-07-27', rotulo: 'Esta semana', entradas: 5000, saidas: 12000, liquido: -7000, acumulado: -7000, contemAtrasados: true,
        saidasDasContas: 11000, saidasDaFatura: 800, saidasRecorrentes: 200 },
      { inicio: '2026-08-03', rotulo: 'Próxima semana', entradas: 9000, saidas: 2000, liquido: 7000, acumulado: 0, contemAtrasados: false },
      { inicio: '2026-08-10', rotulo: '10/08 a 16/08', entradas: 0, saidas: 0, liquido: 0, acumulado: 0, contemAtrasados: false },
    ],
    totalEntradas: 14000,
    totalSaidas: 14000,
    semanasNegativas: 1,
    extras: {
      faturas: [
        { conta: 'Nubank PJ HBR', valor: 554.27, vencimento: '2026-07-16', fechamento: '2026-07-02', situacao: 'fechada', vencida: true, compras: 8, naPrevisao: true },
        { conta: 'C6 - Conta PJ HBR', valor: 245.73, vencimento: '2026-08-27', fechamento: '2026-08-17', situacao: 'aberta', vencida: false, compras: 3, naPrevisao: true },
      ],
      recorrentes: [{ categoria: 'Contabilidade e assessoria', mediaMensal: 915.35, meses: 3 }],
      avisos: [],
    },
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

function renderPainel(saldoInicial?: number | null) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <CashForecastPanel saldoInicial={saldoInicial} />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('CashForecastPanel', () => {
  it('mostra os totais do período', async () => {
    renderPainel();
    expect(await screen.findByText(/A receber \(8 semanas\)/)).toBeInTheDocument();
    expect(screen.getByText(/Sai \(8 semanas\)/)).toBeInTheDocument();
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

  // 26/09/2026: a previsão parte do saldo de hoje (as fichas de saldo), não mais de zero.
  it('com o saldo de hoje, mostra o saldo previsto e avisa a semana que fica no vermelho', async () => {
    renderPainel(5000);
    expect(await screen.findByText('Saldo de hoje')).toBeInTheDocument();
    expect(screen.getAllByText('R$ 5.000,00').length).toBeGreaterThan(0);
    // 5.000 − 7.000 na primeira semana = −2.000; 5.000 + 0 no fim.
    expect(screen.getByText('Saldo previsto no fim')).toBeInTheDocument();
    expect(screen.getByText(/O saldo previsto fica negativo em 1 das próximas 8 semanas — a primeira é/)).toBeInTheDocument();
    expect(screen.getByText('esta semana')).toBeInTheDocument();
  });

  it('com saldo que cobre tudo, não acusa semana negativa de saldo', async () => {
    renderPainel(100000);
    expect(await screen.findByText('Saldo previsto no fim')).toBeInTheDocument();
    expect(screen.queryByText(/O saldo previsto fica negativo/)).not.toBeInTheDocument();
  });

  it('aponta possível duplicidade sem afirmar que é erro', async () => {
    renderPainel();
    expect(await screen.findByText(/Possível lançamento em duplicidade/)).toBeInTheDocument();
    expect(screen.getByText(/Distribuidora Náutica/)).toBeInTheDocument();
    expect(screen.getByText(/Podem ser parcelas legítimas/)).toBeInTheDocument();
  });

  // 27/09/2026: a previsão soma a fatura do cartão e os gastos que se repetem, e diz de onde vem.
  it('diz o que soma além das contas: a fatura de cada cartão e os gastos que se repetem', async () => {
    renderPainel(5000);
    expect(await screen.findByText(/Além das contas lançadas, a previsão soma/)).toBeInTheDocument();
    expect(screen.getByText('Fatura Nubank PJ HBR')).toBeInTheDocument();
    expect(screen.getByText(/venceu por volta de 16\/07 e não aparece pagamento — confira/)).toBeInTheDocument();
    // "lançamento(s)": no ciclo entram compras, parcelas, tarifas e juros.
    expect(screen.getByText(/3 lançamento\(s\) do ciclo aberto até hoje \(fecha em 17\/08\)/)).toBeInTheDocument();
    expect(screen.getByText(/Contabilidade e assessoria R\$ 915,35\/mês/)).toBeInTheDocument();
  });
});

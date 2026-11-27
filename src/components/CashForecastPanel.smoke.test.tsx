// Smoke de render da programação de pagamentos. Mesmo motivo dos outros: montar JSX a
// partir de dados calculados só se prova renderizando.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { CashForecastPanel } from './CashForecastPanel';

const { forecast, duplicadas, estado } = vi.hoisted(() => ({
  estado: { erro: false },
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
        // 24/11/2026: as faturas vêm da mesma conta da fila do WhatsApp (calendário do banco, valor estimado).
        { cartao: 'Nubank', valor: 554.27, total: 554.27, pago: 0, vencimento: '2026-07-16', fechamento: '2026-07-02', situacao: 'fechada', vencida: true, origem: 'banco', naPrevisao: true },
        { cartao: 'C6', valor: 245.73, total: 245.73, pago: 0, vencimento: '2026-08-27', fechamento: '2026-08-17', situacao: 'aberta', vencida: false, origem: 'extrato', naPrevisao: true },
        { cartao: 'Itaú', valor: 0, total: 456.73, pago: 2450.61, vencimento: '2026-07-25', fechamento: '2026-07-19', situacao: 'fechada', vencida: false, origem: 'extrato', naPrevisao: true },
        { cartao: 'Inter', valor: 300, total: 1000, pago: 700, vencimento: '2026-08-05', fechamento: '2026-07-28', situacao: 'fechada', vencida: false, origem: 'extrato', naPrevisao: true },
        { cartao: 'Fora', valor: 99, total: 99, pago: 0, vencimento: '2026-12-05', fechamento: '2026-11-28', situacao: 'aberta', vencida: false, origem: 'extrato', naPrevisao: false },
      ],
      recorrentes: [{ categoria: 'Contabilidade e assessoria', mediaMensal: 915.35, meses: 3 }],
      avisos: [],
      // 27/11/2026: o dado real do dia — 5 contas com o dinheiro já no banco, 1 vencida há mais de 90 dias.
      aReceber: { noBanco: { total: 9080.06, contas: 5 }, antigas: { total: 756, contas: 1 } } as
        { noBanco: { total: number; contas: number }; antigas: { total: number; contas: number } } | undefined,
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
  useCashForecast: () => (estado.erro
    ? { data: undefined, isLoading: false, isError: true, isFetching: false, refetch: () => {} }
    : { data: forecast, isLoading: false }),
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
  // 19/11/2026: leitura que falhava aparecia como "Nada programado para as próximas semanas".
  it('leitura que falha mostra o erro, não "nada programado"', async () => {
    estado.erro = true;
    try {
      renderPainel();
      expect(await screen.findByText(/Não consegui carregar a programação do caixa/)).toBeInTheDocument();
      expect(screen.queryByText(/Nada programado/)).toBeNull();
    } finally {
      estado.erro = false;
    }
  });

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
    expect(screen.getByText('Fatura Nubank')).toBeInTheDocument();
    expect(screen.getByText(/Contabilidade e assessoria R\$ 915,35\/mês/)).toBeInTheDocument();
  });

  // 24/11/2026: a tela diz a fatura como a fila de pagamentos do WhatsApp — vencimento do banco, valor "cerca de".
  it('fatura do cartão: vencimento do banco, valor estimado, e cada situação com a sua frase', async () => {
    renderPainel(5000);
    await screen.findByText(/Além das contas lançadas, a previsão soma/);
    const linha = (nome: string) => screen.getByText(`Fatura ${nome}`).closest('li')!.textContent!.replace(/\s/g, ' ');
    // fechada, total informado pelo banco, sem pagamento e vencida: valor exato (sem "cerca de") e o pedido de conferir
    expect(linha('Nubank')).toBe('Fatura Nubank R$ 554,27 — fatura fechada em 02/07, vencimento 16/07; o extrato não mostra pagamento que cubra — confira');
    // aberta: sempre estimada, com o fechamento "por volta de"
    expect(linha('C6')).toBe('Fatura C6 cerca de R$ 245,73 — o que já está no cartão até hoje (fecha por volta de 17/08, vencimento 27/08)');
    // fechada e coberta: zero a pagar, e diz com quanto foi coberta
    expect(linha('Itaú')).toBe('Fatura Itaú R$ 0,00 — fatura de cerca de R$ 456,73 fechada por volta de 19/07, vencimento 25/07: coberta pelos R$ 2.450,61 pagos desde o fechamento');
    // paga em parte: o que falta
    expect(linha('Inter')).toBe('Fatura Inter cerca de R$ 300,00 — o que falta da fatura de cerca de R$ 1.000,00 fechada por volta de 28/07, vencimento 05/08, depois dos R$ 700,00 pagos desde o fechamento');
    // a que não entrou na previsão (vence depois da janela, ou já lançada como conta) não aparece
    expect(screen.queryByText('Fatura Fora')).not.toBeInTheDocument();
    expect(screen.getByText(/o vencimento é o que o banco informa; o valor é estimado pelo extrato/)).toBeInTheDocument();
    // a regra antiga (data deduzida) dizia "por volta de" no vencimento: não diz mais
    expect(screen.queryByText(/vence por volta de|venceu por volta de/)).not.toBeInTheDocument();
  });

  // 27/11/2026 (cobrança, fatia 6): o dinheiro já no banco e o vencido de mais de 90 dias saem das entradas e aparecem à parte.
  it('diz o que ficou fora das entradas: já no banco esperando baixa e o vencido há mais de 90 dias', async () => {
    renderPainel(5000);
    const bloco = (await screen.findByTestId('previsao-fora-das-entradas')).textContent!.replace(/\s/g, ' ');
    expect(bloco).toContain('Das contas a receber, fica fora das entradas:');
    expect(bloco).toContain('Já no banco, esperando baixa no Extrato R$ 9.080,06 (5 contas) — o dinheiro já está no saldo de hoje; falta dar a baixa no Extrato.');
    expect(bloco).toContain('Vencido há mais de 90 dias R$ 756,00 (1 conta) — sem data para entrar, não conta como entrada desta semana.');
  });

  it('sem nada fora das entradas (ou leitura antiga, sem o campo), o bloco não aparece', async () => {
    const antes = forecast.extras.aReceber;
    try {
      forecast.extras.aReceber = { noBanco: { total: 0, contas: 0 }, antigas: { total: 0, contas: 0 } };
      const r = renderPainel(5000);
      await screen.findByText('Esta semana');
      expect(screen.queryByTestId('previsao-fora-das-entradas')).toBeNull();
      r.unmount();
      forecast.extras.aReceber = undefined;
      renderPainel(5000);
      await screen.findByText('Esta semana');
      expect(screen.queryByTestId('previsao-fora-das-entradas')).toBeNull();
    } finally {
      forecast.extras.aReceber = antes;
    }
  });
});

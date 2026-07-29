// Smoke test de RENDER da conciliação bancária.
//
// Existe pelo mesmo motivo do smoke da AgendaPage: um erro de TDZ derrubou uma página
// inteira em produção em 24/07/2026 e passou por tsc + vite build. Compilar não basta.
// Aqui o risco é maior ainda, porque a tela passou a montar sugestões vindas do backend
// dentro do JSX — um acesso a campo inexistente só aparece renderizando.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { BankReconciliation } from './BankReconciliation';

const { transacoes, sugestoes } = vi.hoisted(() => {
  const transacoes = [
    {
      id: 'tx-1', transaction_date: '2026-07-27', description: 'PIX RECEBIDO RODRIGO',
      amount: 1596.41, transaction_type: 'credit', reconciled: false,
      reconciled_payment_id: null, reconciled_service_order_id: null, source_type: 'bank',
      service_orders: null,
    },
    {
      id: 'tx-2', transaction_date: '2026-07-26', description: 'TARIFA BANCARIA',
      amount: 29.9, transaction_type: 'debit', reconciled: false,
      reconciled_payment_id: null, reconciled_service_order_id: null, source_type: 'bank',
      service_orders: null,
    },
  ];
  const sugestoes = {
    transactions: [
      {
        transaction: { id: 'tx-1' },
        suggestions: [
          {
            candidate: {
              kind: 'quote_deposit', id: 'orc-70', label: 'Sinal do ORÇ-00070',
              amount: 1596.41, direction: 'credit', dueDate: null, referenceDate: '2026-07-25',
              clientName: 'Rodrigo', documentNumber: 'ORÇ-00070', convertsQuote: true,
              serviceOrderId: 'so-70',
            },
            score: 82, tier: 'probable',
            reasons: [
              { signal: 'valor', detail: 'Valor exato', points: 45 },
              { signal: 'nome', detail: 'Nome de Rodrigo aparece no histórico', points: 15 },
            ],
            difference: 0, autoApply: false,
          },
          {
            candidate: {
              kind: 'receivable', id: 'rcv-9', label: 'Parcela 2/3',
              amount: 1550, direction: 'credit', dueDate: '2026-07-25', clientName: 'Outro Cliente',
            },
            score: 41, tier: 'weak',
            reasons: [{ signal: 'valor', detail: 'Recebido R$ 46,41 a mais que o esperado', points: 20 }],
            difference: 46.41, autoApply: false,
          },
        ],
      },
    ],
    applied: [],
    summary: { pendentes: 2, conciliadas: 0, sugeridas: 1, sem_candidato: 1 },
  };
  return { transacoes, sugestoes };
});

vi.mock('@/integrations/supabase/client', () => {
  const builder: any = {};
  for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'order', 'limit', 'is', 'not', 'update', 'insert']) {
    builder[k] = () => builder;
  }
  builder.single = async () => ({ data: null, error: null });
  builder.maybeSingle = async () => ({ data: null, error: null });
  builder.then = (res: any) => Promise.resolve({ data: [], error: null }).then(res);
  return {
    supabase: {
      from: () => builder,
      rpc: async () => ({ data: {}, error: null }),
      functions: { invoke: async () => ({ data: sugestoes, error: null }) },
    },
  };
});

vi.mock('@/hooks/use-financial', () => ({
  useBankTransactions: () => ({ data: transacoes, isLoading: false }),
  useImportBankTransactions: () => ({ mutateAsync: async () => ({ imported: 0, skipped: 0 }), isPending: false }),
  useReconcile: () => ({ mutateAsync: async () => ({}), isPending: false }),
  useDismissBankTransaction: () => ({ mutateAsync: async () => ({}), isPending: false }),
  useUnignoreBankTransaction: () => ({ mutateAsync: async () => ({}), isPending: false }),
  useReceivables: () => ({ data: [] }),
  usePayables: () => ({ data: [] }),
  useCreateReceivable: () => ({ mutateAsync: async () => ({}) }),
  useCreatePayable: () => ({ mutateAsync: async () => ({}) }),
  useRegisterPayment: () => ({ mutateAsync: async () => ({}) }),
}));

vi.mock('@/hooks/use-service-orders', () => ({ useServiceOrders: () => ({ data: [] }) }));
vi.mock('@/hooks/use-reconciliation', async (original) => {
  const real = await original<typeof import('@/hooks/use-reconciliation')>();
  return {
    ...real,
    useReconciliationHealth: () => ({
      data: { total: 10, conciliadas: 4, pendentes: 6, taxa: 40, valorPendente: 5000, diasMaisAntiga: 45, padroesAprendidos: 3 },
    }),
  };
});
vi.mock('@/hooks/use-clients', () => ({ useClients: () => ({ data: [] }) }));
vi.mock('@/hooks/use-suppliers', () => ({ useSuppliers: () => ({ data: [] }) }));

function renderTela() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <BankReconciliation />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('BankReconciliation — render', () => {
  it('renderiza a lista de transações pendentes sem quebrar', async () => {
    renderTela();
    expect(await screen.findByText(/PIX RECEBIDO RODRIGO/)).toBeInTheDocument();
    expect(screen.getByText(/TARIFA BANCARIA/)).toBeInTheDocument();
  });

  it('mostra o botão de análise em lote quando há pendências', async () => {
    renderTela();
    expect(await screen.findByRole('button', { name: /Analisar tudo/i })).toBeInTheDocument();
  });

  it('mostra a saúde da rotina: progresso, atraso e aprendizado', async () => {
    renderTela();
    expect(await screen.findByText(/40% do extrato/)).toBeInTheDocument();
    expect(screen.getByText(/4 de 10 conciliadas/)).toBeInTheDocument();
    expect(screen.getByText(/Mais antiga pendente: 45 dias/)).toBeInTheDocument();
    expect(screen.getByText(/3 padrões aprendidos/)).toBeInTheDocument();
  });

  it('resume a situação da fila no topo', async () => {
    renderTela();
    // "Com correspondência" aparece no indicador e no filtro — ambos de propósito.
    expect((await screen.findAllByText(/Com correspondência/i)).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Sem candidato/i).length).toBeGreaterThan(0);
    expect(screen.getByText(/Entradas a identificar/i)).toBeInTheDocument();
  });

  // O motivo desta tela ter sido refeita: a correspondência só aparecia depois de abrir
  // a transação, então o resumo "N sugestões" não levava a lugar nenhum.
  it('mostra a correspondência na própria linha, sem precisar abrir', async () => {
    renderTela();
    expect(await screen.findByText(/Sinal do ORÇ-00070/)).toBeInTheDocument();
    expect(screen.getByText('82%')).toBeInTheDocument();
    // Transação sem candidato precisa dizer isso, em vez de ficar muda.
    expect(screen.getByText(/Sem correspondência encontrada/)).toBeInTheDocument();
  });

  it('permite confirmar a melhor correspondência direto na linha', async () => {
    renderTela();
    await screen.findByText(/Sinal do ORÇ-00070/);
    expect(screen.getByRole('button', { name: /^Confirmar$/ })).toBeInTheDocument();
  });

  // A tela abre no trabalho do dia; a configuração de onde vêm os dados fica noutra seção,
  // para não soterrar a fila de conciliação como acontecia antes.
  it('separa conciliar de origem dos dados, abrindo em conciliar', async () => {
    const user = userEvent.setup();
    renderTela();
    await screen.findByText(/PIX RECEBIDO RODRIGO/);
    expect(screen.queryByText(/Importar arquivo/)).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Origem dos dados/i }));
    expect(await screen.findByText(/Importar arquivo/)).toBeInTheDocument();
    // A fila sai de cena enquanto a configuração está aberta.
    expect(screen.queryByText(/PIX RECEBIDO RODRIGO/)).not.toBeInTheDocument();
  });

  it('filtra por transações sem candidato', async () => {
    const user = userEvent.setup();
    renderTela();
    await screen.findByText(/PIX RECEBIDO RODRIGO/);
    await user.click(screen.getByRole('button', { name: /^Sem candidato$/ }));
    expect(screen.queryByText(/PIX RECEBIDO RODRIGO/)).not.toBeInTheDocument();
    expect(screen.getByText(/TARIFA BANCARIA/)).toBeInTheDocument();
  });

  // O painel de sugestões é o código novo e o de maior risco: monta JSX a partir de um
  // objeto vindo do backend. Só renderizando dá para saber que não quebra.
  it('abre a transação e renderiza as sugestões pontuadas', async () => {
    const user = userEvent.setup();
    renderTela();

    // Espera a análise chegar (é assíncrona): antes dela, a linha ainda não sabe que há
    // correspondência e o botão continua sendo "Conciliar".
    await screen.findByText(/Sinal do ORÇ-00070/);
    await user.click(screen.getByRole('button', { name: /ver opções/i }));

    // Agora aparece duas vezes: resumido na linha e detalhado no painel aberto.
    expect((await screen.findAllByText(/Sinal do ORÇ-00070/)).length).toBeGreaterThan(1);
    expect(screen.getByText(/82% de confiança/)).toBeInTheDocument();
    expect(screen.getByText(/Sinal de orçamento/)).toBeInTheDocument();
    // Aviso do efeito colateral: conciliar o sinal aprova e converte o orçamento.
    expect(screen.getByText(/vai aprovar o ORÇ-00070/)).toBeInTheDocument();
    // Divergência de valor aparece duas vezes de propósito: como motivo da pontuação
    // e como alerta destacado, para que ninguém confirme sem ver a diferença.
    expect(screen.getAllByText(/a mais que o esperado/).length).toBeGreaterThan(0);
  });
});

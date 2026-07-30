// Smoke de render da caixa de entrada financeira.
//
// Aqui o render é a única validação possível de algo que importa: a separação entre o que
// pode ser aprovado em bloco e o que exige olhar individual acontece na montagem da tela.
// Build e tsc passariam com a regra invertida — e aprovar em lote uma saída de R$ 18 mil é
// exatamente o erro que o limite existe para impedir.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { FinanceReviewInbox } from './FinanceReviewInbox';

const { propostas, aprovarMock } = vi.hoisted(() => ({
  aprovarMock: vi.fn(),
  propostas: [
    {
      id: 'p1', kind: 'create_payable', status: 'pending',
      bank_transaction_id: 't1', related_transaction_id: null,
      title: 'Despesa: POSTO AGRICOPEL LTDA', reasoning: 'Histórico contém "POSTO", que indica Combustível e deslocamento',
      confidence: 88, suggested_amount: 180.5, suggested_date: '2026-07-20',
      suggested_category: 'Combustível e deslocamento', suggested_description: 'POSTO AGRICOPEL LTDA',
      suggested_supplier_id: null, dre_group: 'custo_direto', created_at: '2026-07-20T10:00:00Z',
    },
    {
      id: 'p2', kind: 'create_payable', status: 'pending',
      bank_transaction_id: 't2', related_transaction_id: null,
      title: 'Despesa: MARINE EXPRESS COMERCIAL', reasoning: 'CNPJ/CPF confere com o fornecedor MARINE EXPRESS',
      confidence: 90, suggested_amount: 18001.04, suggested_date: '2026-07-18',
      suggested_category: 'Peças e materiais', suggested_description: 'MARINE EXPRESS COMERCIAL',
      suggested_supplier_id: 'f1', dre_group: 'custo_direto', created_at: '2026-07-18T10:00:00Z',
    },
    {
      id: 'p3', kind: 'internal_transfer', status: 'pending',
      bank_transaction_id: 't3', related_transaction_id: 't4',
      title: 'Transferência entre contas: TRANSF ENVIADA', reasoning: 'Saiu de uma conta e entrou em outra no mesmo dia, pelo mesmo valor',
      confidence: 92, suggested_amount: 300, suggested_date: '2026-07-15',
      suggested_category: 'Transferência entre contas', suggested_description: 'TRANSF ENVIADA',
      suggested_supplier_id: null, dre_group: 'nao_operacional', created_at: '2026-07-15T10:00:00Z',
    },
  ],
}));

vi.mock('@/hooks/use-finance-review', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-finance-review')>();
  return {
    ...real,
    useFinanceReviewQueue: () => ({ data: propostas, isLoading: false }),
    useGerarPropostas: () => ({ mutate: vi.fn(), isPending: false }),
    useAprovarPropostas: () => ({ mutate: aprovarMock, isPending: false }),
    useRecusarPropostas: () => ({ mutate: vi.fn(), isPending: false }),
  };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      select: () => ({ eq: () => ({ eq: () => ({ order: () => Promise.resolve({ data: [], error: null }) }) }) }),
    }),
  },
}));

function renderInbox() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <FinanceReviewInbox />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('FinanceReviewInbox', () => {
  it('separa o que cabe em lote do que exige revisão individual', async () => {
    renderInbox();
    // R$ 180,50 é lote; R$ 18.001,04 e a transferência não são.
    expect(await screen.findByText(/Aprovação em lote/)).toBeInTheDocument();
    expect(screen.getByText(/Aprovação em lote — até .*\(1\)/)).toBeInTheDocument();
    expect(screen.getByText(/Revisar uma a uma .*\(2\)/)).toBeInTheDocument();
  });

  it('deixa claro que aprovar não paga nada', async () => {
    renderInbox();
    expect(await screen.findByText(/nenhum pagamento é feito aqui/i)).toBeInTheDocument();
  });

  it('mostra o motivo da proposta quando pedido', async () => {
    const user = userEvent.setup();
    renderInbox();
    const gatilhos = await screen.findAllByText(/Por que o sistema propôs isto/);
    await user.click(gatilhos[0]);
    expect(await screen.findByText(/que indica Combustível/)).toBeInTheDocument();
  });

  it('só habilita a aprovação em lote depois de selecionar algo', async () => {
    const user = userEvent.setup();
    renderInbox();
    const botao = await screen.findByRole('button', { name: /Aprovar selecionadas/i });
    expect(botao).toBeDisabled();

    await user.click(screen.getByLabelText(/Selecionar todas do lote/i));
    expect(botao).toBeEnabled();
    await user.click(botao);
    // A saída de R$ 18 mil NÃO pode entrar no lote, por mais que "selecionar todas" sugira.
    expect(aprovarMock).toHaveBeenCalledWith(
      expect.objectContaining({ ids: ['p1'] }),
      expect.anything(),
    );
  });

  it('marca a transferência entre contas como fora do resultado', async () => {
    renderInbox();
    expect(await screen.findByText('Não entra no resultado')).toBeInTheDocument();
  });
});

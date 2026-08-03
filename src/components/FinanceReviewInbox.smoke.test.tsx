// Smoke de render da caixa de entrada financeira.
//
// Aqui o render é a única validação possível de algo que importa: a separação entre o que
// pode ser aprovado em bloco e o que exige olhar individual acontece na montagem da tela.
// Build e tsc passariam com a regra invertida — e aprovar em lote uma saída de R$ 18 mil é
// exatamente o erro que o limite existe para impedir.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { FinanceReviewInbox } from './FinanceReviewInbox';

const { propostas, aprovarMock, duplicataMock, regraMock } = vi.hoisted(() => ({
  aprovarMock: vi.fn(),
  duplicataMock: vi.fn(),
  regraMock: vi.fn(),
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
      suggested_supplier_id: 'f1', dre_group: 'custo_direto', applied_rule_id: 'r1',
      created_at: '2026-07-18T10:00:00Z',
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
    useMarcarDuplicata: () => ({ mutate: duplicataMock, isPending: false }),
  };
});

vi.mock('@/hooks/use-financial-categories', () => ({
  useFinancialCategories: () => ({
    data: [
      { name: 'Combustível e deslocamento', dre_group: 'custo_direto' },
      { name: 'Peças e materiais', dre_group: 'custo_direto' },
      { name: 'Pró-labore e retirada', dre_group: 'nao_operacional' },
    ],
    isLoading: false,
  }),
}));

function renderInbox() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <FinanceReviewInbox onCriarRegra={regraMock} />
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

describe('ações da linha', () => {
  it('a categoria fica editável na própria linha, não escondida', async () => {
    // A versão anterior punha o seletor dentro do "por que o sistema propôs isto". Ação
    // atrás de explicação é ação que ninguém encontra.
    renderInbox();
    expect(await screen.findByText('Combustível e deslocamento')).toBeInTheDocument();
  });

  it('marcar duplicata tira a transação da fila, não só a proposta', async () => {
    // Recusar sozinho deixaria a transação pendente, e a próxima varredura a proporia de
    // novo — o gestor recusaria a mesma linha para sempre.
    const user = userEvent.setup();
    renderInbox();
    const botoes = await screen.findAllByRole('button', { name: /duplicata/i });
    await user.click(botoes[0]);
    expect(duplicataMock).toHaveBeenCalledWith(
      expect.objectContaining({ propostaId: 'p1', bankTransactionId: 't1' }),
    );
  });

  it('dá para ensinar uma regra a partir da linha que está na tela', async () => {
    const user = userEvent.setup();
    renderInbox();
    const botoes = await screen.findAllByRole('button', { name: /regra a partir desta linha/i });
    await user.click(botoes[0]);
    expect(regraMock).toHaveBeenCalledWith(
      expect.objectContaining({ set_category: 'Combustível e deslocamento' }),
    );
  });

  it('proposta vinda de regra se identifica como tal', async () => {
    renderInbox();
    expect(await screen.findByText('Pela sua regra')).toBeInTheDocument();
  });
});

describe('criar categoria sem sair da tela', () => {
  it('oferece criar quando nenhuma categoria serve', async () => {
    // São 87 lançamentos em "Outras despesas" de 52 fornecedores diferentes. A lacuna não
    // era disciplina de quem classifica — era o custo de classificar direito.
    const user = userEvent.setup();
    renderInbox();
    const seletores = await screen.findAllByRole('combobox');
    await user.click(seletores[0]);
    expect(await screen.findByText(/Criar categoria nova/)).toBeInTheDocument();
  });

  it('escolher "criar" abre o campo do nome, sem trocar de tela', async () => {
    const user = userEvent.setup();
    renderInbox();
    await user.click((await screen.findAllByRole('combobox'))[0]);
    await user.click(await screen.findByText(/Criar categoria nova/));
    expect(await screen.findByPlaceholderText(/Nome da categoria nova/)).toBeInTheDocument();
  });
});

describe('vínculo que a categoria pede', () => {
  // A categoria diz a que mundo a despesa pertence, e é ela que decide a próxima
  // pergunta. Mostrar os dois campos em toda linha viraria ruído em quase todas; não
  // mostrar nenhum deixa R$ 36 mil de pró-labore sem dono e R$ 37 mil de peça sem serviço.
  it('pede a OS quando é peça ou material', async () => {
    renderInbox();
    // p2 é "Peças e materiais".
    expect(await screen.findByText(/Comprado para qual OS/)).toBeInTheDocument();
  });

  it('não pergunta nada quando a categoria não pede', async () => {
    renderInbox();
    // p1 é combustível: nem favorecido nem OS fazem sentido ali.
    const combustivel = (await screen.findAllByText(/POSTO AGRICOPEL/))[0].closest('div');
    expect(within(combustivel!.parentElement!).queryByText(/Quem recebeu/)).not.toBeInTheDocument();
  });

  it('pede o favorecido quando é pró-labore', async () => {
    const user = userEvent.setup();
    renderInbox();
    // Troca a categoria de p1 para pró-labore e o campo deve aparecer.
    await user.click((await screen.findAllByRole('combobox'))[0]);
    await user.click(await screen.findByText('Pró-labore e retirada'));
    expect(await screen.findByText(/Quem recebeu/)).toBeInTheDocument();
  });

  it('oferece cadastrar o favorecido que falta', async () => {
    // Abrir dois Radix Select em sequência exige esperar o primeiro desmontar: enquanto
    // ele fecha, o overlay deixa a página com pointer-events: none e o clique seguinte
    // não chega em ninguém.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click((await screen.findAllByRole('combobox'))[0]);
    await user.click(await screen.findByText('Pró-labore e retirada'));

    const gatilhoFavorecido = (await screen.findByText(/Quem recebeu/)).closest('button');
    await user.click(gatilhoFavorecido!);
    expect(await screen.findByText(/Cadastrar favorecido/)).toBeInTheDocument();
  });
});

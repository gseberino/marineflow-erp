// Smoke de render da caixa de entrada financeira.
//
// Aqui o render é a única validação possível de algo que importa: a separação entre o que
// pode ser aprovado em bloco e o que exige olhar individual acontece na montagem da tela.
// Build e tsc passariam com a regra invertida — e aprovar em lote uma saída de R$ 18 mil é
// exatamente o erro que o limite existe para impedir.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { FinanceReviewInbox } from './FinanceReviewInbox';

const { propostas, estadoDaFila, aprovarMock, duplicataMock, regraMock, reaplicarMock } = vi.hoisted(() => ({
  aprovarMock: vi.fn(),
  duplicataMock: vi.fn(),
  regraMock: vi.fn(),
  reaplicarMock: vi.fn(),
  /** Estado que os testes de erro e de agrupamento trocam; o resto usa o padrão. */
  estadoDaFila: { error: null as Error | null, dados: null as unknown[] | null },
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
    useFinanceReviewQueue: () => ({
      data: estadoDaFila.error ? [] : (estadoDaFila.dados ?? propostas),
      isLoading: false,
      error: estadoDaFila.error,
    }),
    useGerarPropostas: () => ({ mutate: vi.fn(), isPending: false }),
    useAprovarPropostas: () => ({ mutate: aprovarMock, isPending: false }),
    useRecusarPropostas: () => ({ mutate: vi.fn(), isPending: false }),
    useMarcarDuplicata: () => ({ mutate: duplicataMock, isPending: false }),
    useReaplicarRegras: () => ({ mutate: reaplicarMock, isPending: false }),
    useClassificarComIA: () => ({ mutate: vi.fn(), isPending: false }),
  };
});

// O mock HONRA o `type`, como o hook real (`.eq('type', type)`). Um mock que devolve a
// mesma lista para tudo esconderia exatamente o defeito que o gestor encontrou: entrada
// oferecendo plano de contas de despesa.
vi.mock('@/hooks/use-financial-categories', () => ({
  useFinancialCategories: (type?: 'payable' | 'receivable') => ({
    data: type === 'receivable'
      ? [
          { name: 'Serviços prestados', dre_group: 'receita' },
          { name: 'Venda de peças e produtos', dre_group: 'receita' },
          { name: 'Sinal e adiantamento', dre_group: 'receita' },
        ]
      : [
          { name: 'Combustível e deslocamento', dre_group: 'custo_direto' },
          { name: 'Peças e materiais', dre_group: 'custo_direto' },
          { name: 'Pró-labore e retirada', dre_group: 'nao_operacional' },
        ],
    isLoading: false,
  }),
}));

/**
 * O seletor de categoria do primeiro grupo.
 *
 * Por posição não serve: a barra tem o seletor de ORDEM, que também é um combobox e vem
 * antes. Buscar pelo que ele NÃO é sobrevive a qualquer controle novo no cabeçalho.
 */
async function seletorDeCategoria() {
  const combos = await screen.findAllByRole('combobox');
  return combos.find((c) => c.getAttribute('aria-label') !== 'Ordem da lista')!;
}

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

describe('agrupado por favorecido', () => {
  // Metade da fila cai em "Outras despesas", e essas vêm de poucos favorecidos repetidos:
  // 34 compras no mesmo lugar são UMA pergunta. O agrupamento existe para isso — mas não
  // pode virar um atalho para aprovar despesa grande sem olhar.
  const miudas = Array.from({ length: 22 }, (_, i) => ({
    id: `g${i}`, kind: 'create_payable', status: 'pending',
    bank_transaction_id: `tg${i}`, related_transaction_id: null,
    title: 'Despesa: SPG*LOJA CURITIBA', reasoning: null, confidence: 30,
    suggested_amount: 9, suggested_date: '2026-03-01',
    suggested_category: 'Outras despesas', suggested_description: 'SPG*LOJA CURITIBA',
    suggested_supplier_id: null, dre_group: 'despesa_operacional',
    created_at: '2026-03-01T10:00:00Z',
    bank_transactions: { counterparty_name: 'SPG*LOJA CURITIBA', source_type: 'credit_card' },
  }));
  const grande = {
    ...miudas[0], id: 'g-grande', bank_transaction_id: 'tg-grande', suggested_amount: 4000,
  };

  afterEach(() => { estadoDaFila.dados = null; aprovarMock.mockClear(); });

  it('junta o favorecido repetido numa decisão só', async () => {
    estadoDaFila.dados = [...miudas, grande];
    renderInbox();
    // O badge do grupo, não o resumo da barra: são 23 linhas numa decisão só.
    expect(await screen.findByText('23 propostas')).toBeInTheDocument();
    expect(screen.getByText(/1 exige\(m\) revisão individual/)).toBeInTheDocument();
    expect(screen.getByText(/23 linhas repetidas se resolvem em uma decisão/)).toBeInTheDocument();
  });

  it('não aprova sem categoria escolhida', async () => {
    estadoDaFila.dados = miudas;
    renderInbox();
    expect(await screen.findByRole('button', { name: /Aprovar 22/ })).toBeDisabled();
  });

  // NOTA DE PROJETO: havia aqui um teste garantindo que o grupo aprovasse SÓ as abaixo de
  // R$ 500, deixando a de R$ 4 mil de fora. A regra mudou por decisão do gestor, com um
  // argumento melhor que o original: o que exige atenção é a incerteza, não o valor —
  // pró-labore, salários e impostos são altos por natureza, e travar cada um deles pedia
  // a mesma decisão dezenas de vezes. O que o limite tinha de útil virou a conferência
  // abaixo, onde as maiores aparecem uma a uma antes do clique. Na lista solta, onde a
  // classificação ainda é palpite do sistema, o limite continua valendo.

  it('aprova o grupo inteiro, inclusive as grandes, depois de confirmar', async () => {
    // O limite de valor existe como aproximação de "quanto isto merece de conferência", e
    // serve enquanto a classificação é palpite. Com a categoria definida no cabeçalho, a
    // decisão já foi tomada — segurar a de R$ 4 mil para perguntar de novo seria pedir a
    // mesma coisa duas vezes. O que sobra do limite é mostrar as maiores ANTES do clique.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [...miudas, grande];
    renderInbox();

    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Peças e materiais'));
    await user.click(await screen.findByRole('button', { name: /Aprovar 23/ }));

    // A grande aparece na conferência, com valor à vista.
    expect(await screen.findByText(/1 passa de/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Aprovar as 23/ }));

    const [chamada] = aprovarMock.mock.calls[0];
    expect(chamada.ids).toHaveLength(23);
    expect(chamada.ids).toContain('g-grande');
    // A categoria escolhida uma vez vale para todas as linhas aprovadas.
    expect(chamada.overrides.g0.category).toBe('Peças e materiais');
  });

  it('grupo sem nenhuma grande aprova direto, sem conferência', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = miudas;
    renderInbox();

    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Peças e materiais'));
    await user.click(await screen.findByRole('button', { name: /Aprovar 22/ }));

    expect(aprovarMock).toHaveBeenCalled();
    expect(aprovarMock.mock.calls[0][0].ids).toHaveLength(22);
  });

  it('a conferência não estoura a janela com nome comprido', async () => {
    // Filho de flex nasce com `min-width: auto`: sem `min-w-0`, um nome de estabelecimento
    // longo empurra a linha para fora da caixa e leva o layout junto. O usuário odeia
    // rolagem lateral, e aqui ela quebrava os elementos gráficos.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [{
      ...grande,
      suggested_description: 'EC *ESTABELECIMENTO COM NOME ABSURDAMENTE LONGO QUE NAO CABE NA LINHA SAO PAULO BRA',
    }, ...miudas];
    renderInbox();

    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Peças e materiais'));
    await user.click(await screen.findByRole('button', { name: /Aprovar 23/ }));

    const item = await screen.findByText(/ABSURDAMENTE LONGO/);
    expect(item.className).toMatch(/min-w-0/);
    expect(item.className).toMatch(/break-words/);
  });

  it('marca o grupo inteiro e aprova junto com outro, sem esperar recarga', async () => {
    // O ganho não é o clique a menos: é não ter de esperar a lista voltar do servidor
    // entre um grupo e o seguinte. Marca-se o que for, aprova-se de uma vez.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [...miudas, { ...grande, bank_transactions: { counterparty_name: 'OUTRO LUGAR', source_type: 'bank' } }];
    renderInbox();

    await user.click(await screen.findByLabelText(/Selecionar as 22 de SPG/i));
    await user.click(await screen.findByLabelText(/Selecionar as 1 de OUTRO LUGAR/i));
    expect(await screen.findByText(/selecionada\(s\)/)).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Aprovar selecionadas/i }));
    expect(aprovarMock.mock.calls[0][0].ids).toHaveLength(23);
  });

  it('avisa quando o que está selecionado ainda não tem categoria', async () => {
    // Aprovar assim cria despesa em "Outras despesas", que é a lacuna que esta tela existe
    // para fechar. Não impede — às vezes é mesmo "outras" —, mas descobrir depois custa
    // procurar as linhas uma a uma.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = miudas;
    renderInbox();
    await user.click(await screen.findByLabelText(/Selecionar as 22 de SPG/i));
    expect(await screen.findByText(/22 sem categoria/)).toBeInTheDocument();
  });

  it('dá para escolher a ordem da lista', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [...miudas, grande];
    renderInbox();
    await user.click(await screen.findByLabelText('Ordem da lista'));
    expect(await screen.findByText('Prontos para aprovar')).toBeInTheDocument();
    expect(screen.getByText('Favorecido (A-Z)')).toBeInTheDocument();
  });

  it('diz POR ESCRITO por que não dá para aprovar', async () => {
    // A explicação existia — num `title` de botão desabilitado, que o navegador nunca
    // mostra porque não dispara evento de mouse em elemento apagado. O gestor ficava
    // olhando para um botão morto sem como descobrir o que a tela queria dele.
    estadoDaFila.dados = miudas;
    renderInbox();
    expect(await screen.findByText(/Escolha a categoria acima para poder aprovar/i)).toBeInTheDocument();
  });

  it('grupo em que TODAS passam do limite ainda se resolve de uma vez', async () => {
    // Era o pior caso do desenho antigo: "Nada em lote aqui", botão morto, e vinte
    // decisões idênticas pela frente. Justamente o caso das categorias previsíveis —
    // pró-labore, salários, impostos —, onde o valor alto é a norma e não a exceção.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    // 20 é o piso do modo agrupado — abaixo disso a tela mostra a lista simples.
    estadoDaFila.dados = Array.from({ length: 20 }, (_, i) => ({
      ...grande, id: `gg${i}`, bank_transaction_id: `tgg${i}`,
    }));
    renderInbox();

    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Pró-labore e retirada'));
    await user.click(await screen.findByRole('button', { name: /Aprovar 20/ }));

    // Todas as vinte aparecem na conferência, com valor — uma leitura, não vinte cliques.
    expect(await screen.findByText(/20 passam de/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Aprovar as 20/ }));
    expect(aprovarMock.mock.calls[0][0].ids).toHaveLength(20);
  });

  it('marca QUAIS linhas exigem revisão individual', async () => {
    // O cabeçalho dizia "1 exige revisão individual" e, ao abrir, a linha era idêntica às
    // outras 22. Contar um problema sem apontá-lo é dar trabalho de procurar.
    const user = userEvent.setup();
    estadoDaFila.dados = [...miudas, grande];
    renderInbox();
    await user.click(await screen.findByText(/Ver as 23 linhas/));
    expect(await screen.findAllByText(/aprove aqui/i)).toHaveLength(1);
  });

  it('a linha grande recebe a classificação do grupo, mesmo ficando de fora da aprovação', async () => {
    // É o ponto do desenho: classificar é barato, aprovar é caro. A grande chega à revisão
    // individual já classificada, então o gestor decide UMA coisa, não duas.
    estadoDaFila.dados = [...miudas, grande];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();

    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Peças e materiais'));
    await user.click(await screen.findByText(/Ver as 23 linhas/));

    const selects = await screen.findAllByRole('combobox');
    // Cabeçalho + 23 linhas, todas com a mesma categoria aplicada.
    expect(selects.length).toBeGreaterThan(23);
    expect(screen.getAllByText('Peças e materiais').length).toBeGreaterThan(1);
  });
});

describe('regra nova alcança a fila', () => {
  // A regra era consultada só quando a proposta nascia, e a varredura pula o que já está
  // na fila. Quem ensinava "compra na Corema é ferramenta" continuava corrigindo à mão as
  // 40 compras da Corema já enfileiradas — exatamente o que a regra existia para resolver.
  it('oferece reaplicar as regras ao que já está esperando decisão', async () => {
    const user = userEvent.setup();
    renderInbox();
    const botao = await screen.findByRole('button', { name: /Revisar a fila/i });
    await user.click(botao);
    expect(reaplicarMock).toHaveBeenCalled();
  });
});

describe('falha de leitura', () => {
  // Aconteceu de verdade: o join da identificação virou ambíguo, a consulta passou a
  // falhar, e a tela anunciou "nenhuma proposta pendente" com 1.178 esperando decisão —
  // enquanto o contador do menu, que não usa join, marcava 99+. Consulta que falha não
  // pode ter a mesma aparência de fila zerada.
  afterEach(() => { estadoDaFila.error = null; });

  it('diz que falhou em vez de fingir fila vazia', async () => {
    estadoDaFila.error = new Error('Could not embed because more than one relationship was found');
    renderInbox();
    expect(await screen.findByText(/Não foi possível carregar a fila/i)).toBeInTheDocument();
    expect(screen.getByText(/more than one relationship/)).toBeInTheDocument();
    expect(screen.queryByText(/Nenhuma proposta pendente/)).not.toBeInTheDocument();
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
    await user.click(await seletorDeCategoria());
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
    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Pró-labore e retirada'));
    expect(await screen.findByText(/Quem recebeu/)).toBeInTheDocument();
  });

  it('oferece cadastrar o favorecido que falta', async () => {
    // Abrir dois Radix Select em sequência exige esperar o primeiro desmontar: enquanto
    // ele fecha, o overlay deixa a página com pointer-events: none e o clique seguinte
    // não chega em ninguém.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Pró-labore e retirada'));

    const gatilhoFavorecido = (await screen.findByText(/Quem recebeu/)).closest('button');
    await user.click(gatilhoFavorecido!);
    expect(await screen.findByText(/Cadastrar favorecido/)).toBeInTheDocument();
  });
});

/**
 * Entrada e saída na MESMA fila.
 *
 * Ao abrir o crédito, 87 recebimentos passaram a conviver com 3 pagamentos numa lista só,
 * e a tela — construída quando aqui só havia despesa — não tinha nem filtro por direção
 * nem plano de contas de receita. O gestor: "está tudo misturado, entradas e saídas... as
 * categorias continuam sendo de despesas e não de entradas, o que é errado e confuso".
 */
describe('entrada e saída convivendo na fila', () => {
  const entrada = {
    id: 'e1', kind: 'create_receivable', status: 'pending',
    bank_transaction_id: 'te1', related_transaction_id: null,
    title: 'Receita: CRISLAINE REGINA CIOLI', reasoning: 'Nenhuma regra reconheceu este histórico',
    confidence: 30, suggested_amount: 4500, suggested_date: '2026-07-22',
    suggested_category: 'Outras receitas', suggested_description: 'CRISLAINE REGINA CIOLI',
    suggested_supplier_id: null, suggested_client_id: null,
    dre_group: 'receita', created_at: '2026-07-22T10:00:00Z',
  };

  afterEach(() => { estadoDaFila.dados = null; });

  it('oferece o corte entrada × saída, com as contagens certas', async () => {
    estadoDaFila.dados = [propostas[0], propostas[1], entrada];
    renderInbox();
    expect(await screen.findByRole('button', { name: /Saídas \(2\)/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Entradas \(1\)/ })).toBeInTheDocument();
  });

  it('o filtro esconde de fato o outro lado', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [propostas[0], propostas[1], entrada];
    renderInbox();
    await user.click(await screen.findByRole('button', { name: /Entradas \(1\)/ }));
    expect(await screen.findByText(/CRISLAINE/)).toBeInTheDocument();
    expect(screen.queryByText(/POSTO AGRICOPEL/)).not.toBeInTheDocument();
  });

  it('some quando só há um dos dois — filtro de uma opção é ruído', async () => {
    estadoDaFila.dados = [propostas[0], propostas[1]];
    renderInbox();
    await screen.findByText(/POSTO AGRICOPEL/);
    expect(screen.queryByRole('button', { name: /Entradas \(/ })).not.toBeInTheDocument();
  });

  it('ENTRADA recebe plano de contas de RECEITA, não de despesa', async () => {
    // O defeito exato que o gestor apontou. `CategoriaDespesaSelect` caía no padrão
    // 'payable' e oferecia só despesa — obrigando a classificar um recebimento como gasto.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [entrada];
    renderInbox();

    await user.click(await seletorDeCategoria());
    expect(await screen.findByText('Serviços prestados')).toBeInTheDocument();
    expect(screen.getByText('Venda de peças e produtos')).toBeInTheDocument();
    expect(screen.queryByText('Peças e materiais')).not.toBeInTheDocument();
    expect(screen.queryByText('Pró-labore e retirada')).not.toBeInTheDocument();
  });

  it('SAÍDA continua com plano de despesa', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [propostas[0]];
    renderInbox();
    await user.click(await seletorDeCategoria());
    expect(await screen.findByText('Peças e materiais')).toBeInTheDocument();
    expect(screen.queryByText('Serviços prestados')).not.toBeInTheDocument();
  });
});

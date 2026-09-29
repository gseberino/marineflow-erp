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
    // O limite vem de app_settings; aqui fixo, para o teste não depender de rede.
    useLimiteLote: () => 500,
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
          { name: 'Transferência entre contas', dre_group: 'nao_operacional' },
        ]
      : [
          { name: 'Combustível e deslocamento', dre_group: 'custo_direto' },
          { name: 'Peças e materiais', dre_group: 'custo_direto' },
          { name: 'Pró-labore', dre_group: 'nao_operacional' },
        ],
    isLoading: false,
  }),
}));

// Centros de custo: um ativo e um dos sete antigos, desativado — que não pode ser oferecido.
vi.mock('@/hooks/use-cost-centers', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-cost-centers')>();
  return {
    ...real,
    useCostCenters: () => ({
      data: [
        { id: 'cc-obra', name: 'Obras e reformas da sede', type: 'expense', parent_id: null, active: true },
        { id: 'cc-velho', name: 'Despesas Administrativas', type: 'expense', parent_id: null, active: false },
      ],
    }),
  };
});

// As contas da HBR como estão cadastradas: é delas que sai o "Conta C6", "Cartão Nubank final…".
const { contasDaHBR } = vi.hoisted(() => ({
  contasDaHBR: new Map([
    ['c6', { id: 'c6', label: 'C6 - Conta PJ HBR', institution: null, provider: 'pluggy' }],
    ['nu', { id: 'nu', label: 'Nubank PJ HBR', institution: null, provider: 'pluggy' }],
  ]),
}));
vi.mock('@/hooks/use-bank-connections', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-bank-connections')>()),
  useContasDaHBR: () => contasDaHBR,
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

describe('linha que pode já estar lançada', () => {
  afterEach(() => { estadoDaFila.dados = null; aprovarMock.mockClear(); });

  it('não aprova no escuro: pede casar ou lançar novo, e manda a escolha', async () => {
    aprovarMock.mockClear();
    estadoDaFila.dados = [{
      id: 'p84', kind: 'create_receivable', status: 'pending', bank_transaction_id: 't84', related_transaction_id: null,
      title: 'Receita: POWER LOG LTDA', reasoning: 'x', confidence: 30, suggested_amount: 591.41, suggested_date: '2026-08-20',
      suggested_category: 'Outras receitas', suggested_description: 'POWER LOG LTDA', suggested_supplier_id: null,
      suggested_client_id: null, dre_group: 'receita', created_at: '2026-08-20T10:00:00Z',
      vinculo_sugerido: { principal: {
        tipo: 'existing_payment', id: 'pg84', rotulo: 'Pagamento já lançado: Sinal — ORÇ-00084', valor: 591.41, confianca: 60,
        nivel: 'weak', motivos: ['Valor exato'], diferenca: 0, lancamentoId: 'r84', lado: 'receivable', ordemDeServicoId: 'os84',
        clienteId: 'c', clienteNome: 'ROBSON', converteOrcamento: false, jaLancado: true,
      }, alternativas: [] },
    }];
    const user = userEvent.setup();
    renderInbox();
    // Nem no lote ela entra: vai para a revisão individual.
    expect(await screen.findByText(/Revisar uma a uma .*(1)/)).toBeInTheDocument();
    const aprovar = screen.getByRole('button', { name: /Responda a sugestão de vínculo antes de aprovar/ });
    expect(aprovar).toBeDisabled();
    await user.click(screen.getByRole('radio', { name: /Casar com Sinal — ORÇ-00084/ }));
    const liberado = screen.getByRole('button', { name: 'Aprovar e lançar' });
    expect(liberado).toBeEnabled();
    await user.click(liberado);
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({ ids: ['p84'], overrides: { p84: { vinculo: { id: 'pg84' } } } });
  });
});

/**
 * "É desta OS?" — decisão do dono (26/09/2026): a ligação com o serviço se faz pelo casamento
 * de informações ou à mão, "mas o sistema deve sempre questionar". A OS sugerida não pode
 * chegar ao lançamento sem a pessoa responder.
 */
describe('OS sugerida é pergunta', () => {
  afterEach(() => { estadoDaFila.dados = null; aprovarMock.mockClear(); });

  const comOS = {
    id: 'p9', kind: 'create_payable', status: 'pending', bank_transaction_id: 't9', related_transaction_id: null,
    title: 'Despesa: LOJA DE CABOS', reasoning: 'x', confidence: 92, suggested_amount: 1200, suggested_date: '2026-09-20',
    suggested_category: 'Peças e materiais', suggested_description: 'LOJA DE CABOS', suggested_supplier_id: null,
    suggested_service_order_id: 'os9', dre_group: 'custo_direto', created_at: '2026-09-20T10:00:00Z',
  };

  it('sem resposta, aprovar não leva a OS', async () => {
    estadoDaFila.dados = [comOS];
    const user = userEvent.setup();
    renderInbox();
    expect(await screen.findByText(/É desta OS\?/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toEqual({ ids: ['p9'], overrides: {} });
  });

  it('"Sim, é desta" manda a OS; "Não é" manda sem OS', async () => {
    estadoDaFila.dados = [comOS];
    const user = userEvent.setup();
    renderInbox();
    await user.click(await screen.findByRole('button', { name: 'Sim, é desta' }));
    expect(await screen.findByText(/Ligada à/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({ ids: ['p9'], overrides: { p9: { serviceOrderId: 'os9' } } });

    await user.click(screen.getByRole('button', { name: 'mudar' }));
    await user.click(await screen.findByRole('button', { name: 'Não é' }));
    expect(await screen.findByText(/você disse que não é desta/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[1][0]).toMatchObject({ ids: ['p9'], overrides: { p9: { serviceOrderId: null } } });
  });

  it('linha pequena com OS sugerida não vai para o lote: fica para responder', async () => {
    estadoDaFila.dados = [{ ...comOS, suggested_amount: 80 }];
    renderInbox();
    expect(await screen.findByText(/Revisar uma a uma .*perguntas de vínculo, OS ou "para onde foi" \(1\)/)).toBeInTheDocument();
  });

  it('OS que é do próprio vínculo não pergunta duas vezes', async () => {
    estadoDaFila.dados = [{ ...comOS, vinculo_sugerido: { principal: {
      tipo: 'payable', id: 'c9', rotulo: 'Conta a pagar da OS 60', valor: 1200, confianca: 80, nivel: 'probable',
      motivos: [], diferenca: 0, lancamentoId: 'c9', lado: 'payable', ordemDeServicoId: 'os9', clienteId: null,
      clienteNome: null, converteOrcamento: false, jaLancado: false,
    }, alternativas: [] } }];
    renderInbox();
    expect(await screen.findByText('Despesa: LOJA DE CABOS')).toBeInTheDocument();
    expect(screen.queryByText(/É desta OS\?/)).not.toBeInTheDocument();
  });

  it('OS que o dono anotou já vem respondida — e "não é" desfaz', async () => {
    estadoDaFila.dados = [{ ...comOS, evidencia: { anotacao: { id: 'a1', os_id: 'os9' } } }];
    const user = userEvent.setup();
    renderInbox();
    expect(await screen.findByText(/Você anotou que é da/)).toBeInTheDocument();
    expect(screen.queryByText(/É desta OS\?/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'não é' }));
    expect(await screen.findByText(/você disse que não é desta/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({ overrides: { p9: { serviceOrderId: null } } });
  });

  it('ordem de compra e OS são perguntas separadas: "não é" numa não apaga a outra', async () => {
    estadoDaFila.dados = [{ ...comOS, suggested_purchase_order_id: 'oc9' }];
    const user = userEvent.setup();
    renderInbox();
    expect(await screen.findByText(/Este pagamento é dela\?/)).toBeInTheDocument();
    expect(screen.getByText(/É desta OS\?/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Sim, é desta' }));
    await user.click(screen.getByRole('button', { name: 'Não é' }));
    expect(await screen.findByText(/Não paga a ordem de compra/)).toBeInTheDocument();
    expect(screen.getByText(/Ligada à/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({ overrides: { p9: { purchaseOrderId: null, serviceOrderId: 'os9' } } });
  });

  it('ordem de compra: "Sim, é dela" manda a OC', async () => {
    estadoDaFila.dados = [{ ...comOS, suggested_service_order_id: null, suggested_purchase_order_id: 'oc9' }];
    const user = userEvent.setup();
    renderInbox();
    await user.click(await screen.findByRole('button', { name: 'Sim, é dela' }));
    expect(await screen.findByText(/Paga a/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({ overrides: { p9: { purchaseOrderId: 'oc9' } } });
  });
});

describe('busca na fila do Extrato', () => {
  it('acha pelo valor digitado e as contagens passam a falar só do encontrado', async () => {
    const user = userEvent.setup();
    renderInbox();
    await user.type(await screen.findByLabelText('Buscar'), '18.001,04');
    expect(screen.getByText('1 de 3')).toBeInTheDocument();
    expect(screen.getAllByText(/MARINE EXPRESS/).length).toBeGreaterThan(0);
    expect(screen.queryByText(/POSTO AGRICOPEL/)).not.toBeInTheDocument();
  });

  it('busca sem resultado diz onde a linha pode estar', async () => {
    const user = userEvent.setup();
    renderInbox();
    await user.type(await screen.findByLabelText('Buscar'), 'nao existe nada assim');
    expect(screen.getByText(/Se a linha já foi aprovada, ela está em Contas a/)).toBeInTheDocument();
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

  // NOTA DE PROJETO: a regra deste bloco já mudou duas vezes. A primeira versão aprovava só
  // as abaixo de R$ 500; em agosto o gestor reinterpretou ("o que exige atenção é a
  // incerteza, não o valor") e o grupo passou a aprovar tudo depois de uma conferência; em
  // 14/09/2026 o dono decidiu de novo, e a decisão vale: ACIMA DO LIMITE É UMA A UMA. O botão
  // do grupo alcança só o que está abaixo; a grande fica na linha, já classificada. O servidor
  // recusa em lote o que passa do limite, então a tela não é a única barreira.

  it('o grupo aprova só as abaixo do limite; a grande fica para a linha', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [...miudas, grande];
    renderInbox();

    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Peças e materiais'));
    // 23 propostas no grupo, 22 no botão: a de R$ 4 mil não entra.
    await user.click(await screen.findByRole('button', { name: /Aprovar 22/ }));

    const [chamada] = aprovarMock.mock.calls[0];
    expect(chamada.ids).toHaveLength(22);
    expect(chamada.ids).not.toContain('g-grande');
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

  it('a linha com nome comprido não estoura a janela', async () => {
    // Filho de flex nasce com `min-width: auto`: sem `min-w-0`/`truncate`, um nome de
    // estabelecimento longo empurra a linha para fora da caixa e leva o layout junto. O
    // usuário odeia rolagem lateral. (Antes isto era testado na conferência do grupo, que
    // deixou de existir com a decisão de 14/09 — a linha é onde a grande vive agora.)
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    estadoDaFila.dados = [{
      ...grande,
      title: 'Despesa: EC *ESTABELECIMENTO COM NOME ABSURDAMENTE LONGO QUE NAO CABE NA LINHA SAO PAULO BRA',
    }, ...miudas];
    renderInbox();

    await user.click(await screen.findByText(/Ver as 23 linhas/));
    const item = await screen.findByText('Despesa: EC *ESTABELECIMENTO COM NOME ABSURDAMENTE LONGO QUE NAO CABE NA LINHA SAO PAULO BRA');
    expect(item.className).toMatch(/truncate/);
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

  it('grupo em que TODAS passam do limite diz por escrito que é uma a uma', async () => {
    // Decisão do dono (14/09/2026): valor alto é aprovado individualmente, mesmo quando é a
    // norma da categoria (pró-labore, impostos). O botão do grupo não some nem finge — fica
    // apagado com o motivo à vista, e as linhas continuam aprováveis uma a uma.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    // 20 é o piso do modo agrupado — abaixo disso a tela mostra a lista simples.
    estadoDaFila.dados = Array.from({ length: 20 }, (_, i) => ({
      ...grande, id: `gg${i}`, bank_transaction_id: `tgg${i}`,
    }));
    renderInbox();

    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Pró-labore'));

    expect(await screen.findByRole('button', { name: /Aprovar 0/ })).toBeDisabled();
    expect(screen.getByText(/Todas passam de .* — aprove uma a uma/)).toBeInTheDocument();
    expect(aprovarMock).not.toHaveBeenCalled();
  });

  it('alerta do vigilante vive em seção própria, sem categoria, com "Ciente" no lugar de aprovar', async () => {
    // Decisão do dono (14/09/2026): o vigilante SÓ AVISA. O alerta não pode cair no lote, no
    // grupo por favorecido nem oferecer categoria — "Ciente" e "Descartar" tiram da lista.
    estadoDaFila.dados = [
      ...miudas,
      {
        ...miudas[0], id: 'al1', kind: 'anomaly', bank_transaction_id: null, bank_transactions: null,
        title: 'Valor acima do padrão: UNIFIQUE — R$ 900,00 (costuma ser ~R$ 300,00)',
        reasoning: '4 pagamentos anteriores, mediana R$ 300,00.', suggested_amount: 900, suggested_category: null,
      },
    ];
    renderInbox();
    expect(await screen.findByText(/Alertas do vigilante/)).toBeInTheDocument();
    expect(screen.getByText('Valor acima do padrão: UNIFIQUE — R$ 900,00 (costuma ser ~R$ 300,00)')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Ciente — tirar da lista/ })).toBeInTheDocument();
    // O alerta não entra na contagem do lote nem do grupo: continuam as 22 miúdas.
    expect(screen.getByText('22 propostas')).toBeInTheDocument();
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
    await user.click(await screen.findByRole('button', { name: /Mais ações para Despesa: POSTO AGRICOPEL/i }));
    await user.click(await screen.findByRole('menuitem', { name: /duplicata/i }));
    expect(duplicataMock).toHaveBeenCalledWith(
      expect.objectContaining({ propostaId: 'p1', bankTransactionId: 't1' }),
    );
  });

  it('dá para ensinar uma regra a partir da linha que está na tela', async () => {
    const user = userEvent.setup();
    renderInbox();
    await user.click(await screen.findByRole('button', { name: /Mais ações para Despesa: POSTO AGRICOPEL/i }));
    await user.click(await screen.findByRole('menuitem', { name: /regra a partir desta linha/i }));
    expect(regraMock).toHaveBeenCalledWith(
      expect.objectContaining({ set_category: 'Combustível e deslocamento' }),
    );
  });

  it('na linha só fica o Aprovar; descartar e duplicata esperam no menu, no fim', async () => {
    // Eram quatro ícones lado a lado, com "Descartar" encostado em "Aprovar" e do mesmo
    // tamanho (padrão AcoesDaLinha, pedido do dono de 23/09/2026).
    const user = userEvent.setup();
    renderInbox();
    await screen.findByRole('button', { name: /Mais ações para Despesa: POSTO AGRICOPEL/i });
    expect(screen.queryByRole('button', { name: /Descartar esta proposta/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /duplicata/i })).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Mais ações para Despesa: POSTO AGRICOPEL/i }));
    const itens = (await screen.findAllByRole('menuitem')).map((i) => i.textContent);
    expect(itens).toEqual([
      'Criar uma regra a partir desta linha', 'É duplicata — tirar da fila', 'Descartar esta proposta',
    ]);
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
    await user.click(await screen.findByText('Pró-labore'));
    expect(await screen.findByText(/Quem recebeu/)).toBeInTheDocument();
  });

  it('oferece cadastrar o favorecido que falta', async () => {
    // Abrir dois Radix Select em sequência exige esperar o primeiro desmontar: enquanto
    // ele fecha, o overlay deixa a página com pointer-events: none e o clique seguinte
    // não chega em ninguém.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Pró-labore'));

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
    expect(await screen.findByText('Receita: CRISLAINE REGINA CIOLI')).toBeInTheDocument();
    expect(screen.queryByText(/POSTO AGRICOPEL/)).not.toBeInTheDocument();
  });

  it('some quando só há um dos dois — filtro de uma opção é ruído', async () => {
    estadoDaFila.dados = [propostas[0], propostas[1]];
    renderInbox();
    await screen.findByText('Despesa: POSTO AGRICOPEL LTDA');
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
    expect(screen.queryByText('Pró-labore')).not.toBeInTheDocument();
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

/**
 * "Para onde foi?" e a observação — pedido do dono (26/09/2026): "só tem o campo de selecionar
 * a despesa e os botões de ações, isso não basta". Serviço de terceiro diz para onde foi (o
 * serviço de um cliente ou a própria HBR) e o que foi feito; qualquer linha ganha observação e
 * centro de custo.
 */
describe('serviço de terceiro pergunta para onde foi', () => {
  afterEach(() => { estadoDaFila.dados = null; aprovarMock.mockClear(); regraMock.mockClear(); });

  const servico = {
    id: 'p7', kind: 'create_payable', status: 'pending', bank_transaction_id: 't7', related_transaction_id: null,
    title: 'Despesa: JOAO PINTOR', reasoning: 'x', confidence: 95, suggested_amount: 350, suggested_date: '2026-09-25',
    suggested_category: 'Serviços de terceiros', suggested_description: 'JOAO PINTOR', suggested_supplier_id: null,
    dre_group: 'custo_direto', created_at: '2026-09-25T10:00:00Z',
  };

  it('não entra no lote e não aprova sem dizer para onde foi e o que foi feito', async () => {
    estadoDaFila.dados = [servico];
    renderInbox();
    expect(await screen.findByText(/Revisar uma a uma .*\(1\)/)).toBeInTheDocument();
    expect(screen.getByText('Para onde foi este serviço?')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Serviço de terceiro: diga para onde foi .* e o que foi feito/ })).toBeDisabled();
    expect(screen.queryByText(/Aprovação em lote/)).not.toBeInTheDocument();
  });

  it('"Para a HBR": pede o centro de custo (só os ativos) e manda a categoria da empresa com o que foi feito', async () => {
    estadoDaFila.dados = [servico];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click(await screen.findByRole('button', { name: 'Para a HBR' }));
    await user.type(screen.getByLabelText('O que foi feito'), 'pintura da fachada da sede');
    expect(screen.getByRole('button', { name: /diga o centro de custo/ })).toBeDisabled();

    await user.click(screen.getByLabelText('Centro de custo'));
    expect(screen.queryByText('Despesas Administrativas')).not.toBeInTheDocument();
    await user.click(await screen.findByText('Obras e reformas da sede'));

    const aprovar = await screen.findByRole('button', { name: 'Aprovar e lançar' });
    expect(aprovar).toBeEnabled();
    await user.click(aprovar);
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({
      ids: ['p7'],
      overrides: { p7: {
        destino: 'empresa', category: 'Serviços de terceiros para a empresa', serviceOrderId: null,
        costCenterId: 'cc-obra', notes: 'pintura da fachada da sede',
      } },
    });
  });

  it('"Serviço de um cliente": pede a OS — ou que o serviço não tem OS no sistema', async () => {
    estadoDaFila.dados = [servico];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click(await screen.findByRole('button', { name: 'Serviço de um cliente' }));
    await user.type(screen.getByLabelText('O que foi feito'), 'solda no casco');
    expect(screen.getByRole('button', { name: /diga a OS do cliente/ })).toBeDisabled();

    await user.click(screen.getByLabelText('De qual OS'));
    await user.click(await screen.findByText('O serviço não tem OS no sistema'));
    await user.click(await screen.findByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({
      overrides: { p7: { destino: 'cliente', category: 'Serviços de terceiros', serviceOrderId: null, notes: 'solda no casco' } },
    });
  });

  it('linha comum ganha observação quando o dono quer, e ela vai na aprovação', async () => {
    // A de R$ 18 mil: fica na revisão individual, com o botão de aprovar próprio.
    estadoDaFila.dados = [propostas[1]];
    const user = userEvent.setup();
    renderInbox();
    // Fechada por padrão: centenas de linhas não precisam dela.
    await user.click(await screen.findByRole('button', { name: /\+ Observação e centro de custo/ }));
    await user.type(screen.getByLabelText('Observação'), 'cabos para o estoque');
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({ overrides: { p2: { notes: 'cabos para o estoque' } } });
  });

  it('respondida, a linha pequena não pula de seção: continua onde estava, pronta para aprovar', async () => {
    estadoDaFila.dados = [servico];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click(await screen.findByRole('button', { name: 'Serviço de um cliente' }));
    await user.type(screen.getByLabelText('O que foi feito'), 'solda no casco');
    await user.click(screen.getByLabelText('De qual OS'));
    await user.click(await screen.findByText('O serviço não tem OS no sistema'));
    expect(screen.getByText(/Revisar uma a uma .*\(1\)/)).toBeInTheDocument();
    expect(screen.queryByText(/Aprovação em lote/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Aprovar e lançar' })).toBeEnabled();
  });

  it('regra a partir de uma ENTRADA é pelo CPF/CNPJ e já leva o cliente', async () => {
    estadoDaFila.dados = [{
      id: 'e9', kind: 'create_receivable', status: 'pending', bank_transaction_id: 'te9', related_transaction_id: null,
      title: 'Receita: MARIA SILVA', reasoning: 'x', confidence: 30, suggested_amount: 800, suggested_date: '2026-09-24',
      suggested_category: 'Serviços prestados', suggested_description: 'MARIA SILVA', suggested_supplier_id: null,
      suggested_client_id: 'c-joao', dre_group: 'receita', created_at: '2026-09-24T10:00:00Z',
      bank_transactions: { counterparty_name: 'MARIA SILVA', counterparty_document: '123.456.789-01', source_type: 'bank' },
    }];
    const user = userEvent.setup();
    renderInbox();
    await user.click(await screen.findByRole('button', { name: /Mais ações para Receita: MARIA SILVA/i }));
    await user.click(await screen.findByRole('menuitem', { name: /regra a partir desta linha/i }));
    expect(regraMock).toHaveBeenCalledWith({
      match_type: 'document', match_value: '12345678901', direction: 'credit',
      set_client_id: 'c-joao', set_category: 'Serviços prestados',
    });
  });

  it('entrada sem CPF/CNPJ não vira regra (nome não identifica ninguém)', async () => {
    estadoDaFila.dados = [{
      id: 'e10', kind: 'create_receivable', status: 'pending', bank_transaction_id: 'te10', related_transaction_id: null,
      title: 'Receita: PIX RECEBIDO', reasoning: 'x', confidence: 30, suggested_amount: 800, suggested_date: '2026-09-24',
      suggested_category: 'Outras receitas', suggested_description: 'PIX RECEBIDO', suggested_supplier_id: null,
      suggested_client_id: null, dre_group: 'receita', created_at: '2026-09-24T10:00:00Z',
      bank_transactions: { counterparty_name: null, counterparty_document: null, source_type: 'bank' },
    }];
    const user = userEvent.setup();
    renderInbox();
    await user.click(await screen.findByRole('button', { name: /Mais ações para Receita: PIX RECEBIDO/i }));
    await user.click(await screen.findByRole('menuitem', { name: /regra a partir desta linha/i }));
    expect(regraMock).not.toHaveBeenCalled();
  });
});

describe('revisão de 27/09: centro escondido, contradição e cabeçalho do grupo', () => {
  afterEach(() => { estadoDaFila.dados = null; aprovarMock.mockClear(); });

  const servico = {
    id: 'p7', kind: 'create_payable', status: 'pending', bank_transaction_id: 't7', related_transaction_id: null,
    title: 'Despesa: JOAO PINTOR', reasoning: 'x', confidence: 95, suggested_amount: 650, suggested_date: '2026-09-25',
    suggested_category: 'Serviços de terceiros', suggested_description: 'JOAO PINTOR', suggested_supplier_id: null,
    dre_group: 'custo_direto', created_at: '2026-09-25T10:00:00Z',
  };

  it('voltar de "Para a HBR" para "Serviço de um cliente" tira o centro de custo escondido', async () => {
    estadoDaFila.dados = [servico];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click(await screen.findByRole('button', { name: 'Para a HBR' }));
    await user.click(screen.getByLabelText('Centro de custo'));
    await user.click(await screen.findByText('Obras e reformas da sede'));
    await user.click(screen.getByRole('button', { name: 'Serviço de um cliente' }));
    await user.type(screen.getByLabelText('O que foi feito'), 'solda no casco');
    await user.click(screen.getByLabelText('De qual OS'));
    await user.click(await screen.findByText('O serviço não tem OS no sistema'));
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0].overrides.p7).toMatchObject({ destino: 'cliente', costCenterId: null });
  });

  it('para a HBR E ligada à OS do cliente: a tela não libera (o servidor recusaria)', async () => {
    estadoDaFila.dados = [{ ...servico, suggested_service_order_id: 'os9' }];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    await user.click(await screen.findByRole('button', { name: 'Para a HBR' }));
    await user.click(screen.getByLabelText('Centro de custo'));
    await user.click(await screen.findByText('Obras e reformas da sede'));
    await user.type(screen.getByLabelText('O que foi feito'), 'pintura da sede');
    // "Para a HBR" respondeu "não é desta OS"; desdizer e responder "Sim" contradiz o destino.
    await user.click(screen.getByRole('button', { name: 'mudar' }));
    await user.click(await screen.findByRole('button', { name: 'Sim, é desta' }));
    expect(screen.getByRole('button', { name: /escolha um dos dois/ })).toBeDisabled();
  });

  // 20 é o piso do modo agrupado.
  const doPintor = (i: number, extra: Record<string, unknown> = {}) => ({
    ...servico, id: `g${i}`, bank_transaction_id: `tg${i}`, suggested_amount: 100,
    bank_transactions: { counterparty_name: 'JOAO PINTOR', source_type: 'bank' }, ...extra,
  });

  it('o cabeçalho só pergunta "para onde foram" quando TODAS as linhas são serviço', async () => {
    estadoDaFila.dados = [
      doPintor(0),
      ...Array.from({ length: 19 }, (_, i) => doPintor(i + 1, { suggested_category: 'Outras despesas' })),
    ];
    renderInbox();
    expect(await screen.findByText('20 propostas')).toBeInTheDocument();
    expect(screen.queryByText('Para onde foram estes serviços?')).not.toBeInTheDocument();
  });

  it('respondido no cabeçalho, vale para as linhas sem resposta — e não apaga a de quem respondeu diferente', async () => {
    estadoDaFila.dados = [
      doPintor(0, { title: 'Despesa: JOAO PINTOR (a da lancha)' }),
      ...Array.from({ length: 19 }, (_, i) => doPintor(i + 1)),
    ];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    // Uma linha responde por conta própria: serviço de um cliente.
    await user.click(await screen.findByText(/Ver as 20 linhas/));
    const aDaLancha = (await screen.findByText('Despesa: JOAO PINTOR (a da lancha)')).closest('div.rounded-lg, [class*="p-3"]') as HTMLElement;
    await user.click(within(aDaLancha).getByRole('button', { name: 'Serviço de um cliente' }));

    // O cabeçalho responde "Para a HBR" para o grupo.
    const cabecalho = screen.getByText('Para onde foram estes serviços?').closest('div.space-y-2') as HTMLElement;
    await user.click(within(cabecalho).getByRole('button', { name: 'Para a HBR' }));
    await user.click(within(cabecalho).getByLabelText('Centro de custo'));
    await user.click(await screen.findByText('Obras e reformas da sede'));
    await user.type(within(cabecalho).getByLabelText('O que foi feito'), 'pintura da sede');

    // A linha que respondeu "cliente" continua "cliente".
    expect(within(aDaLancha).getByRole('button', { name: 'Serviço de um cliente' })).toHaveAttribute('aria-pressed', 'true');
    // As outras 19 vão no lote do grupo como despesa da empresa.
    await user.click(screen.getByRole('button', { name: /Aprovar 19/ }));
    const { ids, overrides } = aprovarMock.mock.calls[0][0];
    expect(ids).toHaveLength(19);
    expect(ids).not.toContain('g0');
    expect(overrides.g1).toMatchObject({
      destino: 'empresa', category: 'Serviços de terceiros para a empresa', costCenterId: 'cc-obra', notes: 'pintura da sede',
    });
  });
});

/**
 * Observações do dono de 28/09/2026: de qual conta ou cartão o dinheiro saiu (para ir direto ao
 * aplicativo certo), entrada de transferência sem pedir cliente e a OS conferível sem sair da fila.
 */
describe('observações de 28/09: banco de origem, entrada sem cliente, ver a OS', () => {
  afterEach(() => { estadoDaFila.dados = null; aprovarMock.mockClear(); });

  const entrada = (id: string, categoria: string, extra: Record<string, unknown> = {}) => ({
    id, kind: 'create_receivable', status: 'pending', bank_transaction_id: `t-${id}`, related_transaction_id: null,
    title: 'Receita: HBR ENGENHARIA', reasoning: 'x', confidence: 40, suggested_amount: 2000, suggested_date: '2026-09-27',
    suggested_category: categoria, suggested_description: 'HBR ENGENHARIA', suggested_supplier_id: null,
    suggested_client_id: null, dre_group: 'nao_operacional', created_at: '2026-09-27T10:00:00Z',
    bank_transactions: { counterparty_name: 'HBR ENGENHARIA', source_type: 'bank', bank_connection_id: 'nu', transaction_type: 'credit' },
    ...extra,
  });

  it('a compra no cartão diz QUAL cartão: banco e final', async () => {
    estadoDaFila.dados = [{
      ...propostas[0],
      bank_transactions: { counterparty_name: 'POSTO AGRICOPEL', source_type: 'credit_card', card_last_digits: '4922', bank_connection_id: 'nu' },
    }];
    renderInbox();
    expect(await screen.findByText('Cartão Nubank final 4922')).toBeInTheDocument();
  });

  it('a transferência diz de qual conta saiu e em qual entrou', async () => {
    estadoDaFila.dados = [{
      ...propostas[2],
      bank_transactions: { counterparty_name: null, source_type: 'bank', bank_connection_id: 'c6', transaction_type: 'debit' },
      outra_perna: { source_type: 'bank', card_last_digits: null, bank_connection_id: 'nu', transaction_type: 'credit' },
    }];
    renderInbox();
    expect(await screen.findByText('Conta C6 → Conta Nubank')).toBeInTheDocument();
  });

  it('entrada de transferência entre contas não pede cliente e aprova sem ele', async () => {
    estadoDaFila.dados = [entrada('e20', 'Transferência entre contas')];
    const user = userEvent.setup();
    renderInbox();
    expect(await screen.findByText(/Dinheiro de outra conta da HBR: não é receita e não tem cliente/)).toBeInTheDocument();
    expect(screen.queryByText('De qual cliente veio?')).not.toBeInTheDocument();
    // Sai da fila sem lançamento: não há centro de custo a escolher, só a observação.
    expect(screen.getByRole('button', { name: '+ Observação' })).toBeInTheDocument();
    // Sai sem receita: decisão desta linha, nunca do lote (revisão de 28/09/2026). Na lista é a
    // seção que diz; o selo "Sai sem receita" é do agrupado (finance-inbox-grouping.test).
    expect(screen.getByText(/Revisar uma a uma .*\(1\)/)).toBeInTheDocument();
    expect(screen.queryByText(/Aprovação em lote/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Aprovar e lançar' }));
    // Vai a categoria que a linha mostrou: reclassificada no servidor com a tela aberta, a linha
    // não pode sair com outra que ninguém viu.
    expect(aprovarMock.mock.calls[0][0]).toEqual({ ids: ['e20'], overrides: { e20: { category: 'Transferência entre contas' } } });
  });

  it('entrada PEQUENA trocada para transferência na seção do lote ganha o botão dela', async () => {
    // Abaixo do limite, sem pergunta: nasce no lote, onde a linha não tem botão próprio. Trocada
    // para transferência, o "Aprovar selecionadas" a tira — sem o botão, não haveria saída.
    estadoDaFila.dados = [entrada('e30', 'Outras receitas', { suggested_amount: 200, dre_group: 'receita' })];
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderInbox();
    expect(await screen.findByText(/Aprovação em lote/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Aprovar e lançar' })).not.toBeInTheDocument();
    await user.click(await seletorDeCategoria());
    await user.click(await screen.findByText('Transferência entre contas'));
    await user.click(await screen.findByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({
      ids: ['e30'], overrides: { e30: { category: 'Transferência entre contas' } },
    });
  });

  it('casar numa entrada de transferência é contradição: "nenhum destes" é que sai sem receita', async () => {
    estadoDaFila.dados = [entrada('e31', 'Transferência entre contas', {
      vinculo_sugerido: { principal: {
        tipo: 'receivable', id: 'r1', rotulo: 'Conta a receber de JOÃO', valor: 2000, confianca: 70,
        nivel: 'weak', motivos: ['Valor exato'], diferenca: 0, lancamentoId: 'rec-1', lado: 'receivable', ordemDeServicoId: null,
        clienteId: 'c-joao', clienteNome: 'JOÃO', converteOrcamento: false, jaLancado: false,
      }, alternativas: [] },
    })];
    const user = userEvent.setup();
    renderInbox();
    await user.click(await screen.findByRole('radio', { name: /Casar com Conta a receber de JOÃO/ }));
    const frase = /Casar ou registrar sinal diz que é recebimento de cliente/;
    expect(await screen.findByText(frase)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: frase })).toBeDisabled();
    await user.click(screen.getByRole('radio', { name: /Nenhum destes — sai sem receita/ }));
    await user.click(await screen.findByRole('button', { name: 'Aprovar e lançar' }));
    expect(aprovarMock.mock.calls[0][0]).toMatchObject({ ids: ['e31'], overrides: { e31: { vinculo: 'nenhum' } } });
  });

  it('transferência ou aporte ligado a uma OS não sai: escolha uma só', async () => {
    estadoDaFila.dados = [entrada('e23', 'Aporte de sócio', { suggested_service_order_id: 'os9' })];
    const user = userEvent.setup();
    renderInbox();
    // Sem resposta, a OS sugerida não liga: aprovar é possível.
    expect(await screen.findByRole('button', { name: 'Aprovar e lançar' })).toBeEnabled();
    await user.click(screen.getByRole('button', { name: 'Sim, é desta' }));
    const frase = /ligada a uma OS, mas transferência e aporte de sócio não são receita/;
    expect(await screen.findByText(frase)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: frase })).toBeDisabled();
    // "Não é desta" desfaz a contradição.
    await user.click(screen.getByRole('button', { name: 'mudar' }));
    await user.click(await screen.findByRole('button', { name: 'Não é' }));
    expect(await screen.findByRole('button', { name: 'Aprovar e lançar' })).toBeEnabled();
    expect(screen.queryByText(frase)).not.toBeInTheDocument();
  });

  it('aporte de sócio também não pede cliente', async () => {
    estadoDaFila.dados = [entrada('e21', 'Aporte de sócio')];
    renderInbox();
    expect(await screen.findByText(/Dinheiro do sócio entrando na empresa/)).toBeInTheDocument();
    expect(screen.queryByText('De qual cliente veio?')).not.toBeInTheDocument();
  });

  it('receita de verdade continua pedindo o cliente', async () => {
    estadoDaFila.dados = [entrada('e22', 'Serviços prestados', { dre_group: 'receita' })];
    renderInbox();
    expect(await screen.findByText('De qual cliente veio?')).toBeInTheDocument();
    expect(screen.queryByText(/não é receita e não tem cliente/)).not.toBeInTheDocument();
  });

  it('a OS sugerida tem o botão de conferir, ao lado da pergunta', async () => {
    estadoDaFila.dados = [{
      id: 'p9', kind: 'create_payable', status: 'pending', bank_transaction_id: 't9', related_transaction_id: null,
      title: 'Despesa: LOJA DE CABOS', reasoning: 'x', confidence: 92, suggested_amount: 1200, suggested_date: '2026-09-20',
      suggested_category: 'Peças e materiais', suggested_description: 'LOJA DE CABOS', suggested_supplier_id: null,
      suggested_service_order_id: 'os9', dre_group: 'custo_direto', created_at: '2026-09-20T10:00:00Z',
    }];
    renderInbox();
    const pergunta = (await screen.findByText(/É desta OS\?/)).parentElement as HTMLElement;
    expect(within(pergunta).getByRole('button', { name: 'Ver OS (só leitura)' })).toBeInTheDocument();
  });
});

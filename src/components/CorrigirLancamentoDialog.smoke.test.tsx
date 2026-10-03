// Corrigir lançamento — inclusive pago — e desfazer/cancelar com motivo.
//
// O que se fixa aqui é o que fez o dono parar de confiar no financeiro: o que ele aprovava
// errado não tinha conserto. Conta paga precisa abrir para correção; valor que veio do
// banco não pode mudar à mão; mês fechado só aceita observação; e só o que MUDOU vai para o
// banco — senão a trilha registra dez campos quando ele trocou um.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { CorrigirLancamentoDialog, camposQueMudaram, type Formulario } from './CorrigirLancamentoDialog';
import { DesfazerOuCancelarDialog } from './DesfazerOuCancelarDialog';

const { corrigirMock, desfazerMock, cancelarMock, ajustarMock, tirarMock, entrada, vinculo, periodos, pix } = vi.hoisted(() => ({
  corrigirMock: vi.fn(),
  desfazerMock: vi.fn(),
  cancelarMock: vi.fn(),
  ajustarMock: vi.fn(),
  tirarMock: vi.fn(),
  entrada: { dado: null as null | {
    data: string; valor: number; quem: string; aplicado: number; sobra: number;
    aplicacoes: Array<{ pagamentoId: string; contaId: string; descricao: string; valor: number }>;
  } },
  vinculo: { dado: null as null | {
    linha: { data: string; descricao: string; valor: number; pagamentoId: string | null };
    pagamentos: Array<{ id: string; valor: number; data: string }>;
    nasceuDoExtrato: boolean;
  } },
  periodos: { lista: [] as Array<{ ano: number; mes: number; reaberto_em: string | null }> },
  pix: { partes: null as null | Array<{ id: string; amount: number; expense_category: string | null; divisao_id: string | null }> },
}));

vi.mock('@/hooks/use-lancamentos', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-lancamentos')>()),
  useCorrigirLancamento: () => ({ mutate: corrigirMock, isPending: false }),
  useDesfazerAprovacao: () => ({ mutate: desfazerMock, isPending: false }),
  useCancelarLancamento: () => ({ mutate: cancelarMock, isPending: false }),
  useAjustarAoValorDoBanco: () => ({ mutate: ajustarMock, isPending: false }),
  useVinculoComExtrato: () => ({ data: vinculo.dado, isLoading: false }),
  usePixDividido: () => ({ data: pix.partes }),
  useEntradaAplicada: () => ({ data: entrada.dado, isLoading: false }),
  useDesfazerAplicacao: () => ({ mutate: tirarMock, isPending: false }),
  useAplicarEntradaEmContas: () => ({ mutate: vi.fn(), isPending: false }),
  useContasEmAbertoDoCliente: () => ({ data: [], isLoading: false }),
  usePagamentosSemPixDoCliente: () => ({ data: [] }),
}));
vi.mock('@/hooks/use-fechamento', () => ({ usePeriodosFechados: () => ({ data: periodos.lista }) }));
vi.mock('@/hooks/use-suppliers', () => ({
  useSuppliers: () => ({ data: [{ id: 's1', name: 'Coremma', cnpj_cpf: '11.111.111/0001-11', email: null }] }),
  useCreateSupplier: () => ({ mutateAsync: vi.fn(), isPending: false }),
}));
vi.mock('@/hooks/use-cost-centers', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-cost-centers')>()),
  useCostCenters: () => ({ data: [] }),
}));
vi.mock('@/hooks/use-payees', () => ({
  usePayees: () => ({ data: [] }),
  useServiceOrdersVinculaveis: () => ({ data: [{ id: 'os1', service_order_number: 'OS-60', status: 'in_progress', clients: { name: 'Cliente' } }] }),
  useClientesParaReceita: () => ({ data: [] }),
  ROTULO_TIPO: {},
}));
vi.mock('@/hooks/use-financial-categories', () => ({
  useFinancialCategories: () => ({ data: [{ id: 'c1', name: 'Outras despesas' }, { id: 'c2', name: 'Alimentação de campo' }] }),
}));
vi.mock('@/hooks/use-finance-review', () => ({ useCriarCategoriaDespesa: () => ({ mutate: vi.fn(), isPending: false }) }));

const despesaPagaDoBanco = {
  id: 'p1', description: 'Pix enviado para JOSE', amount: 150, paid_amount: 150, status: 'paid',
  issue_date: '2026-09-10', due_date: '2026-09-10', notes: null, cost_center_id: null,
  bank_transaction_id: 'bt1', expense_category: 'Outras despesas', supplier_id: null, payee_id: null,
  linked_service_order_id: null,
};

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

beforeEach(() => {
  pix.partes = null;
  corrigirMock.mockReset(); desfazerMock.mockReset(); cancelarMock.mockReset(); ajustarMock.mockReset(); tirarMock.mockReset();
  vinculo.dado = null;
  entrada.dado = null;
  periodos.lista = [];
});

describe('CorrigirLancamentoDialog', () => {
  it('abre para uma despesa PAGA, com o valor do banco travado', () => {
    renderizar(<CorrigirLancamentoDialog tipo="payable" lancamento={despesaPagaDoBanco} onFechar={() => {}} />);
    expect(screen.getByText('Corrigir conta a pagar')).toBeInTheDocument();
    expect(screen.getByText(/Ligado a uma linha do banco: o conserto está logo abaixo/)).toBeInTheDocument();
    // Tudo que pode estar errado numa despesa aprovada aparece para correção.
    for (const campo of ['Fornecedor', 'Categoria', 'Favorecido (pessoa)', 'OS (custo de qual serviço)', 'Data do lançamento']) {
      expect(screen.getByText(campo)).toBeInTheDocument();
    }
    // Sem mudança, o botão diz isso em vez de gravar nada.
    expect(screen.getByRole('button', { name: 'Nada mudou' })).toBeDisabled();
  });

  it('manda só o campo que mudou, com o motivo', async () => {
    const user = userEvent.setup();
    renderizar(<CorrigirLancamentoDialog tipo="payable" lancamento={despesaPagaDoBanco} onFechar={() => {}} />);
    const descricao = screen.getByDisplayValue('Pix enviado para JOSE');
    await user.clear(descricao);
    await user.type(descricao, 'Almoço da equipe');
    await user.type(screen.getByPlaceholderText(/Ex\.: era almoço/), 'era almoço');
    await user.click(screen.getByRole('button', { name: 'Salvar correção' }));
    expect(corrigirMock).toHaveBeenCalledTimes(1);
    expect(corrigirMock.mock.calls[0][0]).toEqual({
      tipo: 'payable', id: 'p1', campos: { description: 'Almoço da equipe' }, motivo: 'era almoço',
    });
  });

  it('mês fechado: avisa antes e só deixa a observação mudar', async () => {
    periodos.lista = [{ ano: 2026, mes: 9, reaberto_em: null }];
    const user = userEvent.setup();
    renderizar(<CorrigirLancamentoDialog tipo="payable" lancamento={despesaPagaDoBanco} onFechar={() => {}} />);
    expect(screen.getByText(/O mês deste lançamento está fechado/)).toBeInTheDocument();
    expect(screen.getByDisplayValue('Pix enviado para JOSE')).toBeDisabled();
    await user.type(screen.getByRole('textbox', { name: /Observações/ }), 'conferido com a nota');
    await user.click(screen.getByRole('button', { name: 'Salvar correção' }));
    expect(corrigirMock.mock.calls[0][0].campos).toEqual({ notes: 'conferido com a nota' });
  });
});

describe('CorrigirLancamentoDialog — ligado ao extrato (pedido do dono, 02/10/2026)', () => {
  // O caso que motivou: sinal do ORÇ-00073 de R$ 1.865,47; o cliente pagou R$ 1.866,00.
  const sinal = {
    id: 'r73', description: 'Sinal — ORÇ-00073', amount: 1865.47, paid_amount: 1865.47, status: 'paid',
    issue_date: '2026-07-31', due_date: '2026-07-31', notes: null, cost_center_id: null,
    bank_transaction_id: 'bt73', category: 'Serviços prestados', client_id: 'cli', service_order_id: null,
  };
  const linhaDoSinal = {
    linha: { data: '2026-07-30', descricao: 'RF SILVA ESTACIONAMENTOS LTDA', valor: 1866, pagamentoId: 'pg73' },
    pagamentos: [{ id: 'pg73', valor: 1865.47, data: '2026-07-31' }],
    nasceuDoExtrato: false,
  };

  it('diz o que não bate e ajusta ao valor do banco, com confirmação', async () => {
    const user = userEvent.setup();
    vinculo.dado = linhaDoSinal;
    renderizar(<CorrigirLancamentoDialog tipo="receivable" lancamento={sinal} onFechar={() => {}} />);
    expect(screen.getByText(/Ligado ao extrato: .*RF SILVA ESTACIONAMENTOS LTDA/)).toBeInTheDocument();
    expect(screen.getByText(/o cliente pagou R\$\s?0,53 a mais que este lançamento/)).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Ajustar para R\$\s?1\.866,00/ }));
    expect(ajustarMock).not.toHaveBeenCalled(); // o primeiro clique só mostra o que vai acontecer
    expect(screen.getByText(/passam a valer R\$\s?1\.866,00, o que entrou no banco/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Confirmar ajuste' }));
    expect(ajustarMock).toHaveBeenCalledTimes(1);
    expect(ajustarMock.mock.calls[0][0]).toEqual({ tipo: 'receivable', id: 'r73' });
  });

  it('desfazer diz qual aprovação e o que acontece, e só age na confirmação', async () => {
    const user = userEvent.setup();
    vinculo.dado = linhaDoSinal;
    renderizar(<CorrigirLancamentoDialog tipo="receivable" lancamento={sinal} onFechar={() => {}} />);
    await user.click(screen.getByRole('button', { name: 'Desfazer o vínculo com o extrato' }));
    expect(screen.getByText(/mantém este lançamento .* devolve a linha do banco para a fila do Extrato/)).toBeInTheDocument();
    expect(desfazerMock).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: /Confirmar: desfazer o vínculo/ }));
    expect(desfazerMock).toHaveBeenCalledTimes(1);
    expect(desfazerMock.mock.calls[0][0]).toEqual({ tipo: 'receivable', id: 'r73' });
  });

  it('dois pagamentos: explica e não oferece o ajuste', () => {
    vinculo.dado = {
      linha: { data: '2026-05-20', descricao: 'RITA', valor: 25000, pagamentoId: 'a' },
      pagamentos: [{ id: 'a', valor: 25000, data: '2026-05-20' }, { id: 'b', valor: 4000, data: '2026-07-20' }],
      nasceuDoExtrato: false,
    };
    renderizar(<CorrigirLancamentoDialog tipo="receivable" lancamento={{ ...sinal, amount: 29000, paid_amount: 29000 }} onFechar={() => {}} />);
    expect(screen.getByText(/tem 2 pagamento\(s\)/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Ajustar/ })).not.toBeInTheDocument();
  });

  it('mês fechado: explica e não oferece ajustar nem desfazer', () => {
    vinculo.dado = linhaDoSinal;
    periodos.lista = [{ ano: 2026, mes: 7, reaberto_em: null }];
    renderizar(<CorrigirLancamentoDialog tipo="receivable" lancamento={sinal} onFechar={() => {}} />);
    expect(screen.getByText(/para ajustar ou desfazer, reabra o mês/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Ajustar/ })).not.toBeInTheDocument();
  });
});

describe('CorrigirLancamentoDialog — um Pix para várias contas (forma A, F2, 02/10/2026)', () => {
  // O caso do Lenine: Pix de R$ 4.800 = sinal do ORÇ-00074 (R$ 2.280) + sinal do ORÇ-00077 (R$ 2.520).
  const sinal74 = {
    id: 'r74', description: 'Sinal — ORÇ-00074', amount: 2280, paid_amount: 2280, status: 'paid',
    issue_date: '2026-08-11', due_date: '2026-08-11', notes: null, cost_center_id: null,
    bank_transaction_id: 'btL', category: null, client_id: 'cli', service_order_id: null,
  };
  const linhaDoLenine = {
    linha: { data: '2026-08-11', descricao: 'Pix recebido de LENINE LORI BROCCA', valor: 4800, pagamentoId: 'pa' },
    pagamentos: [{ id: 'pa', valor: 2280, data: '2026-08-11' }],
    nasceuDoExtrato: false,
  };

  it('diz que o Pix pagou também a outra conta, não oferece ajustar e deixa tirar a outra da entrada', async () => {
    const user = userEvent.setup();
    vinculo.dado = linhaDoLenine;
    entrada.dado = {
      data: '2026-08-11', valor: 4800, quem: 'LENINE', aplicado: 4800, sobra: 0,
      aplicacoes: [
        { pagamentoId: 'pa', contaId: 'r74', descricao: 'Sinal — ORÇ-00074', valor: 2280 },
        { pagamentoId: 'pb', contaId: 'r77', descricao: 'Sinal — ORÇ-00077', valor: 2520 },
      ],
    };
    renderizar(<CorrigirLancamentoDialog tipo="receivable" lancamento={sinal74} onFechar={() => {}} />);
    expect(screen.getByText(/pagou também Sinal — ORÇ-00077 \(R\$\s?2\.520,00\)\. Ela está toda aplicada/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Ajustar/ })).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Tirar desta entrada' }));
    expect(tirarMock).not.toHaveBeenCalled(); // primeiro diz o que acontece
    expect(screen.getByText(/"Sinal — ORÇ-00077" deixa de ser paga por esta entrada/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Confirmar: tirar desta entrada' }));
    expect(tirarMock).toHaveBeenCalledTimes(1);
    expect(tirarMock.mock.calls[0][0]).toEqual({ pagamentoId: 'pb' });
  });

  it('Pix maior que a conta: oferece aplicar a sobra em outra conta antes de ajustar', () => {
    vinculo.dado = linhaDoLenine;
    entrada.dado = {
      data: '2026-08-11', valor: 4800, quem: 'LENINE', aplicado: 2280, sobra: 2520,
      aplicacoes: [{ pagamentoId: 'pa', contaId: 'r74', descricao: 'Sinal — ORÇ-00074', valor: 2280 }],
    };
    renderizar(<CorrigirLancamentoDialog tipo="receivable" lancamento={sinal74} onFechar={() => {}} />);
    expect(screen.getByText(/Acima de R\$ 10, avalie: se o Pix pagou também outra conta, aplique a sobra nela/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Aplicar os R\$\s?2\.520,00 que sobraram em outra conta/ })).toBeInTheDocument();
    // Ajustar continua possível (pagou a mais de propósito), mas como segunda opção.
    expect(screen.getByRole('button', { name: /Ajustar para R\$\s?4\.800,00/ })).toBeInTheDocument();
  });
});

describe('camposQueMudaram', () => {
  const base: Formulario = {
    description: 'Peças', notes: '', categoria: 'Outras despesas', contraparte: 's1', payee_id: '',
    os: 'os1', cost_center_id: '', issue_date: '2026-09-01', due_date: '2026-09-01', amount: 100,
  };
  it('traduz para as colunas de cada lado e limpa com null', () => {
    expect(camposQueMudaram(base, { ...base, categoria: 'Alimentação de campo', os: '' }, 'payable'))
      .toEqual({ expense_category: 'Alimentação de campo', linked_service_order_id: null });
    expect(camposQueMudaram(base, { ...base, categoria: 'Serviços', os: '' }, 'receivable'))
      .toEqual({ category: 'Serviços', service_order_id: null });
  });
  it('não trata arredondamento e espaço como mudança', () => {
    expect(camposQueMudaram(base, { ...base, amount: 100.001, description: ' Peças ' }, 'payable')).toEqual({});
  });
});

describe('DesfazerOuCancelarDialog', () => {
  const alvo = { id: 'p1', description: 'Pix enviado para JOSE', amount: 150, bank_transaction_id: 'bt1', origin: 'bank_reconciliation' };

  it('cancelar exige motivo e avisa para onde vai a linha do extrato', async () => {
    const user = userEvent.setup();
    renderizar(<DesfazerOuCancelarDialog tipo="payable" acao="cancelar" lancamento={alvo} onFechar={() => {}} />);
    expect(screen.getByText(/vai para "Fora da fila" com o mesmo motivo/)).toBeInTheDocument();
    const botao = screen.getByRole('button', { name: 'Cancelar lançamento' });
    expect(botao).toBeDisabled();
    await user.type(screen.getByLabelText(/Motivo/), 'despesa pessoal');
    await user.click(botao);
    expect(cancelarMock.mock.calls[0][0]).toEqual({ tipo: 'payable', id: 'p1', motivo: 'despesa pessoal' });
  });

  it('desfazer não exige motivo e diz que a linha volta para a fila', async () => {
    const user = userEvent.setup();
    renderizar(<DesfazerOuCancelarDialog tipo="payable" acao="desfazer" lancamento={alvo} onFechar={() => {}} />);
    expect(screen.getByText(/volta para a fila do Extrato/)).toBeInTheDocument();
    expect(screen.queryByText(/Este Pix está dividido/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Desfazer aprovação' }));
    expect(desfazerMock.mock.calls[0][0]).toEqual({ tipo: 'payable', id: 'p1', motivo: null });
  });

  it('Pix dividido (pró-labore + retirada): avisa antes que a ação vale para o pagamento inteiro', () => {
    pix.partes = [
      { id: 'p2', amount: 2379, expense_category: 'Retirada de sócio', divisao_id: 'p1' },
      { id: 'p1', amount: 1621, expense_category: 'Pró-labore', divisao_id: null },
    ];
    renderizar(<DesfazerOuCancelarDialog tipo="payable" acao="cancelar" lancamento={alvo} onFechar={() => {}} />);
    const aviso = screen.getByText(/Este Pix está dividido/);
    expect(aviso.textContent?.replace(/ /g, ' ')).toBe(
      'Este Pix está dividido em Pró-labore R$ 1.621,00 + Retirada de sócio R$ 2.379,00. '
      + 'Cancelar vale para o pagamento inteiro de R$ 4.000,00. Para mudar só uma parte (um gasto pessoal, por exemplo), use Corrigir.',
    );
  });
});

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

const { corrigirMock, desfazerMock, cancelarMock, periodos } = vi.hoisted(() => ({
  corrigirMock: vi.fn(),
  desfazerMock: vi.fn(),
  cancelarMock: vi.fn(),
  periodos: { lista: [] as Array<{ ano: number; mes: number; reaberto_em: string | null }> },
}));

vi.mock('@/hooks/use-lancamentos', () => ({
  useCorrigirLancamento: () => ({ mutate: corrigirMock, isPending: false }),
  useDesfazerAprovacao: () => ({ mutate: desfazerMock, isPending: false }),
  useCancelarLancamento: () => ({ mutate: cancelarMock, isPending: false }),
}));
vi.mock('@/hooks/use-fechamento', () => ({ usePeriodosFechados: () => ({ data: periodos.lista }) }));
vi.mock('@/hooks/use-suppliers', () => ({
  useSuppliers: () => ({ data: [{ id: 's1', name: 'Coremma', cnpj_cpf: '11.111.111/0001-11', email: null }] }),
  useCreateSupplier: () => ({ mutateAsync: vi.fn(), isPending: false }),
}));
vi.mock('@/hooks/use-cost-centers', () => ({ useCostCenters: () => ({ data: [] }) }));
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
  corrigirMock.mockReset(); desfazerMock.mockReset(); cancelarMock.mockReset();
  periodos.lista = [];
});

describe('CorrigirLancamentoDialog', () => {
  it('abre para uma despesa PAGA, com o valor do banco travado', () => {
    renderizar(<CorrigirLancamentoDialog tipo="payable" lancamento={despesaPagaDoBanco} onFechar={() => {}} />);
    expect(screen.getByText('Corrigir conta a pagar')).toBeInTheDocument();
    expect(screen.getByText(/Veio do extrato\. Para mudar, desfaça a aprovação/)).toBeInTheDocument();
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
    await user.click(screen.getByRole('button', { name: 'Desfazer aprovação' }));
    expect(desfazerMock.mock.calls[0][0]).toEqual({ tipo: 'payable', id: 'p1', motivo: null });
  });
});

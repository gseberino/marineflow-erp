// Extrato por conta, com saldo, e o que foi lançado sozinho (Fase 3).
//
// O que se fixa: o saldo de abertura e de fechamento saem das próprias linhas (a mesma conta
// da conferência); cada linha diz o que virou; "lançados sozinhos" tem interruptor e
// desfazer — o que foi feito sem clique precisa ser visível e reversível.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { ExtratoPorConta } from './ExtratoPorConta';

const { desfazerMock, salvarMock, estado } = vi.hoisted(() => ({
  desfazerMock: vi.fn(),
  salvarMock: vi.fn(),
  estado: { auto: 'on' },
}));

vi.mock('@/hooks/use-bank-connections', () => ({
  useBankConnections: () => ({ data: [{ id: 'c6', label: 'C6 - Conta PJ HBR' }] }),
}));
vi.mock('@/hooks/use-fechamento', () => ({
  useConferenciasDeSaldo: () => ({ data: [{ bank_connection_id: 'c6', fecha: true, diferenca: 0, saldo_do_provedor: 1386.61 }] }),
}));
vi.mock('@/hooks/use-app-settings', () => ({
  useAppSetting: () => estado.auto,
  useUpdateAppSetting: () => ({ mutate: salvarMock, isPending: false }),
}));
vi.mock('@/hooks/use-lancamentos', () => ({
  useDesfazerAprovacao: () => ({ mutate: desfazerMock, isPending: false }),
}));
vi.mock('@/hooks/use-extrato-conta', () => ({
  useLancadosSozinhos: () => ({ data: [{
    id: 'q1', title: 'Despesa: POSTO AGRICOPEL', suggested_amount: 180.5, suggested_category: 'Combustível e deslocamento',
    suggested_date: '2026-09-20', decided_at: '2026-09-21T09:00:00Z', decision_note: 'Lançada sozinha: confiança 90%',
    automatica: 'confianca', created_payable_id: 'p1', created_receivable_id: null, bank_transactions: { bank_connection_id: 'c6' },
  }] }),
  useExtratoDaConta: () => ({ isLoading: false, error: null, data: [
    // Mais recente primeiro, como a função devolve.
    { id: 't3', data: '2026-09-23', descricao: 'Pix enviado', contraparte: 'JOSE CARLOS ABEL', documento: null, tipo: 'debit', valor: -150,
      saldo_apos: 850, situacao: 'lancada', pendente: false, lancamento_tipo: 'payable', lancamento_id: 'p9', lancamento_descricao: 'x',
      categoria: 'Serviços de terceiros', quem: 'José Carlos', tipo_fora: null, motivo_fora: null, proposta_id: null },
    { id: 't2', data: '2026-09-10', descricao: 'Pix recebido', contraparte: 'MP MOTORHOMES', documento: '44051448000100', tipo: 'credit', valor: 500,
      saldo_apos: 1000, situacao: 'nova', pendente: false, lancamento_tipo: null, lancamento_id: null, lancamento_descricao: null,
      categoria: null, quem: null, tipo_fora: null, motivo_fora: null, proposta_id: 'q9' },
    { id: 't1', data: '2026-09-02', descricao: 'PGTO FAT CARTAO', contraparte: null, documento: null, tipo: 'debit', valor: -200,
      saldo_apos: 500, situacao: 'fora', pendente: false, lancamento_tipo: null, lancamento_id: null, lancamento_descricao: null,
      categoria: null, quem: null, tipo_fora: 'fatura_cartao', motivo_fora: 'Pagamento de fatura', proposta_id: null },
  ] }),
}));
vi.mock('@/components/FinanceReviewInbox', () => ({ FinanceReviewInbox: ({ contaId }: { contaId: string | null }) => <div>fila da conta {contaId ?? 'todas'}</div> }));
vi.mock('@/components/IgnoradasPanel', () => ({ IgnoradasPanel: ({ contaId }: { contaId: string | null }) => <div>fora da fila {contaId ?? 'todas'}</div> }));
// As fichas de saldo têm teste próprio; aqui só importa que escolher uma ficha escolhe a conta.
vi.mock('@/components/SaldosDasContas', () => ({
  SaldosDasContas: ({ onEscolher }: { onEscolher?: (id: string | null) => void }) => (
    <div><button type="button" onClick={() => onEscolher?.('c6')}>ficha C6</button><button type="button" onClick={() => onEscolher?.(null)}>ficha todas</button></div>
  ),
}));

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

beforeEach(() => { desfazerMock.mockReset(); salvarMock.mockReset(); estado.auto = 'on'; });

describe('ExtratoPorConta', () => {
  it('abre na fila de todas as contas; extrato com saldo pede uma conta, por escrito', async () => {
    const user = userEvent.setup();
    renderizar(<ExtratoPorConta />);
    expect(screen.getByText('fila da conta todas')).toBeInTheDocument();
    // Botão apagado não mostra dica: o motivo tem de estar escrito.
    await user.click(screen.getByRole('tab', { name: 'Extrato com saldo' }));
    expect(screen.getByText(/Escolha uma conta nas fichas acima/)).toBeInTheDocument();
  });

  it('a ficha escolhe a conta da fila', async () => {
    const user = userEvent.setup();
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: 'ficha C6' }));
    expect(screen.getByText('fila da conta c6')).toBeInTheDocument();
  });

  it('lançados sozinhos: interruptor e desfazer', async () => {
    const user = userEvent.setup();
    renderizar(<ExtratoPorConta />);
    await user.click(screen.getByRole('button', { name: /Lançados sozinhos/ }));
    expect(screen.getByText('Despesa: POSTO AGRICOPEL')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Desfazer/ }));
    expect(desfazerMock.mock.calls[0][0]).toMatchObject({ tipo: 'payable', id: 'p1' });
    // Desligar pede confirmação: o primeiro clique não muda nada.
    await user.click(screen.getByRole('button', { name: 'Ligado — desligar' }));
    expect(salvarMock).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: 'Sim, desligar' }));
    expect(salvarMock).toHaveBeenCalledWith({ key: 'finance_auto_approve', value: 'off' });
  });

  it('link antigo de "Fora da fila" abre essa visão', () => {
    renderizar(<ExtratoPorConta visaoInicial="fora" />);
    expect(screen.getByText('fora da fila todas')).toBeInTheDocument();
  });
});

describe('ExtratoComSaldo (dentro do Extrato por conta)', () => {
  it('mostra saldo de abertura e fechamento e o que cada linha virou', async () => {
    const { ExtratoComSaldo } = await import('./ExtratoComSaldo');
    renderizar(<ExtratoComSaldo conexaoId="c6" nomeDaConta="C6" />);
    // Abertura = saldo da linha mais antiga menos o valor dela: 500 − (−200) = 700.
    expect(screen.getByText('R$ 700,00')).toBeInTheDocument();
    expect(screen.getByText('R$ 850,00')).toBeInTheDocument();
    expect(screen.getByText(/Lançada:/)).toBeInTheDocument();
    expect(screen.getByText('Esperando decisão no Extrato')).toBeInTheDocument();
    expect(screen.getByText(/Fora da fila: Pagamento de fatura/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Lançadas (1)' })).toBeInTheDocument();
  });
});

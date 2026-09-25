// Caixa pela tela: o botão diz o que falta, "do bolso do sócio" pede o sócio, saque vai
// para mover_caixa e a anotação sem classificação não sai.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { LancarNoCaixaDialog, AnotarTransacaoDialog, AnotacoesAguardando } from './CaixaDialogs';

const { lancar, mover, anotar, cancelar } = vi.hoisted(() => ({
  lancar: vi.fn(), mover: vi.fn(), anotar: vi.fn(), cancelar: vi.fn(),
}));

vi.mock('@/hooks/use-caixa', () => ({
  useLancarNoCaixa: () => ({ mutate: lancar, isPending: false }),
  useMoverCaixa: () => ({ mutate: mover, isPending: false }),
  useAjustarCaixa: () => ({ mutate: vi.fn(), isPending: false }),
  useAnotarTransacao: () => ({ mutate: anotar, isPending: false }),
  useCancelarAnotacao: () => ({ mutate: cancelar, isPending: false }),
  useAnotacoesAguardando: () => ({ data: [{ id: 'a1', sentido: 'debit', valor: 1500, data_prevista: '2026-09-25', documento: '90136409000122', nome: 'TSD', categoria: 'Frete e importação', descricao: null, criada_em: '2026-09-25T10:00:00Z', suppliers: { name: 'TSD LOGISTICA' } }] }),
}));
vi.mock('@/hooks/use-payees', () => ({
  usePayees: () => ({ data: [
    { id: 'p-gus', name: 'Gustavo Seberino', kind: 'socio' },
    { id: 'p-rob', name: 'Roberto Silva', kind: 'diarista' },
  ] }),
  useServiceOrdersVinculaveis: () => ({ data: [] }),
  useClientesParaReceita: () => ({ data: [{ id: 'c-mp', name: 'MP MOTOR HOMES' }] }),
  ROTULO_TIPO: { socio: 'Sócio', diarista: 'Diarista' },
}));
vi.mock('@/hooks/use-suppliers', () => ({ useSuppliers: () => ({ data: [] }) }));
vi.mock('@/hooks/use-financial-categories', () => ({ useFinancialCategories: () => ({ data: [{ id: '1', name: 'Alimentação de campo' }] }) }));
vi.mock('@/hooks/use-finance-review', () => ({ useCriarCategoriaDespesa: () => ({ mutate: vi.fn(), isPending: false }) }));

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

beforeEach(() => { lancar.mockReset(); mover.mockReset(); anotar.mockReset(); cancelar.mockReset(); });

describe('LancarNoCaixaDialog', () => {
  it('o botão diz o que falta, na ordem em que se preenche', async () => {
    const user = userEvent.setup();
    renderizar(<LancarNoCaixaDialog onFechar={() => {}} />);
    expect(screen.getByRole('button', { name: 'Falta o valor' })).toBeDisabled();
    await user.type(screen.getByLabelText('Valor'), '5000');
    expect(screen.getByRole('button', { name: 'Falta o que foi' })).toBeDisabled();
    await user.type(screen.getByLabelText('O que foi *'), 'Almoço da equipe');
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(lancar.mock.calls[0][0]).toMatchObject({ sentido: 'saida', valor: 50, descricao: 'Almoço da equipe', pagoPor: 'caixa' });
  });

  it('do bolso do sócio exige o sócio', async () => {
    const user = userEvent.setup();
    renderizar(<LancarNoCaixaDialog onFechar={() => {}} />);
    await user.type(screen.getByLabelText('Valor'), '8000');
    await user.type(screen.getByLabelText('O que foi *'), 'Peça no balcão');
    await user.click(screen.getByRole('checkbox'));
    expect(screen.getByRole('button', { name: 'Falta o sócio que pagou' })).toBeDisabled();
  });

  it('saque do banco vai para mover_caixa, sem descrição', async () => {
    const user = userEvent.setup();
    renderizar(<LancarNoCaixaDialog onFechar={() => {}} />);
    await user.click(screen.getByRole('tab', { name: 'Saque do banco' }));
    await user.type(screen.getByLabelText('Valor'), '50000');
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(mover.mock.calls[0][0]).toMatchObject({ sentido: 'saque', valor: 500 });
    expect(lancar).not.toHaveBeenCalled();
  });

  it('recebimento exige cliente', async () => {
    const user = userEvent.setup();
    renderizar(<LancarNoCaixaDialog onFechar={() => {}} />);
    await user.click(screen.getByRole('tab', { name: 'Recebimento' }));
    await user.type(screen.getByLabelText('Valor'), '30000');
    await user.type(screen.getByLabelText('O que foi *'), 'Serviço');
    expect(screen.getByRole('button', { name: 'Falta o cliente' })).toBeDisabled();
  });
});

describe('anotação antecipada', () => {
  it('não anota sem dizer como classificar', async () => {
    const user = userEvent.setup();
    renderizar(<AnotarTransacaoDialog onFechar={() => {}} />);
    await user.type(screen.getByLabelText('Valor'), '150000');
    expect(screen.getByRole('button', { name: 'Anotar' })).toBeDisabled();
  });

  it('lista o que espera o banco, com cancelar', async () => {
    const user = userEvent.setup();
    renderizar(<AnotacoesAguardando />);
    expect(screen.getByText(/esperando o banco \(1\)/)).toBeInTheDocument();
    expect(screen.getByText(/TSD LOGISTICA/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Cancelar anotação' }));
    expect(cancelar).toHaveBeenCalledWith('a1');
  });
});

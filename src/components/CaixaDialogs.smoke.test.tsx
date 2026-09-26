// Lançar à mão pela tela ("+ Lançar") e a anotação antecipada: o botão diz o que falta, cada
// "por onde" chama a função certa do banco, e a anotação sem classificação não sai.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { AnotarTransacaoDialog, AnotacoesAguardando } from './CaixaDialogs';
import { LancarDialog } from './LancarDialog';

const { lancar, mover, anotar, cancelar, ajustar, criarPagar, criarReceber } = vi.hoisted(() => ({
  lancar: vi.fn(), mover: vi.fn(), anotar: vi.fn(), cancelar: vi.fn(), ajustar: vi.fn(), criarPagar: vi.fn(), criarReceber: vi.fn(),
}));

vi.mock('@/hooks/use-caixa', () => ({
  useLancarNoCaixa: () => ({ mutate: lancar, isPending: false }),
  useMoverCaixa: () => ({ mutate: mover, isPending: false }),
  useAjustarCaixa: () => ({ mutate: ajustar, isPending: false }),
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
vi.mock('@/hooks/use-financial', () => ({
  useCreatePayable: () => ({ mutate: criarPagar, isPending: false }),
  useCreateReceivable: () => ({ mutate: criarReceber, isPending: false }),
}));
vi.mock('@/hooks/use-financial-categories', () => ({ useFinancialCategories: () => ({ data: [{ id: '1', name: 'Alimentação de campo' }] }) }));
vi.mock('@/hooks/use-finance-review', () => ({ useCriarCategoriaDespesa: () => ({ mutate: vi.fn(), isPending: false }), useFinanceRules: () => ({ data: [] }) }));

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

beforeEach(() => { for (const m of [lancar, mover, anotar, cancelar, ajustar, criarPagar, criarReceber]) m.mockReset(); });

describe('LancarDialog ("+ Lançar")', () => {
  it('o botão diz o que falta, na ordem em que se preenche; dinheiro vai para o Caixa com a categoria do texto', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog onFechar={() => {}} />);
    expect(screen.getByRole('button', { name: 'Falta o valor' })).toBeDisabled();
    await user.type(screen.getByLabelText('Valor'), '5000');
    expect(screen.getByRole('button', { name: 'Falta o que foi' })).toBeDisabled();
    await user.type(screen.getByLabelText('O que foi *'), 'Almoço da equipe');
    expect(screen.getByRole('button', { name: 'Falta por onde' })).toBeDisabled();
    // O teste do dono (25/09): almoço tem de ir para Alimentação de campo, dito ANTES de gravar.
    expect(screen.getByText('Alimentação de campo')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Dinheiro do Caixa' }));
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(lancar.mock.calls[0][0]).toMatchObject({
      sentido: 'saida', valor: 50, descricao: 'Almoço da equipe', pagoPor: 'caixa', categoria: 'Alimentação de campo',
    });
  });

  it('a ficha do Caixa abre já em "Dinheiro do Caixa"', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog porOndeInicial="caixa" onFechar={() => {}} />);
    await user.type(screen.getByLabelText('Valor'), '2000');
    await user.type(screen.getByLabelText('O que foi *'), 'Gasolina da van');
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(lancar.mock.calls[0][0]).toMatchObject({ pagoPor: 'caixa', categoria: 'Combustível e deslocamento' });
  });

  it('do bolso do sócio exige o sócio e vira reembolso', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog onFechar={() => {}} />);
    await user.type(screen.getByLabelText('Valor'), '8000');
    await user.type(screen.getByLabelText('O que foi *'), 'Peça no balcão');
    await user.click(screen.getByRole('button', { name: 'Do bolso de um sócio' }));
    expect(screen.getByRole('button', { name: 'Falta o sócio' })).toBeDisabled();
  });

  it('Pix/débito fica anotado para casar com a linha do banco', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog onFechar={() => {}} />);
    await user.type(screen.getByLabelText('Valor'), '6480');
    await user.type(screen.getByLabelText('O que foi *'), 'posto na estrada');
    await user.click(screen.getByRole('button', { name: 'Pix, débito ou boleto' }));
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(anotar.mock.calls[0][0]).toMatchObject({ sentido: 'saida', valor: 64.8, categoria: 'Combustível e deslocamento', descricao: 'posto na estrada' });
    expect(lancar).not.toHaveBeenCalled();
  });

  it('anotação do banco não manda a categoria reserva: sem pista, pede a categoria ou para quem', async () => {
    // Mandar "Outras despesas" por falta de palpite apagaria a categoria que o motor acharia
    // sozinho quando a linha chegasse (revisão de 26/09).
    const user = userEvent.setup();
    renderizar(<LancarDialog onFechar={() => {}} />);
    await user.type(screen.getByLabelText('Valor'), '3000');
    await user.type(screen.getByLabelText('O que foi *'), 'coisa diversa');
    await user.click(screen.getByRole('button', { name: 'Pix, débito ou boleto' }));
    expect(screen.getByRole('button', { name: 'Falta a categoria ou para quem' })).toBeDisabled();
    expect(anotar).not.toHaveBeenCalled();
  });

  it('"Ainda vou pagar" pede o vencimento e cria a conta a pagar', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog onFechar={() => {}} />);
    await user.type(screen.getByLabelText('Valor'), '120000');
    await user.type(screen.getByLabelText('O que foi *'), 'Aluguel de outubro');
    await user.click(screen.getByRole('button', { name: 'Ainda vou pagar' }));
    expect(screen.getByRole('button', { name: 'Falta o vencimento' })).toBeDisabled();
    await user.type(screen.getByLabelText('Vencimento *'), '2026-10-10');
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(criarPagar.mock.calls[0][0]).toMatchObject({ amount: 1200, due_date: '2026-10-10', expense_category: 'Aluguel e condomínio' });
  });

  it('saque do banco vai para mover_caixa, sem descrição', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog onFechar={() => {}} />);
    await user.click(screen.getByRole('tab', { name: 'Transferência' }));
    await user.type(screen.getByLabelText('Valor'), '50000');
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(mover.mock.calls[0][0]).toMatchObject({ sentido: 'saque', valor: 500 });
    expect(lancar).not.toHaveBeenCalled();
  });

  it('recebimento exige cliente', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog onFechar={() => {}} />);
    await user.click(screen.getByRole('tab', { name: 'Recebimento' }));
    await user.type(screen.getByLabelText('Valor'), '30000');
    await user.type(screen.getByLabelText('O que foi *'), 'Serviço');
    expect(screen.getByRole('button', { name: 'Falta o cliente' })).toBeDisabled();
  });

  it('"Contei o dinheiro" acerta o Caixa com o motivo', async () => {
    const user = userEvent.setup();
    renderizar(<LancarDialog tipoInicial="contagem" onFechar={() => {}} />);
    expect(screen.getByRole('button', { name: 'Falta o motivo' })).toBeDisabled();
    await user.type(screen.getByLabelText('Saldo contado'), '64000');
    await user.type(screen.getByLabelText('Motivo'), 'saldo inicial');
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(ajustar.mock.calls[0][0]).toMatchObject({ saldoContado: 640, motivo: 'saldo inicial' });
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

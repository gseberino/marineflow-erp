// As fichas de saldo: o Caixa e os dois botões sempre à vista; no Extrato, a ficha escolhe a conta.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { SaldosDasContas } from './SaldosDasContas';

vi.mock('@/hooks/use-saldo-das-contas', () => ({
  useSaldoDasContas: () => ({ isLoading: false, error: null, data: {
    disponivel: 3146.61,
    contas: [
      { id: 'c6', nome: 'C6 - Conta PJ HBR', ehCaixa: false, saldo: 3246.61, conferidoEm: '2026-09-25T21:00:14Z', confere: true, diferenca: 0, contado: true },
      { id: 'cx', nome: 'Caixa (dinheiro)', ehCaixa: true, saldo: -100, conferidoEm: null, confere: null, diferenca: null, contado: false },
    ],
  } }),
}));
vi.mock('@/components/LancarDialog', () => ({
  LancarDialog: ({ tipoInicial, porOndeInicial }: { tipoInicial?: string; porOndeInicial?: string }) =>
    <div>{tipoInicial === 'contagem' ? 'janela contei o dinheiro' : `janela lançar ${porOndeInicial ?? ''}`}</div>,
}));

function renderizar(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider>{ui}</I18nProvider></QueryClientProvider>);
}

describe('SaldosDasContas', () => {
  it('mostra o saldo de cada conta, o total e o aviso de contar o Caixa', () => {
    renderizar(<SaldosDasContas />);
    expect(screen.getByText('R$ 3.246,61')).toBeInTheDocument();
    expect(screen.getByText(/-R\$\s?100,00|R\$\s?-100,00/)).toBeInTheDocument();
    expect(screen.getByText('R$ 3.146,61')).toBeInTheDocument();
    expect(screen.getByText(/conte o dinheiro para começar/)).toBeInTheDocument();
    expect(screen.getByText(/confere/)).toBeInTheDocument();
  });

  it('os botões do Caixa estão sempre à vista e abrem as janelas', async () => {
    const user = userEvent.setup();
    renderizar(<SaldosDasContas />);
    await user.click(screen.getByRole('button', { name: /Contei o dinheiro/ }));
    expect(screen.getByText('janela contei o dinheiro')).toBeInTheDocument();
  });

  it('no Extrato, a ficha escolhe a conta', async () => {
    const user = userEvent.setup();
    const escolher = vi.fn();
    renderizar(<SaldosDasContas contaAtiva={null} onEscolher={escolher} />);
    await user.click(screen.getByRole('button', { name: /C6 - Conta PJ HBR/ }));
    expect(escolher).toHaveBeenCalledWith('c6');
    expect(screen.getByRole('button', { name: /Todas as contas/ })).toHaveAttribute('aria-pressed', 'true');
  });
});

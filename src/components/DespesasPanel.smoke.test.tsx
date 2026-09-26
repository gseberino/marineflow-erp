// A tela Despesas: por categoria, todas as saídas (com o filtro vindo da categoria) e para conferir.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { DespesasPanel } from './DespesasPanel';

const despesa = (o: Record<string, unknown>) => ({
  id: 'x', data: '2026-09-20', descricao: '', valor: 10, categoria: 'Alimentação de campo', grupo: 'custo_direto',
  quem: 'Padaria', deOnde: 'C6', quemClassificou: 'voce', os: null, status: 'paid', semNome: false, bruto: {}, ...o,
});

vi.mock('@/hooks/use-despesas', async (orig) => {
  const real = await orig<typeof import('@/hooks/use-despesas')>();
  return {
    ...real,
    useDespesas: () => ({ isLoading: false, error: null, data: [
      despesa({ id: 'a', valor: 100, quem: 'Almoço equipe', deOnde: 'Caixa (dinheiro)', quemClassificou: 'caixa' }),
      despesa({ id: 'b', valor: 64.8, categoria: 'Outras despesas', grupo: 'despesa_operacional', quem: 'DEBITO DE CARTAO', semNome: true }),
      despesa({ id: 'c', valor: 900, categoria: 'Pagamento de fatura de cartão', grupo: 'nao_operacional', quem: 'C6' }),
      despesa({ id: 'd', valor: 50, categoria: 'Combustível e deslocamento', quem: 'POSTO', quemClassificou: 'confianca' }),
    ] }),
  };
});
vi.mock('@/components/CorrigirLancamentoDialog', () => ({ CorrigirLancamentoDialog: () => <div>janela corrigir</div> }));

function renderizar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><I18nProvider><DespesasPanel /></I18nProvider></QueryClientProvider>);
}

describe('DespesasPanel', () => {
  it('o total bate com o DRE: fatura fica fora até pedir para incluir', async () => {
    const user = userEvent.setup();
    renderizar();
    expect(screen.getByText('R$ 214,80')).toBeInTheDocument();
    expect(screen.queryByText('Pagamento de fatura de cartão')).not.toBeInTheDocument();
    await user.click(screen.getByRole('switch'));
    expect(screen.getByText('R$ 1.114,80')).toBeInTheDocument();
  });

  it('clicar na categoria abre as saídas dela, com de onde saiu e quem classificou', async () => {
    const user = userEvent.setup();
    renderizar();
    await user.click(screen.getByRole('button', { name: /Alimentação de campo/ }));
    expect(screen.getByRole('tab', { name: 'Todas as saídas' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('Almoço equipe')).toBeInTheDocument();
    expect(screen.getByText(/de Caixa \(dinheiro\) · lançado no Caixa/)).toBeInTheDocument();
    expect(screen.queryByText('POSTO')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Corrigir Almoço equipe' }));
    expect(screen.getByText('janela corrigir')).toBeInTheDocument();
  });

  it('para conferir: Outras despesas, sem quem recebeu e lançados sozinhos', async () => {
    const user = userEvent.setup();
    renderizar();
    await user.click(screen.getByRole('tab', { name: 'Para conferir' }));
    expect(screen.getByText(/Em "Outras despesas": 1/)).toBeInTheDocument();
    expect(screen.getByText(/Sem quem recebeu: 1/)).toBeInTheDocument();
    expect(screen.getByText(/Lançados sozinhos: 1/)).toBeInTheDocument();
  });
});

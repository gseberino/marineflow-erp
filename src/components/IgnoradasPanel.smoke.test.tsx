// Smoke de render do livro das ignoradas.
//
// O que se testa aqui não é layout: é que sair da fila deixou de ser sumiço. A tela tem de
// mostrar o que saiu, quanto valia, por quê — e avisar a CONSEQUÊNCIA antes de desfazer,
// porque devolver uma duplicata só repõe a linha, enquanto devolver uma parcela apaga o
// lançamento da compra inteira.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { IgnoradasPanel } from './IgnoradasPanel';

const { grupos, desfazerMock } = vi.hoisted(() => ({
  desfazerMock: vi.fn(),
  grupos: [
    {
      kind: 'duplicata',
      rotulo: 'Duplicata da importação',
      motivo: 'Duplicata da importação manual (mesma transação veio pela sincronização)',
      total: 163020.03,
      transacoes: [
        { id: 'd1', transaction_date: '2026-05-10', description: 'PIX ENVIADO', amount: 1200, counterparty_name: 'FORNECEDOR A', dismissed_at: null },
        { id: 'd2', transaction_date: '2026-05-11', description: 'PIX ENVIADO', amount: 800, counterparty_name: 'FORNECEDOR B', dismissed_at: null },
      ],
    },
    {
      kind: 'parcela',
      rotulo: 'Parcela de compra parcelada',
      motivo: 'Parcela da compra lançada em 2025-11-06 (10x)',
      total: 5038.4,
      transacoes: [
        { id: 'p1', transaction_date: '2026-01-25', description: 'EC *INOHOUSE', amount: 629.8, counterparty_name: 'EC *INOHOUSE', dismissed_at: '2026-08-05T10:00:00Z' },
      ],
    },
  ],
}));

vi.mock('@/hooks/use-finance-review', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-finance-review')>();
  return {
    ...real,
    useIgnoradas: () => ({ data: grupos, isLoading: false }),
    useDesfazerIgnorada: () => ({ mutate: desfazerMock, isPending: false }),
  };
});

function renderPanel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><IgnoradasPanel /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('livro das ignoradas', () => {
  afterEach(() => desfazerMock.mockClear());

  it('mostra o total e diz que nada some do sistema', async () => {
    renderPanel();
    expect(await screen.findByText(/Transações fora da fila/)).toBeInTheDocument();
    expect(screen.getByText(/Nenhuma some do sistema/)).toBeInTheDocument();
  });

  it('agrupa por motivo, com quantidade e valor', async () => {
    renderPanel();
    expect(await screen.findByText('Duplicata da importação')).toBeInTheDocument();
    expect(screen.getByText('Parcela de compra parcelada')).toBeInTheDocument();
  });

  it('avisa a consequência ANTES de devolver — e ela muda por tipo', async () => {
    // Devolver duplicata repõe a linha; devolver parcela apaga o lançamento da compra
    // inteira. Um aviso genérico esconderia justamente a diferença que importa.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderPanel();
    const botoes = await screen.findAllByRole('button', { name: /Devolver à fila/i });
    await user.click(botoes[1]);
    expect(await screen.findByText(/desfaz a COMPRA inteira/)).toBeInTheDocument();
  });

  it('devolve o grupo inteiro depois de confirmar', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderPanel();
    await user.click((await screen.findAllByRole('button', { name: /Devolver à fila/i }))[0]);
    await user.click(await screen.findByRole('button', { name: /^Devolver à fila$/i }));
    expect(desfazerMock).toHaveBeenCalledWith(['d1', 'd2']);
  });

  it('devolve uma linha sozinha, sem mexer no resto', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderPanel();
    await user.click(await screen.findByText(/Ver as 2/));
    await user.click((await screen.findAllByRole('button', { name: /^Devolver$/ }))[0]);
    expect(desfazerMock).toHaveBeenCalledWith(['d1']);
  });
});

// Smoke de render das conexões bancárias. O painel monta estado de sincronização a partir
// de datas e status vindos do banco — só renderizando dá para saber que não quebra.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { BankConnectionsPanel } from './BankConnectionsPanel';

const { conexoes } = vi.hoisted(() => ({
  conexoes: [
    {
      id: 'c1', provider: 'pluggy', external_id: 'item-abc-123', label: 'C6 — conta PJ',
      institution: 'C6 Bank', account_kind: 'bank', active: true,
      last_synced_at: new Date().toISOString(), last_sync_status: 'ok',
      last_sync_message: '12 transação(ões) nova(s)', last_sync_imported: 12,
      last_transaction_date: '2026-07-27',
    },
    {
      id: 'c2', provider: 'pluggy', external_id: 'item-def-456', label: 'Nubank PJ',
      institution: 'Nubank', account_kind: 'bank', active: true,
      last_synced_at: null, last_sync_status: 'error',
      last_sync_message: 'A conexão com o banco caiu. Reconecte esta conta no meu.pluggy.ai.',
      last_sync_imported: 0, last_transaction_date: null,
    },
  ],
}));

vi.mock('@/hooks/use-bank-connections', () => ({
  useBankConnections: () => ({ data: conexoes, isLoading: false }),
  useSaveBankConnection: () => ({ mutateAsync: async () => {}, isPending: false }),
  useDeleteBankConnection: () => ({ mutateAsync: async () => {}, isPending: false }),
  useSyncBank: () => ({ mutateAsync: async () => ({ ok: true, message: 'ok', resultados: [] }), isPending: false }),
  useListPluggyItems: () => ({ mutateAsync: async () => ({ itens: [], clientIdPrefixo: 'abcd1234' }), isPending: false }),
}));

function renderPainel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <BankConnectionsPanel />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('BankConnectionsPanel', () => {
  it('lista as contas conectadas', async () => {
    renderPainel();
    expect(await screen.findByText('C6 — conta PJ')).toBeInTheDocument();
    expect(screen.getByText('Nubank PJ')).toBeInTheDocument();
  });

  it('mostra conexão saudável e conexão com problema de formas distintas', async () => {
    renderPainel();
    expect(await screen.findByText(/em dia/)).toBeInTheDocument();
    expect(screen.getByText(/com problema/)).toBeInTheDocument();
    // O motivo precisa aparecer: consentimento caído é o erro mais comum e a ação de
    // conserto (reconectar no portal) não é óbvia.
    expect(screen.getByText(/Reconecte esta conta no meu.pluggy.ai/)).toBeInTheDocument();
  });

  it('explica onde encontrar o Item ID ao abrir o cadastro', async () => {
    const user = userEvent.setup();
    renderPainel();
    await user.click(screen.getByRole('button', { name: /Conectar conta/i }));
    expect(await screen.findByText(/Onde encontrar o Item ID/)).toBeInTheDocument();
    // Aparece no roteiro e também na mensagem de erro da conexão caída — ambos de propósito.
    expect(screen.getAllByText(/meu\.pluggy\.ai/).length).toBeGreaterThan(0);
    expect(screen.getByText(/Ir para Demo/)).toBeInTheDocument();
  });

  it('oferece buscar o extrato quando há conexões', async () => {
    renderPainel();
    expect(await screen.findByRole('button', { name: /Buscar extrato/i })).toBeInTheDocument();
  });
});

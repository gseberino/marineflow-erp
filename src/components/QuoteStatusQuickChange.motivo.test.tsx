// Retorno F5 (P12.2 e P12.3): "Reprovar" abre o seletor do motivo, com o rótulo acima ("Por que o orçamento foi perdido?"),
// as seis opções e uma nota opcional de até 200 caracteres. O botão só se habilita com um motivo; sem confirmação extra
// (marcar perdido é reversível pela própria tela). O selo do reprovado mostra o motivo.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { QuoteStatusQuickChange, rotuloDoMotivoDaPerda } from './QuoteStatusQuickChange';

const chamadas = vi.hoisted(() => ({ mutate: [] as unknown[] }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) }) }) },
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: async () => {} }));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: () => {} }) }));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {}, info: () => {} } }));
vi.mock('@/hooks/use-payment-conditions', () => ({ usePaymentConditionPresets: () => ({ data: [] }) }));
vi.mock('@/hooks/use-service-orders', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-service-orders')>();
  return {
    ...real,
    useUpdateQuoteStatus: () => ({
      mutateAsync: async (v: unknown) => { chamadas.mutate.push(v); return {}; },
      isPending: false,
    }),
  };
});

function renderSelo(quoteStatus: string, motivoPerda?: string | null) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <QuoteStatusQuickChange orderId="so-1" currentQuoteStatus={quoteStatus} serviceOrderNumber="ORÇ-00151" grandTotal={9840} motivoPerda={motivoPerda} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  chamadas.mutate.length = 0;
});

describe('QuoteStatusQuickChange — o motivo da perda (F5)', () => {
  it('"Reprovado" no menu abre o seletor; sem motivo o botão fica desabilitado e nada é gravado', async () => {
    const user = userEvent.setup();
    renderSelo('sent');
    await user.click(screen.getByRole('button', { name: /enviado/i }));
    await user.click(await screen.findByText('Reprovado'));
    expect(await screen.findByText('Por que o orçamento foi perdido?')).toBeTruthy();
    for (const op of ['Sumiu (sem resposta)', 'Fechou com outro', 'Desistiu', 'Preço', 'Prazo', 'Outro']) {
      expect(screen.getByLabelText(op)).toBeTruthy();
    }
    const botao = screen.getByRole('button', { name: 'Marcar como perdido' }) as HTMLButtonElement;
    expect(botao.disabled).toBe(true);
    expect(chamadas.mutate).toEqual([]);
  });

  it('com motivo, o botão habilita e o mutate leva o motivo e a nota; a nota tem no máximo 200 caracteres', async () => {
    const user = userEvent.setup();
    renderSelo('awaiting_approval');
    await user.click(screen.getByRole('button', { name: /aguardando/i }));
    await user.click(await screen.findByText('Reprovado'));
    await user.click(screen.getByLabelText('Fechou com outro'));
    const nota = screen.getByLabelText(/Nota/) as HTMLTextAreaElement;
    expect(nota.maxLength).toBe(200);
    fireEvent.change(nota, { target: { value: 'fechou com a concorrente' } });
    const botao = screen.getByRole('button', { name: 'Marcar como perdido' }) as HTMLButtonElement;
    expect(botao.disabled).toBe(false);
    await user.click(botao);
    await waitFor(() => expect(chamadas.mutate).toEqual([
      { id: 'so-1', quoteStatus: 'rejected', motivoPerda: 'fechou_com_outro', notaPerda: 'fechou com a concorrente' },
    ]));
  });

  it('"Voltar" fecha sem gravar; as outras transições seguem sem o seletor', async () => {
    const user = userEvent.setup();
    renderSelo('draft');
    await user.click(screen.getByRole('button', { name: /elabora/i }));
    await user.click(await screen.findByText('Reprovado'));
    await user.click(screen.getByRole('button', { name: 'Voltar' }));
    expect(chamadas.mutate).toEqual([]);
    await user.click(screen.getByRole('button', { name: /elabora/i }));
    await user.click(await screen.findByText('Enviado'));
    await waitFor(() => expect(chamadas.mutate).toEqual([{ id: 'so-1', quoteStatus: 'sent' }]));
  });

  it('"Desistência" (aguardando sinal) marca perdido com o motivo desistiu, num clique, como antes', async () => {
    renderSelo('awaiting_deposit');
    fireEvent.click(screen.getByRole('button', { name: /desist/i }));
    await waitFor(() => expect(chamadas.mutate).toEqual([{ id: 'so-1', quoteStatus: 'rejected', motivoPerda: 'desistiu' }]));
  });

  it('o selo do reprovado mostra o motivo; o antigo, "sem motivo (antigo)"; sem motivo, o de antes', () => {
    renderSelo('rejected', 'fechou_com_outro');
    expect(screen.getByText('Reprovado · fechou com outro')).toBeTruthy();
    expect(rotuloDoMotivoDaPerda('sem_motivo_antigo')).toBe('sem motivo (antigo)');
    expect(rotuloDoMotivoDaPerda('preco')).toBe('preço');
    expect(rotuloDoMotivoDaPerda(null)).toBe(null);
  });

  it('o selo do reprovado antigo e o sem motivo', () => {
    const { unmount } = renderSelo('rejected', 'sem_motivo_antigo');
    expect(screen.getByText('Reprovado · sem motivo (antigo)')).toBeTruthy();
    unmount();
    renderSelo('rejected');
    expect(screen.getByText('Reprovado')).toBeTruthy();
  });
});

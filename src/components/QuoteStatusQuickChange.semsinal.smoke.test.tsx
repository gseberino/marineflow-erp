// Converter orçamento em OS SEM sinal (27/10/2026): do selo "Aguardando sinal" e do menu de
// "Aprovado". Prova a ordem das gravações — condição "100% na entrega" + orçamento aprovado, depois
// a conversão pelo mesmo caminho do "Converter em OS" — e que nada grava antes de confirmar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { QuoteStatusQuickChange } from './QuoteStatusQuickChange';

const chamadas = vi.hoisted(() => ({
  ordem: [] as string[], update: [] as unknown[], status: [] as unknown[], assinadoEm: null as string | null,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      // leitura do signed_at ao abrir a confirmação
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { signed_at: chamadas.assinadoEm }, error: null }) }) }),
      update: (v: unknown) => {
        chamadas.ordem.push('update');
        chamadas.update.push(v);
        return { eq: async () => ({ error: null }) };
      },
    }),
  },
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: async () => {} }));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: () => {} }) }));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {}, info: () => {} } }));
vi.mock('@/hooks/use-payment-conditions', () => ({
  usePaymentConditionPresets: () => ({
    data: [
      { id: 'p-50', label: '50% de sinal + 50% na entrega', installments: [
        { tipo: 'aprovacao', services_pct: 50, parts_pct: 50, expenses_pct: 50 },
        { tipo: 'entrega', services_pct: 50, parts_pct: 50, expenses_pct: 50 },
      ] },
      { id: 'p-entrega', label: '100% na entrega', installments: [
        { tipo: 'entrega', services_pct: 100, parts_pct: 100, expenses_pct: 100, days_after_approval: 0 },
      ] },
    ],
  }),
}));
vi.mock('@/hooks/use-service-orders', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-service-orders')>();
  return {
    ...real,
    useUpdateQuoteStatus: () => ({ mutateAsync: async () => ({}), isPending: false }),
    useUpdateServiceOrderStatus: () => ({
      mutateAsync: async (v: unknown) => {
        chamadas.ordem.push('status');
        chamadas.status.push(v);
        return { mudou: true, status: 'approved', texto: '', justConverted: true, numero: 'OS-00321' };
      },
      isPending: false,
    }),
  };
});
vi.mock('@/components/purchasing/PurchaseNeedsDialog', () => ({
  PurchaseNeedsDialog: ({ serviceOrderNumber }: { serviceOrderNumber?: string }) => <div>aviso de compra {serviceOrderNumber}</div>,
}));

function renderSelo(quoteStatus: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <QuoteStatusQuickChange orderId="so-1" currentQuoteStatus={quoteStatus} serviceOrderNumber="ORÇ-00321" grandTotal={4200} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  chamadas.ordem.length = 0;
  chamadas.update.length = 0;
  chamadas.status.length = 0;
  chamadas.assinadoEm = null;
});

describe('QuoteStatusQuickChange — converter sem sinal', () => {
  it('de "Aguardando sinal": confirma, troca a condição, aprova e converte — nessa ordem', async () => {
    renderSelo('awaiting_deposit');
    fireEvent.click(screen.getByRole('button', { name: /sem sinal/i }));

    // Antes de confirmar, nada foi gravado.
    expect(screen.getByText(/Converter ORÇ-00321 em OS sem sinal\?/)).toBeTruthy();
    expect(screen.getByText(/4\.200,00/)).toBeTruthy();
    expect(chamadas.ordem).toEqual([]);

    fireEvent.click(screen.getByRole('button', { name: 'Converter sem sinal' }));
    await waitFor(() => expect(chamadas.ordem).toEqual(['update', 'status']));
    expect(chamadas.update[0]).toEqual({
      payment_condition_preset_id: 'p-entrega',
      payment_conditions: '100% na entrega',
      custom_payment_installments: null,
      quote_status: 'approved',
    });
    expect(chamadas.status[0]).toEqual({ id: 'so-1', status: 'approved' });
    // A conversão abre o aviso de necessidade de compra, com o número novo.
    await waitFor(() => expect(screen.getByText('aviso de compra OS-00321')).toBeTruthy());
  });

  it('orçamento assinado: a confirmação avisa que o cliente assina de novo', async () => {
    chamadas.assinadoEm = '2026-10-20T10:00:00Z';
    renderSelo('awaiting_deposit');
    fireEvent.click(screen.getByRole('button', { name: /sem sinal/i }));
    expect(await screen.findByText(/precisa assinar de novo/)).toBeTruthy();
  });

  it('sem assinatura, não há aviso de reassinatura', async () => {
    renderSelo('awaiting_deposit');
    fireEvent.click(screen.getByRole('button', { name: /sem sinal/i }));
    await screen.findByText(/Converter ORÇ-00321 em OS sem sinal\?/);
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByText(/precisa assinar de novo/)).toBeNull();
  });

  it('"Voltar" não grava nada', () => {
    renderSelo('awaiting_deposit');
    fireEvent.click(screen.getByRole('button', { name: /sem sinal/i }));
    fireEvent.click(screen.getByRole('button', { name: 'Voltar' }));
    expect(chamadas.ordem).toEqual([]);
  });

  it('de "Aprovado": a opção aparece no menu do selo', async () => {
    const user = userEvent.setup();
    renderSelo('approved');
    await user.click(screen.getByRole('button', { name: /aprovado/i }));
    await user.click(await screen.findByText('Converter em OS sem sinal'));
    expect(screen.getByText(/Converter ORÇ-00321 em OS sem sinal\?/)).toBeTruthy();
  });
});

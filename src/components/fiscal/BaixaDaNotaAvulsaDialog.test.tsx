// "Baixar estoque + gerar recebível" da nota avulsa (D33, 01/10/2026). O que se protege: o plano
// que a nota declarou é lançado no centavo; mexer nos campos avisa que diverge da nota; à vista
// manda um recebível só (sem parcelas) para a função do banco.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const banco = vi.hoisted(() => ({
  chamadas: [] as Array<{ nome: string; args: unknown }>,
  toasts: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: async (nome: string, args: unknown) => {
      banco.chamadas.push({ nome, args });
      if (nome === 'register_payment_and_update_balance') return { data: { payment_id: 'pg-1' }, error: null };
      return { data: { ok: true, stock_items: 1, installments: 3, receivable_id: 'rec-1', amount: 500, issue_date: '2026-09-10' }, error: null };
    },
  },
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: vi.fn(async () => undefined) }));
vi.mock('sonner', () => ({
  toast: {
    loading: () => 't1',
    warning: (m: string) => banco.toasts.push(`aviso: ${m}`),
    success: (m: string) => banco.toasts.push(m),
    error: (m: string) => banco.toasts.push(`erro: ${m}`),
  },
}));

import { BaixaDaNotaAvulsaDialog } from './BaixaDaNotaAvulsaDialog';

const parcelada = {
  id: 'nf-25', series: 2, number: 25, status: 'authorized', origin_type: 'manual',
  authorized_at: '2026-07-10T12:00:00-03:00',
  payment_terms: {
    mode: 'parcelado', method: '14',
    installments: [
      { due_date: '2026-08-10', amount: 5237.99, method: '14' },
      { due_date: '2026-09-09', amount: 5237.99, method: '14' },
      { due_date: '2026-10-09', amount: 5238.02, method: '14' },
    ],
  },
  request_payload: { purpose: 1, items: [{ quantity: 1, unit_price: 15714 }] },
};
const aVista = {
  id: 'nf-30', series: 2, number: 30, status: 'authorized', origin_type: 'manual',
  authorized_at: '2026-09-10T12:00:00-03:00',
  request_payload: { purpose: 1, payments: [{ method: '03' }], items: [{ quantity: 2, unit_price: 250 }] },
};

function montar(doc: unknown, ocupado = false) {
  const marcas: Array<[string, boolean]> = [];
  const onClose = vi.fn();
  render(
    <QueryClientProvider client={new QueryClient()}>
      <I18nProvider>
        <BaixaDaNotaAvulsaDialog doc={doc} ocupado={ocupado} marcarOcupado={(id, b) => marcas.push([id, b])} onClose={onClose} />
      </I18nProvider>
    </QueryClientProvider>,
  );
  return { marcas, onClose };
}

beforeEach(() => {
  banco.chamadas = [];
  banco.toasts = [];
});

describe('BaixaDaNotaAvulsaDialog', () => {
  it('nota parcelada: mostra o plano da nota e lança exatamente ele', async () => {
    const { marcas, onClose } = montar(parcelada);
    expect(screen.getByText(/Plano declarado na nota — 3x/)).toBeTruthy();
    expect(screen.getByText('Será lançado exatamente assim, no centavo.')).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: /Confirmar lançamento/ }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(banco.chamadas).toEqual([{
      nome: 'settle_nfe_stock_and_receivable',
      args: { p_document_id: 'nf-25', p_installments: parcelada.payment_terms.installments },
    }]);
    expect(marcas).toEqual([['nf-25', true], ['nf-25', false]]);
  });

  it('mexer no plano avisa que diverge da nota e recalcula', async () => {
    montar(parcelada);
    fireEvent.change(screen.getByLabelText('Parcelas'), { target: { value: '2' } });
    expect(screen.getByText('Você alterou o plano.')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /Confirmar lançamento/ }));
    await waitFor(() => expect(banco.chamadas).toHaveLength(1));
    const enviado = (banco.chamadas[0].args as { p_installments: Array<{ amount: number }> }).p_installments;
    expect(enviado.map((p) => p.amount)).toEqual([7857, 7857]);
  });

  it('à vista: um recebível só, sem parcelas', async () => {
    const { onClose } = montar(aVista);
    expect(screen.getByText('Esta nota não declarou plano de pagamento.')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /Confirmar lançamento/ }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(banco.chamadas).toEqual([{
      nome: 'settle_nfe_stock_and_receivable', args: { p_document_id: 'nf-30', p_installments: null },
    }]);
  });

  it('com a nota ocupada, não deixa confirmar de novo', () => {
    montar(aVista, true);
    expect((screen.getByRole('button', { name: /Confirmar lançamento/ }) as HTMLButtonElement).disabled).toBe(true);
  });
});

// Venda de balcão (07/10/2026): o cliente pagou na hora e o recebível nascia em aberto.
describe('Já recebi no balcão', () => {
  beforeEach(() => { banco.chamadas = []; banco.toasts = []; });

  it('à vista no cartão: a opção aparece e, marcada, registra o pagamento pela mesma função da tela', async () => {
    montar(aVista);
    const opcao = screen.getByTestId('recebido-na-hora');
    fireEvent.click(opcao.querySelector('button')!);
    fireEvent.click(screen.getByRole('button', { name: /Confirmar lançamento/ }));
    await waitFor(() => expect(banco.chamadas.map((c) => c.nome)).toEqual(['settle_nfe_stock_and_receivable', 'register_payment_and_update_balance']));
    const pagamento = banco.chamadas[1].args as Record<string, unknown>;
    expect(pagamento).toMatchObject({ p_receivable_id: 'rec-1', p_amount: 500, p_payment_method: 'credit_card', p_payment_date: '2026-09-10' });
    await waitFor(() => expect(banco.toasts.join(' | ')).toContain('Recebido e lançado como pago'));
  });

  it('sem marcar, só a baixa (o recebível fica em aberto, como antes)', async () => {
    montar(aVista);
    fireEvent.click(screen.getByRole('button', { name: /Confirmar lançamento/ }));
    await waitFor(() => expect(banco.chamadas.map((c) => c.nome)).toEqual(['settle_nfe_stock_and_receivable']));
  });

  it('parcelado não oferece (cada parcela é paga quando vencer)', () => {
    montar(parcelada);
    expect(screen.queryByTestId('recebido-na-hora')).toBeNull();
  });
});

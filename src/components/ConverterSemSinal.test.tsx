// Converter sem sinal — "o serviço já foi feito" (18/11/2026, OS-00129): a confirmação mostra a data do orçamento e o aviso
// com os sinais (a mesma regra do cartão do assistente); marcado, a porta vai direto a concluída com a saída do dia.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useEffect, type ReactNode } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => ({
  os: {} as Record<string, unknown>,
  recebiveis: [] as { paid_amount: number | null; status: string }[],
  status: [] as Record<string, unknown>[],
  updates: [] as Record<string, unknown>[],
  aviso: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const q: any = {
        select: () => q,
        eq: () => q,
        update: (v: Record<string, unknown>) => { h.updates.push(v); return q; },
        maybeSingle: () => Promise.resolve({ data: h.os, error: null }),
        then: (ok: (v: unknown) => unknown) =>
          Promise.resolve({ data: tabela === 'receivables' ? h.recebiveis : null, error: null }).then(ok),
      };
      return q;
    },
  },
}));
vi.mock('@/hooks/use-service-orders', () => ({
  useUpdateServiceOrderStatus: () => ({
    mutateAsync: async (v: Record<string, unknown>) => {
      h.status.push(v);
      return { mudou: true, status: v.status, numero: 'OS-00129', justConverted: true };
    },
  }),
}));
vi.mock('@/hooks/use-payment-conditions', () => ({
  usePaymentConditionPresets: () => ({ data: [{ id: 'p-entrega', label: '100% na entrega', installments: [
    { tipo: 'entrega', services_pct: 100, parts_pct: 100, expenses_pct: 100, days_after_approval: 0 }] }] }),
}));
vi.mock('@/hooks/use-purchase-needs-prompt', () => ({ usePurchaseNeedsPrompt: () => ({ promptIfConverted: h.aviso, dialog: null }) }));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }));

import { useConverterSemSinal } from './ConverterSemSinal';

function Tela() {
  const { pedir, dialogo } = useConverterSemSinal();
  useEffect(() => { pedir({ id: 'os-129', number: 'ORÇ-00129', client: 'Cliente', grandTotal: 750 }); }, [pedir]);
  return <>{dialogo}</>;
}
function comQuery(children: ReactNode) {
  return <QueryClientProvider client={new QueryClient()}>{children}</QueryClientProvider>;
}

describe('ConverterSemSinal — o serviço já foi feito', () => {
  beforeEach(() => {
    h.os = { signed_at: null, created_at: '2026-10-28T13:09:39Z', technician_notes: 'Foi necessário instalar um conversor',
      diagnosis: 'Diagnóstico', check_in_at: null, check_out_at: null };
    h.recebiveis = [{ paid_amount: 750, status: 'paid' }];
    h.status = [];
    h.updates = [];
    h.aviso.mockClear();
  });

  it('a OS-00129: mostra a data e o aviso com os sinais; marcado + dia, a porta vai a concluída com a saída às 17:00 e sem aviso de compra', async () => {
    render(comQuery(<Tela />));
    const atencao = await screen.findByText(/Atenção: orçamento de 28\/10/);
    expect(atencao.textContent).toContain('já com diagnóstico, nota técnica e R$');
    expect(atencao.textContent).toContain('750,00 já recebido');

    await userEvent.click(screen.getByLabelText('O serviço já foi feito'));
    const dia = screen.getByLabelText('Feito em') as HTMLInputElement;
    await userEvent.clear(dia);
    await userEvent.type(dia, '2026-10-31');
    expect(screen.queryByText(/Atenção:/)).toBeNull();
    await userEvent.click(screen.getByRole('button', { name: 'Converter já concluída' }));

    await waitFor(() => expect(h.status).toEqual([{ id: 'os-129', status: 'completed', checkOut: '2026-10-31T17:00:00-03:00' }]));
    expect(h.updates[0]).toMatchObject({ payment_conditions: '100% na entrega', quote_status: 'approved' });
    expect(h.aviso).not.toHaveBeenCalled();
  });

  it('sem marcar: a conversão de sempre (aprovada) e o aviso de compra', async () => {
    render(comQuery(<Tela />));
    await screen.findByText(/Atenção:/);
    await userEvent.click(screen.getByRole('button', { name: 'Converter sem sinal' }));
    await waitFor(() => expect(h.status).toEqual([{ id: 'os-129', status: 'approved' }]));
    expect(h.aviso).toHaveBeenCalled();
  });

  it('orçamento novo e limpo: a data aparece, o aviso não', async () => {
    h.os = { ...h.os, created_at: new Date().toISOString(), technician_notes: null, diagnosis: null };
    h.recebiveis = [];
    render(comQuery(<Tela />));
    await screen.findByText(/Orçamento de .* \(de hoje\)\./);
    expect(screen.queryByText(/Atenção:/)).toBeNull();
  });
});

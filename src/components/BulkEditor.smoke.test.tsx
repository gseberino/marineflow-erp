// Edição em lote (inventário de 03/10/2026). O que se protege: o estoque é salvo pelo ajuste com
// movimento (o banco recusa gravar o saldo direto desde a fase E do estoque) e, se um item falha,
// os outros salvam e o que falhou continua marcado; em tela estreita, cartões — sem rolagem lateral.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';

const banco = vi.hoisted(() => ({
  updates: [] as Array<{ tabela: string; valores: Record<string, unknown>; id: string }>,
  rpcs: [] as Array<{ nome: string; args: Record<string, unknown> }>,
  falhaNoUpdate: null as string | null,
  toasts: [] as string[],
  // Mesma referência a cada render, como o react-query devolve (array novo a cada render faria o
  // efeito da tela recarregar os dados sem fim).
  produtos: {
    data: [
      { id: 'p1', name: 'Anodo', sku: 'A1', category: '', brand: '', cost_price: 10, sale_price: 20, stock_quantity: 5, minimum_stock: 1, active: true },
      { id: 'p2', name: 'Bomba', sku: 'B1', category: '', brand: '', cost_price: 100, sale_price: 200, stock_quantity: 2, minimum_stock: 0, active: true },
    ],
    refetch: () => {},
  },
  servicos: { data: [] as unknown[], refetch: () => {} },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => ({
      update: (valores: Record<string, unknown>) => ({
        eq: async (_c: string, id: string) => {
          banco.updates.push({ tabela, valores, id });
          return { error: banco.falhaNoUpdate && id === banco.falhaNoUpdate ? { message: 'recusado' } : null };
        },
      }),
    }),
    rpc: async (nome: string, args: Record<string, unknown>) => {
      banco.rpcs.push({ nome, args });
      return { error: null };
    },
  },
}));
vi.mock('@/hooks/use-products', () => ({ useProducts: () => banco.produtos }));
vi.mock('@/hooks/use-services', () => ({ useServices: () => banco.servicos }));
vi.mock('sonner', () => ({
  toast: { success: (m: string) => banco.toasts.push(m), error: (m: string) => banco.toasts.push(m) },
}));

import { BulkEditor } from './BulkEditor';

function telaEstreita(estreita: boolean) {
  window.matchMedia = ((q: string) => ({
    matches: estreita, media: q, onchange: null,
    addListener: () => {}, removeListener: () => {}, addEventListener: () => {}, removeEventListener: () => {}, dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
}

function renderizar() {
  return render(<I18nProvider><BulkEditor entityType="products" open onOpenChange={() => {}} /></I18nProvider>);
}

beforeEach(() => {
  banco.updates = []; banco.rpcs = []; banco.falhaNoUpdate = null; banco.toasts = [];
});

describe('BulkEditor', () => {
  it('tela estreita: cartões em vez da tabela larga', () => {
    telaEstreita(true);
    renderizar();
    expect(screen.getByTestId('bulk-cartoes')).toBeInTheDocument();
    expect(screen.queryByRole('table')).not.toBeInTheDocument();
  });

  it('estoque vai pelo ajuste com movimento; preço pela atualização normal', async () => {
    telaEstreita(true);
    const user = userEvent.setup();
    renderizar();
    const estoques = screen.getAllByDisplayValue('5');
    await user.clear(estoques[0]);
    await user.type(estoques[0], '8');
    const precos = screen.getAllByDisplayValue('20');
    await user.clear(precos[0]);
    await user.type(precos[0], '25');
    await user.click(screen.getByRole('button', { name: /\(1\)/ }));
    await waitFor(() => expect(banco.rpcs).toHaveLength(1));
    expect(banco.rpcs[0]).toEqual({ nome: 'ajustar_estoque', args: { p_produto: 'p1', p_nova_quantidade: 8, p_motivo: 'Edição em lote' } });
    expect(banco.updates).toEqual([{ tabela: 'products', valores: { sale_price: 25 }, id: 'p1' }]);
  });

  it('um item que falha não derruba os outros e continua marcado', async () => {
    telaEstreita(true);
    banco.falhaNoUpdate = 'p1';
    const user = userEvent.setup();
    renderizar();
    const precos = screen.getAllByDisplayValue('20');
    await user.clear(precos[0]);
    await user.type(precos[0], '25');
    const precosB = screen.getAllByDisplayValue('200');
    await user.clear(precosB[0]);
    await user.type(precosB[0], '210');
    await user.click(screen.getByRole('button', { name: /\(2\)/ }));
    await waitFor(() => expect(banco.toasts.some((t) => /1 item\(ns\) não salvaram/.test(t))).toBe(true));
    expect(banco.updates.map((u) => u.id).sort()).toEqual(['p1', 'p2']);
    // O que falhou continua para salvar de novo.
    expect(screen.getByRole('button', { name: /\(1\)/ })).toBeInTheDocument();
  });
});

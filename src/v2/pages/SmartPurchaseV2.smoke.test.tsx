// Assistente de Compras v2 — a v2 tinha regredido dois consertos que a v1 já tem:
// 1. A consulta comparava o estoque com o TEXTO 'minimum_stock' (o PostgREST não compara coluna
//    com coluna; o numeric recusa o texto) e, no erro, a tela dizia "Estoque saudável!".
// 2. "Gerar lista de compra" só dava um aviso e dizia "acompanhe em Ordens de Compra" — nada era
//    criado. Agora abre a cotação com os itens escolhidos, como a v1.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import SmartPurchaseV2 from './SmartPurchaseV2';

const estado = vi.hoisted(() => ({ falhar: false }));

const produtos = [
  // disponível 2 − 1 reservado = 1, abaixo do mínimo 3: repõe até o dobro → 6 − 1 = 5
  { id: 'p1', name: 'Impelidor', sku: 'IMP-1', unit: 'UN', stock_quantity: 2, reserved_quantity: 1, minimum_stock: 3,
    cost_price: 50, active: true, suppliers: { name: 'Náutica X' } },
  { id: 'p2', name: 'Filtro de óleo', sku: 'F-1', unit: 'UN', stock_quantity: 10, reserved_quantity: 0, minimum_stock: 2,
    cost_price: 20, active: true, suppliers: null },
  // sem mínimo definido não há régua de reposição
  { id: 'p3', name: 'Parafuso inox', sku: 'P-1', unit: 'UN', stock_quantity: 0, reserved_quantity: 0, minimum_stock: 0,
    cost_price: 1, active: true, suppliers: null },
];

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => ({
      select: () => {
        if (tabela === 'product_availability') {
          return Promise.resolve({ data: produtos.map(({ id, stock_quantity, reserved_quantity }) => ({ id, stock_quantity, reserved_quantity })), error: null });
        }
        const recusa = { data: null, error: { message: 'invalid input syntax for type numeric: "minimum_stock"' } };
        return {
          eq: () => Promise.resolve(estado.falhar ? { data: null, error: { message: 'sem conexão' } } : { data: produtos, error: null }),
          // o filtro coluna-a-coluna que o PostgREST não tem: 'minimum_stock' vira valor e o numeric recusa
          filter: () => ({ order: () => Promise.resolve(recusa) }),
        };
      },
    }),
  },
}));
vi.mock('@/v2/components/V2Shell', () => ({ V2Shell: ({ children }: { children: React.ReactNode }) => <>{children}</> }));
vi.mock('@/components/purchasing/NewQuoteRequestDialog', () => ({
  NewQuoteRequestDialog: ({ open, prefilledItems }: { open: boolean; prefilledItems?: unknown[] }) =>
    open ? <div role="dialog" aria-label="Nova cotação">{JSON.stringify(prefilledItems)}</div> : null,
}));
vi.mock('sonner', () => ({ toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) }));

function renderTela() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <SmartPurchaseV2 />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => { estado.falhar = false; });

describe('Assistente de Compras v2', () => {
  it('lista só o que está com o DISPONÍVEL no mínimo ou abaixo (e com mínimo definido)', async () => {
    renderTela();
    expect(await screen.findByText('Impelidor')).toBeInTheDocument();
    expect(screen.queryByText('Filtro de óleo')).not.toBeInTheDocument();
    expect(screen.queryByText('Parafuso inox')).not.toBeInTheDocument();
    expect(screen.queryByText(/Estoque saudável/)).not.toBeInTheDocument();
    // a estimativa usa a mesma quantidade sugerida da cotação: 5 × R$ 50,00
    expect(screen.getByText(/R\$\s?250,00/)).toBeInTheDocument();
  });

  it('"Cotar selecionados" abre a cotação com os itens e a quantidade sugerida; nada de "lista gerada"', async () => {
    const user = userEvent.setup();
    renderTela();
    await screen.findByText('Impelidor');
    await user.click(screen.getByRole('checkbox', { name: 'Selecionar p1' }));
    await user.click(screen.getByRole('button', { name: /Cotar selecionados/ }));
    const dialogo = await screen.findByRole('dialog', { name: 'Nova cotação' });
    expect(JSON.parse(dialogo.textContent ?? '')).toEqual([{ description: 'Impelidor', quantity: 5, product_id: 'p1' }]);
    expect(screen.queryByText(/Lista gerada/)).not.toBeInTheDocument();
    expect(within(document.body).queryByRole('button', { name: /Gerar lista de compra/ })).not.toBeInTheDocument();
  });

  it('se a leitura falha, diz que falhou — não "Estoque saudável!"', async () => {
    estado.falhar = true;
    renderTela();
    expect(await screen.findByText(/Não deu para ler o estoque/)).toBeInTheDocument();
    expect(screen.queryByText(/Estoque saudável/)).not.toBeInTheDocument();
  });
});

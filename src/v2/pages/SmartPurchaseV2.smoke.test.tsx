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

const estado = vi.hoisted(() => ({
  falhar: false,
  falharDisponivel: false,
  /** Os filtros que a tela pediu ao servidor, em ordem: ['gt', coluna, valor] / ['in', coluna, ids]. */
  pedidos: [] as unknown[][],
  /** Troca o catálogo num teste; nulo, vale `produtos`. */
  catalogo: null as Array<Record<string, unknown>> | null,
}));

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

// Um PostgREST de mentira que faz o que o de verdade faria com os filtros pedidos: `gt` no
// mínimo e `in` nos ids. Assim o teste vê o que a tela PEDIU, não só o que ela mostrou.
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => ({
      select: () => {
        const catalogo = (estado.catalogo ?? produtos) as Array<Record<string, any>>;
        if (tabela === 'product_availability') {
          return {
            in: (coluna: string, ids: string[]) => {
              estado.pedidos.push(['in', coluna, ids]);
              if (estado.falharDisponivel) return Promise.resolve({ data: null, error: { message: 'permission denied for view product_availability' } });
              const linhas = catalogo
                .filter((p) => ids.includes(p.id))
                .map(({ id, stock_quantity, reserved_quantity }) => ({ id, stock_quantity, reserved_quantity }));
              return Promise.resolve({ data: linhas, error: null });
            },
          };
        }
        const recusa = { data: null, error: { message: 'invalid input syntax for type numeric: "minimum_stock"' } };
        return {
          eq: () => ({
            gt: (coluna: string, valor: number) => {
              estado.pedidos.push(['gt', coluna, valor]);
              if (estado.falhar) return Promise.resolve({ data: null, error: { message: 'sem conexão' } });
              return Promise.resolve({ data: catalogo.filter((p) => Number(p[coluna] ?? 0) > valor), error: null });
            },
          }),
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

beforeEach(() => {
  estado.falhar = false;
  estado.falharDisponivel = false;
  estado.pedidos.length = 0;
  estado.catalogo = null;
});

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

  // 11/10/2026: a tela lia todos os produtos e todo o disponível e filtrava no navegador — o
  // PostgREST corta em 1000 linhas calado. Agora o mínimo vai ao servidor e o disponível é
  // pedido só dos produtos que vieram.
  it('pede ao servidor só os produtos com mínimo, e o disponível só deles', async () => {
    renderTela();
    await screen.findByText('Impelidor');
    expect(estado.pedidos).toEqual([
      ['gt', 'minimum_stock', 0],
      ['in', 'id', ['p1', 'p2']],
    ]);
    // o p3, sem mínimo, nem chega a pedir disponível
    expect(JSON.stringify(estado.pedidos)).not.toContain('p3');
  });

  it('nenhum produto com mínimo: não pede disponível e diz que está saudável', async () => {
    estado.catalogo = [produtos[2]];
    renderTela();
    expect(await screen.findByText(/Estoque saudável/)).toBeInTheDocument();
    expect(estado.pedidos).toEqual([['gt', 'minimum_stock', 0]]);
  });

  it('o disponível é pedido em lotes de 200 ids (a lista vai na URL)', async () => {
    // Só a primeira está abaixo do mínimo: as outras 449 vêm do servidor, mas a tela não as lista.
    estado.catalogo = Array.from({ length: 450 }, (_, i) => ({
      id: `q${i}`, name: `Peça ${i}`, sku: null, unit: 'UN', stock_quantity: i === 0 ? 0 : 5, reserved_quantity: 0,
      minimum_stock: 1, cost_price: 1, active: true, suppliers: null,
    }));
    renderTela();
    await screen.findByText('Peça 0');
    const lotes = estado.pedidos.filter((p) => p[0] === 'in').map((p) => (p[2] as string[]).length);
    expect(lotes).toEqual([200, 200, 50]);
  });

  // Antes o erro do disponível era ignorado: o cálculo caía no físico, esquecia a reserva e a
  // tela podia dizer "Estoque saudável!" com peça prometida a uma OS.
  it('erro no disponível mostra o erro, nunca "Estoque saudável!"', async () => {
    estado.falharDisponivel = true;
    renderTela();
    expect(await screen.findByText(/Não deu para ler o estoque: permission denied/)).toBeInTheDocument();
    expect(screen.queryByText(/Estoque saudável/)).not.toBeInTheDocument();
    expect(screen.queryByText('Impelidor')).not.toBeInTheDocument();
  });
});

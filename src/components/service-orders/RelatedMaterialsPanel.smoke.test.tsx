// Smoke do "costuma entrar junto".
//
// A regra que mais importa: a EVIDÊNCIA aparece na linha. "5 de 5" e "3 de 4"
// pedem decisões diferentes, e trocar isso por um selo de "recomendado" tiraria
// de quem lê a única coisa que dá para julgar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { RelatedMaterialsPanel } from './RelatedMaterialsPanel';

const { estado, recalcTotals, inseridas } = vi.hoisted(() => ({
  estado: { itens: [] as unknown[] },
  recalcTotals: vi.fn(async (_soId: string) => {}),
  inseridas: [] as unknown[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: async () => ({ data: estado.itens, error: null }),
    from: () => ({
      select: () => ({ eq: () => ({ single: async () => ({ data: { cost_price: 1, sale_price: 2 } }) }) }),
      insert: async (linha: unknown) => { inseridas.push(linha); return { error: null }; },
    }),
  },
}));
// O total da OS só muda pelo recalcTotals (não há gatilho no banco que o recalcule).
vi.mock('@/hooks/use-service-orders', () => ({ recalcTotals: (soId: string) => recalcTotals(soId) }));

function renderPanel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <RelatedMaterialsPanel serviceOrderId="os1" />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => { estado.itens = []; inseridas.length = 0; recalcTotals.mockClear(); });

describe('materiais que costumam entrar junto', () => {
  it('sem sugestão, não ocupa espaço', async () => {
    const { container } = renderPanel();
    await screen.findByText((_, el) => el?.tagName === 'DIV', {}, { timeout: 50 }).catch(() => {});
    expect(container.textContent).not.toContain('Costuma entrar junto');
  });

  it('mostra a contagem que sustenta a sugestão', async () => {
    estado.itens = [{
      product_id: 'p1', product_name: 'Tela GX Touch 50', unit: 'UN', sale_price: 3200,
      por_causa_de: 'CENTRAL DE CONTROLE CERBO GX', juntos: 5, de_total: 5, pct: 100,
    }];
    renderPanel();

    expect(await screen.findByText('Tela GX Touch 50')).toBeInTheDocument();
    // A evidência, não um selo.
    expect(screen.getByText(/5 de 5/)).toBeInTheDocument();
    expect(screen.getByText(/CENTRAL DE CONTROLE CERBO GX/)).toBeInTheDocument();
  });

  it('diz que a quantidade é 1 e por quê', async () => {
    estado.itens = [{
      product_id: 'p1', product_name: 'Porta Fusível MIDI', unit: 'pcs', sale_price: 27.48,
      por_causa_de: 'Kit Cabos', juntos: 3, de_total: 4, pct: 75,
    }];
    renderPanel();
    // O histórico diz que o item vem junto, não quantos vêm — e a tela assume
    // isso em vez de chutar quantidade.
    expect(await screen.findByText(/não quantos/)).toBeInTheDocument();
  });

  it('"Incluir" lança a peça e recalcula o total da OS (senão o total, o PDF e o recebível ficam velhos)', async () => {
    estado.itens = [{
      product_id: 'p1', product_name: 'Tela GX Touch 50', unit: 'UN', sale_price: 3200,
      por_causa_de: 'CENTRAL DE CONTROLE CERBO GX', juntos: 5, de_total: 5, pct: 100,
    }];
    renderPanel();
    await userEvent.setup().click(await screen.findByRole('button', { name: /Incluir/ }));
    await waitFor(() => expect(recalcTotals).toHaveBeenCalledWith('os1'));
    expect(inseridas).toEqual([expect.objectContaining({ service_order_id: 'os1', product_id: 'p1', quantity: 1 })]);
  });
});

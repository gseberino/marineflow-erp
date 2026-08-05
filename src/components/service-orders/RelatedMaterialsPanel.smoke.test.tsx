// Smoke do "costuma entrar junto".
//
// A regra que mais importa: a EVIDÊNCIA aparece na linha. "5 de 5" e "3 de 4"
// pedem decisões diferentes, e trocar isso por um selo de "recomendado" tiraria
// de quem lê a única coisa que dá para julgar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { RelatedMaterialsPanel } from './RelatedMaterialsPanel';

const { estado } = vi.hoisted(() => ({ estado: { itens: [] as any[] } }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: async () => ({ data: estado.itens, error: null }),
    from: () => ({
      select: () => ({ eq: () => ({ single: async () => ({ data: { cost_price: 1, sale_price: 2 } }) }) }),
      insert: async () => ({ error: null }),
    }),
  },
}));

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

beforeEach(() => { estado.itens = []; });

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
});

// A categoria criada na hora (seletor de categoria da Conciliação, do Caixa…) nasce no grupo do
// DRE que a tela sugeriu. Sem sugestão, o padrão segue o tipo: a de ENTRADA (o "Anotar" do Caixa,
// sentido entrada) é receita — em despesa operacional, o DRE subtrairia o recebimento como despesa.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useCriarCategoriaDespesa } from './use-finance-review';

const { inseridas } = vi.hoisted(() => ({ inseridas: [] as Array<Record<string, unknown>> }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      insert: (linha: Record<string, unknown>) => {
        inseridas.push(linha);
        return { select: () => ({ single: async () => ({ data: { name: linha.name }, error: null }) }) };
      },
    }),
  },
}));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

function usar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: qc }, children);
  return renderHook(() => useCriarCategoriaDespesa(), { wrapper }).result;
}

beforeEach(() => { inseridas.length = 0; });

describe('useCriarCategoriaDespesa: o grupo do DRE da categoria nova', () => {
  it('sem sugestão, a de entrada nasce em receita', async () => {
    const r = usar();
    await r.current.mutateAsync({ name: 'Aluguel de equipamento', dre_group: null, type: 'receivable' });
    await waitFor(() => expect(inseridas).toHaveLength(1));
    expect(inseridas[0]).toMatchObject({ type: 'receivable', dre_group: 'receita' });
  });

  it('sem sugestão, a de saída continua em despesa operacional', async () => {
    const r = usar();
    await r.current.mutateAsync({ name: 'Seguro da lancha', dre_group: null });
    expect(inseridas[0]).toMatchObject({ type: 'payable', dre_group: 'despesa_operacional' });
  });

  it('a sugestão da tela manda', async () => {
    const r = usar();
    await r.current.mutateAsync({ name: 'Frete aéreo', dre_group: 'custo_direto' });
    expect(inseridas[0]).toMatchObject({ dre_group: 'custo_direto' });
  });
});

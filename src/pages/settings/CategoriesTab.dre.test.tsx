// Categoria criada em Configurações nasce num grupo do DRE. Sem grupo (a coluna não tem DEFAULT),
// a despesa dela caía em "sem grupo" — fora de todas as linhas do resultado — e não há tela para
// dar o grupo depois. Mesmo padrão da categoria criada na hora (useCriarCategoriaDespesa).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { CategoriesTab } from './CategoriesTab';

const { inseridas } = vi.hoisted(() => ({ inseridas: [] as Array<Record<string, unknown>> }));

vi.mock('@/integrations/supabase/client', () => {
  const consulta: Record<string, unknown> = {
    eq: () => consulta,
    order: () => consulta,
    then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok),
  };
  return {
    supabase: {
      from: () => ({
        select: () => consulta,
        insert: (linha: Record<string, unknown>) => {
          inseridas.push(linha);
          return { select: () => ({ single: async () => ({ data: { id: 'c1', ...linha }, error: null }) }) };
        },
      }),
    },
  };
});
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn() } }));

function renderTab() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <CategoriesTab />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

async function criar(coluna: 0 | 1, nome: string) {
  const user = userEvent.setup();
  await user.click(screen.getAllByRole('button', { name: /Nova Categoria/ })[coluna]);
  fireEvent.change(screen.getByPlaceholderText('Nome da Categoria'), { target: { value: nome } });
  await user.click(screen.getByRole('button', { name: 'Salvar' }));
}

beforeEach(() => { inseridas.length = 0; });

describe('Configurações › Categorias: o grupo do DRE', () => {
  it('a categoria de despesa nasce em despesa operacional (não em "sem grupo")', async () => {
    renderTab();
    await criar(0, 'Seguro da lancha');
    await waitFor(() => expect(inseridas).toHaveLength(1));
    expect(inseridas[0]).toMatchObject({ name: 'Seguro da lancha', type: 'payable', dre_group: 'despesa_operacional' });
  });

  it('a categoria de receita nasce em receita', async () => {
    renderTab();
    await criar(1, 'Aluguel de equipamento');
    await waitFor(() => expect(inseridas).toHaveLength(1));
    expect(inseridas[0]).toMatchObject({ name: 'Aluguel de equipamento', type: 'receivable', dre_group: 'receita' });
  });
});

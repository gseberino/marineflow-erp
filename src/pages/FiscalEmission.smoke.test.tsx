// Smoke test de RENDER da FiscalEmission — a página fiscal é a mais complexa e
// crítica do ERP (emite documento fiscal real), e não tinha nenhuma proteção de
// render. O build (vite/esbuild) só remove tipos e o tsc da raiz não checa nada
// (files:[]), então um erro de ordenação/TDZ ou deref de null derruba a página
// inteira e passa batido — foi exatamente o que aconteceu na AgendaPage em prod
// (ver AgendaPage.smoke.test.tsx). Compilar não basta: renderizar pega.
import { describe, it, expect } from 'vitest';
import { vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import FiscalEmission from './FiscalEmission';

// Builder de query encadeável que resolve para vazio (mesmo padrão do smoke da
// AgendaPage) — cobre .select().order().limit().maybeSingle() etc. sem tocar rede.
const { queryBuilder } = vi.hoisted(() => {
  const queryBuilder = (): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'order',
      'limit', 'is', 'not', 'like', 'update', 'insert', 'delete', 'upsert', 'filter']) {
      o[k] = () => o;
    }
    o.maybeSingle = async () => ({ data: null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: any) => Promise.resolve({ data: [], error: null }).then(res);
    return o;
  };
  return { queryBuilder };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => queryBuilder(),
    rpc: async () => ({ data: [], error: null }),
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
    channel: () => ({ on() { return this; }, subscribe() { return this; } }),
    removeChannel: () => {},
    functions: {
      // As queries de montagem chamam 'environment' e 'diagnostics'. A página lê
      // data.data.environment / data.data — devolver um shape seguro basta.
      invoke: async (_name: string, opts: any) => {
        const action = opts?.body?.action;
        if (action === 'environment') {
          return { data: { data: { environment: 'homologacao' } }, error: null };
        }
        return { data: { data: {} }, error: null };
      },
    },
  },
}));

vi.mock('@/hooks/use-clients', () => ({ useClients: () => ({ data: [] }) }));
vi.mock('@/hooks/use-products', () => ({ useProducts: () => ({ data: [] }) }));
vi.mock('@/hooks/use-product-categories', () => ({ useProductCategories: () => ({ data: [] }) }));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: {} }) }));

// Diálogos filhos com cadeia própria de hooks (cadastro de cliente etc.) — fora
// do escopo do smoke da PÁGINA; neutraliza igual o smoke da AgendaPage fez com
// PaymentDialog.
vi.mock('@/components/ClientFormDialog', () => ({ ClientFormDialog: () => null }));

function renderPage() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <FiscalEmission />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('FiscalEmission — smoke de render', () => {
  it('renderiza a página sem lançar (regressão de TDZ/deref no render)', async () => {
    renderPage();
    // findBy* espera as queries de montagem (environment/diagnostics) resolverem
    // dentro de act — assim o smoke cobre TAMBÉM o re-render com os dados já carregados,
    // que é onde um deref de null costuma estourar.
    expect(await screen.findByText('Emissão Fiscal (NF-e)')).toBeTruthy();
  });
});

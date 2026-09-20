// Smoke de RENDER de Configurações depois da decomposição em src/pages/settings/* (20/09/2026).
// tsc e build passam com import circular, TDZ ou ícone inexistente; só montar a página de
// verdade mostra. Cada aba é aberta uma vez para que o código dela execute.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

vi.mock('@/integrations/supabase/client', () => {
  const builder = (): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'is', 'not', 'or', 'order', 'limit', 'range', 'filter', 'ilike', 'like', 'upsert', 'insert', 'update', 'delete']) {
      o[k] = () => o;
    }
    o.single = async () => ({ data: null, error: null });
    o.maybeSingle = async () => ({ data: null, error: null });
    o.then = (res: any) => Promise.resolve({ data: [], error: null }).then(res);
    return o;
  };
  return {
    supabase: {
      from: () => builder(),
      rpc: async () => ({ data: null, error: null }),
      storage: { from: () => ({ getPublicUrl: () => ({ data: { publicUrl: '' } }), upload: async () => ({ data: null, error: null }) }) },
      auth: { getUser: async () => ({ data: { user: null }, error: null }), getSession: async () => ({ data: { session: null }, error: null }) },
      functions: { invoke: async () => ({ data: null, error: null }) },
    },
  };
});

vi.mock('@/hooks/use-auth', () => ({
  useAuth: () => ({ user: { id: 'u1', role: 'admin', email: 'x@y.z', metadata: {} }, isAdmin: true, loading: false }),
}));

import { I18nProvider } from '@/i18n';
import SettingsPage from './SettingsPage';

function renderPagina() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={['/v2/settings']}>
          <SettingsPage />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('Configurações — render depois da decomposição', () => {
  it('monta a página com todas as abas', async () => {
    renderPagina();
    for (const nome of [/^Empresa$/i, /^Usuários$/i, /^Sistema$/i]) {
      expect(await screen.findByRole('tab', { name: nome })).toBeInTheDocument();
    }
  });

  it('cada aba abre sem quebrar', async () => {
    const user = userEvent.setup();
    renderPagina();
    const abas = await screen.findAllByRole('tab');
    expect(abas.length).toBeGreaterThanOrEqual(6);
    for (const aba of abas) {
      await user.click(aba);
      // Radix mantém um painel ativo por vez; se um componente extraído estourar no
      // render, o erro derruba o teste aqui.
      expect(document.querySelector('[role="tabpanel"][data-state="active"]')).toBeTruthy();
    }
  });
});

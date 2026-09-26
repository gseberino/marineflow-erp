// Fornecedores com a aba "Saúde do cadastro" (26/09/2026): a casa da tela que conserta o
// cadastro de fornecedor, que vivia entre as 14 abas do Financeiro. Só admin e financeiro a
// veem — as correções mexem no cadastro e a evidência vem do extrato.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import SuppliersListV2 from './SuppliersListV2';

const { papel } = vi.hoisted(() => ({ papel: { role: 'admin' } }));
const rotaAtual = { caminho: '' };
function EspiaoDeRota() {
  const l = useLocation();
  rotaAtual.caminho = l.pathname;
  return null;
}

vi.mock('@/hooks/use-auth', () => ({ useAuth: () => ({ user: { id: 'u1', role: papel.role } }) }));
vi.mock('@/hooks/use-suppliers', () => ({
  useSuppliers: () => ({ isLoading: false, error: null, data: [{ id: 's1', name: 'Toli Distribuidora', active: true }] }),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: () => ({ select: () => Promise.resolve({ data: [], error: null }) }) },
}));
vi.mock('@/components/SaudeDoCadastroPanel', () => ({ SaudeDoCadastroPanel: () => <div>painel saúde do cadastro</div> }));
vi.mock('@/components/SupplierFormDialog', () => ({ SupplierFormDialog: () => null }));
vi.mock('@/components/ImportWizard', () => ({ ImportWizard: () => null }));
vi.mock('@/components/FilterPresets', () => ({ FilterPresets: () => null }));

function renderFornecedores(inicio = '/v2/suppliers') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[inicio]}>
          <EspiaoDeRota />
          <Routes>
            <Route path="/v2/suppliers/:aba?" element={<SuppliersListV2 />} />
          </Routes>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => { papel.role = 'admin'; });

describe('Fornecedores — aba Saúde do cadastro', () => {
  it('admin vê as duas abas e a Saúde do cadastro abre pela rota nova', async () => {
    const user = userEvent.setup();
    renderFornecedores();
    expect(await screen.findByRole('tab', { name: 'Saúde do cadastro' })).toBeInTheDocument();
    expect(screen.getAllByText('Toli Distribuidora').length).toBeGreaterThan(0);
    await user.click(screen.getByRole('tab', { name: 'Saúde do cadastro' }));
    expect(rotaAtual.caminho).toBe('/v2/suppliers/saude');
    expect(await screen.findByText('painel saúde do cadastro')).toBeInTheDocument();
  });

  it('o link direto /v2/suppliers/saude abre a aba', async () => {
    renderFornecedores('/v2/suppliers/saude');
    expect(await screen.findByText('painel saúde do cadastro')).toBeInTheDocument();
    expect(screen.getByText(/atrapalham o reconhecimento automático/)).toBeInTheDocument();
  });

  it('técnico não vê a aba, e o link direto volta para a lista', async () => {
    papel.role = 'technician';
    renderFornecedores('/v2/suppliers/saude');
    expect((await screen.findAllByText('Toli Distribuidora')).length).toBeGreaterThan(0);
    expect(screen.queryByRole('tab')).not.toBeInTheDocument();
    expect(screen.queryByText('painel saúde do cadastro')).not.toBeInTheDocument();
    expect(rotaAtual.caminho).toBe('/v2/suppliers');
  });
});

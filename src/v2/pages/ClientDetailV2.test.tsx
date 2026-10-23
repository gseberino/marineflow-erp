// Ficha do cliente (v2), aba das embarcações e veículos: cada cartão mostra os campos do tipo
// (dono, 22/10/2026). Motorhome em metros, sem vaga de píer e sem "Sem marina".
// Aba Financeiro (leva 8, 22/10/2026): "Quem paga por este cliente" só para administrador e financeiro.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { I18nProvider } from '@/i18n';

vi.mock('@/hooks/use-clients', () => {
  const r = { isLoading: false, data: { id: 'c1', name: 'Fulano', type: 'individual', active: true } };
  return { useClient: () => r };
});
vi.mock('@/hooks/use-vessels', () => {
  const r = {
    data: [
      { id: 'l', name: 'Netuno II', asset_type: 'Lancha', length_feet: 40, manufacturer: 'Schaefer', model: '400', year: null, marinas: null, current_dock_position: 'B12' },
      { id: 'm', name: 'Vitória Star', asset_type: 'Motorhome', length_feet: 40, manufacturer: 'Iveco', model: 'Daily', year: null, marinas: null, current_dock_position: 'Rua A, 01' },
      { id: 'e', name: 'Inversor', asset_type: 'Equipamento', length_feet: 3, manufacturer: null, model: null, year: null, marinas: { name: 'Oficina' }, current_dock_position: null },
    ],
  };
  return { useVesselsForClient: () => r };
});
const estado = vi.hoisted(() => ({
  cargo: undefined as string | undefined,
  tabelas: [] as string[],
  pagadores: [] as unknown[],
}));
vi.mock('@/hooks/use-auth', () => ({
  useOptionalAuth: () => (estado.cargo ? { user: { id: 'u1', role: estado.cargo } } : null),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (t: string) => {
      estado.tabelas.push(t);
      const q = {
        select: () => q, eq: () => q,
        order: async () => ({ data: t === 'pagadores_do_cliente' ? estado.pagadores : [], error: null }),
      };
      return q;
    },
  },
}));
vi.mock('@/components/ClientFormDialog', () => ({ ClientFormDialog: () => null }));
vi.mock('@/components/ClientStatementDialog', () => ({ ClientStatementDialog: () => null }));
vi.mock('@/components/RecordHistory', () => ({ RecordHistory: () => null }));
vi.mock('@/components/agenda/EntityTasksPanel', () => ({ EntityTasksPanel: () => null }));
vi.mock('@/components/agenda/OpenLoopsPanel', () => ({ OpenLoopsPanel: () => null }));
vi.mock('@/components/VesselFormDialog', () => ({ VesselFormDialog: () => null }));

import ClientDetailV2 from './ClientDetailV2';

function abrir() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={['/v2/clients/c1']}>
          <Routes><Route path="/v2/clients/:id" element={<ClientDetailV2 />} /></Routes>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

const cartao = (nome: string) => screen.getByText(nome).closest('a') as HTMLElement;

describe('ClientDetailV2 — cartões pelo tipo', () => {
  it('lancha como era: pés, "Sem marina" e a vaga', () => {
    abrir();
    const c = cartao('Lancha Netuno II');
    expect(c).toHaveTextContent('40 pés');
    expect(c).toHaveTextContent('Sem marina · B12');
    expect(c.querySelector('.lucide-ship')).toBeTruthy();
  });

  it('motorhome: metros, sem "Sem marina" e sem a vaga de píer, ícone de motorhome', () => {
    abrir();
    const c = cartao('Motorhome Vitória Star');
    expect(c).toHaveTextContent('12,2 m');
    expect(c).not.toHaveTextContent(/pés|ft|Sem marina|Rua A/);
    expect(c).toHaveTextContent('Local não informado');
    expect(c.querySelector('.lucide-caravan')).toBeTruthy();
  });

  it('equipamento: sem comprimento, com o local', () => {
    abrir();
    const c = cartao('Equipamento Inversor');
    expect(c).not.toHaveTextContent(/pés|\d m\b/);
    expect(c).toHaveTextContent('Oficina');
    expect(c.querySelector('.lucide-wrench')).toBeTruthy();
  });
});

describe('ClientDetailV2 — aba Financeiro: quem paga por este cliente', () => {
  const PROPOSTO = {
    id: 'pg1', client_id: 'c1', documento: '12345678901', nome: 'MARIA SOUZA', relacao: 'conjuge', situacao: 'proposto',
    observacao: null, origem: 'historico', bank_transaction_id: 'bt1', proposto_por: 'u2', proposto_em: '2026-10-20T12:00:00Z',
    confirmado_por: null, confirmado_em: null, decidido_motivo: null, proposto: { full_name: 'Fin' }, confirmado: null,
  };

  beforeEach(() => {
    estado.cargo = undefined;
    estado.tabelas = [];
    estado.pagadores = [PROPOSTO];
  });

  async function abrirFinanceiro() {
    const user = userEvent.setup();
    abrir();
    await user.click(screen.getByRole('tab', { name: /financeiro/i }));
  }

  it('administrador vê a seção, o CPF mascarado, a relação e o "Confirmar" do proposto', async () => {
    estado.cargo = 'admin';
    await abrirFinanceiro();
    const secao = (await screen.findByRole('heading', { name: 'Quem paga por este cliente' })).closest('section') as HTMLElement;
    expect(await within(secao).findByText('MARIA SOUZA')).toBeInTheDocument();
    expect(secao).toHaveTextContent('Cônjuge · CPF ***.456.789-**');
    expect(secao).not.toHaveTextContent('12345678901');
    expect(secao).toHaveTextContent('Proposto por Fin');
    expect(within(secao).getByRole('button', { name: /Confirmar/ })).toBeInTheDocument();
    expect(estado.tabelas).toContain('pagadores_do_cliente');
  });

  it('financeiro vê a seção, mas sem "Confirmar" (o SIM é do administrador)', async () => {
    estado.cargo = 'financial';
    await abrirFinanceiro();
    const secao = (await screen.findByRole('heading', { name: 'Quem paga por este cliente' })).closest('section') as HTMLElement;
    expect(await within(secao).findByText('MARIA SOUZA')).toBeInTheDocument();
    expect(within(secao).queryByRole('button', { name: /Confirmar/ })).toBeNull();
    expect(within(secao).getByRole('button', { name: /Mais ações para pagador MARIA SOUZA/ })).toBeInTheDocument();
  });

  it.each(['technician', 'seller', 'external_seller'])('%s: a seção some e a consulta nem sai', async (cargo) => {
    estado.cargo = cargo;
    await abrirFinanceiro();
    // a aba abriu (o resto do financeiro continua lá); só a seção dos pagadores não existe
    expect(screen.getByRole('tabpanel')).toHaveTextContent('Nenhum registro financeiro.');
    expect(screen.queryByText('Quem paga por este cliente')).toBeNull();
    expect(screen.queryByText('MARIA SOUZA')).toBeNull();
    expect(estado.tabelas).not.toContain('pagadores_do_cliente');
  });
});

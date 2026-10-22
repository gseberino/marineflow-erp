// Ficha do cliente (v2), aba das embarcações e veículos: cada cartão mostra os campos do tipo
// (dono, 22/10/2026). Motorhome em metros, sem vaga de píer e sem "Sem marina".
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
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
vi.mock('@/integrations/supabase/client', () => {
  const q = { select: () => q, eq: () => q, order: async () => ({ data: [], error: null }) };
  return { supabase: { from: () => q } };
});
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

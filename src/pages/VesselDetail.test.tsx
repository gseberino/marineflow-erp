// Ficha da embarcação ou veículo (/vessels/:id e /v2/vessels/:id, que embrulha esta tela): só os
// campos do tipo (dono, 22/10/2026). Motorhome sem boca, calado, píer, propulsão e eletrônica de
// navegação, comprimento em metros; equipamento sem comprimento e sem motores; barco como era.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

let cadastroAtual: Record<string, unknown> = {};
let resposta = { data: cadastroAtual, isLoading: false };

vi.mock('@/hooks/use-vessels', () => ({ useVessel: () => resposta }));
vi.mock('@/hooks/use-auth', () => {
  const r = { user: { role: 'technician' } };
  return { useAuth: () => r };
});
vi.mock('@/integrations/supabase/client', () => {
  const q = { select: () => q, eq: () => q, order: async () => ({ data: [], error: null }) };
  return { supabase: { from: () => q } };
});
vi.mock('@/components/agenda/MaintenancePlansPanel', () => ({ MaintenancePlansPanel: () => null }));
vi.mock('@/components/agenda/EntityTasksPanel', () => ({ EntityTasksPanel: () => null }));
vi.mock('@/components/RecordHistory', () => ({ RecordHistory: () => null }));
vi.mock('@/components/dropbox/PastaNoDropbox', () => ({ PastaDoBarcoBotao: () => null }));
vi.mock('@/components/dropbox/ArquivosDoBarco', () => ({ ArquivosDoBarco: () => null }));
vi.mock('@/components/VesselFormDialog', () => ({ VesselFormDialog: () => null }));

import VesselDetail from './VesselDetail';

function cadastro(p: Record<string, unknown>) {
  cadastroAtual = {
    id: 'v1', client_id: 'c1', name: 'Vitória Star', active: true, asset_type: null, manufacturer: null, model: null,
    year: null, length_feet: null, beam_feet: null, draft_feet: null, hull_id_or_registration: null,
    engine_brand: null, engine_model: null, engine_quantity: null, engine_type: null, propulsion_type: null,
    shore_power_type: null, battery_bank_summary: null, inverter_charger_summary: null,
    navigation_electronics_summary: null, electrical_system_notes: null, current_dock_position: null,
    current_marina_name_snapshot: null, marina_id: null, access_notes: null,
    clients: { name: 'Fulano' }, marinas: null,
    ...p,
  };
  resposta = { data: cadastroAtual, isLoading: false };
}

function abrir(aba = 'overview') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[`/vessels/v1?tab=${aba}`]}>
          <Routes><Route path="/vessels/:id" element={<VesselDetail />} /></Routes>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

/** O valor ao lado do rótulo numa linha da ficha. */
const linha = (rotulo: string) => screen.getByText(rotulo).parentElement as HTMLElement;

beforeEach(() => cadastro({}));

describe('VesselDetail — campos pelo tipo', () => {
  it('motorhome: cabeçalho e ficha em metros, sem campos de barco, "Onde fica" e "Energia externa"', () => {
    cadastro({
      asset_type: 'Motorhome', manufacturer: 'Iveco', model: 'Daily', year: 2020, length_feet: 40,
      beam_feet: 8, draft_feet: 1, propulsion_type: 'Diesel', current_dock_position: 'Rua A, 01',
      shore_power_type: '220 V', marinas: { name: 'Pátio HBR' },
    });
    abrir();
    expect(screen.getByText('Motorhome • Iveco Daily (2020) • 12,2 m • Proprietário: Fulano')).toBeInTheDocument();
    expect(within(linha('Comprimento')).getByText('12,2 m')).toBeInTheDocument();
    for (const r of ['Boca', 'Calado', 'Propulsão', 'Posição no Píer', 'Marina', 'Energia de cais']) {
      expect(screen.queryByText(r)).not.toBeInTheDocument();
    }
    expect(within(linha('Onde fica')).getByText('Pátio HBR')).toBeInTheDocument();
    expect(within(linha('Energia externa (tomada ou camping)')).getByText('220 V')).toBeInTheDocument();
    expect(screen.queryByText(/ ft\b/)).not.toBeInTheDocument();
    expect(document.querySelector('h1 .lucide-caravan')).toBeTruthy();
  });

  it('lancha fica como era: boca, calado, propulsão, marina, píer e energia de cais, em pés', () => {
    cadastro({
      asset_type: 'Lancha', name: 'Netuno II', length_feet: 40, beam_feet: 12.5, draft_feet: 3,
      propulsion_type: 'Centro-rabeta', current_dock_position: 'B12', shore_power_type: '110 V', marinas: { name: 'Marina Itajaí' },
    });
    abrir();
    expect(within(linha('Comprimento')).getByText('40 pés')).toBeInTheDocument();
    expect(within(linha('Boca')).getByText('12,5 pés')).toBeInTheDocument();
    expect(within(linha('Calado')).getByText('3 pés')).toBeInTheDocument();
    expect(within(linha('Propulsão')).getByText('Centro-rabeta')).toBeInTheDocument();
    expect(within(linha('Marina')).getByText('Marina Itajaí')).toBeInTheDocument();
    expect(within(linha('Posição no Píer')).getByText('B12')).toBeInTheDocument();
    expect(within(linha('Energia de cais')).getByText('110 V')).toBeInTheDocument();
    expect(document.querySelector('h1 .lucide-ship')).toBeTruthy();
  });

  it('perfil técnico do motorhome: motores sim, eletrônica de navegação não', () => {
    cadastro({ asset_type: 'Motorhome', engine_brand: 'Iveco', navigation_electronics_summary: 'GPS' });
    abrir('technical');
    expect(screen.getByText('Motores')).toBeInTheDocument();
    expect(screen.queryByText('Eletrônica de Navegação')).not.toBeInTheDocument();
    expect(screen.queryByText('GPS')).not.toBeInTheDocument();
  });

  it('equipamento: sem comprimento, sem motores, sem eletrônica de navegação', () => {
    cadastro({ asset_type: 'Equipamento', name: 'Inversor', length_feet: 3, engine_brand: 'Volvo' });
    const { unmount } = abrir();
    expect(screen.queryByText('Comprimento')).not.toBeInTheDocument();
    expect(screen.queryByText(/3 pés|0,9 m/)).not.toBeInTheDocument();
    expect(document.querySelector('h1 .lucide-wrench')).toBeTruthy();
    unmount();
    abrir('technical');
    expect(screen.queryByText('Motores')).not.toBeInTheDocument();
    expect(screen.queryByText('Eletrônica de Navegação')).not.toBeInTheDocument();
    expect(screen.getByText('Sistemas de Energia')).toBeInTheDocument();
  });
});

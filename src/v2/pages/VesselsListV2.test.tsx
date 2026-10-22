// Lista de embarcações e veículos (v2): comprimento pelo tipo, "Onde fica" para a lista mista e a
// busca pelo tipo e pelos sinônimos (decisões do dono, 22/10/2026).
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';

vi.mock('@/hooks/use-vessels', () => {
  const r = {
    isLoading: false, error: null,
    data: [
      { id: 'l', name: 'Netuno II', asset_type: 'Lancha', length_feet: 40, clients: { name: 'Ana' }, marinas: { name: 'Marina Itajaí' } },
      { id: 'm', name: 'Vitória Star', asset_type: 'Motorhome', length_feet: 40, clients: { name: 'Bruno' }, marinas: { name: 'Pátio HBR' } },
      { id: 'j', name: 'Verde', asset_type: 'Jet Ski', length_feet: null, clients: { name: 'Caio' }, marinas: null },
      { id: 'e', name: 'Inversor', asset_type: 'Equipamento', length_feet: 3, clients: { name: 'Davi' }, marinas: null },
    ],
  };
  return { useVessels: () => r };
});
vi.mock('@/components/VesselFormDialog', () => ({ VesselFormDialog: () => null }));
vi.mock('@/components/FilterPresets', () => ({ FilterPresets: () => null }));

import VesselsListV2 from './VesselsListV2';

// A DataTable mostra as colunas que cabem na largura medida; no jsdom tudo mede 0. Uma tela larga
// faz todas aparecerem.
Object.defineProperty(HTMLElement.prototype, 'clientWidth', { configurable: true, get: () => 1600 });

function abrir() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter><VesselsListV2 /></MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('VesselsListV2 — pelo tipo', () => {
  it('comprimento em pés no barco, em metros no veículo, nada no equipamento; nunca "ft"', () => {
    abrir();
    // Na tabela e no cartão do celular (os dois estão no DOM; o CSS escolhe qual aparece).
    expect(screen.getAllByText(/40 pés/).length).toBe(2);
    expect(screen.getAllByText(/12,2 m/).length).toBe(2);
    expect(screen.queryByText(/\bft\b/)).not.toBeInTheDocument();
    expect(screen.queryByText(/0,9 m|3 pés/)).not.toBeInTheDocument();
  });

  it('a coluna do local é "Onde fica" (lista mista) e o "Jet Ski" antigo aparece como Moto aquática', () => {
    abrir();
    expect(screen.getByRole('columnheader', { name: /Onde fica/ })).toBeInTheDocument();
    expect(screen.queryByRole('columnheader', { name: /^Marina/ })).not.toBeInTheDocument();
    expect(screen.getAllByText(/Moto aquática ·/).length).toBeGreaterThan(0);
    expect(screen.queryByText(/Jet Ski/)).not.toBeInTheDocument();
  });

  it('a busca acha pelo tipo e pelos sinônimos ("motorhome", "jet ski")', async () => {
    const user = userEvent.setup();
    abrir();
    const busca = screen.getByPlaceholderText(/Buscar por nome/);
    await user.type(busca, 'motorhome');
    expect(screen.getAllByText('Vitória Star').length).toBeGreaterThan(0);
    expect(screen.queryByText('Netuno II')).not.toBeInTheDocument();
    await user.clear(busca);
    await user.type(busca, 'jet ski');
    expect(screen.getAllByText('Verde').length).toBeGreaterThan(0);
    expect(screen.queryByText('Vitória Star')).not.toBeInTheDocument();
  });
});

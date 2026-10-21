// Seção "Cliente & Embarcação" montada: ficha do cliente, ficha da embarcação e o contato do
// solicitante escolhido (20/10/2026).
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';

vi.mock('@/components/ClientFormDialog', () => ({ ClientFormDialog: () => null }));
vi.mock('@/components/VesselFormDialog', () => ({ VesselFormDialog: () => null }));
vi.mock('@/hooks/use-ficha-cliente', () => ({
  useSaldoEmAberto: () => ({ data: undefined }),
  useClientesRecentes: () => ({ data: [] }),
}));

import { GeneralSections } from './general-sections';

const cliente = {
  id: 'c1', name: 'João da Silva', active: true, type: 'individual', phone: '(47) 99999-1234', whatsapp: null,
  email: null, cpf_cnpj: null, address_line_1: null, neighborhood: null, city: null, state: null, postal_code: null,
  notes: null, opt_out_whatsapp: false, ie_indicator: 9, state_registration: null,
};
const barco = {
  id: 'v1', client_id: 'c1', name: 'Netuno II', active: true, asset_type: 'Lancha', manufacturer: 'Schaefer',
  model: '400', year: 2019, length_feet: 40, marina_id: null, marinas: null,
};
const marinheiro = { id: 'k1', vessel_id: 'v1', full_name: 'Pedro Marinheiro', role: 'captain', phone: '(47) 98888-7777', email: null, active: true };

function renderiza(form: Record<string, unknown>) {
  const nada = () => {};
  return render(
    <I18nProvider>
      <MemoryRouter>
        <GeneralSections
          isNew={false} isLocked={false} orderData={null}
          form={{ status: 'draft', priority: 'normal', service_type: 'repair', requested_by_name: '', ...form }}
          set={nada} setForm={nada}
          clients={[cliente]} allVessels={[barco]} clientVessels={[barco]} marinas={[]} appUsers={[]}
          vesselContacts={[marinheiro]}
          selectedTechnicians={[]} setSelectedTechnicians={nada}
          setQuickMarinaOpen={nada} setQuickMarinaName={nada}
          isOptimizing={false} optimizeText={nada}
        />
      </MemoryRouter>
    </I18nProvider>,
  );
}

describe('GeneralSections — cliente, embarcação e solicitante', () => {
  it('com cliente, embarcação e solicitante escolhidos, as três fichas aparecem', () => {
    renderiza({ client_id: 'c1', vessel_id: 'v1', requested_by_contact_id: 'k1' });
    expect(screen.getByLabelText('Dados do cliente')).toHaveTextContent('João da Silva');
    expect(screen.getByLabelText('Dados da embarcação')).toHaveTextContent('Lancha · Schaefer 400');
    expect(screen.getByRole('link', { name: /\(47\) 98888-7777/ })).toHaveAttribute('href', 'tel:+5547988887777');
    expect(screen.getByRole('link', { name: 'Abrir conversa com o solicitante no WhatsApp' }))
      .toHaveAttribute('href', 'https://wa.me/5547988887777');
  });

  it('sem embarcação e sem solicitante, nenhuma ficha a mais', () => {
    renderiza({ client_id: 'c1', vessel_id: '', requested_by_contact_id: '' });
    expect(screen.queryByLabelText('Dados da embarcação')).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /98888-7777/ })).not.toBeInTheDocument();
  });
});

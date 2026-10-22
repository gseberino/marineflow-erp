// Cadastro de embarcação ou veículo: a lista de tipos e os campos de cada tipo (decisões do dono,
// 22/10/2026). Veículo não tem boca, calado, píer, propulsão nem eletrônica de navegação, e se
// mede em metros; o que já está gravado nesses campos volta igual ao salvar.
//
// Todo mock devolve a MESMA referência a cada chamada (ver ProductFormDialog.smoke.test.tsx):
// objeto novo por render faz os useEffect do formulário entrarem em laço.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';
import type { Tables } from '@/integrations/supabase/types';

const atualizar = vi.fn(async (..._: unknown[]) => ({}));
const criar = vi.fn(async (..._: unknown[]) => ({ id: 'novo', name: 'Novo' }));
// Cargo de quem usa: escritório por padrão; os testes do técnico trocam.
const sessao = vi.hoisted(() => ({ cargo: 'admin' as string | undefined }));

vi.mock('@/hooks/use-auth', () => {
  const porCargo = new Map<string | undefined, unknown>();
  const auth = () => {
    if (!porCargo.has(sessao.cargo)) porCargo.set(sessao.cargo, { user: { id: 'u1', role: sessao.cargo }, loading: false });
    return porCargo.get(sessao.cargo);
  };
  return { useOptionalAuth: auth, useAuth: auth };
});

vi.mock('@/hooks/use-vessels', () => {
  const upd = { mutateAsync: (...a: unknown[]) => atualizar(...a), isPending: false };
  const cre = { mutateAsync: (...a: unknown[]) => criar(...a), isPending: false };
  return { useUpdateVessel: () => upd, useCreateVessel: () => cre };
});
vi.mock('@/hooks/use-clients', () => {
  const r = { data: [{ id: 'c1', name: 'Fulano', active: true, cpf_cnpj: null, email: null }] };
  return { useClients: () => r };
});
vi.mock('@/hooks/use-marinas', () => {
  const r = { data: [] };
  return { useMarinas: () => r };
});
vi.mock('@/hooks/use-vessel-contacts', () => {
  const lista = { data: [], isLoading: false };
  const m = { mutateAsync: async () => ({}), isPending: false };
  return { useVesselContacts: () => lista, useCreateVesselContact: () => m, VESSEL_CONTACT_ROLES: [{ value: 'owner', label: 'Proprietário' }] };
});

import { VesselFormDialog } from './VesselFormDialog';

type Vessel = Tables<'vessels'>;

function cadastro(p: Partial<Vessel>): Vessel {
  return {
    id: 'v1', client_id: 'c1', name: 'Vitória Star', active: true, asset_type: null, manufacturer: null, model: null,
    year: null, length_feet: null, beam_feet: null, draft_feet: null, hull_id_or_registration: null,
    engine_brand: null, engine_model: null, engine_quantity: 1, engine_type: null, propulsion_type: null,
    shore_power_type: null, battery_bank_summary: null, inverter_charger_summary: null,
    navigation_electronics_summary: null, electrical_system_notes: null, current_dock_position: null,
    current_marina_name_snapshot: null, marina_id: null, access_notes: null, created_at: '', updated_at: '',
    ...p,
  } as Vessel;
}

const abrir = (vessel?: Vessel | null) =>
  render(
    <I18nProvider>
      <VesselFormDialog open onOpenChange={() => {}} vessel={vessel} />
    </I18nProvider>,
  );

const seletorDeTipo = () => screen.getByRole('combobox', { name: 'Tipo' });

beforeEach(() => {
  atualizar.mockClear();
  criar.mockClear();
  sessao.cargo = 'admin';
});

// Só o escritório troca o DONO de um cadastro que já existe (decisão do dono, 22/10/2026).
describe('VesselFormDialog — quem troca o dono', () => {
  const campoDoDono = () => screen.getByRole('combobox', { name: /Selecionar Cliente/ });

  it('técnico editando: dono travado, com o motivo pelo tipo; o salvar não manda client_id', async () => {
    sessao.cargo = 'technician';
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Motorhome', access_notes: 'portaria' }));
    expect(campoDoDono()).toBeDisabled();
    expect(screen.getByText('Só o escritório troca o dono do motorhome.')).toBeInTheDocument();
    expect(campoDoDono()).toHaveAccessibleDescription('Só o escritório troca o dono do motorhome.');
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({ id: 'v1', access_notes: 'portaria' }));
    expect(atualizar.mock.calls[0][0]).not.toHaveProperty('client_id');
  });

  it('técnico criando: o dono é escolhido livremente', () => {
    sessao.cargo = 'technician';
    abrir();
    expect(campoDoDono()).toBeEnabled();
    expect(screen.queryByText(/Só o escritório troca o dono/)).not.toBeInTheDocument();
  });

  it('escritório editando: dono livre e o client_id vai no salvar', async () => {
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Lancha' }));
    expect(campoDoDono()).toBeEnabled();
    expect(screen.queryByText(/Só o escritório troca o dono/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({ id: 'v1', client_id: 'c1' }));
  });

  it('cargo ainda não carregado: travado, sem motivo (falha fechada), e o client_id não vai', async () => {
    sessao.cargo = undefined;
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Lancha' }));
    expect(campoDoDono()).toBeDisabled();
    expect(screen.queryByText(/Só o escritório troca o dono/)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar.mock.calls[0][0]).not.toHaveProperty('client_id');
  });
});

describe('VesselFormDialog — lista de tipos (decisão 1, 22/10/2026)', () => {
  it('por grupo, com "Moto aquática", os "Outros" de cada grupo, Automóvel e Equipamento; sem "Jet Ski"', async () => {
    const user = userEvent.setup();
    abrir();
    await user.click(seletorDeTipo());
    const lista = screen.getByRole('listbox');
    for (const grupo of ['Embarcações', 'Veículos', 'Bancada']) expect(within(lista).getByText(grupo)).toBeInTheDocument();
    for (const tipo of ['Lancha', 'Veleiro', 'Catamarã', 'Moto aquática', 'Outra embarcação', 'Trailer', 'Camper', 'Automóvel', 'Outro veículo']) {
      expect(within(lista).getByRole('option', { name: tipo })).toBeInTheDocument();
    }
    expect(within(lista).getByRole('option', { name: 'Motorhome — inclui van convertida' })).toBeInTheDocument();
    expect(within(lista).getByRole('option', { name: 'Equipamento — atendido na bancada' })).toBeInTheDocument();
    expect(within(lista).queryByRole('option', { name: /jet ski/i })).not.toBeInTheDocument();
    expect(within(lista).queryByRole('option', { name: 'Outro' })).not.toBeInTheDocument();
  });

  it('escolhido o Motorhome, o campo fechado mostra só o tipo (a dica fica na lista)', async () => {
    const user = userEvent.setup();
    abrir();
    await user.click(seletorDeTipo());
    await user.click(screen.getByRole('option', { name: 'Motorhome — inclui van convertida' }));
    expect(seletorDeTipo()).toHaveTextContent(/^Motorhome$/);
  });

  it('o rótulo é "Tipo *" e a palavra "unidade" não aparece para o usuário', () => {
    abrir();
    expect(screen.getByText('Tipo *')).toBeInTheDocument();
    expect(screen.getByRole('dialog').textContent ?? '').not.toMatch(/unidade/i);
  });

  it('cadastro antigo "Jet Ski" aparece como Moto aquática; Automóvel e Equipamento não ficam vazios', () => {
    const { unmount } = abrir(cadastro({ asset_type: 'Jet Ski' }));
    expect(seletorDeTipo()).toHaveTextContent('Moto aquática');
    unmount();
    const r2 = abrir(cadastro({ asset_type: 'Automóvel' }));
    expect(seletorDeTipo()).toHaveTextContent('Automóvel');
    r2.unmount();
    abrir(cadastro({ asset_type: 'Equipamento' }));
    expect(seletorDeTipo()).toHaveTextContent('Equipamento');
  });

  it('tipo gravado que a lista não tem aparece como está, em vez do campo vazio', async () => {
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Escuna' }));
    expect(seletorDeTipo()).toHaveTextContent('Escuna');
    await user.click(seletorDeTipo());
    expect(within(screen.getByRole('listbox')).getByText('Cadastrado como')).toBeInTheDocument();
  });

  it('abrir e salvar um tipo fora da lista não apaga o tipo (o seletor vazio de antes)', async () => {
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Escuna', name: 'Velha' }));
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({ asset_type: 'Escuna' }));
  });

  it('salvar o "Jet Ski" antigo grava o valor novo', async () => {
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Jet Ski', name: 'Azul' }));
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({ id: 'v1', asset_type: 'Moto aquática' }));
  });
});

describe('VesselFormDialog — campos pelo tipo (decisão 4, 22/10/2026)', () => {
  it('barco fica como estava: boca, calado, píer, propulsão, eletrônica, comprimento em pés, Marina', () => {
    abrir(cadastro({ asset_type: 'Lancha', name: 'Netuno II', length_feet: 40 }));
    for (const r of ['Boca (pés)', 'Calado (pés)', 'Posição no Píer', 'Tipo de Propulsão', 'Eletrônica de Navegação', 'Energia de cais']) {
      expect(screen.getByLabelText(r)).toBeInTheDocument();
    }
    expect(screen.getByLabelText('Comprimento (pés)')).toHaveValue(40);
    expect(screen.getByText('Marina')).toBeInTheDocument();
  });

  it('veículo: sem os campos náuticos, comprimento em metros, "Energia externa" e "Onde fica"', () => {
    abrir(cadastro({ asset_type: 'Motorhome', length_feet: 40 }));
    for (const r of [/Boca/, /Calado/, /Píer/, /Propulsão/, /Eletrônica de Navegação/, /Energia de cais/]) {
      expect(screen.queryByLabelText(r)).not.toBeInTheDocument();
    }
    expect(screen.queryByLabelText('Comprimento (pés)')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Comprimento (m)')).toHaveValue(12.19);
    expect(screen.getByLabelText('Energia externa (tomada ou camping)')).toBeInTheDocument();
    expect(screen.getByText('Onde fica')).toBeInTheDocument();
    expect(screen.queryByText('Marina')).not.toBeInTheDocument();
    // Motores continuam no veículo.
    expect(screen.getByText('Marca do Motor')).toBeInTheDocument();
  });

  it('equipamento: sem comprimento e sem motores', () => {
    abrir(cadastro({ asset_type: 'Equipamento', name: 'Bancada', length_feet: 3 }));
    expect(screen.queryByLabelText(/Comprimento/)).not.toBeInTheDocument();
    expect(screen.queryByText('Marca do Motor')).not.toBeInTheDocument();
    expect(screen.queryByText('Quantidade de Motores')).not.toBeInTheDocument();
    expect(screen.getByText('Onde fica')).toBeInTheDocument();
  });

  it('salvar o veículo sem mexer não muda a medida nem apaga o que os campos escondidos guardam', async () => {
    const user = userEvent.setup();
    abrir(cadastro({
      asset_type: 'Motorhome', length_feet: 23.79, beam_feet: 8, draft_feet: 1,
      current_dock_position: 'Rua A, 01', propulsion_type: 'Diesel', navigation_electronics_summary: 'GPS',
    }));
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({
      length_feet: 23.79, beam_feet: 8, draft_feet: 1,
      current_dock_position: 'Rua A, 01', propulsion_type: 'Diesel', navigation_electronics_summary: 'GPS',
    }));
  });

  it('o comprimento digitado em metros vai para o banco em pés', async () => {
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Motorhome', length_feet: null }));
    await user.type(screen.getByLabelText('Comprimento (m)'), '7.5');
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({ length_feet: 24.61 }));
  });

  it('apagar o comprimento em metros deixa a medida vazia', async () => {
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Trailer', length_feet: 20 }));
    await user.clear(screen.getByLabelText('Comprimento (m)'));
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    // null (não undefined): undefined some do PATCH e a medida antiga ficava no banco.
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({ length_feet: null }));
  });

  it('trocar o tipo de lancha para motorhome mostra a mesma medida, agora em metros', async () => {
    const user = userEvent.setup();
    abrir(cadastro({ asset_type: 'Lancha', length_feet: 40 }));
    await user.click(seletorDeTipo());
    await user.click(screen.getByRole('option', { name: 'Motorhome — inclui van convertida' }));
    expect(screen.getByLabelText('Comprimento (m)')).toHaveValue(12.19);
  });
});

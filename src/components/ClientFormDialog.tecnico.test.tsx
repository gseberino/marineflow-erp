// Nome, CPF/CNPJ e tipo de um cliente que já existe, só o escritório muda (decisão do dono,
// 22/10/2026); telefone, e-mail e endereço o técnico continua podendo. Criar continua livre.
//
// Todo mock devolve a MESMA referência a cada chamada: objeto novo por render faz os useEffect do
// formulário entrarem em laço (ver VesselFormDialog.test.tsx).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';
import type { Client } from '@/hooks/use-clients';

const atualizar = vi.fn(async (..._: unknown[]) => ({}));
const criar = vi.fn(async (..._: unknown[]) => ({ id: 'novo', name: 'Novo' }));
const sessao = vi.hoisted(() => ({ cargo: 'admin' as string | undefined }));

vi.mock('@/hooks/use-auth', () => {
  const porCargo = new Map<string | undefined, unknown>();
  const auth = () => {
    if (!porCargo.has(sessao.cargo)) porCargo.set(sessao.cargo, { user: { id: 'u1', role: sessao.cargo }, loading: false });
    return porCargo.get(sessao.cargo);
  };
  return { useOptionalAuth: auth, useAuth: auth };
});
vi.mock('@/hooks/use-clients', () => {
  const upd = { mutateAsync: (...a: unknown[]) => atualizar(...a), isPending: false };
  const cre = { mutateAsync: (...a: unknown[]) => criar(...a), isPending: false };
  return { useUpdateClient: () => upd, useCreateClient: () => cre };
});
vi.mock('@/hooks/use-cnpj', () => {
  const r = { cnpjLoading: false, fetchByCnpj: async () => null };
  return { useCnpj: () => r };
});
vi.mock('@/hooks/use-client-whatsapp-settings', () => {
  const lista = { data: [], isLoading: false };
  const m = { mutateAsync: async () => ({}), isPending: false };
  return {
    useClientWhatsAppSettings: () => lista,
    useUpsertClientWhatsAppSetting: () => m,
    useDeleteClientWhatsAppSetting: () => m,
    pickClientSetting: () => null,
  };
});

import { ClientFormDialog } from './ClientFormDialog';

const MOTIVO = 'Só o escritório muda o nome, o CPF/CNPJ e o tipo do cliente. Telefone, e-mail e endereço você pode mudar.';

const cliente = {
  id: 'c1', type: 'company', name: 'Marina Azul Ltda', cpf_cnpj: '12.345.678/0001-90', phone: '(47) 99999-0000',
  whatsapp: null, email: 'contato@azul.com', postal_code: null, address_line_1: null, address_line_2: null,
  city: 'Itajaí', state: 'SC', country: 'Brazil', notes: null, active: true,
} as unknown as Client;

const abrir = (client?: Client | null) =>
  render(
    <I18nProvider>
      <ClientFormDialog open onOpenChange={() => {}} client={client} />
    </I18nProvider>,
  );

const campoTipo = () => screen.getByRole('combobox', { name: 'Tipo' });
const campoNome = () => screen.getByLabelText(/Nome Completo/);
const campoDocumento = () => screen.getByLabelText('CNPJ');

beforeEach(() => {
  atualizar.mockClear();
  criar.mockClear();
  sessao.cargo = 'admin';
});

describe('ClientFormDialog — quem muda nome, CPF/CNPJ e tipo', () => {
  it('técnico editando: os três travados, com o motivo, sem a busca na Receita', () => {
    sessao.cargo = 'technician';
    abrir(cliente);
    for (const campo of [campoTipo(), campoNome(), campoDocumento()]) {
      expect(campo).toBeDisabled();
      expect(campo).toHaveAccessibleDescription(MOTIVO);
    }
    expect(screen.getByText(MOTIVO)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Buscar dados da empresa pelo CNPJ' })).not.toBeInTheDocument();
  });

  it('técnico editando: muda o telefone; o salvar não manda nome, CPF/CNPJ nem tipo', async () => {
    sessao.cargo = 'technician';
    const user = userEvent.setup();
    abrir(cliente);
    const telefone = screen.getByLabelText('Telefone');
    expect(telefone).toBeEnabled();
    await user.clear(telefone);
    await user.type(telefone, '47988887777');
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledTimes(1);
    const enviado = atualizar.mock.calls[0][0] as Record<string, unknown>;
    expect(enviado).toMatchObject({ id: 'c1', phone: '(47) 98888-7777', email: 'contato@azul.com', city: 'Itajaí' });
    for (const coluna of ['name', 'cpf_cnpj', 'type']) expect(enviado).not.toHaveProperty(coluna);
  });

  it('técnico criando: os três livres', () => {
    sessao.cargo = 'technician';
    abrir();
    for (const campo of [campoTipo(), campoNome()]) expect(campo).toBeEnabled();
    expect(screen.getByLabelText('CPF')).toBeEnabled();
    expect(screen.queryByText(MOTIVO)).not.toBeInTheDocument();
  });

  it('escritório editando: os três livres e vão no salvar', async () => {
    const user = userEvent.setup();
    abrir(cliente);
    for (const campo of [campoTipo(), campoNome(), campoDocumento()]) expect(campo).toBeEnabled();
    expect(screen.queryByText(MOTIVO)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(atualizar).toHaveBeenCalledWith(expect.objectContaining({
      id: 'c1', name: 'Marina Azul Ltda', cpf_cnpj: '12.345.678/0001-90', type: 'company',
    }));
  });

  it('cargo ainda não carregado: travados, sem motivo (falha fechada), e não vão no salvar', async () => {
    sessao.cargo = undefined;
    const user = userEvent.setup();
    abrir(cliente);
    for (const campo of [campoTipo(), campoNome(), campoDocumento()]) expect(campo).toBeDisabled();
    expect(screen.queryByText(MOTIVO)).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    const enviado = atualizar.mock.calls[0][0] as Record<string, unknown>;
    for (const coluna of ['name', 'cpf_cnpj', 'type']) expect(enviado).not.toHaveProperty(coluna);
  });
});

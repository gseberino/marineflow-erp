// Cliente da OS: busca em cima, ficha embaixo, editar cadastro sem sair da OS (20/10/2026).
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { Client } from '@/hooks/use-clients';

// O diálogo de verdade grava no banco; aqui só importa que abre com o cliente certo.
vi.mock('@/components/ClientFormDialog', () => ({
  ClientFormDialog: ({ open, client, initialName }: { open: boolean; client?: Client | null; initialName?: string }) =>
    open ? <div role="dialog">{client ? `editando ${client.name}` : `novo ${initialName ?? ''}`}</div> : null,
}));

import { ClienteDaOrdem } from './ClienteDaOrdem';

function cliente(p: Partial<Client> & Pick<Client, 'id' | 'name'>): Client {
  return {
    active: true, type: 'individual', cpf_cnpj: null, phone: null, whatsapp: null, email: null,
    address_line_1: null, address_line_2: null, address_number: null, address_complement: null,
    neighborhood: null, city: null, state: null, postal_code: null, country: 'Brazil', notes: null,
    ie_indicator: 9, state_registration: null, display_name: null, communication_tone: null,
    opt_out_whatsapp: false, created_at: '', updated_at: '',
    ...p,
  };
}

const joao = cliente({
  id: 'c1', name: 'João da Silva', cpf_cnpj: '123.456.789-00', phone: '(47) 99999-1234',
  email: 'joao@exemplo.com', address_line_1: 'Rua A, 10', neighborhood: 'Centro', city: 'Itajaí',
  state: 'SC', postal_code: '88300-000', notes: 'Só aprova por e-mail',
});
const semNada = cliente({ id: 'c2', name: 'Pedro Sem Cadastro' });
const clientes = [joao, semNada];

function renderiza(props: Partial<Parameters<typeof ClienteDaOrdem>[0]> = {}) {
  const onChange = vi.fn();
  const utils = render(
    <MemoryRouter>
      <ClienteDaOrdem value="" onChange={onChange} clients={clientes} {...props} />
    </MemoryRouter>,
  );
  return { ...utils, onChange };
}

describe('ClienteDaOrdem', () => {
  it('sem cliente: só a busca; achar pelo telefone e escolher', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza();
    expect(screen.queryByLabelText('Dados do cliente')).not.toBeInTheDocument();

    await user.type(screen.getByRole('combobox'), '47999991234');
    const opcao = await screen.findByRole('option', { name: /João da Silva/ });
    await user.click(opcao);
    expect(onChange).toHaveBeenCalledWith('c1', 'João da Silva');
  });

  it('Enter escolhe o primeiro resultado', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza();
    await user.type(screen.getByRole('combobox'), 'pedro{Enter}');
    expect(onChange).toHaveBeenCalledWith('c2', 'Pedro Sem Cadastro');
  });

  it('com cliente: a ficha mostra contato, endereço e observações', () => {
    renderiza({ value: 'c1' });
    const ficha = screen.getByLabelText('Dados do cliente');
    expect(within(ficha).getByText('João da Silva')).toBeInTheDocument();
    expect(within(ficha).getByText('123.456.789-00')).toBeInTheDocument();
    expect(within(ficha).getByRole('link', { name: '(47) 99999-1234' })).toHaveAttribute('href', 'tel:+5547999991234');
    expect(within(ficha).getByRole('link', { name: /WhatsApp/ })).toHaveAttribute('href', 'https://wa.me/5547999991234');
    expect(within(ficha).getByRole('link', { name: 'joao@exemplo.com' })).toHaveAttribute('href', 'mailto:joao@exemplo.com');
    expect(within(ficha).getByText(/Rua A, 10 — Centro, Itajaí\/SC/)).toBeInTheDocument();
    expect(within(ficha).getByText('Só aprova por e-mail')).toBeInTheDocument();
    expect(within(ficha).queryByText(/falta/)).not.toBeInTheDocument();
    expect(within(ficha).getByRole('link', { name: /Histórico e financeiro/ })).toHaveAttribute('href', '/v2/clients/c1');
  });

  it('cadastro incompleto: avisa o que deixa de funcionar', () => {
    renderiza({ value: 'c2' });
    const ficha = screen.getByLabelText('Dados do cliente');
    expect(within(ficha).getByText(/Sem telefone/)).toBeInTheDocument();
    expect(within(ficha).getByText('Para a nota fiscal falta: CPF/CNPJ, rua, bairro, cidade, UF, CEP.')).toBeInTheDocument();
  });

  it('Editar cadastro abre o diálogo com o cliente da OS', async () => {
    const user = userEvent.setup();
    renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /Editar cadastro/ }));
    expect(screen.getByRole('dialog')).toHaveTextContent('editando João da Silva');
  });

  it('cadastrar novo leva o que foi digitado', async () => {
    const user = userEvent.setup();
    renderiza();
    await user.type(screen.getByRole('combobox'), 'Fulano Novo');
    await user.click(await screen.findByRole('option', { name: /Cadastrar "Fulano Novo"/ }));
    expect(screen.getByRole('dialog')).toHaveTextContent('novo Fulano Novo');
  });

  it('escolher o mesmo cliente de novo não é troca (não apaga a embarcação)', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ value: 'c1' });
    await user.type(screen.getByRole('combobox'), 'joão');
    await user.click(await screen.findByRole('option', { name: /João da Silva/ }));
    expect(onChange).not.toHaveBeenCalled();
  });

  it('OS travada: sem busca, mas a ficha e o editar ficam', () => {
    renderiza({ value: 'c1', disabled: true });
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados do cliente')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Editar cadastro/ })).toBeInTheDocument();
  });

  it('lista ainda carregando → carregada: a tela continua de pé e a ficha aparece', () => {
    const onChange = vi.fn();
    const { rerender } = render(
      <MemoryRouter><ClienteDaOrdem value="c1" onChange={onChange} clients={undefined} /></MemoryRouter>,
    );
    expect(screen.queryByLabelText('Dados do cliente')).not.toBeInTheDocument();
    rerender(<MemoryRouter><ClienteDaOrdem value="c1" onChange={onChange} clients={clientes} /></MemoryRouter>);
    expect(screen.getByLabelText('Dados do cliente')).toHaveTextContent('João da Silva');
  });
});

// Cliente da OS: sem cliente, a busca; com cliente, só a ficha (rótulos em cima de cada dado) e o
// "Trocar" à parte — a troca não acontece por um clique perdido, e a que tira o que já está gravado
// pede confirmação dizendo o que sai (20 e 21/10/2026).
import { useState } from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { Client } from '@/hooks/use-clients';

// O diálogo de verdade grava no banco; aqui só importa que abre com o cliente certo.
vi.mock('@/components/ClientFormDialog', () => ({
  ClientFormDialog: ({ open, client, initialName }: { open: boolean; client?: Client | null; initialName?: string }) =>
    open ? <div role="dialog">{client ? `editando ${client.name}` : `novo ${initialName ?? ''}`}</div> : null,
}));

// Saldo e recentes vêm do banco; aqui o teste decide o que eles devolvem.
const extras = vi.hoisted(() => ({
  saldo: undefined as undefined | { emAberto: number; vencidos: number; valorVencido: number },
  recentes: [] as string[],
}));
vi.mock('@/hooks/use-ficha-cliente', () => ({
  useSaldoEmAberto: () => ({ data: extras.saldo }),
  useClientesRecentes: () => ({ data: extras.recentes }),
}));

import { ClienteDaOrdem } from './ClienteDaOrdem';

function cliente(p: Partial<Client> & Pick<Client, 'id' | 'name'>): Client {
  return {
    active: true, type: 'individual', cpf_cnpj: null, phone: null, whatsapp: null, email: null,
    address_line_1: null, address_line_2: null, address_number: null, address_complement: null,
    neighborhood: null, city: null, state: null, postal_code: null, country: 'Brazil', notes: null,
    ie_indicator: 9, state_registration: null, display_name: null, communication_tone: null,
    opt_out_whatsapp: false, generico: false, created_at: '', updated_at: '',
    ...p,
  };
}

const joao = cliente({
  id: 'c1', name: 'João da Silva', cpf_cnpj: '123.456.789-00', phone: '(47) 99999-1234',
  email: 'joao@exemplo.com', address_line_1: 'Rua A, 10', neighborhood: 'Centro', city: 'Itajaí',
  state: 'SC', postal_code: '88300-000', notes: 'Só aprova por e-mail',
});
const semNada = cliente({ id: 'c2', name: 'Pedro Sem Cadastro' });
const empresa = cliente({ id: 'c3', name: 'Marina Itajaí Ltda', type: 'company' });
const clientes = [joao, semNada, empresa];

type Props = Parameters<typeof ClienteDaOrdem>[0];
function renderiza(props: Partial<Props> = {}) {
  const onChange = vi.fn();
  const utils = render(
    <MemoryRouter>
      <ClienteDaOrdem rotulo="Cliente *" value="" onChange={onChange} clients={clientes} {...props} />
    </MemoryRouter>,
  );
  return { ...utils, onChange };
}

/** Ficha → "Trocar" → digita e clica no resultado. */
async function trocarPara(user: ReturnType<typeof userEvent.setup>, termo: string, nome: RegExp) {
  await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
  await user.type(screen.getByRole('combobox'), termo);
  await user.click(await screen.findByRole('option', { name: nome }));
}

beforeEach(() => { extras.saldo = undefined; extras.recentes = []; });

describe('ClienteDaOrdem — escolher e trocar', () => {
  it('sem cliente: só a busca; achar pelo telefone e escolher', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza();
    expect(screen.queryByLabelText('Dados do cliente')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Trocar cliente/ })).not.toBeInTheDocument();
    await user.type(screen.getByRole('combobox'), '47999991234');
    await user.click(await screen.findByRole('option', { name: /João da Silva/ }));
    expect(onChange).toHaveBeenCalledWith('c1', 'João da Silva');
  });

  it('Enter escolhe o primeiro resultado (digitado)', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza();
    await user.type(screen.getByRole('combobox'), 'pedro{Enter}');
    expect(onChange).toHaveBeenCalledWith('c2', 'Pedro Sem Cadastro');
  });

  it('com cliente: a busca some — só a ficha e o "Trocar"', () => {
    renderiza({ value: 'c1' });
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados do cliente')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Trocar cliente (atual: João da Silva)' })).toBeInTheDocument();
  });

  it('"Trocar" abre a busca com o foco nela, lista fechada: Enter sem digitar não troca', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    const busca = screen.getByRole('combobox');
    expect(busca).toHaveFocus();
    expect(screen.getByText(/por:/)).toHaveTextContent('Trocar João da Silva por:');
    expect(screen.queryByRole('option')).not.toBeInTheDocument();
    await user.keyboard('{Enter}');
    expect(onChange).not.toHaveBeenCalled();
  });

  it('Cancelar e Esc voltam para a ficha sem trocar', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    await user.click(screen.getByRole('button', { name: 'Cancelar a troca e manter João da Silva' }));
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados do cliente')).toBeInTheDocument();
    // a busca sumiu com o foco dentro: o foco volta para o "Trocar"
    await waitFor(() => expect(screen.getByRole('button', { name: /^Trocar cliente/ })).toHaveFocus());

    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    await user.type(screen.getByRole('combobox'), 'ped');
    await user.keyboard('{Escape}'); // 1º Esc: fecha a lista e limpa
    expect(screen.getByRole('combobox')).toBeInTheDocument();
    await user.keyboard('{Escape}'); // 2º Esc: sai da troca
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(onChange).not.toHaveBeenCalled();
  });

  it('clicar fora do bloco sai da troca', async () => {
    const user = userEvent.setup();
    renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    fireEvent.pointerDown(document.body, { pointerType: 'mouse' });
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
  });

  it('no toque, só sai no toque completo (rolar a página começando fora não cancela)', async () => {
    const user = userEvent.setup();
    renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    // o jsdom não tem PointerEvent: o pointerType vai à mão
    const toque = new Event('pointerdown', { bubbles: true });
    Object.defineProperty(toque, 'pointerType', { value: 'touch' });
    document.body.dispatchEvent(toque);
    expect(screen.getByRole('combobox')).toBeInTheDocument(); // começo de rolagem: fica
    fireEvent.click(document.body);
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
  });

  it('o "OK" do teclado (blur) fecha a lista mas não apaga o que foi digitado', async () => {
    const user = userEvent.setup();
    renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    await user.type(screen.getByRole('combobox'), 'ped');
    fireEvent.blur(screen.getByRole('combobox'));
    expect(screen.queryByRole('option')).not.toBeInTheDocument();
    expect(screen.getByRole('combobox')).toHaveValue('ped');
  });

  it('se a OS trava (ou chega o motivo de não trocar) com a troca aberta, ela fecha', async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    const tela = (p: Partial<Props>) => (
      <MemoryRouter><ClienteDaOrdem rotulo="Cliente *" value="c1" onChange={onChange} clients={clientes} {...p} /></MemoryRouter>
    );
    const { rerender } = render(tela({}));
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    expect(screen.getByRole('combobox')).toBeInTheDocument();
    rerender(tela({ semTroca: 'Para trocar o cliente, desagrupe antes.' }));
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(screen.queryByText(/por:/)).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados do cliente')).toBeInTheDocument();
    rerender(tela({ disabled: true }));
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados do cliente')).toBeInTheDocument();
  });

  it('OS nova (nada gravado): troca direto, sem perguntar', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ value: 'c1', ordemSalva: false, perdas: { embarcacao: 'Netuno II' } });
    await trocarPara(user, 'pedro', /Pedro Sem Cadastro/);
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
    expect(onChange).toHaveBeenCalledWith('c2', 'Pedro Sem Cadastro');
  });

  it('OS salva sem embarcação nem solicitante: troca direto', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ value: 'c1', ordemSalva: true, perdas: { embarcacao: null, solicitante: null } });
    await trocarPara(user, 'pedro', /Pedro Sem Cadastro/);
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
    expect(onChange).toHaveBeenCalledWith('c2', 'Pedro Sem Cadastro');
  });

  it('OS salva com embarcação e solicitante: pergunta dizendo o que sai; "Manter" não troca', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({
      value: 'c1', ordemSalva: true, documento: 'orçamento',
      perdas: { embarcacao: 'Iveco Daily', tipoDaEmbarcacao: 'Motorhome', solicitante: 'Pedro Marinheiro' },
    });
    await trocarPara(user, 'pedro', /Pedro Sem Cadastro/);
    const dialogo = await screen.findByRole('alertdialog');
    expect(within(dialogo).getByText('Trocar o cliente deste orçamento?')).toBeInTheDocument();
    // A unidade que sai pelo tipo dela (decisão 9): nunca "a embarcação Iveco Daily".
    expect(within(dialogo).getByText(
      'De João da Silva para Pedro Sem Cadastro. Saem: o motorhome Iveco Daily e o solicitante Pedro Marinheiro.',
    )).toBeInTheDocument();
    await user.click(within(dialogo).getByRole('button', { name: 'Manter o cliente atual' }));
    expect(onChange).not.toHaveBeenCalled();
    expect(screen.getByLabelText('Dados do cliente')).toHaveTextContent('João da Silva');
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('button', { name: /^Trocar cliente/ })).toHaveFocus());
  });

  it('… e "Trocar cliente" troca, anuncia e devolve o foco ao "Trocar" depois de o diálogo fechar', async () => {
    const user = userEvent.setup();
    // estado de verdade: o value muda e a ficha nova aparece
    function ComEstado() {
      const [v, setV] = useState('c1');
      return (
        <MemoryRouter>
          <ClienteDaOrdem rotulo="Cliente *" value={v} onChange={(id) => setV(id)} clients={clientes}
            ordemSalva perdas={{ embarcacao: 'Netuno II' }} />
        </MemoryRouter>
      );
    }
    render(<ComEstado />);
    await trocarPara(user, 'pedro', /Pedro Sem Cadastro/);
    const dialogo = await screen.findByRole('alertdialog');
    expect(within(dialogo).getByText('Trocar o cliente desta OS?')).toBeInTheDocument();
    await user.click(within(dialogo).getByRole('button', { name: 'Trocar cliente' }));
    expect(screen.getByLabelText('Dados do cliente')).toHaveTextContent('Pedro Sem Cadastro');
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Cliente trocado para Pedro Sem Cadastro.'));
    await waitFor(() => expect(screen.getByRole('button', { name: /^Trocar cliente/ })).toHaveFocus());
  });

  it('cadastrar um novo com perda pergunta ANTES de abrir o cadastro', async () => {
    const user = userEvent.setup();
    renderiza({ value: 'c1', ordemSalva: true, perdas: { embarcacao: 'Netuno II' } });
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    await user.type(screen.getByRole('combobox'), 'Fulano Novo');
    await user.click(await screen.findByRole('option', { name: /Cadastrar "Fulano Novo"/ }));
    const dialogo = await screen.findByRole('alertdialog');
    expect(within(dialogo).getByText(/para um cliente novo/)).toBeInTheDocument();
    expect(screen.queryByText(/novo Fulano Novo/)).not.toBeInTheDocument();
    await user.click(within(dialogo).getByRole('button', { name: 'Trocar cliente' }));
    expect(screen.getByRole('dialog')).toHaveTextContent('novo Fulano Novo');
  });

  it('escolher o próprio cliente atual não é troca', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ value: 'c1', ordemSalva: true, perdas: { embarcacao: 'Netuno II' } });
    await trocarPara(user, 'joão', /João da Silva/);
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
    expect(onChange).not.toHaveBeenCalled();
  });

  it('na busca da troca o atual vem marcado e fica fora dos últimos clientes', async () => {
    extras.recentes = ['c1', 'c2'];
    const user = userEvent.setup();
    renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /^Trocar cliente/ }));
    await user.click(screen.getByRole('combobox'));
    expect(screen.getByText('Últimos clientes')).toBeInTheDocument();
    expect(screen.getAllByRole('option')[0]).toHaveTextContent('Pedro Sem Cadastro');
    await user.type(screen.getByRole('combobox'), 'joão');
    expect(await screen.findByRole('option', { name: /João da Silva/ })).toHaveTextContent('Cliente atual');
  });

  it('a trava que chega com a confirmação aberta vale: confirmar não troca', async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    const tela = (p: Partial<Props>) => (
      <MemoryRouter>
        <ClienteDaOrdem rotulo="Cliente *" value="c1" onChange={onChange} clients={clientes}
          ordemSalva perdas={{ embarcacao: 'Netuno II' }} {...p} />
      </MemoryRouter>
    );
    const { rerender } = render(tela({}));
    await trocarPara(user, 'pedro', /Pedro Sem Cadastro/);
    const dialogo = await screen.findByRole('alertdialog');
    // a consulta do agrupamento responde agora: este orçamento reúne outros
    rerender(tela({ semTroca: 'Para trocar o cliente, desagrupe antes.' }));
    await user.click(within(dialogo).getByRole('button', { name: 'Trocar cliente' }));
    expect(onChange).not.toHaveBeenCalled();
  });

  it('ainda conferindo o agrupamento (semTroca = true): sem "Trocar" e sem mensagem', () => {
    renderiza({ value: 'c1', semTroca: true });
    expect(screen.queryByRole('button', { name: /^Trocar cliente/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/desagrupe/)).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados do cliente')).toBeInTheDocument();
  });

  it('orçamento que reúne outros: sem "Trocar", com o motivo', () => {
    renderiza({ value: 'c1', semTroca: 'Para trocar o cliente, desagrupe antes.' });
    expect(screen.queryByRole('button', { name: /^Trocar cliente/ })).not.toBeInTheDocument();
    expect(screen.getByText('Para trocar o cliente, desagrupe antes.')).toBeInTheDocument();
  });

  it('OS travada: sem busca e sem "Trocar", mas a ficha e o editar ficam', () => {
    renderiza({ value: 'c1', disabled: true });
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Trocar cliente/ })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados do cliente')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Editar cadastro/ })).toBeInTheDocument();
  });

  it('cadastrar novo (sem cliente ainda) leva o que foi digitado', async () => {
    const user = userEvent.setup();
    renderiza();
    await user.type(screen.getByRole('combobox'), 'Fulano Novo');
    await user.click(await screen.findByRole('option', { name: /Cadastrar "Fulano Novo"/ }));
    expect(screen.getByRole('dialog')).toHaveTextContent('novo Fulano Novo');
  });

  it('antes de digitar, os últimos clientes vêm no topo, sem repetir na lista de todos', async () => {
    extras.recentes = ['c2'];
    const user = userEvent.setup();
    const { onChange } = renderiza();
    await user.click(screen.getByRole('combobox'));
    expect(screen.getByText('Últimos clientes')).toBeInTheDocument();
    expect(screen.getAllByRole('option')[0]).toHaveTextContent('Pedro Sem Cadastro');
    expect(screen.getAllByRole('option', { name: /Pedro Sem Cadastro/ })).toHaveLength(1);
    await user.click(screen.getAllByRole('option')[0]);
    expect(onChange).toHaveBeenCalledWith('c2', 'Pedro Sem Cadastro');
  });
});

describe('ClienteDaOrdem — a ficha, com o rótulo em cima de cada dado', () => {
  /** O valor que está logo abaixo do rótulo (dt → dd). */
  const valorDe = (ficha: HTMLElement, rotulo: string) =>
    within(ficha).getByText(rotulo, { selector: 'dt' }).nextElementSibling as HTMLElement;

  it('cada dado com o seu rótulo', () => {
    renderiza({ value: 'c1' });
    const ficha = screen.getByLabelText('Dados do cliente');
    expect(valorDe(ficha, 'CPF')).toHaveTextContent('123.456.789-00');
    expect(within(valorDe(ficha, 'Telefone / WhatsApp')).getByRole('link', { name: '(47) 99999-1234' }))
      .toHaveAttribute('href', 'tel:+5547999991234');
    expect(within(ficha).getByRole('link', { name: /WhatsApp/ })).toHaveAttribute('href', 'https://wa.me/5547999991234');
    expect(within(valorDe(ficha, 'E-mail')).getByRole('link', { name: 'joao@exemplo.com' }))
      .toHaveAttribute('href', 'mailto:joao@exemplo.com');
    expect(within(ficha).queryByText(/falta/)).not.toBeInTheDocument();
    expect(valorDe(ficha, 'Endereço')).toHaveTextContent('Rua A, 10 — Centro, Itajaí/SC · CEP 88300-000');
    expect(valorDe(ficha, 'Observações do cadastro')).toHaveTextContent('Só aprova por e-mail');
    expect(within(ficha).getByRole('link', { name: /Histórico e financeiro/ })).toHaveAttribute('href', '/v2/clients/c1');
  });

  it('o que a nota exige aparece como "Não informado"; o opcional some', () => {
    renderiza({ value: 'c2' });
    const ficha = screen.getByLabelText('Dados do cliente');
    expect(valorDe(ficha, 'CPF')).toHaveTextContent('Não informado');
    expect(valorDe(ficha, 'Telefone / WhatsApp')).toHaveTextContent('Não informado');
    expect(valorDe(ficha, 'Endereço')).toHaveTextContent('Não informado');
    expect(within(ficha).queryByText('E-mail')).not.toBeInTheDocument();
    expect(within(ficha).getByText(/Sem telefone/)).toBeInTheDocument();
    expect(within(ficha).getByText('Para a nota fiscal falta: CPF/CNPJ, rua, bairro, cidade, UF, CEP.')).toBeInTheDocument();
  });

  it('empresa sem documento: o rótulo é CNPJ', () => {
    renderiza({ value: 'c3' });
    expect(within(screen.getByLabelText('Dados do cliente')).getByText('CNPJ', { selector: 'dt' })).toBeInTheDocument();
  });

  it('saldo em aberto com os vencidos destacados', () => {
    extras.saldo = { emAberto: 2406, vencidos: 1, valorVencido: 1650 };
    renderiza({ value: 'c1' });
    expect(valorDe(screen.getByLabelText('Dados do cliente'), 'Em aberto'))
      .toHaveTextContent(/R\$\s?2\.406,00 · 1 vencido \(R\$\s?1\.650,00\)/);
  });

  it('sem saldo (ou cargo que não vê o financeiro): nenhuma linha de valores', () => {
    renderiza({ value: 'c1' });
    expect(screen.queryByText('Em aberto')).not.toBeInTheDocument();
  });

  it('"Editar cadastro" abre o diálogo com o cliente da OS', async () => {
    const user = userEvent.setup();
    renderiza({ value: 'c1' });
    await user.click(screen.getByRole('button', { name: /Editar cadastro/ }));
    expect(screen.getByRole('dialog')).toHaveTextContent('editando João da Silva');
  });

  it('lista ainda carregando → carregada: a tela continua de pé e a ficha aparece', () => {
    const onChange = vi.fn();
    const { rerender } = render(
      <MemoryRouter><ClienteDaOrdem rotulo="Cliente *" value="c1" onChange={onChange} clients={undefined} /></MemoryRouter>,
    );
    expect(screen.queryByLabelText('Dados do cliente')).not.toBeInTheDocument();
    rerender(<MemoryRouter><ClienteDaOrdem rotulo="Cliente *" value="c1" onChange={onChange} clients={clientes} /></MemoryRouter>);
    expect(screen.getByLabelText('Dados do cliente')).toHaveTextContent('João da Silva');
  });
});

// "Cobrar juntas" (Fase 0, 28/10/2026): o caso da MP MOTOR HOMES pela tela (OS-00045 + OS-00046 =
// R$ 1.670 em aberto), as recusas que aparecem antes do botão e o envio só com as OS escolhidas.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CobrarJuntasDialog, type ClienteParaCobrar } from './CobrarJuntasDialog';

const { enviarMock, estado } = vi.hoisted(() => ({
  enviarMock: vi.fn(),
  estado: {
    pix: [] as Array<{ valor: number; data: string | null }>,
    settings: { pix_key: 'hbr@pix' } as Record<string, string>,
    hora: 14,
    // as cobranças abertas da conta r45 e da OS-00046 sem conta: nenhuma conta ganha cobrança nova
    cobrancas: undefined as Array<{ receivable_id: string | null; service_order_id: string | null }> | undefined,
  },
}));

vi.mock('@/hooks/use-cobrar-juntas', () => ({
  usePixEsperandoDoCliente: () => ({ data: estado.pix, isLoading: false, error: null }),
  useEnviarCobrarJuntas: () => ({ mutate: enviarMock, isPending: false }),
  useCobrancasFormais: () => ({ data: estado.cobrancas }),
  horaDoCobrarJuntas: () => estado.hora,
}));
vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: estado.settings }),
}));

const CONTAS = [
  { id: 's45', service_order_id: 'os45', numero_os: 'OS-00045', description: 'Sinal', status: 'paid', amount: 500, paid_amount: 500, balance_amount: 0, due_date: '2026-06-01' },
  { id: 'r45', service_order_id: 'os45', numero_os: 'OS-00045', description: 'Saldo', status: 'pending', amount: 1650, paid_amount: 0, balance_amount: 1650, due_date: '2026-07-22' },
  { id: 'r46', service_order_id: 'os46', numero_os: 'OS-00046', description: 'Saldo', status: 'partially_paid', amount: 50, paid_amount: 30, balance_amount: 20, due_date: '2026-07-22' },
  { id: 'r99', service_order_id: 'os99', numero_os: 'OS-00099', description: 'Saldo', status: 'pending', amount: 300, paid_amount: 0, balance_amount: 300, due_date: '2026-07-22' },
];
const MP: ClienteParaCobrar = { id: 'cli', name: 'MP MOTOR HOMES', whatsapp: '47999990000', generico: false, opt_out_whatsapp: false };

function renderizar(cliente: ClienteParaCobrar = MP, osIniciais?: string[], contas = CONTAS) {
  return render(<CobrarJuntasDialog open onOpenChange={() => {}} cliente={cliente} contas={contas} osIniciais={osIniciais} />);
}

beforeEach(() => {
  enviarMock.mockReset();
  estado.pix = [];
  estado.settings = { pix_key: 'hbr@pix' };
  estado.hora = 14;
  estado.cobrancas = [{ receivable_id: 'r45', service_order_id: 'os45' }, { receivable_id: null, service_order_id: 'os46' }];
});

describe('CobrarJuntasDialog', () => {
  it('abre com as OS escolhidas, mostra o saldo de cada uma e envia só as contas abertas delas', async () => {
    const user = userEvent.setup();
    renderizar(MP, ['os45', 'os46']);
    expect(screen.getByRole('checkbox', { name: 'Cobrar a OS-00045' })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: 'Cobrar a OS-00046' })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: 'Cobrar a OS-00099' })).not.toBeChecked();
    expect(screen.getByTestId('cobrar-juntas-total')).toHaveTextContent(/1\.670,00/);
    const msg = screen.getByLabelText('Mensagem') as HTMLTextAreaElement;
    expect(msg.value).toContain('OS: OS-00045, OS-00046');
    expect(msg.value).toMatch(/Em aberto: R\$\s1\.670,00/);
    expect(msg.value).not.toContain('Sinal');
    expect(screen.queryByRole('alert')).toBeNull();

    await user.click(screen.getByRole('button', { name: /Enviar ao cliente/ }));
    expect(enviarMock).toHaveBeenCalledTimes(1);
    const envio = enviarMock.mock.calls[0][0];
    // Cada conta com o saldo que a tela mostrou: o envio relê e recusa se mudou.
    expect([...envio.contas].sort((a: { id: string }, b: { id: string }) => a.id.localeCompare(b.id)))
      .toEqual([{ id: 'r45', saldo: 1650 }, { id: 'r46', saldo: 20 }]);
    expect(envio.servicoIds.sort()).toEqual(['os45', 'os46']);
    // O destino não vai da tela: o hook relê o cadastro.
    expect(envio).not.toHaveProperty('telefone');
  });

  it('o WhatsApp é o do cadastro, só exibido (não há campo para digitar outro número)', () => {
    renderizar(MP, ['os45', 'os46']);
    expect(screen.getByTestId('cobrar-juntas-fone')).toHaveTextContent('47999990000');
    expect(screen.getAllByRole('textbox')).toHaveLength(1); // só a mensagem
  });

  it('desmarcar uma OS refaz a mensagem e o total — e com uma OS só recusa, como a tool', async () => {
    const user = userEvent.setup();
    renderizar(MP, ['os45', 'os46']);
    await user.click(screen.getByRole('checkbox', { name: 'Cobrar a OS-00045' }));
    expect(screen.getByTestId('cobrar-juntas-total')).toHaveTextContent(/20,00/);
    const msg = screen.getByLabelText('Mensagem') as HTMLTextAreaElement;
    expect(msg.value).not.toContain('OS-00045');
    expect(screen.getByRole('alert')).toHaveTextContent('Cobrar juntas é para 2 OS ou mais');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });

  it('mais de 10 OS recusa, como a tool', () => {
    const muitas = Array.from({ length: 11 }, (_, i) => ({
      id: `c${i}`, service_order_id: `os${i}`, numero_os: `OS-001${String(i).padStart(2, '0')}`, description: 'Saldo',
      status: 'pending', amount: 100, paid_amount: 0, balance_amount: 100, due_date: '2026-07-22',
    }));
    renderizar(MP, undefined, muitas);
    expect(screen.getByRole('alert')).toHaveTextContent('Cobre no máximo 10 OS de uma vez');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });

  it('fora do horário de cobrança (22h em Brasília) trava, como o portão do assistente', () => {
    estado.hora = 22;
    renderizar(MP, ['os45', 'os46']);
    expect(screen.getByRole('alert')).toHaveTextContent('Fora do horário de cobrança (22h');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });

  it('contas que já têm cobrança: nenhum aviso de criação', () => {
    renderizar(MP, ['os45', 'os46']);
    expect(screen.queryByTestId('cobrar-juntas-cria-cobranca')).toBeNull();
  });

  it('sem cobrança nas contas (a MP): avisa antes do botão que a cobrança é criada junto (não trava)', () => {
    estado.cobrancas = [];
    renderizar(MP, ['os45', 'os46']);
    expect(screen.getByTestId('cobrar-juntas-cria-cobranca')).toHaveTextContent(
      '2 contas não têm cobrança registrada: elas são criadas junto com o envio (aparecem em Cobranças), e o lembrete não repete hoje.');
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeEnabled();
  });

  it('cadastro genérico: recusa aparece antes do botão e o envio fica travado', () => {
    renderizar({ ...MP, name: 'Cliente Final', generico: true });
    expect(screen.getByRole('alert')).toHaveTextContent('O cadastro Cliente Final é genérico, sem CPF/CNPJ');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });

  it('Pix esperando no Extrato, opt-out e piso travam com o texto do lembrete de cobrança', () => {
    estado.pix = [{ valor: 1670, data: '2026-10-27' }];
    const { unmount } = renderizar(MP, ['os45', 'os46']);
    expect(screen.getByRole('alert')).toHaveTextContent('entrada esperando no Extrato');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
    unmount();

    estado.pix = [];
    const r2 = renderizar({ ...MP, opt_out_whatsapp: true }, ['os45', 'os46']);
    expect(screen.getByRole('alert')).toHaveTextContent('opt-out');
    r2.unmount();

    estado.settings = { pix_key: 'hbr@pix', collection_min_amount: '5000' };
    renderizar(MP, ['os45', 'os46']);
    expect(screen.getByRole('alert')).toHaveTextContent('abaixo do piso');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });
});

// Fatura FAT-N (Fechar juntas F1, 20/11/2026): OS todas executadas → as contas viram a fatura no envio.
describe('CobrarJuntasDialog com fatura', () => {
  const FATURA = {
    id: 'f1', numero: 'FAT-00007', clientId: 'cli', status: 'open' as const, vencimento: '2026-07-22',
    total: 1670, recebido: 0, saldo: 1670, contas: 2, os: ['OS-00045', 'OS-00046'], criadaEm: '2026-11-20T12:00:00Z',
  };
  const renderizarComFatura = (contas: typeof CONTAS, osQueFaturam: string[], faturas = [FATURA]) =>
    render(<CobrarJuntasDialog open onOpenChange={() => {}} cliente={MP} contas={contas} osIniciais={['os45', 'os46']}
      osQueFaturam={osQueFaturam} faturas={faturas} />);

  it('sem fatura ainda: avisa que vira fatura, põe o número provisório e envia pedindo a fatura', async () => {
    const user = userEvent.setup();
    renderizarComFatura(CONTAS, ['os45', 'os46', 'os99'], []);
    expect(screen.getByTestId('cobrar-juntas-fatura')).toHaveTextContent('Ao enviar, estas contas viram uma fatura');
    const msg = screen.getByLabelText('Mensagem') as HTMLTextAreaElement;
    expect(msg.value).toContain('OS: OS-00045, OS-00046\nFatura: FAT-(número ao enviar)');
    await user.click(screen.getByRole('button', { name: /Enviar ao cliente/ }));
    expect(enviarMock.mock.calls[0][0]).toMatchObject({ comFatura: true });
  });

  it('as contas já são uma fatura aberta: a mensagem cita o número dela', () => {
    const contas = CONTAS.map((c) => (c.id === 'r45' || c.id === 'r46' ? { ...c, invoice_id: 'f1' } : c));
    renderizarComFatura(contas, ['os45', 'os46']);
    expect((screen.getByLabelText('Mensagem') as HTMLTextAreaElement).value).toContain('Fatura: FAT-00007');
    expect(screen.getByTestId('cobrar-juntas-fatura')).toHaveTextContent('Estas contas são a fatura FAT-00007.');
  });

  it('uma OS ainda em execução: sai como antes, sem fatura', async () => {
    const user = userEvent.setup();
    renderizarComFatura(CONTAS, ['os45'], []);
    expect(screen.getByTestId('cobrar-juntas-fatura')).toHaveTextContent('Sem fatura: OS-00046 ainda não terminou');
    expect((screen.getByLabelText('Mensagem') as HTMLTextAreaElement).value).not.toContain('Fatura:');
    await user.click(screen.getByRole('button', { name: /Enviar ao cliente/ }));
    expect(enviarMock.mock.calls[0][0]).not.toHaveProperty('comFatura');
  });

  it('parte das contas noutra fatura: trava antes do botão', () => {
    const contas = CONTAS.map((c) => (c.id === 'r45' ? { ...c, invoice_id: 'f1' } : c));
    renderizarComFatura(contas, ['os45', 'os46']);
    expect(screen.getByRole('alert')).toHaveTextContent('Parte destas contas já está na fatura FAT-00007');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });
});

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
    cobrancas: 2 as number | undefined,
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
  estado.cobrancas = 2;
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

  it('sem cobrança formal nas contas: avisa antes do botão que o envio não fica registrado (não trava)', () => {
    estado.cobrancas = 0;
    renderizar(MP, ['os45', 'os46']);
    expect(screen.getByTestId('cobrar-juntas-sem-cobranca')).toHaveTextContent('o envio não fica registrado');
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
    expect(screen.getByRole('alert')).toHaveTextContent('Pix esperando no Extrato');
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

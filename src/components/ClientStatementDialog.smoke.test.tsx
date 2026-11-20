// "Enviar extrato" com as travas do Cobrar juntas (dono, 20/11/2026: "Sim, as mesmas travas"): a tela
// mostra o motivo quando barra, o destino é o WhatsApp do cadastro (sem campo para digitar) e o envio
// leva as contas com saldo para o hook reler.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ClientStatementDialog } from './ClientStatementDialog';
import type { ClienteParaCobrar } from '@/components/client/CobrarJuntasDialog';

const { enviarMock, estado } = vi.hoisted(() => ({
  enviarMock: vi.fn(),
  estado: {
    pix: [] as Array<{ valor: number; data: string | null }>,
    settings: { pix_key: 'hbr@pix' } as Record<string, string>,
    hora: 14,
  },
}));

vi.mock('@/hooks/use-cobrar-juntas', () => ({
  usePixEsperandoDoCliente: () => ({ data: estado.pix, isLoading: false, error: null }),
  useEnviarExtrato: () => ({ mutate: enviarMock, isPending: false }),
  horaDoCobrarJuntas: () => estado.hora,
}));
vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: estado.settings }),
}));

const CONTAS = [
  { id: 's45', service_order_id: 'os45', numero_os: 'OS-00045', description: 'Sinal', status: 'paid', amount: 500, paid_amount: 500, balance_amount: 0, due_date: '2026-06-01' },
  { id: 'r45', service_order_id: 'os45', numero_os: 'OS-00045', description: 'Saldo', status: 'pending', amount: 1650, paid_amount: 0, balance_amount: 1650, due_date: '2026-07-22' },
  { id: 'r46', service_order_id: 'os46', numero_os: 'OS-00046', description: 'Saldo', status: 'partially_paid', amount: 50, paid_amount: 30, balance_amount: 20, due_date: '2026-07-22' },
];
const MP: ClienteParaCobrar = { id: 'cli', name: 'MP MOTOR HOMES', whatsapp: '47999990000', generico: false, opt_out_whatsapp: false };

function renderizar(cliente: ClienteParaCobrar = MP, items = CONTAS) {
  return render(<ClientStatementDialog open onOpenChange={() => {}} cliente={cliente} items={items} />);
}

beforeEach(() => {
  enviarMock.mockReset();
  estado.pix = [];
  estado.settings = { pix_key: 'hbr@pix' };
  estado.hora = 14;
});

describe('ClientStatementDialog (Enviar extrato)', () => {
  it('sem trava: mostra o extrato, o WhatsApp do cadastro e envia as contas com saldo', async () => {
    const user = userEvent.setup();
    renderizar();
    expect(screen.getByTestId('enviar-extrato-fone')).toHaveTextContent('47999990000');
    expect(screen.getAllByRole('textbox')).toHaveLength(1); // só o extrato: o número não se digita
    const msg = screen.getByLabelText('Extrato') as HTMLTextAreaElement;
    expect(msg.value).toContain('Extrato financeiro');
    expect(msg.value).toMatch(/Em aberto: R\$\s1\.670,00/);
    expect(screen.queryByRole('alert')).toBeNull();

    await user.click(screen.getByRole('button', { name: /Enviar ao cliente/ }));
    expect(enviarMock).toHaveBeenCalledTimes(1);
    const envio = enviarMock.mock.calls[0][0];
    expect(envio.cliente.id).toBe('cli');
    expect(envio.contas).toEqual([{ id: 'r45', saldo: 1650 }, { id: 'r46', saldo: 20 }]);
    expect(envio).not.toHaveProperty('telefone');
  });

  it('cadastro genérico: o motivo aparece e o envio fica travado', () => {
    renderizar({ ...MP, name: 'Cliente Final', generico: true });
    expect(screen.getByRole('alert')).toHaveTextContent('O cadastro Cliente Final é genérico, sem CPF/CNPJ');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });

  it('Pix esperando no Extrato, opt-out, piso, sem telefone e fora do horário travam com o mesmo texto do Cobrar juntas', () => {
    estado.pix = [{ valor: 1670, data: '2026-10-27' }];
    let r = renderizar();
    expect(screen.getByRole('alert')).toHaveTextContent('Pix esperando no Extrato');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
    r.unmount();
    estado.pix = [];

    r = renderizar({ ...MP, opt_out_whatsapp: true });
    expect(screen.getByRole('alert')).toHaveTextContent('opt-out');
    r.unmount();

    r = renderizar({ ...MP, whatsapp: null, phone: null });
    expect(screen.getByRole('alert')).toHaveTextContent('Sem telefone');
    expect(screen.getByTestId('enviar-extrato-fone')).toHaveTextContent('Sem telefone no cadastro');
    r.unmount();

    estado.hora = 22;
    r = renderizar();
    expect(screen.getByRole('alert')).toHaveTextContent('Fora do horário de cobrança (22h');
    r.unmount();
    estado.hora = 14;

    estado.settings = { pix_key: 'hbr@pix', collection_min_amount: '5000' };
    renderizar();
    expect(screen.getByRole('alert')).toHaveTextContent('abaixo do piso');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });

  it('tudo pago: não há o que cobrar (trava)', () => {
    renderizar(MP, [CONTAS[0]]);
    expect(screen.getByRole('alert')).toHaveTextContent('Este cliente não tem saldo em aberto: não há o que cobrar.');
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeDisabled();
  });

  it('uma conta só com saldo NÃO trava (o extrato não tem contagem de OS)', () => {
    renderizar(MP, [CONTAS[1]]);
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.getByRole('button', { name: /Enviar ao cliente/ })).toBeEnabled();
  });
});

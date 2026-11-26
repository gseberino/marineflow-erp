// "Cobrar em lote" (dono, 26/11/2026: "1. A"): uma mensagem por cliente com a conferência da ficha — a lista de quem
// recebe, quem fica de fora e por quê, a mensagem de cada um, a confirmação, e o envio cliente a cliente pelas travas.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BulkBillingReminderDialog } from './BulkBillingReminderDialog';
import { intervaloDoLote } from '@/lib/cobrar-em-lote';

const { estado, enviarMock } = vi.hoisted(() => ({
  estado: {
    hora: 14,
    contas: [] as Array<Record<string, unknown>>,
    clientes: [] as Array<Record<string, unknown>>,
    erroContas: null as null | { message: string },
    pix: [] as Array<{ clienteId: string; valor: number; data: string | null }>,
    cobradosHoje: new Map<string, string>(),
    erroConfig: false,
  },
  enviarMock: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => {
  const consulta = (tabela: string) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const q: any = {};
    for (const m of ['select', 'not', 'order', 'limit', 'in', 'eq', 'range']) q[m] = () => q;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    q.then = (ok: any, erro: any) => Promise.resolve(
      tabela === 'receivables'
        ? { data: estado.erroContas ? null : estado.contas, error: estado.erroContas }
        : { data: estado.clientes, error: null },
    ).then(ok, erro);
    return q;
  };
  return { supabase: { from: (t: string) => consulta(t) } };
});
vi.mock('@/hooks/use-cobrar-juntas', () => ({
  enviarCobrancaDoCliente: enviarMock,
  horaDoCobrarJuntas: () => estado.hora,
  // como o de verdade: relê tudo de ['receivables'] (inclusive a lista do lote aberta)
  invalidarDepoisDoLote: (qc: { invalidateQueries: (f: unknown) => unknown }) => qc.invalidateQueries({ queryKey: ['receivables'] }),
  lerCobradosHoje: async () => estado.cobradosHoje,
}));
vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => (estado.erroConfig
    ? { data: undefined, isSuccess: false, isError: true, isLoading: false }
    : { data: { pix_key: 'hbr@pix', collection_min_amount: '200' }, isSuccess: true, isError: false, isLoading: false }),
}));
vi.mock('../../supabase/functions/_shared/receivables/dinheiro-esperando', () => ({
  lerDinheiroEsperando: async () => estado.pix,
}));

const conta = (id: string, client_id: string, extra: Record<string, unknown> = {}) => ({
  id, client_id, description: `Saldo ${id}`, status: 'pending', amount: 1000, paid_amount: 0, balance_amount: 1000,
  due_date: '2026-01-10', service_order_id: null, service_orders: null, ...extra,
});
const cliente = (id: string, name: string, extra: Record<string, unknown> = {}) => ({
  id, name, generico: false, opt_out_whatsapp: false, whatsapp: `(47) 99999-000${id}`, phone: null, ...extra,
});

function abrir() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <BulkBillingReminderDialog open onOpenChange={() => {}} initialFilter="overdue" />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  intervaloDoLote.ms = 0;
  estado.hora = 14;
  estado.erroContas = null;
  estado.pix = [];
  estado.cobradosHoje = new Map();
  estado.erroConfig = false;
  estado.contas = [conta('a1', '1', { amount: 3000, balance_amount: 3000 }), conta('a2', '1', { due_date: '2099-01-01' }), conta('b1', '2'), conta('c1', '3')];
  estado.clientes = [cliente('1', 'Bertoldi'), cliente('2', 'João Hang'), cliente('3', 'Nelson', { opt_out_whatsapp: true })];
  enviarMock.mockReset();
  enviarMock.mockResolvedValue({ deduplicado: false, aviso: null, cobrancasRegistradas: 1, cobrancasCriadas: 0 });
});

describe('BulkBillingReminderDialog (Cobrar em lote)', () => {
  it('lista um item por cliente, mostra quem fica de fora e por quê, e a mensagem de cada um', async () => {
    const user = userEvent.setup();
    abrir();
    const itens = await screen.findAllByTestId('lote-item');
    expect(itens).toHaveLength(2);
    expect(itens[0]).toHaveTextContent('Bertoldi');
    expect(itens[0]).toHaveTextContent(/em aberto R\$\s4\.000,00 · vencido R\$\s3\.000,00/);
    expect(screen.getByTestId('lote-fora')).toHaveTextContent('Nelson: Este cliente pediu para não receber mensagens no WhatsApp (opt-out)');
    await user.click(within(itens[0]).getByRole('button', { name: /Mensagem/ }));
    expect(within(itens[0]).getByText(/Cobrança — HBR/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Enviar a 2 clientes/ })).toBeEnabled();
  });

  it('confirma antes, envia cliente a cliente pela cobrança do cliente (o que foi desmarcado não vai) e mostra o resultado', async () => {
    const user = userEvent.setup();
    abrir();
    const itens = await screen.findAllByTestId('lote-item');
    await user.click(within(itens[1]).getByRole('checkbox'));
    await user.click(screen.getByRole('button', { name: /Enviar a 1 cliente/ }));
    expect(enviarMock).not.toHaveBeenCalled(); // primeiro a confirmação
    await user.click(screen.getByRole('button', { name: /Confirmar: enviar 1 mensagem/ }));
    await waitFor(() => expect(screen.getByTestId('lote-resultado')).toHaveTextContent('Enviadas: 1'));
    expect(enviarMock).toHaveBeenCalledTimes(1);
    const envio = enviarMock.mock.calls[0][0];
    expect(envio.cliente).toEqual({ id: '1', name: 'Bertoldi', generico: false });
    expect(envio.contas).toEqual([{ id: 'a1', saldo: 3000 }, { id: 'a2', saldo: 1000 }]);
    expect(envio.mensagem.startsWith('📋 *Cobrança — HBR*\nCliente: Bertoldi')).toBe(true);
  });

  it('a recusa no envio (as travas relidas) aparece na linha e não se repete', async () => {
    const user = userEvent.setup();
    enviarMock.mockRejectedValueOnce(new Error('Este cliente tem entrada esperando no Extrato (R$ 3.000,00 de 25/11).'));
    abrir();
    await screen.findAllByTestId('lote-item');
    await user.click(screen.getByRole('button', { name: /Enviar a 2 clientes/ }));
    await user.click(screen.getByRole('button', { name: /Confirmar: enviar 2 mensagens/ }));
    await waitFor(() => expect(screen.getByTestId('lote-resultado')).toHaveTextContent('Enviadas: 1 · já tinham saído hoje: 0 · não saíram: 1'));
    expect(screen.getByText(/Não saiu: Este cliente tem entrada esperando no Extrato/)).toBeInTheDocument();
    expect(enviarMock).toHaveBeenCalledTimes(2);
  });

  it('fora do horário: o motivo aparece e o envio fica travado', async () => {
    estado.hora = 21;
    abrir();
    await screen.findAllByTestId('lote-item');
    expect(screen.getByRole('alert')).toHaveTextContent('Fora do horário de cobrança (21h');
    expect(screen.getByRole('button', { name: /Enviar a 2 clientes/ })).toBeDisabled();
  });

  it('leitura que falha: nada para enviar, com o motivo', async () => {
    estado.erroContas = { message: 'permission denied' };
    abrir();
    expect(await screen.findByRole('alert')).toHaveTextContent('Não consegui ler as contas em aberto: permission denied Nada foi enviado');
    expect(screen.queryByRole('button', { name: /Enviar a/ })).toBeNull();
  });

  it('já cobrado hoje e entrada esperando no Extrato ficam de fora', async () => {
    estado.cobradosHoje = new Map([['1', '2026-11-26T13:15:00Z']]);
    estado.pix = [{ clienteId: '2', valor: 1000, data: '2026-11-20' }];
    abrir();
    expect(await screen.findByTestId('lote-vazio')).toBeInTheDocument();
    const fora = screen.getByTestId('lote-fora');
    expect(fora).toHaveTextContent('Bertoldi: Já recebeu cobrança hoje (às 10h15).');
    expect(fora).toHaveTextContent('João Hang: Este cliente tem entrada esperando no Extrato');
  });
});

// Revisão de 26/11/2026: o que muda entre a leitura e o envio, a releitura depois do envio, as configurações e a saída da tela.
describe('BulkBillingReminderDialog — consertos da revisão', () => {
  it('cobrado por outro caminho DEPOIS da leitura: aquele não recebe; o outro sim', async () => {
    const user = userEvent.setup();
    abrir();
    await screen.findAllByTestId('lote-item');
    estado.cobradosHoje = new Map([['1', '2026-11-26T13:05:00Z']]); // o assistente cobrou o Bertoldi às 10h05
    await user.click(screen.getByRole('button', { name: /Enviar a 2 clientes/ }));
    await user.click(screen.getByRole('button', { name: /Confirmar: enviar 2 mensagens/ }));
    await waitFor(() => expect(screen.getByTestId('lote-resultado')).toHaveTextContent('Enviadas: 1 · já tinham saído hoje: 0 · não saíram: 1'));
    expect(enviarMock).toHaveBeenCalledTimes(1);
    expect(enviarMock.mock.calls[0][0].cliente.id).toBe('2');
    expect(screen.getByText((_, el) => el?.tagName === 'SPAN' && (el.textContent ?? '').includes('Já recebeu cobrança hoje (às 10h05), depois que a lista foi aberta'))).toBeInTheDocument();
  });

  it('depois do envio a releitura não apaga o resultado de cada um', async () => {
    const user = userEvent.setup();
    enviarMock.mockImplementation(async (e: { cliente: { id: string } }) => {
      estado.cobradosHoje = new Map([...estado.cobradosHoje, [e.cliente.id, '2026-11-26T13:00:00Z']]);
      return { deduplicado: false, aviso: null, cobrancasRegistradas: 1, cobrancasCriadas: 0 };
    });
    abrir();
    await screen.findAllByTestId('lote-item');
    await user.click(screen.getByRole('button', { name: /Enviar a 2 clientes/ }));
    await user.click(screen.getByRole('button', { name: /Confirmar: enviar 2 mensagens/ }));
    await waitFor(() => expect(screen.getByTestId('lote-resultado')).toHaveTextContent('Enviadas: 2'));
    await new Promise((r) => setTimeout(r, 50));
    expect(screen.getAllByText('Enviada.')).toHaveLength(2);
    expect(screen.queryByTestId('lote-vazio')).toBeNull();
  });

  it('configurações que não leram: o motivo aparece e nada sai', async () => {
    estado.erroConfig = true;
    abrir();
    await screen.findAllByTestId('lote-item');
    expect(screen.getByText(/Não consegui ler as configurações/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Enviar a 2 clientes/ })).toBeDisabled();
  });

  it('a tela saiu no meio do envio: o laço para depois do cliente da vez', async () => {
    const user = userEvent.setup();
    intervaloDoLote.ms = 300;
    const r = abrir();
    await screen.findAllByTestId('lote-item');
    await user.click(screen.getByRole('button', { name: /Enviar a 2 clientes/ }));
    await user.click(screen.getByRole('button', { name: /Confirmar: enviar 2 mensagens/ }));
    await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(1));
    r.unmount();
    await new Promise((res) => setTimeout(res, 500));
    expect(enviarMock).toHaveBeenCalledTimes(1);
  });
});

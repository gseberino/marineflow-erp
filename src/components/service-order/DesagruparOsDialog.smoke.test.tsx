// Desagrupar OS (28/10/2026): o aviso de que as edições da agrupada não voltam, a chamada ao banco com o hook
// de verdade (só o cliente do Supabase é de mentira) e o caminho de volta à primeira original.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DesagruparOsDialog } from './DesagruparOsDialog';

const { rpcMock, navigateMock, toastMock } = vi.hoisted(() => ({
  rpcMock: vi.fn(),
  navigateMock: vi.fn(),
  toastMock: { success: vi.fn(), error: vi.fn() },
}));

vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: rpcMock } }));
vi.mock('sonner', () => ({ toast: toastMock }));
vi.mock('react-router-dom', async (original) => ({
  ...(await original<typeof import('react-router-dom')>()),
  useNavigate: () => navigateMock,
}));

const ORIGENS = [
  { id: 'a', numero: 'OS-00100' },
  { id: 'b', numero: 'OS-00128' },
];

function renderizar(origens = ORIGENS) {
  const onFechar = vi.fn();
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <DesagruparOsDialog aberto onFechar={onFechar} agrupadoId="nova-1" agrupadoNumero="OS-00140" origens={origens} />
    </QueryClientProvider>,
  );
  return { onFechar };
}

const botao = () => screen.getByRole('button', { name: 'Desagrupar' });

beforeEach(() => {
  rpcMock.mockReset();
  navigateMock.mockReset();
  toastMock.success.mockReset();
  toastMock.error.mockReset();
});

describe('DesagruparOsDialog', () => {
  it('diz o que acontece, inclusive que o dinheiro volta e as edições da agrupada não', () => {
    renderizar();
    expect(screen.getByText(/OS-00100, OS-00128 voltam a valer como estavam antes do agrupamento, com o link antigo/)).toBeInTheDocument();
    expect(screen.getByText(/Sinais, contas a receber, cobranças, tarefas e pedidos de compra que vieram delas voltam para cada uma/)).toBeInTheDocument();
    expect(screen.getByText(/OS-00140 fica cancelada como histórico e o link dela para de funcionar/)).toBeInTheDocument();
    expect(screen.getByText(/As alterações feitas na OS-00140 não voltam/)).toBeInTheDocument();
    expect(screen.getByText(/não começou a ser executada/)).toBeInTheDocument();
  });

  it('uma original só: no singular', () => {
    renderizar([{ id: 'a', numero: 'OS-00100' }]);
    expect(screen.getByText(/OS-00100 volta a valer como estava antes do agrupamento/)).toBeInTheDocument();
  });

  it('chama o banco só com a agrupada, uma vez mesmo com clique duplo', async () => {
    rpcMock.mockReturnValue(new Promise(() => {}));
    renderizar();
    await userEvent.dblClick(botao());
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock).toHaveBeenCalledWith('desagrupar_os', { p_agrupado: 'nova-1' });
    expect(botao()).toBeDisabled();
  });

  it('no sucesso avisa, fecha e abre a primeira original', async () => {
    rpcMock.mockResolvedValue({
      data: {
        agrupado_id: 'nova-1', agrupado: 'OS-00140', origens: ['OS-00100', 'OS-00128'], origens_ids: ['a', 'b'],
        registros_devolvidos: 6, envios_cancelados: 0, envios_reativados: 0,
      },
      error: null,
    });
    const { onFechar } = renderizar();
    await userEvent.click(botao());
    await vi.waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/v2/service-orders/a'));
    expect(toastMock.success).toHaveBeenCalledWith('Desagrupado: OS-00100, OS-00128 voltaram a valer; OS-00140 foi cancelada');
    expect(onFechar).toHaveBeenCalled();
  });

  it('mostra a recusa do banco como ela veio', async () => {
    const frase = 'OS-00140 já começou a ser executada (hora apontada): não dá para desagrupar.';
    rpcMock.mockResolvedValue({ data: null, error: { message: frase, code: '22023' } });
    const { onFechar } = renderizar();
    await userEvent.click(botao());
    expect(await screen.findByRole('alert')).toHaveTextContent(frase);
    expect(toastMock.error).toHaveBeenCalledWith(frase);
    expect(navigateMock).not.toHaveBeenCalled();
    expect(onFechar).not.toHaveBeenCalled();
    expect(botao()).toBeEnabled();
  });
});

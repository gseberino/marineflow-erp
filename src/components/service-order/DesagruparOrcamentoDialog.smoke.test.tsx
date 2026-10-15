// Desagrupar orçamentos (15/10/2026): o aviso de que as edições do agrupado não voltam, a chamada ao banco
// com o hook de verdade (só o cliente do Supabase é de mentira) e o caminho de volta ao primeiro original.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DesagruparOrcamentoDialog } from './DesagruparOrcamentoDialog';

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
  { id: 'a', numero: 'ORÇ-00001' },
  { id: 'b', numero: 'ORÇ-00002' },
];

function renderizar() {
  const onFechar = vi.fn();
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <DesagruparOrcamentoDialog aberto onFechar={onFechar} agrupadoId="novo-1" agrupadoNumero="ORÇ-00100" origens={ORIGENS} />
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

describe('DesagruparOrcamentoDialog', () => {
  it('diz o que acontece, inclusive que as edições do agrupado não voltam', () => {
    renderizar();
    expect(screen.getByText(/ORÇ-00001, ORÇ-00002 voltam a valer exatamente como estavam, com o link antigo/)).toBeInTheDocument();
    expect(screen.getByText(/ORÇ-00100 fica cancelado como histórico e o link dele para de funcionar/)).toBeInTheDocument();
    expect(screen.getByText(/As alterações feitas no ORÇ-00100 não voltam/)).toBeInTheDocument();
  });

  it('chama o banco só com o agrupado, uma vez mesmo com clique duplo', async () => {
    rpcMock.mockReturnValue(new Promise(() => {}));
    renderizar();
    await userEvent.dblClick(botao());
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock).toHaveBeenCalledWith('desagrupar_orcamentos', { p_agrupado: 'novo-1' });
    expect(botao()).toBeDisabled();
  });

  it('no sucesso avisa, fecha e abre o primeiro original', async () => {
    rpcMock.mockResolvedValue({
      data: { agrupado_id: 'novo-1', agrupado: 'ORÇ-00100', origens: ['ORÇ-00001', 'ORÇ-00002'], origens_ids: ['a', 'b'], envios_cancelados: 0 },
      error: null,
    });
    const { onFechar } = renderizar();
    await userEvent.click(botao());
    await vi.waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/v2/service-orders/a'));
    expect(toastMock.success).toHaveBeenCalledWith('Desagrupado: ORÇ-00001, ORÇ-00002 voltaram a valer; ORÇ-00100 foi cancelado');
    expect(onFechar).toHaveBeenCalled();
  });

  it('mostra a recusa do banco como ela veio', async () => {
    const frase = 'ORÇ-00100 já foi assinado pelo cliente: não dá para desagrupar.';
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

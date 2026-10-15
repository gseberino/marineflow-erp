// Agrupar orçamentos (15/10/2026): da escolha na janela até a chamada ao banco, com o hook de verdade
// (só a lista de candidatos e o cliente do Supabase são de mentira).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { CandidatoAgrupar } from '@/lib/agrupar-orcamentos';
import { AgruparOrcamentosDialog } from './AgruparOrcamentosDialog';

const { rpcMock, navigateMock, toastMock, estado } = vi.hoisted(() => ({
  rpcMock: vi.fn(),
  navigateMock: vi.fn(),
  toastMock: { success: vi.fn(), error: vi.fn() },
  estado: { candidatos: [] as unknown[] },
}));

vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: rpcMock } }));
vi.mock('sonner', () => ({ toast: toastMock }));
vi.mock('react-router-dom', async (original) => ({
  ...(await original<typeof import('react-router-dom')>()),
  useNavigate: () => navigateMock,
}));
vi.mock('@/hooks/use-agrupar-orcamentos', async (original) => ({
  ...(await original<typeof import('@/hooks/use-agrupar-orcamentos')>()),
  useCandidatosParaAgrupar: () => ({ data: estado.candidatos, isLoading: false, error: null }),
}));

function orc(over: Partial<CandidatoAgrupar>): CandidatoAgrupar {
  return {
    id: 'x', service_order_number: 'ORÇ-0000X', status: 'draft', quote_status: 'draft', grand_total: 0,
    created_at: '2026-10-01T12:00:00+00:00', client_id: 'cli-1', vessel_id: 'ves-1', signed_at: null,
    converted_to_os_at: null, merged_into_id: null, discount_amount: 0, tax_amount: 0, commission_rate: 0,
    commissioned_user_id: null, commissioned_person: null, payment_condition_preset_id: null,
    payment_conditions: null, travel_cost_total: 0, problem_description: null,
    ...over,
  };
}

const A = orc({ id: 'a', service_order_number: 'ORÇ-00001', grand_total: 0.1, created_at: '2026-10-01T12:00:00+00:00', problem_description: 'Troca do inversor' });
const B = orc({ id: 'b', service_order_number: 'ORÇ-00002', grand_total: 0.2, created_at: '2026-10-02T12:00:00+00:00' });
const C = orc({ id: 'c', service_order_number: 'ORÇ-00003', grand_total: 50, created_at: '2026-10-03T12:00:00+00:00' });
const REJEITADO = orc({ id: 'r', service_order_number: 'ORÇ-00004', quote_status: 'rejected', grand_total: 70, created_at: '2026-10-04T12:00:00+00:00' });

function renderizar(preSelecionados: string[], principalSugerido?: string) {
  const onFechar = vi.fn();
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <AgruparOrcamentosDialog
        aberto
        onFechar={onFechar}
        clientId="cli-1"
        vesselId="ves-1"
        preSelecionados={preSelecionados}
        principalSugerido={principalSugerido}
      />
    </QueryClientProvider>,
  );
  return { onFechar };
}

const caixa = (numero: string) => screen.getByRole('checkbox', { name: `Incluir ${numero}` });
const botaoAgrupar = () => screen.getByRole('button', { name: /^Agrupar \d+ orçamentos?$/ });

beforeEach(() => {
  rpcMock.mockReset();
  navigateMock.mockReset();
  toastMock.success.mockReset();
  toastMock.error.mockReset();
  estado.candidatos = [A, B, C, REJEITADO];
});

describe('AgruparOrcamentosDialog', () => {
  it('abre com os pré-selecionados marcados e o Reprovado desabilitado, com o motivo', () => {
    renderizar(['a', 'b', 'r']);
    expect(caixa('ORÇ-00001')).toBeChecked();
    expect(caixa('ORÇ-00002')).toBeChecked();
    expect(caixa('ORÇ-00003')).not.toBeChecked();
    expect(caixa('ORÇ-00004')).toBeDisabled();
    expect(caixa('ORÇ-00004')).not.toBeChecked();
    expect(within(caixa('ORÇ-00004').closest('li') as HTMLElement).getByText('Reprovado')).toBeInTheDocument();
    // a rejeitada não entra na conta: 2 escolhidos, R$ 0,30
    expect(botaoAgrupar()).toHaveTextContent('Agrupar 2 orçamentos');
    expect(screen.getByText(/Total previsto: R\$\s0,30/)).toBeInTheDocument();
    expect(screen.getByText(/link antigo deles para de funcionar/)).toBeInTheDocument();
    expect(screen.getByText(/comissão é recalculada sobre o total novo/)).toBeInTheDocument();
  });

  it('com 1 orçamento o botão fica desabilitado', async () => {
    renderizar(['a', 'b']);
    expect(botaoAgrupar()).toBeEnabled();
    await userEvent.click(caixa('ORÇ-00002'));
    expect(botaoAgrupar()).toHaveTextContent('Agrupar 1 orçamento');
    expect(botaoAgrupar()).toBeDisabled();
    await userEvent.click(botaoAgrupar());
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it('chama o banco com exatamente os escolhidos, o principal e a soma vista na tela', async () => {
    rpcMock.mockReturnValue(new Promise(() => {}));
    renderizar(['a'], 'b');
    await userEvent.click(caixa('ORÇ-00002'));
    // o principal sugerido pela tela de origem vem marcado; o dono troca para o outro
    expect(screen.getByRole('radio', { name: 'ORÇ-00002' })).toBeChecked();
    await userEvent.click(screen.getByRole('radio', { name: 'ORÇ-00001' }));
    await userEvent.click(botaoAgrupar());
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock).toHaveBeenCalledWith('agrupar_orcamentos', { p_orcamentos: ['a', 'b'], p_base: 'a', p_total_esperado: 0.3 });
    expect(Object.keys(rpcMock.mock.calls[0]![1] as object).sort()).toEqual(['p_base', 'p_orcamentos', 'p_total_esperado']);
  });

  it('sem principal sugerido, o principal é o mais antigo', async () => {
    rpcMock.mockReturnValue(new Promise(() => {}));
    renderizar(['c', 'b']);
    expect(screen.getByRole('radio', { name: 'ORÇ-00002' })).toBeChecked();
    await userEvent.click(botaoAgrupar());
    expect(rpcMock).toHaveBeenCalledWith('agrupar_orcamentos', { p_orcamentos: ['b', 'c'], p_base: 'b', p_total_esperado: 50.2 });
  });

  it('dois cliques seguidos chamam o banco uma vez só', async () => {
    rpcMock.mockReturnValue(new Promise(() => {}));
    renderizar(['a', 'b']);
    await userEvent.dblClick(botaoAgrupar());
    await userEvent.click(botaoAgrupar());
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(botaoAgrupar()).toBeDisabled();
  });

  it('mostra a recusa do banco como ela veio', async () => {
    const frase = 'ORÇ-00002 está ligado a: conta a receber/sinal. Resolva isso antes de agrupar.';
    rpcMock.mockResolvedValue({ data: null, error: { message: frase, code: '22023' } });
    const { onFechar } = renderizar(['a', 'b']);
    await userEvent.click(botaoAgrupar());
    expect(await screen.findByRole('alert')).toHaveTextContent(frase);
    expect(toastMock.error).toHaveBeenCalledWith(frase);
    expect(navigateMock).not.toHaveBeenCalled();
    expect(onFechar).not.toHaveBeenCalled();
    // destrava para tentar de novo
    expect(botaoAgrupar()).toBeEnabled();
  });

  it('no sucesso avisa, fecha e abre o orçamento novo', async () => {
    rpcMock.mockResolvedValue({
      data: {
        service_order_id: 'novo-1', numero: 'ORÇ-00100', agrupamento_id: 'g-1', origens: ['ORÇ-00001', 'ORÇ-00002'],
        principal: 'ORÇ-00001', servicos: 2, pecas: 3, envios_cancelados: 0, total_geral: 0.3, comissao: 0,
      },
      error: null,
    });
    const { onFechar } = renderizar(['a', 'b']);
    await userEvent.click(botaoAgrupar());
    await vi.waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/v2/service-orders/novo-1'));
    expect(toastMock.success).toHaveBeenCalledWith('Criado ORÇ-00100: reúne ORÇ-00001, ORÇ-00002');
    expect(onFechar).toHaveBeenCalled();
  });

  it('avisa em destaque quando as comissões são diferentes', () => {
    estado.candidatos = [A, { ...B, commission_rate: 5, commissioned_person: 'Felipe' }];
    renderizar(['a', 'b']);
    const avisos = screen.getByRole('list', { name: 'Diferenças entre os orçamentos' });
    expect(within(avisos).getByText(/^Comissões diferentes: ORÇ-00001 sem comissão; ORÇ-00002 5% \(Felipe\)/)).toBeInTheDocument();
  });
});

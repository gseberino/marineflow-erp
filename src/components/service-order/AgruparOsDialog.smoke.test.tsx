// Agrupar OS (28/10/2026): da escolha na janela até a chamada ao banco, com o hook de verdade (só a lista
// de candidatas, a prévia do que vai junto e o cliente do Supabase são de mentira).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { CandidataOs } from '@/lib/agrupar-os';
import { AgruparOsDialog } from './AgruparOsDialog';

const { rpcMock, navigateMock, toastMock, estado } = vi.hoisted(() => ({
  rpcMock: vi.fn(),
  navigateMock: vi.fn(),
  toastMock: { success: vi.fn(), error: vi.fn() },
  estado: {
    candidatas: [] as unknown[],
    previa: { recebiveis: [], tarefas: [], compras: [] } as unknown,
    previaChamadaCom: [] as string[][],
    banco: new Map() as Map<string, { elegivel: boolean; motivo: string | null }>,
  },
}));

vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: rpcMock } }));
vi.mock('sonner', () => ({ toast: toastMock }));
vi.mock('react-router-dom', async (original) => ({
  ...(await original<typeof import('react-router-dom')>()),
  useNavigate: () => navigateMock,
}));
vi.mock('@/hooks/use-agrupar-os', async (original) => ({
  ...(await original<typeof import('@/hooks/use-agrupar-os')>()),
  useCandidatasOsParaAgrupar: () => ({ data: estado.candidatas, isLoading: false, error: null }),
  useLeituraOsParaAgrupar: () => ({ data: estado.banco }),
  usePreviaDoAgrupamentoOs: (ids: string[], enabled: boolean) => {
    if (enabled) estado.previaChamadaCom.push(ids);
    return { data: enabled ? estado.previa : undefined, isLoading: false, error: null };
  },
}));

function os(over: Partial<CandidataOs>): CandidataOs {
  return {
    id: 'x', service_order_number: 'OS-0000X', status: 'approved', quote_status: 'approved', grand_total: 0,
    created_at: '2026-10-01T12:00:00+00:00', client_id: 'cli-1', vessel_id: 'ves-1', signed_at: null,
    converted_to_os_at: '2026-10-01T13:00:00+00:00', merged_into_id: null, discount_amount: 0, tax_amount: 0,
    commission_rate: 0, commissioned_user_id: null, commissioned_person: null, payment_condition_preset_id: null,
    payment_conditions: null, travel_cost_total: 0, problem_description: null, scheduled_start_at: null,
    card_fee_passthrough_enabled: false, operational_cost_total: 0,
    ...over,
  };
}

const A = os({ id: 'a', service_order_number: 'OS-00100', grand_total: 5709, created_at: '2026-10-01T12:00:00+00:00', problem_description: 'Starlink' });
const B = os({ id: 'b', service_order_number: 'OS-00128', grand_total: 1000, created_at: '2026-10-02T12:00:00+00:00' });
const C = os({ id: 'c', service_order_number: 'OS-00130', grand_total: 50, created_at: '2026-10-03T12:00:00+00:00', signed_at: '2026-10-04T10:00:00Z' });
const EM_EXECUCAO = os({ id: 'e', service_order_number: 'OS-00131', status: 'in_progress', grand_total: 70, created_at: '2026-10-04T12:00:00+00:00' });

function renderizar(preSelecionados: string[], principalSugerido?: string) {
  const onFechar = vi.fn();
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <AgruparOsDialog
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
const botaoAgrupar = () => screen.getByRole('button', { name: /^Agrupar \d+ OS$/ });

beforeEach(() => {
  rpcMock.mockReset();
  navigateMock.mockReset();
  toastMock.success.mockReset();
  toastMock.error.mockReset();
  estado.candidatas = [A, B, C, EM_EXECUCAO];
  estado.previa = { recebiveis: [], tarefas: [], compras: [] };
  estado.previaChamadaCom = [];
  estado.banco = new Map();
});

describe('AgruparOsDialog', () => {
  it('abre com as pré-selecionadas marcadas e a OS em execução desabilitada, com o motivo', () => {
    renderizar(['a', 'b', 'e']);
    expect(caixa('OS-00100')).toBeChecked();
    expect(caixa('OS-00128')).toBeChecked();
    expect(caixa('OS-00130')).not.toBeChecked();
    expect(caixa('OS-00131')).toBeDisabled();
    expect(caixa('OS-00131')).not.toBeChecked();
    expect(within(caixa('OS-00131').closest('li') as HTMLElement).getByText('Em execução')).toBeInTheDocument();
    expect(botaoAgrupar()).toHaveTextContent('Agrupar 2 OS');
    expect(screen.getByText(/Total previsto: R\$\s6\.709,00/)).toBeInTheDocument();
    expect(screen.getByText(/link antigo delas para de funcionar/)).toBeInTheDocument();
    expect(screen.getByText(/comissão é recalculada sobre o total novo/)).toBeInTheDocument();
    // a prévia do que vai junto lê só as escolhidas que podem entrar
    expect(estado.previaChamadaCom.at(-1)).toEqual(['a', 'b']);
  });

  it('mostra o dinheiro, as tarefas e as compras que vão junto', () => {
    estado.previa = {
      recebiveis: [
        { id: 'r1', service_order_id: 'a', description: 'Sinal', amount: 2869.5, paid_amount: 2869.5, status: 'paid', is_deposit: true, due_date: '2026-10-01' },
        { id: 'r2', service_order_id: 'b', description: 'Sinal', amount: 1000, paid_amount: 1000, status: 'paid', is_deposit: true, due_date: '2026-10-02' },
        { id: 'r3', service_order_id: 'a', description: 'Saldo', amount: 2839.5, paid_amount: 0, status: 'pending', is_deposit: false, due_date: '2026-11-01' },
      ],
      tarefas: [{ id: 't1', related_entity_id: 'a', title: 'Comprar 1 item', due_at: null, scheduled_start_at: null }],
      compras: [{ id: 'p1', service_order_id: 'b', po_number: 'OC-00002', status: 'sent', total_amount: 300 }],
    };
    renderizar(['a', 'b']);
    const grupo = screen.getByRole('group', { name: 'O que vai junto para a OS nova' });
    expect(within(grupo).getByText(/3 contas a receber: R\$\s6\.709,00, das quais R\$\s3\.869,50 já recebidos e R\$\s2\.839,50 em aberto/)).toBeInTheDocument();
    const contas = within(grupo).getByRole('list', { name: 'Contas a receber que vão junto' });
    expect(within(contas).getByText(/^OS-00100: Sinal de R\$\s2\.869,50 · pago$/)).toBeInTheDocument();
    expect(within(contas).getByText(/^OS-00100: Conta a receber de R\$\s2\.839,50 · em aberto$/)).toBeInTheDocument();
    expect(within(grupo).getByText('Comprar 1 item (OS-00100)')).toBeInTheDocument();
    expect(within(grupo).getByText(/^OC-00002 · Enviada ao fornecedor · R\$\s300,00 \(OS-00128\)$/)).toBeInTheDocument();
  });

  it('avisa da assinatura que fica na original e da regra da NFS-e', async () => {
    renderizar(['a', 'c']);
    const avisos = screen.getByRole('list', { name: 'Avisos antes de agrupar' });
    expect(within(avisos).getByText(/^OS-00130 foi assinada pelo cliente: a assinatura fica nela/)).toBeInTheDocument();
    expect(within(avisos).getByText(/^Nota fiscal: uma NFS-e cobre um tomador/)).toBeInTheDocument();
  });

  it('com 1 OS o botão fica desabilitado', async () => {
    renderizar(['a', 'b']);
    expect(botaoAgrupar()).toBeEnabled();
    await userEvent.click(caixa('OS-00128'));
    expect(botaoAgrupar()).toHaveTextContent('Agrupar 1 OS');
    expect(botaoAgrupar()).toBeDisabled();
    await userEvent.click(botaoAgrupar());
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it('chama o banco com exatamente as escolhidas, a principal e a soma vista na tela', async () => {
    rpcMock.mockReturnValue(new Promise(() => {}));
    renderizar(['a'], 'b');
    await userEvent.click(caixa('OS-00128'));
    expect(screen.getByRole('radio', { name: 'OS-00128' })).toBeChecked();
    await userEvent.click(screen.getByRole('radio', { name: 'OS-00100' }));
    await userEvent.click(botaoAgrupar());
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock).toHaveBeenCalledWith('agrupar_os', { p_os: ['a', 'b'], p_base: 'a', p_total_esperado: 6709 });
    // p_autor nunca sai da tela: o autor é o usuário da sessão
    expect(Object.keys(rpcMock.mock.calls[0]![1] as object).sort()).toEqual(['p_base', 'p_os', 'p_total_esperado']);
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
    const frase = 'OS-00128 já começou a ser executada (hora apontada). Agrupar só junta OS que ainda não começaram; cada OS executada mantém seu histórico.';
    rpcMock.mockResolvedValue({ data: null, error: { message: frase, code: '22023' } });
    const { onFechar } = renderizar(['a', 'b']);
    await userEvent.click(botaoAgrupar());
    expect(await screen.findByRole('alert')).toHaveTextContent(frase);
    expect(toastMock.error).toHaveBeenCalledWith(frase);
    expect(navigateMock).not.toHaveBeenCalled();
    expect(onFechar).not.toHaveBeenCalled();
    expect(botaoAgrupar()).toBeEnabled();
  });

  it('no sucesso avisa (com os avisos do banco), fecha e abre a OS nova', async () => {
    rpcMock.mockResolvedValue({
      data: {
        service_order_id: 'nova-1', numero: 'OS-00140', agrupamento_id: 'g-1', origens: ['OS-00100', 'OS-00128'],
        principal: 'OS-00100', servicos: 2, pecas: 3, recebiveis_movidos: 3, cobrancas_movidas: 1, tarefas_movidas: 1,
        tecnicos: 2, envios_cancelados: 0, total_geral: 6709, comissao: 0, avisos: ['Assinaturas ficaram nas OS originais.'],
      },
      error: null,
    });
    const { onFechar } = renderizar(['a', 'b']);
    await userEvent.click(botaoAgrupar());
    await vi.waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/v2/service-orders/nova-1'));
    expect(toastMock.success).toHaveBeenCalledWith('Criada OS-00140: reúne OS-00100, OS-00128', {
      description: 'Assinaturas ficaram nas OS originais.',
    });
    expect(onFechar).toHaveBeenCalled();
  });

  it('o que só o banco enxerga (comissão, nota, hora apontada) trava a caixa com a frase dele', async () => {
    const frase = 'OS-00128 tem comissão lançada. Uma OS com nota, fatura ou comissão não entra num agrupamento: resolva isso antes ou deixe-a de fora.';
    estado.banco = new Map([
      ['a', { elegivel: true, motivo: null }],
      ['b', { elegivel: false, motivo: frase }],
    ]);
    renderizar(['a', 'b']);
    expect(caixa('OS-00128')).toBeDisabled();
    expect(caixa('OS-00128')).not.toBeChecked();
    const li = caixa('OS-00128').closest('li') as HTMLElement;
    expect(within(li).getByText('Não entra')).toBeInTheDocument();
    expect(within(li).getByText(frase)).toBeInTheDocument();
    // a que ficou de fora não entra na conta nem na chamada
    expect(botaoAgrupar()).toHaveTextContent('Agrupar 1 OS');
    expect(botaoAgrupar()).toBeDisabled();
  });

  it('avisa situação e data de atendimento diferentes da principal', () => {
    estado.candidatas = [
      { ...A, status: 'approved', scheduled_start_at: '2026-11-03T13:00:00Z' },
      { ...B, status: 'scheduled', scheduled_start_at: '2026-11-05T17:30:00Z' },
    ];
    renderizar(['a', 'b']);
    const avisos = screen.getByRole('list', { name: 'Avisos antes de agrupar' });
    expect(within(avisos).getByText('As OS estão em situações diferentes: a OS nova fica com a situação da principal (OS-00100).')).toBeInTheDocument();
    expect(within(avisos).getByText(/^Tem atendimento marcado em outra data: OS-00128 \(05\/11\/2026, 14:30\)/)).toBeInTheDocument();
  });

  it('sem candidatas, diz que não há OS em aberto', () => {
    estado.candidatas = [];
    renderizar([]);
    expect(screen.getByText(/Nenhuma OS em aberto deste cliente/)).toBeInTheDocument();
  });
});

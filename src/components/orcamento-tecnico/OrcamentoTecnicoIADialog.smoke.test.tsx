// Orçamento técnico com IA (03/10/2026): pedido → espera → proposta → rascunho, pela tela.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { OrcamentoTecnicoIADialog } from './OrcamentoTecnicoIADialog';

const { solicitarMock, criarMock, cancelarMock, estado } = vi.hoisted(() => ({
  solicitarMock: vi.fn(),
  criarMock: vi.fn(),
  cancelarMock: vi.fn(),
  estado: { recentes: [] as unknown[], job: undefined as unknown },
}));

vi.mock('@/hooks/use-orcamento-tecnico-ia', () => ({
  useSolicitarOrcamentoTecnico: () => ({ mutate: solicitarMock, isPending: false }),
  useCriarRascunhoDoOrcamentoTecnico: () => ({ mutate: criarMock, isPending: false }),
  useCancelarPedidoDeOrcamentoTecnico: () => ({ mutate: cancelarMock, isPending: false }),
  usePedidosDeOrcamentoTecnico: () => ({ data: estado.recentes }),
  useJobDeOrcamentoTecnico: (id: string | null) => ({ data: id ? estado.job : undefined }),
}));
vi.mock('@/hooks/use-clients', () => ({
  useClients: () => ({ data: [{ id: 'cli-1', name: 'Cliente A', active: true }] }),
}));
vi.mock('@/hooks/use-vessels', () => ({
  useVessels: () => ({
    data: [
      { id: 'ves-1', name: 'Lancha A', client_id: 'cli-1', active: true },
      { id: 'ves-2', name: 'De outro cliente', client_id: 'cli-2', active: true },
    ],
  }),
}));
vi.mock('@/components/ClientCombobox', () => ({
  ClientCombobox: ({ value, onChange }: { value: string; onChange: (id: string, nome: string) => void }) => (
    <select aria-label="Escolher cliente" value={value} onChange={(e) => onChange(e.target.value, 'Cliente A')}>
      <option value="">—</option>
      <option value="cli-1">Cliente A</option>
    </select>
  ),
}));
vi.mock('@/components/VesselSelect', () => ({
  VesselSelect: ({ value, onChange, vessels, disabled }: { value: string; onChange: (id: string) => void; vessels: Array<{ id: string; name: string }>; disabled?: boolean }) => (
    <select aria-label="Escolher ativo" value={value} disabled={disabled} onChange={(e) => onChange(e.target.value)}>
      <option value="">—</option>
      {vessels.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
    </select>
  ),
}));

const recente = { id: 'job-1', status: 'completed', created_at: '2026-10-03T20:00:00Z', completed_at: null, model: 'opus', prompt: 'Instalar Orion', error_code: null };

function jobCom(over: Record<string, unknown> = {}) {
  return {
    id: 'job-1', status: 'completed', created_at: '2026-10-03T20:00:00Z', started_at: '2026-10-03T20:00:05Z',
    completed_at: '2026-10-03T20:02:05Z', model: 'opus', model_used: 'claude-opus-5-5', duration_ms: 120_000,
    error: null, error_code: null, prompt: 'Instalar Orion', attempts: 1, max_attempts: 2,
    metadata: { tipo: 'orcamento_tecnico' },
    response: {
      format: 'json_schema', text: '{}',
      data: {
        premissas_tecnicas: ['Sistema 12 V'],
        perguntas_pendentes: ['Qual a distância até a bateria de partida?'],
        margem_adotada: { criterio: 'markup mediano praticado', markup: 1.5 },
        orcamentos: [{
          titulo: 'Instalação do Orion 12/12-30A',
          observacoes_valores_provisorios: ['Terminal 16 mm² — Valor provisório — aguardando cotação do fornecedor'],
          resumo: { custo_estimado: 120, margem_aplicada_pct: 50, total_materiais_e_equipamentos: 182, total_mao_de_obra: 0, total_geral: 182 },
          itens: [
            { tipo: 'equipamento', descricao: 'Orion-Tr Smart 12/12-30A', produto_id: 'p1', servico_id: null, quantidade: 1, unidade: 'UN', custo_unitario: 100, origem_do_custo: 'Cadastro SKU 2598', data_do_custo: '2026-07-27', provisorio: false, preco_venda_unitario: 150, total_venda: 150 },
            { tipo: 'material', descricao: 'Terminal 16 mm²', produto_id: null, servico_id: null, quantidade: 4, unidade: 'UN', custo_unitario: 5, origem_do_custo: 'Estimado pelo 25 mm²', data_do_custo: null, provisorio: true, preco_venda_unitario: 8, total_venda: 32 },
          ],
        }],
      },
    },
    ...over,
  };
}

function renderizar() {
  return render(
    <MemoryRouter>
      <OrcamentoTecnicoIADialog aberto onFechar={() => {}} />
    </MemoryRouter>,
  );
}

async function abrirPedidoRecente() {
  await userEvent.click(screen.getByRole('button', { name: /Abrir o pedido de/ }));
}

beforeEach(() => {
  solicitarMock.mockReset();
  criarMock.mockReset();
  cancelarMock.mockReset();
  estado.recentes = [];
  estado.job = undefined;
});

describe('OrcamentoTecnicoIADialog', () => {
  it('só envia pedido com detalhe suficiente, com o modelo escolhido', async () => {
    renderizar();
    const gerar = screen.getByRole('button', { name: /Gerar proposta/ });
    await userEvent.type(screen.getByLabelText('O que precisa ser orçado?'), 'curto');
    expect(gerar).toBeDisabled();
    await userEvent.type(screen.getByLabelText('O que precisa ser orçado?'), ' — instalar um Orion 12/12-30A numa lancha');
    await userEvent.click(screen.getByRole('button', { name: /Sonnet/ }));
    await userEvent.click(gerar);
    expect(solicitarMock).toHaveBeenCalledWith(
      { pedido: 'curto — instalar um Orion 12/12-30A numa lancha', modelo: 'sonnet' },
      expect.anything(),
    );
  });

  it('mostra a espera e deixa cancelar', async () => {
    estado.recentes = [{ ...recente, status: 'processing' }];
    estado.job = jobCom({ status: 'processing', response: null, completed_at: null, duration_ms: null });
    renderizar();
    await abrirPedidoRecente();
    expect(screen.getByText('O Claude está montando a proposta…')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Cancelar pedido' }));
    expect(cancelarMock).toHaveBeenCalledWith('job-1');
  });

  it('explica a falha em português (limite da assinatura)', async () => {
    estado.recentes = [{ ...recente, status: 'failed' }];
    estado.job = jobCom({ status: 'failed', response: null, error_code: 'rate_limited', error: 'x' });
    renderizar();
    await abrirPedidoRecente();
    expect(screen.getByText(/limite de uso da assinatura do Claude/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Novo pedido/ })).toBeInTheDocument();
  });

  it('mostra a proposta e cria o rascunho só com cliente e ativo escolhidos', async () => {
    estado.recentes = [recente];
    estado.job = jobCom();
    renderizar();
    await abrirPedidoRecente();

    expect(screen.getByText('Instalação do Orion 12/12-30A')).toBeInTheDocument();
    expect(screen.getByText('Orion-Tr Smart 12/12-30A')).toBeInTheDocument();
    expect(screen.getByText('Provisório')).toBeInTheDocument();
    expect(screen.getByText('Qual a distância até a bateria de partida?')).toBeInTheDocument();
    expect(screen.queryByText(/não bate/)).not.toBeInTheDocument();

    const criar = screen.getByRole('button', { name: 'Criar rascunho deste orçamento' });
    expect(criar).toBeDisabled();
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Escolher cliente' }), 'cli-1');
    // cliente com um ativo só: escolhido sozinho; o ativo de outro cliente nem aparece
    expect(screen.getByRole('combobox', { name: 'Escolher ativo' })).toHaveValue('ves-1');
    expect(screen.queryByRole('option', { name: 'De outro cliente' })).not.toBeInTheDocument();
    await userEvent.click(criar);
    expect(criarMock).toHaveBeenCalledWith({ jobId: 'job-1', indice: 0, clienteId: 'cli-1', ativoId: 'ves-1' }, expect.anything());
  });

  it('avisa quando as contas do modelo não fecham', async () => {
    const job = jobCom();
    (job.response as { data: { orcamentos: Array<{ resumo: { total_geral: number } }> } }).data.orcamentos[0]!.resumo.total_geral = 999;
    estado.recentes = [recente];
    estado.job = job;
    renderizar();
    await abrirPedidoRecente();
    expect(screen.getByText('O total geral declarado não bate com a soma das linhas.')).toBeInTheDocument();
  });

  it('proposta que já virou rascunho oferece abrir em vez de criar de novo', async () => {
    estado.recentes = [recente];
    estado.job = jobCom({ metadata: { tipo: 'orcamento_tecnico', rascunhos: { '0': 'so-9' } } });
    renderizar();
    await abrirPedidoRecente();
    expect(screen.getByRole('button', { name: /Abrir o rascunho/ })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Criar rascunho deste orçamento' })).not.toBeInTheDocument();
  });
});

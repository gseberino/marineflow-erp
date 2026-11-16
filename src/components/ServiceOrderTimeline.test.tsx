// Render da aba Histórico da OS (F4 do histórico de documentos, 16/11/2026).
//
// O que se protege aqui é o que a casa já perdeu antes: leitura que falha virando "nenhuma
// alteração" (a pessoa conclui que ninguém mexeu, quando na verdade não deu para ler), o erro cru
// do banco na cara do técnico, e o botão de desfazer num documento que o banco vai recusar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const h = vi.hoisted(() => ({
  papel: 'admin' as string | undefined,
  rpc: vi.fn(),
  recalc: vi.fn(),
  qc: null as import('@tanstack/react-query').QueryClient | null,
}));

vi.mock('@/hooks/use-auth', () => ({
  useOptionalAuth: () => (h.papel ? { user: { id: 'u1', role: h.papel } } : null),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: (...a: unknown[]) => h.rpc(...a) },
}));
vi.mock('@/hooks/use-service-orders', () => ({ recalcTotals: (...a: unknown[]) => h.recalc(...a) }));
vi.mock('@/lib/diagnostics', () => ({ logError: vi.fn() }));

import { ServiceOrderTimeline } from './ServiceOrderTimeline';

const OS = '11111111-2222-3333-4444-555555555555';
const DOC = { tipo: 'os', numero: 'ORÇ-00112', id: OS };

const ALTERACOES = {
  documento: DOC, modo: 'alteracoes', total_de_eventos: 2, aviso: null,
  eventos: [{
    quando: '15/11/2026 14:32', quando_iso: '2026-11-15T17:32:00Z', quem: 'Gustavo', por_onde: 'tela', desfazivel: true,
    itens: [
      {
        item: 'Peça: Bomba de porão 12V', acao: 'alterado', motivo: null, registro_id: 'reg-1', desfazivel: true,
        mudancas: [
          { campo: 'Quantidade', antes: '1', depois: '2', calculado: false },
          { campo: 'Total da linha', antes: 'R$ 350,00', depois: 'R$ 700,00', calculado: true },
        ],
      },
      { item: 'Versão 3 (enviado)', acao: 'versão guardada', motivo: null, registro_id: 'reg-2', desfazivel: false, mudancas: [] },
    ],
  }, {
    // só a situação mudou: o banco diz que não se desfaz
    quando: '14/11/2026 08:00', quando_iso: '2026-11-14T11:00:00Z', quem: 'Ana', por_onde: 'tela', desfazivel: false,
    itens: [{
      item: 'Documento', acao: 'alterado', motivo: null, registro_id: 'reg-3', desfazivel: false,
      mudancas: [{ campo: 'Situação', antes: 'Rascunho', depois: 'Enviado', calculado: false }],
    }],
  }],
};

const VERSOES = {
  documento: DOC, modo: 'versoes',
  versoes: [{
    versao: 2, marco: 'enviado', quando: '10/11/2026 09:00', quando_iso: '2026-11-10T12:00:00Z', quem: 'Gustavo',
    situacao: 'Orçamento', total: 'R$ 1.200,00', pecas: 1, servicos: 2,
  }],
};

const SIMULACAO = {
  documento: 'ORÇ-00112',
  o_que_muda: {
    cabecalho: [], itens_incluidos: [], itens_removidos: [],
    itens_alterados: [{ item: 'Peça: Bomba de porão 12V', mudancas: [{ campo: 'Quantidade', antes: '2', depois: '1', calculado: false }] }],
    sem_diferenca: false,
  },
  nao_desfeito: [{ item: 'Peça: Cabo', campo: 'Preço', motivo: 'foi alterado de novo depois; ficou como está' }],
  avisos: [{
    item: 'Peça: Filtro',
    aviso: 'sai do documento e leva junto: item de pedido de compra PC-00007 (isso não volta numa restauração futura)',
  }],
  total_antes: 'R$ 1.550,00', total_depois: 'R$ 1.200,00', pede_nova_assinatura: false,
  hash_do_documento: 'abc123', simulacao: true, restaurado: false, documento_id: OS,
};

function respostaPadrao(nome: string, args: Record<string, unknown>) {
  if (nome === 'documento_historico' && args.p_modo === 'alteracoes') return Promise.resolve({ data: ALTERACOES, error: null });
  if (nome === 'documento_historico' && args.p_modo === 'versoes') return Promise.resolve({ data: VERSOES, error: null });
  if (nome === 'documento_restaurar' && args.p_simular) return Promise.resolve({ data: SIMULACAO, error: null });
  if (nome === 'documento_restaurar') {
    return Promise.resolve({ data: { ...SIMULACAO, simulacao: false, restaurado: true, versao_nova: 4 }, error: null });
  }
  return Promise.resolve({ data: null, error: { code: 'XX000', message: `rpc inesperada ${nome}` } });
}

function renderTimeline(documento: { status?: string; invoicing_status?: string | null; merged_into_id?: string | null } = { status: 'draft' }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  h.qc = qc;
  return render(
    <QueryClientProvider client={qc}>
      <ServiceOrderTimeline orderId={OS} documento={documento} />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  h.papel = 'admin';
  h.rpc.mockReset();
  h.rpc.mockImplementation(respostaPadrao);
  h.recalc.mockReset();
  h.recalc.mockResolvedValue(undefined);
});

describe('ServiceOrderTimeline — histórico pelo banco', () => {
  it('carregando, depois um evento com as mudanças e, na outra aba, uma versão', async () => {
    let soltar!: (v: unknown) => void;
    h.rpc.mockImplementationOnce(() => new Promise((r) => { soltar = r; }));
    const user = userEvent.setup();
    renderTimeline();

    expect(screen.getByLabelText('Carregando o histórico')).toBeInTheDocument();
    expect(h.rpc).toHaveBeenCalledWith('documento_historico', expect.objectContaining({
      p_tipo: 'os', p_ref: OS, p_modo: 'alteracoes', p_limite: 20,
    }));

    soltar({ data: ALTERACOES, error: null });
    expect(await screen.findByText('15/11/2026 14:32')).toBeInTheDocument();
    expect(screen.getByText('Peça: Bomba de porão 12V')).toBeInTheDocument();
    expect(screen.getByText('R$ 700,00')).toBeInTheDocument();
    // o campo calculado aparece, mas marcado como recalculado
    expect(screen.getByText('(recalculado)')).toBeInTheDocument();
    expect(screen.queryByText(/Nenhuma alteração/)).not.toBeInTheDocument();

    await user.click(screen.getByRole('tab', { name: 'Versões' }));
    const versao = await screen.findByTestId('versao-do-documento');
    expect(within(versao).getByText('Versão 2')).toBeInTheDocument();
    expect(within(versao).getByText('R$ 1.200,00')).toBeInTheDocument();
    expect(within(versao).getByRole('button', { name: /mais ações para versão 2/i })).toBeInTheDocument();
  });

  it('erro de leitura mostra a falha e o tentar de novo — nunca "nenhuma alteração"', async () => {
    h.rpc.mockImplementation(() => Promise.resolve({ data: null, error: { code: 'XX000', message: 'a conexão caiu' } }));
    const user = userEvent.setup();
    renderTimeline();

    expect(await screen.findByText(/Não foi possível carregar o histórico/)).toBeInTheDocument();
    expect(screen.getByText('a conexão caiu')).toBeInTheDocument();
    expect(screen.queryByText(/Nenhuma alteração/)).not.toBeInTheDocument();

    h.rpc.mockImplementation(respostaPadrao);
    await user.click(screen.getByRole('button', { name: /Tentar de novo/ }));
    expect(await screen.findByText('15/11/2026 14:32')).toBeInTheDocument();
  });

  it('42501 (cargo sem acesso) vira a frase amigável, não o erro cru', async () => {
    h.rpc.mockImplementation(() => Promise.resolve({
      data: null, error: { code: '42501', message: 'O histórico de documentos é só para administrador e financeiro.' },
    }));
    renderTimeline();
    expect(await screen.findByText('O histórico é visível só para administrador e financeiro.')).toBeInTheDocument();
    expect(screen.queryByText(/Não foi possível carregar/)).not.toBeInTheDocument();
    expect(screen.queryByText(/Nenhuma alteração/)).not.toBeInTheDocument();
  });

  it('técnico nem pergunta ao banco: vê a mesma frase', () => {
    h.papel = 'technician';
    renderTimeline();
    expect(screen.getByText('O histórico é visível só para administrador e financeiro.')).toBeInTheDocument();
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it('documento concluído (ou agrupado, ou faturado): o desfazer some', async () => {
    const a = renderTimeline({ status: 'completed' });
    await screen.findByText('15/11/2026 14:32');
    expect(screen.queryByRole('button', { name: /mais ações para alteração/i })).not.toBeInTheDocument();
    expect(screen.getByText(/Concluída: desfazer e voltar versão só valem para documento em aberto/)).toBeInTheDocument();
    a.unmount();

    const b = renderTimeline({ status: 'in_progress', merged_into_id: 'outra-os' });
    await screen.findByText('15/11/2026 14:32');
    expect(screen.queryByRole('button', { name: /mais ações para alteração/i })).not.toBeInTheDocument();
    b.unmount();

    // financeiro numa OS aberta vê; vendedor não
    h.papel = 'seller';
    const c = renderTimeline({ status: 'open' });
    expect(screen.getByText('O histórico é visível só para administrador e financeiro.')).toBeInTheDocument();
    c.unmount();
  });

  it('documento aberto: desfazer simula, mostra o que muda e só então confirma com o hash', async () => {
    const user = userEvent.setup();
    renderTimeline({ status: 'open' });
    const invalidar = vi.spyOn(h.qc!, 'invalidateQueries');
    await screen.findByText('15/11/2026 14:32');

    await user.click(screen.getByRole('button', { name: /mais ações para alteração de 15\/11\/2026 14:32/i }));
    await user.click(await screen.findByText('Desfazer esta alteração'));

    // simulação primeiro, só com os registros desfazíveis (a "versão guardada" fica de fora)
    expect(h.rpc).toHaveBeenCalledWith('documento_restaurar', {
      p_ref: OS, p_eventos: ['reg-1'], p_simular: true,
    });
    const dialogo = await screen.findByRole('dialog');
    expect(await within(dialogo).findByText('R$ 1.200,00')).toBeInTheDocument();
    expect(within(dialogo).getByText('Motivo (opcional)')).toBeInTheDocument();
    // o que vai junto e não volta aparece destacado, além do que fica como está
    const avisos = within(dialogo).getByTestId('avisos-da-restauracao');
    expect(within(avisos).getByText('Peça: Filtro:')).toBeInTheDocument();
    expect(within(avisos).getByText(/leva junto: item de pedido de compra PC-00007/)).toBeInTheDocument();
    expect(within(dialogo).getByText('Fica como está')).toBeInTheDocument();
    expect(within(dialogo).getByText(/foi alterado de novo depois/)).toBeInTheDocument();

    await user.type(within(dialogo).getByLabelText('Motivo (opcional)'), 'cliente desistiu');
    await user.click(within(dialogo).getByRole('button', { name: 'Desfazer' }));

    await waitFor(() => expect(h.rpc).toHaveBeenCalledWith('documento_restaurar', {
      p_ref: OS, p_eventos: ['reg-1'], p_motivo: 'cliente desistiu', p_simular: false, p_conferir_hash: 'abc123',
    }));
    // a cascata das parcelas roda depois de gravar (a RPC não redistribui)
    await waitFor(() => expect(h.recalc).toHaveBeenCalledWith(OS));
    // o quadro de assinaturas relê (documento assinado volta a pedir assinatura)
    await waitFor(() => expect(invalidar).toHaveBeenCalledWith({ queryKey: ['so-signatures', OS] }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  });

  it('evento sem nada desfazível (só situação) não oferece o desfazer', async () => {
    renderTimeline({ status: 'open' });
    await screen.findByText('14/11/2026 08:00');
    expect(screen.getByRole('button', { name: /mais ações para alteração de 15\/11\/2026 14:32/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /mais ações para alteração de 14\/11\/2026 08:00/i })).not.toBeInTheDocument();
  });

  it('simulação sem diferença mostra a mensagem do banco e não deixa confirmar', async () => {
    h.rpc.mockImplementation((nome: string, args: Record<string, unknown>) => {
      if (nome === 'documento_restaurar') {
        return Promise.resolve({
          data: {
            ...SIMULACAO, avisos: [], nao_desfeito: [], total_depois: SIMULACAO.total_antes,
            o_que_muda: { ...SIMULACAO.o_que_muda, itens_alterados: [], sem_diferenca: true },
            mensagem: 'Nada a mudar: o documento já está assim (conferido).',
          },
          error: null,
        });
      }
      return respostaPadrao(nome, args);
    });
    const user = userEvent.setup();
    renderTimeline({ status: 'open' });
    await screen.findByText('15/11/2026 14:32');
    await user.click(screen.getByRole('button', { name: /mais ações para alteração de 15\/11\/2026 14:32/i }));
    await user.click(await screen.findByText('Desfazer esta alteração'));
    const dialogo = await screen.findByRole('dialog');
    expect(await within(dialogo).findByText('Nada a mudar: o documento já está assim (conferido).')).toBeInTheDocument();
    expect(within(dialogo).queryByTestId('avisos-da-restauracao')).not.toBeInTheDocument();
    expect(within(dialogo).getByRole('button', { name: 'Desfazer' })).toBeDisabled();
  });
});

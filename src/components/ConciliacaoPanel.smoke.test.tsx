// Smoke de render da Conciliação — a que parte do LANÇAMENTO.
//
// O que se testa aqui não é layout: é que a tela responde a pergunta certa. A anterior
// partia do extrato e listava toda linha ainda não tratada; esta parte do que foi
// registrado e procura o par no banco. Se um dia alguém reinverter isso, estes testes caem.
//
// Também se testa o que já custou caro neste módulo:
//   · lista vazia por ERRO tem de aparecer como erro, não como "nada a fazer" (PGRST201
//     deixou 1.178 propostas invisíveis atrás de uma tela vazia);
//   · candidato do extrato só pode ter o SINAL certo — casar saída com entrada é erro
//     silencioso, porque o valor bate.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { ConciliacaoPanel } from './ConciliacaoPanel';

const { estado, conciliarMock } = vi.hoisted(() => ({
  conciliarMock: vi.fn(),
  estado: {
    semExtrato: [
      {
        lado: 'receivable', id: 'r1', description: 'Serviço de instalação',
        amount: 9700, status: 'paid', due_date: '2026-04-27', issue_date: '2026-04-20',
        contraparte: 'Cliente Náutico Ltda', categoria: 'Serviços',
        bank_transaction_id: null, situacao: 'sem_extrato',
        extrato_data: null, extrato_valor: null, extrato_descricao: null, diferenca: null,
      },
      {
        lado: 'payable', id: 'p1', description: 'Peças',
        amount: 1200, status: 'pending', due_date: '2026-05-01', issue_date: '2026-04-25',
        contraparte: 'Fornecedor A', categoria: 'Peças e materiais',
        bank_transaction_id: null, situacao: 'sem_extrato',
        extrato_data: null, extrato_valor: null, extrato_descricao: null, diferenca: null,
      },
    ],
    conciliados: [
      {
        lado: 'payable', id: 'p2', description: 'Energia',
        amount: 540.5, status: 'paid', due_date: '2026-06-10', issue_date: '2026-06-01',
        contraparte: 'Celesc', categoria: 'Energia',
        bank_transaction_id: 'bt9', situacao: 'conciliado',
        extrato_data: '2026-06-10', extrato_valor: 530.5, extrato_descricao: 'DEB CELESC',
        diferenca: 10,
      },
    ],
    // Uma entrada e uma saída: a tela só pode oferecer a do sinal certo.
    livres: [
      { id: 'bt1', transaction_date: '2026-04-27', description: 'TED RECEBIDA', amount: 9700, transaction_type: 'credit', counterparty_name: 'CLIENTE NAUTICO LTDA', counterparty_document: '12345678000199', e_cartao: false },
      { id: 'bt2', transaction_date: '2026-04-28', description: 'PIX RECEBIDO', amount: 400, transaction_type: 'credit', counterparty_name: 'OUTRO', counterparty_document: null, e_cartao: false },
    ],
    erro: null as Error | null,
  },
}));

vi.mock('@/hooks/use-conciliacao', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-conciliacao')>();
  return {
    ...real,
    useLancamentosSemExtrato: () => ({ data: estado.semExtrato, isLoading: false, error: estado.erro }),
    useLancamentosConciliados: () => ({ data: estado.conciliados, isLoading: false, error: null }),
    useExtratoLivre: (lado: string | null) => ({
      // Espelha o filtro real do hook: só o sinal compatível com o lado do lançamento.
      data: estado.livres.filter((t) =>
        t.transaction_type === (lado === 'payable' ? 'debit' : 'credit')),
      isLoading: false, error: null,
    }),
    useConciliarLancamento: () => ({ mutate: conciliarMock, isPending: false }),
    useDesconciliarLancamento: () => ({ mutate: vi.fn(), isPending: false }),
  };
});

function renderPanel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><ConciliacaoPanel /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('conciliação (parte do lançamento)', () => {
  afterEach(() => { conciliarMock.mockClear(); estado.erro = null; });

  it('abre com conteúdo, não em branco', async () => {
    // A regressão que este teste existe para pegar: aba nova que renderiza só esqueleto.
    renderPanel();
    expect(await screen.findByText('Conciliação')).toBeInTheDocument();
  });

  it('diz que a triagem do extrato é OUTRA tela', async () => {
    // O erro conceitual que originou tudo. Se a tela voltar a se vender como o lugar de
    // tratar o extrato, a separação se perdeu.
    renderPanel();
    expect(await screen.findByText(/Extrato/)).toBeInTheDocument();
    expect(screen.getByText(/O que você lançou no sistema, conferido contra o extrato/))
      .toBeInTheDocument();
  });

  it('lista lançamentos sem par, dos dois lados', async () => {
    renderPanel();
    expect(await screen.findByText('Cliente Náutico Ltda')).toBeInTheDocument();
    expect(screen.getByText('Fornecedor A')).toBeInTheDocument();
  });

  it('avisa quando um conciliado tem valor diferente do extrato', async () => {
    renderPanel();
    expect(await screen.findByText(/valor diferente do extrato/)).toBeInTheDocument();
  });

  it('só oferece candidato do SINAL certo — e marca o valor exato', async () => {
    // Casar um recebimento com uma saída é erro silencioso: o valor bate e ninguém percebe.
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderPanel();
    await user.click(await screen.findByText('Cliente Náutico Ltda'));
    expect(await screen.findByText('CLIENTE NAUTICO LTDA')).toBeInTheDocument();
    expect(screen.getByText('valor exato')).toBeInTheDocument();
    // A saída do outro lançamento não pode aparecer entre os candidatos desta entrada.
    expect(screen.queryByText('DEB CELESC')).not.toBeInTheDocument();
  });

  it('casa o lançamento com a linha escolhida', async () => {
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderPanel();
    await user.click(await screen.findByText('Cliente Náutico Ltda'));
    await user.click((await screen.findAllByRole('button', { name: /Casar/i }))[0]);
    expect(conciliarMock).toHaveBeenCalledWith(
      expect.objectContaining({ lado: 'receivable', id: 'r1', bankTransactionId: 'bt1' }),
      expect.anything(),
    );
  });

  it('mostra o ERRO em vez de fingir lista vazia', async () => {
    // Uma tela vazia por falha de consulta diz "nada a fazer" — e foi assim que 1.178
    // propostas ficaram invisíveis atrás de um PGRST201.
    estado.erro = new Error('PGRST201: relacionamento ambíguo');
    renderPanel();
    expect(await screen.findByText(/Não deu para carregar a conciliação/)).toBeInTheDocument();
    expect(screen.getByText(/PGRST201/)).toBeInTheDocument();
  });
});

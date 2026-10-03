// "Este Pix paga…" (forma A, F2 — 02/10/2026): o caso do Lenine pela tela, a sobra que trava e o
// sinal lançado à mão que o Pix passa a explicar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { EstePixPagaDialog } from './EstePixPagaDialog';
import type { ParecePagar } from '../../supabase/functions/_shared/banking/parece-pagar';

const { aplicarMock, dados } = vi.hoisted(() => ({
  aplicarMock: vi.fn(),
  dados: {
    entrada: null as null | { data: string; valor: number; quem: string; aplicado: number; sobra: number; aplicacoes: unknown[] },
    contas: [] as Array<{ id: string; descricao: string; documento: string | null; vencimento: string; valor: number; pago: number; saldo: number }>,
    pagamentos: [] as Array<{ id: string; contaId: string; descricao: string; documento: string | null; data: string; valor: number }>,
  },
}));

vi.mock('@/hooks/use-lancamentos', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-lancamentos')>()),
  useEntradaAplicada: () => ({ data: dados.entrada, isLoading: false }),
  useContasEmAbertoDoCliente: () => ({ data: dados.contas, isLoading: false }),
  usePagamentosSemPixDoCliente: () => ({ data: dados.pagamentos }),
  useAplicarEntradaEmContas: () => ({ mutate: aplicarMock, isPending: false }),
}));
vi.mock('@/hooks/use-payees', () => ({
  useClientesParaReceita: () => ({ data: [{ id: 'cli', name: 'Cliente Final' }] }),
}));

function renderizar(sugestao?: ParecePagar) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <EstePixPagaDialog aberto onFechar={() => {}} entradaId="btL" clienteInicial="cli" sugestao={sugestao} />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  aplicarMock.mockReset();
  dados.entrada = { data: '2026-08-11', valor: 4800, quem: 'LENINE LORI BROCCA', aplicado: 0, sobra: 4800, aplicacoes: [] };
  dados.contas = [
    { id: 'r74', descricao: 'Sinal — ORÇ-00074', documento: 'ORÇ-00074', vencimento: '2026-08-11', valor: 2280, pago: 0, saldo: 2280 },
    { id: 'r77', descricao: 'Sinal — ORÇ-00077', documento: 'ORÇ-00077', vencimento: '2026-08-12', valor: 2520, pago: 0, saldo: 2520 },
  ];
  dados.pagamentos = [];
});

describe('EstePixPagaDialog', () => {
  it('o Pix do Lenine paga os dois sinais: valores preenchidos, sem sobra, aplica com confirmação', async () => {
    const user = userEvent.setup();
    renderizar();
    expect(screen.getByText(/LENINE LORI BROCCA · R\$\s?4\.800,00/)).toBeInTheDocument();

    await user.click(screen.getByRole('checkbox', { name: 'Este Pix paga Sinal — ORÇ-00074' }));
    await user.click(screen.getByRole('checkbox', { name: 'Este Pix paga Sinal — ORÇ-00077' }));
    expect(screen.getByRole('textbox', { name: 'Quanto vai para Sinal — ORÇ-00074' })).toHaveValue('2.280,00');
    expect(screen.getByRole('textbox', { name: 'Quanto vai para Sinal — ORÇ-00077' })).toHaveValue('2.520,00');
    expect(within(screen.getByTestId('resumo-da-aplicacao')).getByText(/sobra R\$\s?0,00/)).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Aplicar' }));
    expect(aplicarMock).not.toHaveBeenCalled(); // primeiro diz o que vai acontecer
    expect(screen.getByText(/Vai registrar 2 pagamento\(s\) com a data desta entrada/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Confirmar' }));
    expect(aplicarMock).toHaveBeenCalledTimes(1);
    expect(aplicarMock.mock.calls[0][0]).toEqual({
      bankTransactionId: 'btL',
      aplicacoes: [
        { receivable_id: 'r74', valor: 2280, quitar: false },
        { receivable_id: 'r77', valor: 2520, quitar: false },
      ],
    });
  });

  it('com sobra, não deixa aplicar e diz por quê', async () => {
    const user = userEvent.setup();
    renderizar();
    await user.click(screen.getByRole('checkbox', { name: 'Este Pix paga Sinal — ORÇ-00074' }));
    expect(screen.getByText(/Sobram R\$\s?2\.520,00 desta entrada/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeDisabled();
  });

  it('"preencher pela mais antiga" distribui a entrada pelos vencimentos', async () => {
    const user = userEvent.setup();
    renderizar();
    await user.click(screen.getByRole('button', { name: 'Preencher pela mais antiga' }));
    expect(screen.getByRole('textbox', { name: 'Quanto vai para Sinal — ORÇ-00074' })).toHaveValue('2.280,00');
    expect(screen.getByRole('textbox', { name: 'Quanto vai para Sinal — ORÇ-00077' })).toHaveValue('2.520,00');
    expect(screen.getByRole('button', { name: 'Aplicar' })).toBeEnabled();
  });

  it('o sinal lançado à mão: o Pix passa a ser a origem dele, sem criar outro pagamento', async () => {
    const user = userEvent.setup();
    dados.entrada = { data: '2026-08-11', valor: 2280, quem: 'LENINE', aplicado: 0, sobra: 2280, aplicacoes: [] };
    dados.contas = [];
    dados.pagamentos = [{ id: 'pg74', contaId: 'r74', descricao: 'Sinal — ORÇ-00074', documento: 'ORÇ-00074', data: '2026-08-11', valor: 2280 }];
    renderizar();
    await user.click(screen.getByRole('checkbox', { name: 'Este Pix é o pagamento de Sinal — ORÇ-00074' }));
    await user.click(screen.getByRole('button', { name: 'Aplicar' }));
    await user.click(screen.getByRole('button', { name: 'Confirmar' }));
    expect(aplicarMock.mock.calls[0][0]).toEqual({ bankTransactionId: 'btL', aplicacoes: [{ pagamento_id: 'pg74' }] });
  });

  it('até R$ 10 a menos: oferece quitar com desconto, marcado', async () => {
    const user = userEvent.setup();
    dados.entrada = { data: '2026-08-11', valor: 995, quem: 'X', aplicado: 0, sobra: 995, aplicacoes: [] };
    dados.contas = [{ id: 'r1', descricao: 'Conta de 1000', documento: null, vencimento: '2026-08-01', valor: 1000, pago: 0, saldo: 1000 }];
    renderizar();
    await user.click(screen.getByRole('checkbox', { name: 'Este Pix paga Conta de 1000' }));
    expect(screen.getByRole('textbox', { name: 'Quanto vai para Conta de 1000' })).toHaveValue('995,00');
    expect(screen.getByRole('checkbox', { name: 'Quitar Conta de 1000 com desconto' })).toBeChecked();
    await user.click(screen.getByRole('button', { name: 'Aplicar' }));
    await user.click(screen.getByRole('button', { name: 'Confirmar' }));
    expect(aplicarMock.mock.calls[0][0].aplicacoes).toEqual([{ receivable_id: 'r1', valor: 995, quitar: true }]);
  });

  it('aberto pela sugestão (F4): contas e pagamento à mão já marcados, aplica com o mesmo clique', async () => {
    const user = userEvent.setup();
    dados.entrada = { data: '2026-08-11', valor: 4805, quem: 'CLIENTE', aplicado: 0, sobra: 4805, aplicacoes: [] };
    dados.pagamentos = [{ id: 'pg9', contaId: 'r9', descricao: 'Sinal — ORÇ-00009', documento: null, data: '2026-08-11', valor: 5 }];
    renderizar({
      itens: [
        { tipo: 'conta', id: 'r74', rotulo: 'Sinal — ORÇ-00074', saldo: 2280, valor: 2280, quitar: false },
        { tipo: 'conta', id: 'r77', rotulo: 'Sinal — ORÇ-00077', saldo: 2520, valor: 2520, quitar: false },
        { tipo: 'pagamento', id: 'pg9', rotulo: 'ORÇ-00009 (lançado à mão em 11/08)', saldo: 5, valor: 5, quitar: false },
      ],
      diferenca: 0, outraCombinacao: false, parcial: false,
    });
    expect(screen.getByTestId('preenchido-pela-sugestao')).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: 'Este Pix paga Sinal — ORÇ-00074' })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: 'Este Pix paga Sinal — ORÇ-00077' })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: 'Este Pix é o pagamento de Sinal — ORÇ-00009' })).toBeChecked();
    expect(screen.getByRole('textbox', { name: 'Quanto vai para Sinal — ORÇ-00077' })).toHaveValue('2.520,00');
    await user.click(screen.getByRole('button', { name: 'Aplicar' }));
    await user.click(screen.getByRole('button', { name: 'Confirmar' }));
    expect(aplicarMock.mock.calls[0][0].aplicacoes).toEqual([
      { receivable_id: 'r74', valor: 2280, quitar: false },
      { receivable_id: 'r77', valor: 2520, quitar: false },
      { pagamento_id: 'pg9' },
    ]);
  });
});

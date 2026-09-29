// Financeiro › Diárias: cartões com o saldo de cada freelancer, extrato com saldo corrido e
// excluir com Desfazer (sem diálogo de confirmação).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { DiariasPanel } from './DiariasPanel';

const apagar = vi.fn();
const registrar = vi.fn();
const toastFn = vi.fn();

vi.mock('sonner', () => ({
  toast: Object.assign((...a: unknown[]) => toastFn(...a), { success: vi.fn(), error: vi.fn() }),
}));

const pessoas = [
  { id: 'r', nome: 'Roberto', diaria: 160, desde: '2026-08-25', dias: 12, trabalhado: 1980, pago: 1530,
    ultimo_pagamento: '2026-09-27', saldo_final: 450, estado: 'deve' },
  { id: 'm', nome: 'Mickael', diaria: 130, desde: '2026-08-25', dias: 4, trabalhado: 580, pago: 600,
    ultimo_pagamento: '2026-08-28', saldo_final: -20, estado: 'adiantado' },
];

vi.mock('@/hooks/use-diarias', async (orig) => {
  const real = await orig<typeof import('@/hooks/use-diarias')>();
  return {
    ...real,
    useResumoFreelancers: () => ({ isLoading: false, error: null, data: {
      pessoas, trabalhado: 2560, pago: 2130, dias: 16, deve: 450, adiantado: 20,
    } }),
    useContaCorrente: () => ({ isLoading: false, error: null, data: {
      favorecido: { id: 'r', nome: 'Roberto', desde: '2026-08-25', saldo_inicial: 0, diaria: 160 },
      de: null, ate: null, saldo_anterior: 0, dias: 1, trabalhado: 180, pago: 100, saldo_final: 80, estado: 'deve',
      linhas: [
        { data: '2026-09-16', tipo: 'dia', id: 'd1', jornada: 'inteiro', fracao: 1, valor_diaria: 160, extras: 20,
          descontos: 0, trabalhado: 180, pago: 0, descricao: null, conta: null, categoria: null,
          observacao: 'Gerador do Marcelo', os: [{ id: 'o1', numero: 'OS-0042' }], saldo: 180 },
        { data: '2026-09-22', tipo: 'pagamento', id: 'p1', jornada: null, fracao: null, valor_diaria: null, extras: null,
          descontos: null, trabalhado: 0, pago: 100, descricao: 'Pix enviado para Roberto', conta: 'C6 - Conta PJ HBR',
          categoria: 'Diárias de freelancers', observacao: null, os: [], saldo: 80 },
      ],
    } }),
    useApagarDiaria: () => ({ isPending: false, mutateAsync: apagar }),
    useRegistrarDiaria: () => ({ isPending: false, mutateAsync: registrar }),
  };
});
vi.mock('@/hooks/use-payees', () => ({ useServiceOrdersVinculaveis: () => ({ data: [] }) }));

function renderizar(aba: 'resumo' | 'extrato', onVerExtrato = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <DiariasPanel aba={aba} filtro={{ periodo: 'tudo', favorecidoId: aba === 'extrato' ? 'r' : null }}
                      onFiltro={vi.fn()} onVerExtrato={onVerExtrato} />
      </I18nProvider>
    </QueryClientProvider>,
  );
  return { onVerExtrato };
}

beforeEach(() => { apagar.mockReset(); registrar.mockReset(); toastFn.mockReset(); });

describe('DiariasPanel', () => {
  it('um cartão por freelancer, com o saldo e se você deve ou adiantou', async () => {
    const user = userEvent.setup();
    const { onVerExtrato } = renderizar('resumo');
    expect(screen.getByText('Roberto')).toBeInTheDocument();
    expect(screen.getByText('Mickael')).toBeInTheDocument();
    expect(screen.getAllByText('Você deve').length).toBeGreaterThan(0);
    expect(screen.getByText('Adiantado')).toBeInTheDocument();
    await user.click(screen.getAllByRole('button', { name: 'Ver extrato' })[0]);
    expect(onVerExtrato).toHaveBeenCalledWith('r');
  });

  it('o extrato mostra o dia com a OS e o pagamento com a conta de onde saiu', () => {
    renderizar('extrato');
    expect(screen.getByText('OS OS-0042')).toBeInTheDocument();
    expect(screen.getByText(/Gerador do Marcelo/)).toBeInTheDocument();
    expect(screen.getByText('C6 - Conta PJ HBR')).toBeInTheDocument();
    expect(screen.getByText(/Pix enviado para Roberto · Diárias de freelancers/)).toBeInTheDocument();
  });

  it('excluir não pergunta: apaga e oferece Desfazer, que registra o dia de novo como era', async () => {
    const user = userEvent.setup();
    const apagado = { favorecido_id: 'r', data: '2026-09-16', jornada: 'inteiro', valor_diaria: 160, extras: 20,
                      descontos: 0, observacao: 'Gerador do Marcelo', os_ids: ['o1'] };
    apagar.mockResolvedValue({ apagado, message: 'Diária de Roberto em qua 16/09 apagada.' });
    registrar.mockResolvedValue({ acao: 'criado', diaria_id: 'd2', message: 'ok' });
    renderizar('extrato');

    await user.click(screen.getByRole('button', { name: /Mais ações para dia qua 16\/09/i }));
    await user.click(await screen.findByRole('menuitem', { name: /Excluir o dia/ }));

    expect(apagar).toHaveBeenCalledWith('d1');
    const [mensagem, opcoes] = toastFn.mock.calls[0] as [string, { action: { label: string; onClick: () => void } }];
    expect(mensagem).toMatch(/apagada/);
    expect(opcoes.action.label).toBe('Desfazer');
    opcoes.action.onClick();
    expect(registrar).toHaveBeenCalledWith({
      favorecidoId: 'r', data: '2026-09-16', jornada: 'inteiro', osIds: ['o1'], observacao: 'Gerador do Marcelo',
      extras: 20, descontos: 0, valorDiaria: 160,
    });
  });
});

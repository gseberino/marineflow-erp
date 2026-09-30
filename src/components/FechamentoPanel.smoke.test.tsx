// Fechamento: a conferência de saldo mostra a situação de HOJE de cada conta.
//
// Antes, a tela contava as 50 últimas conferências e dizia "N não fecharam". Em 25/09/2026
// isso mostraria seis falhas do C6 causadas por um erro de conta já corrigido (débito
// somando em vez de subtrair). O que decide se dá para fechar o mês é se cada conta
// confere agora — e é isso que este teste fixa.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import { FechamentoPanel } from './FechamentoPanel';

const { conferencias, checklist } = vi.hoisted(() => ({
  checklist: { atual: { pronto: false, itens: [
    { chave: 'saldo_confere', titulo: 'O saldo de cada conta confere com o banco', ok: true, bloqueia: true, quantidade: 0, detalhe: 'Todas conferem.' },
    { chave: 'extrato_tratado', titulo: 'Todo movimento do banco no mês tem destino', ok: false, bloqueia: true, quantidade: 36, detalhe: '36 linha(s) esperando no Extrato.' },
    { chave: 'outras_despesas', titulo: 'Pouco em "Outras despesas"', ok: false, bloqueia: false, quantidade: 2, detalhe: '2 lançamentos.' },
  ] } as { pronto: boolean; itens: unknown[] } },
  conferencias: [
    // Mais recentes primeiro, como a consulta devolve.
    { id: 'c6-hoje', conferido_em: '2026-09-25T21:00:00Z', diferenca: 0, fecha: true, observacao: null, bank_connection_id: 'c6', saldo_do_provedor: 1386.61, saldo_calculado: 1386.61 },
    { id: 'nu-hoje', conferido_em: '2026-09-25T21:00:00Z', diferenca: -250, fecha: false, observacao: null, bank_connection_id: 'nu', saldo_do_provedor: 0, saldo_calculado: 250 },
    { id: 'c6-ontem', conferido_em: '2026-09-24T09:00:00Z', diferenca: -11053.7, fecha: false, observacao: '[Conta errada, corrigida em 25/09/2026: débitos eram somados]', bank_connection_id: 'c6', saldo_do_provedor: 1636.61, saldo_calculado: 12690.31 },
    { id: 'c6-anteontem', conferido_em: '2026-09-23T09:00:00Z', diferenca: -9183.5, fecha: false, observacao: '[Conta errada, corrigida em 25/09/2026: débitos eram somados]', bank_connection_id: 'c6', saldo_do_provedor: 2571.71, saldo_calculado: 11755.21 },
  ],
}));

vi.mock('@/hooks/use-fechamento', () => ({
  usePeriodosFechados: () => ({ data: [], isLoading: false }),
  useFecharPeriodo: () => ({ mutate: vi.fn(), isPending: false }),
  useReabrirPeriodo: () => ({ mutate: vi.fn(), isPending: false }),
  useTrilhaDeConciliacao: () => ({
    data: [{ id: 't1', ocorrido_em: '2026-09-25T17:00:00Z', acao: 'cancelou_lancamento', valor: 1111.44, detalhe: 'Compra parcelada lançada em dobro', autor: null }],
  }),
  useConferenciasDeSaldo: () => ({ data: conferencias }),
  useChecklistDoMes: () => ({ isLoading: false, data: checklist.atual }),
  useLinhasDoChecklist: (_a: number, _m: number, chave: string | null) => ({
    isLoading: false, error: null,
    data: chave === 'extrato_tratado'
      ? [{ tipo: 'extrato', id: 't1', data: '2026-08-12', valor: -350, descricao: 'Pix enviado para Kamell', quem: 'KAMELL', detalhe: 'Saída esperando destino no Extrato.' }]
      : chave === 'outras_despesas'
        ? [{ tipo: 'payable', id: 'p1', data: '2026-08-03', valor: -12.5, descricao: 'Tarifa', quem: null, detalhe: null }]
        : [],
  }),
  ROTULO_DA_ACAO: { cancelou_lancamento: 'Cancelou lançamento' },
}));

const demonstrativo = vi.hoisted(() => ({ gerar: vi.fn() }));
vi.mock('@/hooks/use-demonstrativo-do-mes', () => ({
  useDemonstrativoDoMes: () => ({ gerar: demonstrativo.gerar, gerando: false }),
}));

vi.mock('@/hooks/use-bank-connections', () => ({
  useBankConnections: () => ({ data: [{ id: 'c6', label: 'C6 - Conta PJ HBR' }, { id: 'nu', label: 'Nubank PJ HBR' }] }),
}));

function renderPainel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MemoryRouter>
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <FechamentoPanel />
      </I18nProvider>
    </QueryClientProvider>
    </MemoryRouter>,
  );
}

describe('FechamentoPanel — conferência de saldo', () => {
  it('conta só a situação atual: o C6 confere hoje, as falhas antigas não contam', () => {
    renderPainel();
    // Só o Nubank difere hoje. As duas falhas antigas do C6 não viram "3 não fecharam".
    expect(screen.getByText(/Uma conta não confere/)).toBeInTheDocument();
    expect(screen.queryByText(/3 contas/)).not.toBeInTheDocument();
  });

  it('cada conta aparece uma vez, com o nome e a situação', () => {
    renderPainel();
    expect(screen.getAllByText('C6 - Conta PJ HBR')).toHaveLength(1);
    expect(screen.getByText('confere')).toBeInTheDocument();
    expect(screen.getByText((texto) => texto.startsWith('difere '))).toBeInTheDocument();
  });

  it('a trilha nomeia o cancelamento em português', () => {
    renderPainel();
    expect(screen.getByText('Cancelou lançamento')).toBeInTheDocument();
  });

  it('o mês que não está pronto não fecha no botão principal, e diz por quê', () => {
    renderPainel();
    expect(screen.getByText('Ainda não.')).toBeInTheDocument();
    expect(screen.getByText('36 linha(s) esperando no Extrato.')).toBeInTheDocument();
    expect(screen.getByText(/\(aviso\)/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^Fechar [a-zç]+\/\d{4}$/ })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Fechar mesmo assim…' })).toBeInTheDocument();
  });
});

describe('FechamentoPanel — demonstrativo do mês', () => {
  it('o botão gera o demonstrativo do mês escolhido, dizendo se está fechado', () => {
    renderPainel();
    const botao = screen.getByRole('button', { name: /Demonstrativo de .+ \(PDF\)/ });
    fireEvent.click(botao);
    expect(demonstrativo.gerar).toHaveBeenCalledTimes(1);
    const [ano, mes, fechado] = demonstrativo.gerar.mock.calls[0];
    expect(typeof ano).toBe('number');
    expect(mes).toBeGreaterThanOrEqual(1);
    expect(fechado).toBe(false);
  });
});

describe('FechamentoPanel — Ver as linhas de um aviso', () => {
  it('o aviso com pendência abre a lista; lançamento tem Corrigir; linha do banco leva ao Extrato', () => {
    renderPainel();
    // Item OK não tem botão; item com pendência tem "Ver N".
    expect(screen.queryByRole('button', { name: 'Ver 0' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Ver 36' }));
    expect(screen.getByText('Pix enviado para Kamell')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Abrir a fila do Extrato' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Corrigir' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Fechar' }));

    fireEvent.click(screen.getByRole('button', { name: 'Ver 2' }));
    expect(screen.getByText('Tarifa')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Corrigir' })).toBeInTheDocument();
  });
});

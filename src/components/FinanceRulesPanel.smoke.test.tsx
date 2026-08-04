// Smoke de render das regras do financeiro.
//
// O que importa provar aqui é a separação entre o que o gestor mandou e o que o sistema
// achou: uma regra proposta pela IA NÃO pode aparecer como se estivesse valendo. Build e
// tsc passariam com as duas listas trocadas, e o efeito seria o sistema classificando
// despesas por um palpite que ninguém aprovou.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { FinanceRulesPanel, frasearRegra } from './FinanceRulesPanel';
import type { RegraFinanceira } from '@/hooks/use-finance-review';

const { regras, mudarStatusMock, proporMock, lancamentos } = vi.hoisted(() => ({
  lancamentos: [
    { id: 'l1', description: 'Parafusos e fixadores', amount: 1240, issue_date: '2026-07-12',
      expense_category: 'Ferramentas e equipamentos', supplier_name: null, fornecedor: 'Coremma Ltda',
      contraparte: null, documento: '12345678000190', banco: '336', meio: 'PIX' },
    { id: 'l2', description: 'Juros de dívida encerrada', amount: 18.4, issue_date: '2026-07-02',
      expense_category: 'Juros e encargos', supplier_name: null, fornecedor: null,
      contraparte: null, documento: null, banco: null, meio: null },
  ],
  mudarStatusMock: vi.fn(),
  proporMock: vi.fn(),
  regras: [
    {
      id: 'r1', match_type: 'counterparty', match_value: 'GUSTAVO SEBERINO DA SILVA',
      direction: 'debit', min_amount: null, max_amount: null,
      set_category: 'Pró-labore e retiradas', set_dre_group: 'nao_operacional', set_supplier_id: null,
      autonomy: 'apply', origin: 'user', status: 'active', reasoning: null, note: null,
      times_applied: 12, last_applied_at: '2026-07-28T10:00:00Z', created_at: '2026-07-01T10:00:00Z',
    },
    {
      id: 'r2', match_type: 'supplier', match_value: 'f-marine',
      direction: 'debit', min_amount: null, max_amount: null,
      set_category: 'Frete e importação', set_dre_group: 'custo_direto', set_supplier_id: 'f-marine',
      autonomy: 'suggest', origin: 'ai', status: 'proposed',
      reasoning: 'As últimas 6 despesas de Marine Express foram lançadas como Frete e importação, sem exceção.',
      note: null, times_applied: 0, last_applied_at: null, created_at: '2026-07-29T10:00:00Z',
    },
    {
      id: 'r3', match_type: 'text', match_value: 'POSTO',
      direction: 'debit', min_amount: null, max_amount: null,
      set_category: 'Combustível e deslocamento', set_dre_group: 'custo_direto', set_supplier_id: null,
      autonomy: 'suggest', origin: 'user', status: 'paused', reasoning: null, note: null,
      times_applied: 3, last_applied_at: null, created_at: '2026-07-10T10:00:00Z',
    },
  ] as RegraFinanceira[],
}));

vi.mock('@/hooks/use-finance-review', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-finance-review')>();
  return {
    ...real,
    useFinanceRules: () => ({ data: regras, isLoading: false }),
    useSalvarRegra: () => ({ mutate: vi.fn(), isPending: false }),
    useMudarStatusRegra: () => ({ mutate: mudarStatusMock, isPending: false }),
    useProporRegras: () => ({ mutate: proporMock, isPending: false }),
    useLancamentosDaRegra: () => ({ data: lancamentos, isLoading: false }),
  };
});

vi.mock('@/hooks/use-suppliers', () => ({
  useSuppliers: () => ({ data: [{ id: 'f-marine', name: 'Marine Express' }], isLoading: false }),
}));

vi.mock('@/hooks/use-financial-categories', () => ({
  useFinancialCategories: () => ({
    data: [{ name: 'Frete e importação', dre_group: 'custo_direto' }], isLoading: false,
  }),
}));

function renderPainel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><FinanceRulesPanel /></I18nProvider>
    </QueryClientProvider>,
  );
}

describe('FinanceRulesPanel', () => {
  it('não mistura o que vale agora com o que o sistema apenas sugeriu', async () => {
    renderPainel();
    expect(await screen.findByText(/O sistema notou um padrão e sugere \(1\)/)).toBeInTheDocument();
    expect(screen.getByText(/Valendo agora \(1\)/)).toBeInTheDocument();
    expect(screen.getByText(/Pausadas \(1\)/)).toBeInTheDocument();
  });

  it('mostra o motivo da sugestão — aceitar sem motivo é apostar', async () => {
    renderPainel();
    expect(await screen.findByText(/6 despesas de Marine Express/)).toBeInTheDocument();
  });

  it('sinaliza qual regra age sozinha', async () => {
    renderPainel();
    expect(await screen.findByText('Lança sozinha')).toBeInTheDocument();
  });

  it('mostra quanto a regra já trabalhou', async () => {
    renderPainel();
    expect(await screen.findByText(/aplicada 12x/)).toBeInTheDocument();
  });

  it('aceitar uma sugestão a torna ativa, não a apaga', async () => {
    const user = userEvent.setup();
    renderPainel();
    const aceitar = await screen.findByTitle('Aceitar');
    await user.click(aceitar);
    expect(mudarStatusMock).toHaveBeenCalledWith({ id: 'r2', status: 'active' });
  });

  it('recusar marca como recusada, para não voltar a ser sugerida', async () => {
    const user = userEvent.setup();
    renderPainel();
    await user.click(await screen.findByTitle('Recusar'));
    expect(mudarStatusMock).toHaveBeenCalledWith({ id: 'r2', status: 'rejected' });
  });
});

describe('frase da regra', () => {
  const base: RegraFinanceira = {
    id: 'x', match_type: 'counterparty', match_value: 'FULANO', direction: 'debit',
    min_amount: null, max_amount: null, set_category: 'Pró-labore', set_dre_group: null,
    set_supplier_id: null, autonomy: 'suggest', origin: 'user', status: 'active',
    reasoning: null, note: null, times_applied: 0, last_applied_at: null, created_at: '',
  };

  it('descreve o alvo em português, não em nome de campo', () => {
    expect(frasearRegra(base)).toBe('pagamentos para "FULANO" → Pró-labore');
  });

  it('inclui a faixa de valor quando existe', () => {
    expect(frasearRegra({ ...base, min_amount: 1000 })).toContain('acima de R$ 1000');
    expect(frasearRegra({ ...base, max_amount: 50 })).toContain('até R$ 50');
  });

  it('usa o nome do fornecedor quando a regra é por fornecedor', () => {
    const r = { ...base, match_type: 'supplier' as const, match_value: 'f-1' };
    expect(frasearRegra(r, 'Marine Express')).toContain('Marine Express');
  });
});

describe('histórico que embasa a regra', () => {
  // Sem ver as transações, aceitar uma regra é confiar num resumo. O resumo esconde o que
  // muda a decisão: valor fora da curva, ou um lançamento de outro fornecedor parecido.
  it('mostra data, favorecido, descrição, categoria e valor', async () => {
    renderPainel();
    // O formato da data é decisão do i18n e muda com o locale — o que precisa estar lá é
    // uma data, não uma grafia específica.
    // Uma data por lançamento — o formato em si é decisão do i18n e muda com o locale.
    expect((await screen.findAllByText(/2026/)).length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText('Coremma Ltda')).toBeInTheDocument();
    expect(screen.getByText(/Parafusos e fixadores/)).toBeInTheDocument();
    expect(screen.getByText(/1\.240,00/)).toBeInTheDocument();
  });

  it('diz que é operação do banco quando não há favorecido', async () => {
    // "Juros de dívida encerrada" não tem para quem — e célula vazia parece dado faltando,
    // não ausência legítima.
    renderPainel();
    expect(await screen.findByText(/sem favorecido — operação do banco/)).toBeInTheDocument();
  });

  it('mostra o documento e o banco de quem recebeu, quando existem', async () => {
    renderPainel();
    expect(await screen.findByText(/12\.345\.678\/0001-90/)).toBeInTheDocument();
  });

  it('avisa quando o histórico tem mais de uma categoria', async () => {
    // É o sinal de que a "unanimidade" alegada pela sugestão não é real.
    renderPainel();
    expect(await screen.findByText(/2 categorias diferentes/)).toBeInTheDocument();
  });

  it('soma o total do histórico', async () => {
    renderPainel();
    expect(await screen.findByText(/Total/)).toBeInTheDocument();
  });
});

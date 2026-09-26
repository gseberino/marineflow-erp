// Smoke de render do Financeiro v2 — um cômodo por assunto (26/09/2026).
//
// Antes, toda rota /v2/financial/<secao> mostrava a MESMA barra com 14 abas; o dono achou
// "abas demais". O que este teste guarda:
//   · cada rota abre SÓ o seu assunto, com título próprio e, no máximo, um nível de abas;
//   · os links antigos (?tab=, /cartoes, /rules, /fechamento, /dre…) chegam ao lugar novo;
//   · aba troca a rota sem sair do cômodo (a regressão de 30/07 era aba que levava embora);
//   · "+ Lançar" em toda tela, ?lancar= abrindo direto, e a semente de regra do Extrato.
// tsc e build passam com qualquer um desses quebrado — só o render mostra.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import FinancialV2 from './FinancialV2';

// O roteador é real de propósito: trocar de aba MUDA a URL, e o que se protege é que ela
// continue dentro do Financeiro. Um mock de navigate esconderia exatamente isso.
const rotaAtual = { caminho: '' };
function EspiaoDeRota() {
  const l = useLocation();
  rotaAtual.caminho = l.pathname + l.search;
  return null;
}

const vazio = { data: [], isLoading: false, error: null };
vi.mock('@/hooks/use-financial', () => ({
  useReceivables: () => vazio,
  usePayables: () => vazio,
  useFinancialSummary: () => ({
    data: { total_receivable: 0, overdue_receivable: 0, total_payable: 0, overdue_payable: 0, entrou_no_mes: 12367.99, saiu_no_mes: 8873.35 },
    isLoading: false, error: null,
  }),
  useCashFlow: () => ({ data: [{ month: 'Set/26', inflow: 12367.99, outflow: 8873.35, net: 3494.64 }] }),
}));
vi.mock('@/hooks/use-fluxo-de-caixa', () => ({
  useFluxoDeCaixa: () => ({
    data: {
      meses: [],
      total: { entrou: 12367.99, saiu: 8873.35, liquido: 3494.64, quantidade: 33, transferencias: { entrou: 0, saiu: 153 }, creditoDoCartao: { entrou: 0, saiu: 0 } },
      deFora: {},
    },
  }),
}));
vi.mock('@/hooks/use-service-order-expenses', () => ({
  usePendingReimbursements: () => ({ data: [{ id: 'r1' }, { id: 'r2' }] }),
}));

// Os painéis não são o objeto do teste: o que importa é que cada rota e cada aba os alcança.
vi.mock('@/components/ConciliacaoPanel', () => ({ ConciliacaoPanel: () => <div>painel conciliação</div> }));
vi.mock('@/components/FechamentoPanel', () => ({ FechamentoPanel: () => <div>painel fechamento</div> }));
vi.mock('@/components/BankSourcesPanel', () => ({ BankSourcesPanel: () => <div>painel contas</div> }));
vi.mock('@/components/CartoesPanel', () => ({ CartoesPanel: () => <div>painel cartões</div> }));
vi.mock('@/components/SaudeDoCadastroPanel', () => ({ SaudeDoCadastroPanel: () => <div>painel saúde do cadastro</div> }));
vi.mock('@/components/DespesasPanel', () => ({ DespesasPanel: () => <div>painel despesas</div> }));
vi.mock('@/components/ReimbursementsPanel', () => ({ ReimbursementsPanel: () => <div>painel reembolsos</div> }));
vi.mock('@/v2/pages/CommissionsV2', () => ({ PainelDeComissoes: () => <div>painel comissões</div> }));
vi.mock('@/components/FinanceRulesPanel', () => ({
  FinanceRulesPanel: () => <div>painel regras</div>,
  EditorDeRegra: ({ regra }: { regra: { match_value: string } }) => <div>editor de regra {regra.match_value}</div>,
}));
// O Extrato por conta tem teste próprio; aqui ele mostra a visão e a conta que recebeu, e
// deixa escolher conta e criar regra, para provar que a tela passa as duas coisas adiante.
vi.mock('@/components/ExtratoPorConta', () => ({
  ExtratoPorConta: ({ visao, contaId, onEscolherConta, onCriarRegra }: {
    visao: string; contaId: string | null; onEscolherConta: (id: string | null) => void;
    onCriarRegra: (s: { match_value: string }) => void;
  }) => (
    <div>
      <p>extrato visão {visao} conta {contaId ?? 'todas'}</p>
      <button type="button" onClick={() => onEscolherConta('c6')}>escolher C6</button>
      <button type="button" onClick={() => onCriarRegra({ match_value: 'POSTO' })}>criar regra</button>
    </div>
  ),
}));
vi.mock('@/components/FinancialFilterPanel', () => ({
  FinancialFilterPanel: () => <div>filtros</div>,
  applyFilters: (rows: unknown[]) => rows,
  defaultFilters: {},
}));
vi.mock('@/components/PaymentDialog', () => ({ PaymentDialog: () => null }));
vi.mock('@/components/DesfazerOuCancelarDialog', () => ({ DesfazerOuCancelarDialog: () => null }));
vi.mock('@/components/LancarDialog', () => ({
  LancarDialog: ({ tipoInicial, porOndeInicial }: { tipoInicial?: string; porOndeInicial?: string }) =>
    <div>janela lançar {tipoInicial ?? 'despesa'} {porOndeInicial ?? ''}</div>,
}));
vi.mock('@/components/SaldosDasContas', () => ({ SaldosDasContas: () => <div>fichas de saldo</div> }));

function renderFinanceiro(inicio = '/v2/financial') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[inicio]}>
          <EspiaoDeRota />
          <Routes>
            {/* O mesmo desenho do App: uma rota só, com segmentos opcionais. */}
            <Route path="/v2/financial/:secao?/:aba?" element={<FinancialV2 />} />
            <Route path="*" element={<div>fora do financeiro</div>} />
          </Routes>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

const abas = () => screen.queryAllByRole('tab').map((a) => a.textContent?.trim());

describe('Financeiro — um cômodo por assunto', () => {
  it('a barra de 14 abas acabou: nenhuma tela mostra DRE, Aging ou Programação como aba', async () => {
    for (const rota of ['/v2/financial', '/v2/financial/inbox', '/v2/financial/reconciliation', '/v2/financial/payables', '/v2/financial/despesas', '/v2/financial/banks']) {
      const { unmount } = renderFinanceiro(rota);
      await screen.findByRole('heading', { level: 1 });
      for (const velha of ['DRE / Avançado', 'Aging', 'Programação', 'Saúde do cadastro', 'Contas bancárias']) {
        expect(abas(), `"${velha}" voltou como aba em ${rota}`).not.toContain(velha);
      }
      expect(abas().length, `${rota} tem abas demais`).toBeLessThanOrEqual(5);
      unmount();
    }
  });

  it('Visão Geral: título próprio, sem abas, e o fluxo pelo extrato', async () => {
    renderFinanceiro('/v2/financial');
    expect(await screen.findByRole('heading', { level: 1, name: 'Visão Geral' })).toBeInTheDocument();
    expect(abas()).toEqual([]);
    expect(screen.getByText('Entrou no mês (extrato)')).toBeInTheDocument();
    expect(screen.getByText('Saiu no mês (extrato)')).toBeInTheDocument();
    expect(screen.getByText('R$ 12.367,99')).toBeInTheDocument();
    // O "?" explica de onde vem o número.
    expect(screen.getByRole('button', { name: 'De onde vem o Entrou no mês' })).toBeInTheDocument();
    // O que ficou à parte é dito, não escondido.
    expect(screen.getByText(/Ficaram à parte, sem somar em Entrou e Saiu: transferências entre contas suas/)).toBeInTheDocument();
  });

  it('Extrato: as cinco abas do dono, nesta ordem, e cada uma alcança o seu painel', async () => {
    const user = userEvent.setup();
    const { container } = renderFinanceiro('/v2/financial/inbox');
    expect(await screen.findByRole('heading', { level: 1, name: 'Extrato' })).toBeInTheDocument();
    expect(abas()).toEqual(['Para revisar', 'Extrato com saldo', 'Fora da fila', 'Cartão de crédito', 'Regras']);
    expect(screen.getByText('extrato visão revisar conta todas')).toBeInTheDocument();

    for (const [aba, rota, texto] of [
      ['Extrato com saldo', '/v2/financial/inbox/saldo', 'extrato visão saldo'],
      ['Fora da fila', '/v2/financial/inbox/fora', 'extrato visão fora'],
      ['Cartão de crédito', '/v2/financial/inbox/cartao', 'painel cartões'],
      ['Regras', '/v2/financial/inbox/regras', 'painel regras'],
      ['Para revisar', '/v2/financial/inbox', 'extrato visão revisar'],
    ] as const) {
      await user.click(screen.getByRole('tab', { name: aba }));
      expect(rotaAtual.caminho).toBe(rota);
      expect(await screen.findByText(new RegExp(texto))).toBeInTheDocument();
      const painel = container.querySelector('[role="tabpanel"][data-state="active"]');
      expect(painel?.textContent?.trim().length, `aba "${aba}" abre vazia`).toBeGreaterThan(0);
    }
  });

  it('Extrato: a conta escolhida nas fichas sobrevive à troca de aba', async () => {
    const user = userEvent.setup();
    renderFinanceiro('/v2/financial/inbox');
    await user.click(await screen.findByRole('button', { name: 'escolher C6' }));
    expect(screen.getByText('extrato visão revisar conta c6')).toBeInTheDocument();
    await user.click(screen.getByRole('tab', { name: 'Extrato com saldo' }));
    expect(await screen.findByText('extrato visão saldo conta c6')).toBeInTheDocument();
  });

  it('Extrato: "criar regra" de uma linha abre o editor já preenchido', async () => {
    const user = userEvent.setup();
    renderFinanceiro('/v2/financial/inbox');
    await user.click(await screen.findByRole('button', { name: 'criar regra' }));
    expect(screen.getByText('editor de regra POSTO')).toBeInTheDocument();
  });

  it('Conciliação: Conciliação · Fechar o mês', async () => {
    const user = userEvent.setup();
    renderFinanceiro('/v2/financial/reconciliation');
    expect(await screen.findByRole('heading', { level: 1, name: 'Conciliação' })).toBeInTheDocument();
    expect(abas()).toEqual(['Conciliação', 'Fechar o mês']);
    expect(screen.getByText('painel conciliação')).toBeInTheDocument();
    await user.click(screen.getByRole('tab', { name: 'Fechar o mês' }));
    expect(rotaAtual.caminho).toBe('/v2/financial/reconciliation/fechar');
    expect(await screen.findByText('painel fechamento')).toBeInTheDocument();
  });

  it('Contas a Pagar: Em aberto · Reembolsos (com a contagem) · Comissões', async () => {
    const user = userEvent.setup();
    renderFinanceiro('/v2/financial/payables');
    expect(await screen.findByRole('heading', { level: 1, name: 'Contas a Pagar' })).toBeInTheDocument();
    expect(abas()).toEqual(['Em aberto', 'Reembolsos (2)', 'Comissões']);
    expect(screen.getByRole('button', { name: /Nova conta a pagar/ })).toBeInTheDocument();
    await user.click(screen.getByRole('tab', { name: 'Reembolsos (2)' }));
    expect(await screen.findByText('painel reembolsos')).toBeInTheDocument();
    await user.click(screen.getByRole('tab', { name: 'Comissões' }));
    expect(rotaAtual.caminho).toBe('/v2/financial/payables/comissoes');
    expect(await screen.findByText('painel comissões')).toBeInTheDocument();
  });

  it('"Nova conta a pagar" abre o "+ Lançar" já em despesa a pagar depois', async () => {
    const user = userEvent.setup();
    renderFinanceiro('/v2/financial/payables');
    await user.click(await screen.findByRole('button', { name: /Nova conta a pagar/ }));
    expect(screen.getByText('janela lançar despesa depois')).toBeInTheDocument();
  });

  it('Despesas, Contas bancárias e Saúde do cadastro: uma tela cada, sem abas', async () => {
    for (const [rota, titulo, painel] of [
      ['/v2/financial/despesas', 'Despesas', 'painel despesas'],
      ['/v2/financial/banks', 'Contas bancárias', 'painel contas'],
      ['/v2/financial/cadastro', 'Saúde do cadastro', 'painel saúde do cadastro'],
    ] as const) {
      const { unmount } = renderFinanceiro(rota);
      expect(await screen.findByRole('heading', { level: 1, name: titulo })).toBeInTheDocument();
      expect(screen.getByText(painel)).toBeInTheDocument();
      expect(abas()).toEqual([]);
      unmount();
    }
  });

  it('a rota antiga da Saúde do cadastro continua abrindo o painel e diz onde ele mora agora', async () => {
    renderFinanceiro('/v2/financial/cadastro');
    const link = await screen.findByRole('link', { name: /Fornecedores › Saúde do cadastro/ });
    expect(link).toHaveAttribute('href', '/v2/suppliers/saude');
  });

  it('cada tela tem breadcrumb "Financeiro › nome" e diz para que serve', async () => {
    renderFinanceiro('/v2/financial/inbox/regras');
    const trilha = await screen.findByRole('navigation', { name: 'Trilha de navegação' });
    expect(trilha).toHaveTextContent('Financeiro/Extrato');
    expect(screen.getByText(/O que você ensinou o sistema a classificar/)).toBeInTheDocument();
  });

  it('"+ Lançar" está no topo de toda tela do Financeiro', async () => {
    const user = userEvent.setup();
    for (const rota of ['/v2/financial', '/v2/financial/inbox/cartao', '/v2/financial/reconciliation/fechar', '/v2/financial/payables/comissoes', '/v2/financial/despesas', '/v2/financial/banks']) {
      const { unmount } = renderFinanceiro(rota);
      await user.click(await screen.findByRole('button', { name: /^Lançar$/ }));
      expect(screen.getByText(/janela lançar despesa/)).toBeInTheDocument();
      unmount();
    }
  });

  it('link com ?lancar=recebimento abre a janela já em Recebimento', async () => {
    renderFinanceiro('/v2/financial?lancar=recebimento');
    expect(await screen.findByText(/janela lançar recebimento/)).toBeInTheDocument();
  });

  it('oferece a saída para a versão anterior durante a transição', async () => {
    renderFinanceiro('/v2/financial/despesas');
    const link = await screen.findByRole('link', { name: /versão anterior/i });
    // Sem o ?legacy=1 a rota antiga redirecionaria de volta para cá, em laço.
    expect(link).toHaveAttribute('href', '/financial?legacy=1');
  });

  it('mostra o aviso de que as abas mudaram de lugar', async () => {
    renderFinanceiro('/v2/financial/inbox');
    expect(await screen.findByText('As abas mudaram de lugar.')).toBeInTheDocument();
  });
});

describe('Financeiro — links antigos levam ao lugar novo', () => {
  it.each([
    ['/v2/financial?tab=inbox', '/v2/financial/inbox', /extrato visão revisar/],
    ['/v2/financial?tab=payables', '/v2/financial/payables', /Nova conta a pagar/],
    ['/v2/financial?tab=overview', '/v2/financial', /Entrou no mês \(extrato\)/],
    ['/v2/financial/extrato', '/v2/financial/inbox', /extrato visão revisar/],
    ['/v2/financial/ignoradas', '/v2/financial/inbox/fora', /extrato visão fora/],
    ['/v2/financial/cartoes', '/v2/financial/inbox/cartao', /painel cartões/],
    ['/v2/financial/rules', '/v2/financial/inbox/regras', /painel regras/],
    ['/v2/financial/fechamento', '/v2/financial/reconciliation/fechar', /painel fechamento/],
    ['/v2/financial/comissoes', '/v2/financial/payables/comissoes', /painel comissões/],
    ['/v2/financial/overview', '/v2/financial', /Entrou no mês \(extrato\)/],
    ['/v2/financial/nao-existe', '/v2/financial', /Entrou no mês \(extrato\)/],
    ['/v2/financial/inbox/nao-existe', '/v2/financial/inbox', /extrato visão revisar/],
    ['/v2/financial/despesas/sobra', '/v2/financial/despesas', /painel despesas/],
  ])('%s → %s', async (antigo, novo, texto) => {
    renderFinanceiro(antigo);
    expect(await screen.findByText(texto)).toBeInTheDocument();
    expect(rotaAtual.caminho).toBe(novo);
  });

  it.each([
    ['/v2/financial/dre', '/v2/reports/dre'],
    ['/v2/financial/aging', '/v2/reports/aging'],
    ['/v2/financial/forecast', '/v2/reports/fluxo'],
    ['/v2/financial?tab=dre', '/v2/reports/dre'],
    ['/v2/financial?tab=receivables', '/v2/receivables'],
  ])('%s sai do Financeiro para %s', async (antigo, novo) => {
    renderFinanceiro(antigo);
    expect(await screen.findByText('fora do financeiro')).toBeInTheDocument();
    expect(rotaAtual.caminho).toBe(novo);
  });

  it('o resto da query atravessa o redirecionamento (?lancar= do assistente)', async () => {
    renderFinanceiro('/v2/financial?tab=payables&lancar=despesa');
    expect(await screen.findByText(/janela lançar despesa/)).toBeInTheDocument();
    expect(rotaAtual.caminho).toBe('/v2/financial/payables?lancar=despesa');
  });
});

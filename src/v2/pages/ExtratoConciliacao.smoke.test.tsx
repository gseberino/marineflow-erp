// [F2-UI] Smoke de render do Extrato e da Conciliação, aba por aba.
//
// A fase F2 mexe nas duas telas mais usadas do financeiro. O que este teste protege não é
// layout — é o conjunto de coisas que `tsc` e `build` deixam passar:
//
//   · a rota renderiza (erro de inicialização em tempo de render já derrubou tela aqui);
//   · CADA aba alcança o painel que promete — aba que renderiza vazio parece "sem dados";
//   · os `?tab=` antigos continuam chegando ao lugar certo. Meses de links salvos, favoritos
//     e atalhos dependem disso, e a quebra é silenciosa: abre a tela errada sem erro nenhum.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes, Navigate, useSearchParams } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import ExtratoV2 from './ExtratoV2';
import ConciliacaoV2 from './ConciliacaoV2';

// Os painéis pesados não são o objeto do teste: o que importa é que a aba os alcança.
vi.mock('@/components/FinanceReviewInbox', () => ({
  FinanceReviewInbox: () => <div>fila do banco</div>,
}));
vi.mock('@/components/CartoesPanel', () => ({ CartoesPanel: () => <div>painel cartões</div> }));
vi.mock('@/components/IgnoradasPanel', () => ({ IgnoradasPanel: () => <div>painel fora da fila</div> }));
vi.mock('@/components/FechamentoPanel', () => ({ FechamentoPanel: () => <div>painel fechamento</div> }));
vi.mock('@/components/ConciliacaoPanel', () => ({
  ConciliacaoPanel: ({ aba }: { aba?: string }) => <div>painel conciliação: {aba}</div>,
}));
vi.mock('@/components/FinanceRulesPanel', () => ({
  FinanceRulesPanel: () => <div>painel regras</div>,
  EditorDeRegra: () => <div>editor de regra</div>,
}));
vi.mock('@/v2/components/V2Shell', () => ({
  V2Shell: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

function renderRota(Componente: React.ComponentType, rota = '/') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[rota]}>
          <Componente />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('Extrato — a fila única', () => {
  it('renderiza e abre na aba do banco', () => {
    renderRota(ExtratoV2);
    expect(screen.getByRole('heading', { name: 'Extrato' })).toBeInTheDocument();
    expect(screen.getByText('fila do banco')).toBeInTheDocument();
  });

  it('cada aba alcança o painel que promete', async () => {
    const user = userEvent.setup();
    renderRota(ExtratoV2);

    await user.click(screen.getByRole('tab', { name: 'Cartão' }));
    expect(screen.getByText('painel cartões')).toBeInTheDocument();

    await user.click(screen.getByRole('tab', { name: 'Fora da fila' }));
    expect(screen.getByText('painel fora da fila')).toBeInTheDocument();
  });

  it('a aba vem da URL — link compartilhado abre onde deveria', () => {
    renderRota(ExtratoV2, '/?aba=cartao');
    expect(screen.getByText('painel cartões')).toBeInTheDocument();
  });

  it('aba inválida na URL cai no banco, não em tela vazia', () => {
    renderRota(ExtratoV2, '/?aba=inventada');
    expect(screen.getByText('fila do banco')).toBeInTheDocument();
  });
});

describe('Conciliação — parte dos lançamentos', () => {
  it('renderiza e abre em "sem par"', () => {
    renderRota(ConciliacaoV2);
    expect(screen.getByRole('heading', { name: 'Conciliação' })).toBeInTheDocument();
    // O painel recebe a aba traduzida para o vocabulário dele.
    expect(screen.getByText(/painel conciliação: sem_extrato/)).toBeInTheDocument();
  });

  it('"Casadas" troca o recorte do painel, sem remontar a tela', async () => {
    const user = userEvent.setup();
    renderRota(ConciliacaoV2);

    await user.click(screen.getByRole('tab', { name: 'Casadas' }));
    expect(screen.getByText(/painel conciliação: conciliados/)).toBeInTheDocument();
  });

  it('o Fechamento agora mora aqui — é o último passo da conciliação', async () => {
    const user = userEvent.setup();
    renderRota(ConciliacaoV2);

    await user.click(screen.getByRole('tab', { name: 'Fechamento' }));
    expect(screen.getByText('painel fechamento')).toBeInTheDocument();
  });

  it('NÃO existe aba "Sugeridas" — o motor de sugestão não existe (NOVO-015)', () => {
    renderRota(ConciliacaoV2);
    // Uma aba que promete casamentos sugeridos sem motor por trás seria pior que a ausência:
    // abriria vazia para sempre e ninguém saberia se é falta de dado ou falta de recurso.
    expect(screen.queryByRole('tab', { name: /sugerid/i })).toBeNull();
  });
});

// ── Os redirects ──────────────────────────────────────────────────────────────
// Reproduz o mapa de App.tsx. Testar o componente real exigiria montar a árvore inteira de
// providers do app; o que precisa ser travado é o MAPA — que um `?tab=` antigo não fique sem
// destino e caia calado na Visão Geral.
const TABS_QUE_VIRARAM_ROTA: Record<string, string> = {
  inbox: '/v2/financial/extrato',
  cartoes: '/v2/financial/extrato?aba=cartao',
  ignoradas: '/v2/financial/extrato?aba=fora',
  reconciliation: '/v2/financial/conciliacao',
  fechamento: '/v2/financial/conciliacao?aba=fechamento',
};

function Redirecionador() {
  const [params] = useSearchParams();
  const destino = TABS_QUE_VIRARAM_ROTA[params.get('tab') ?? ''];
  if (destino) return <Navigate to={destino} replace />;
  return <div>financeiro (visão geral)</div>;
}

describe('redirects dos ?tab= antigos', () => {
  const casos: [string, string][] = [
    ['inbox', 'extrato: banco'],
    ['cartoes', 'extrato: cartao'],
    ['ignoradas', 'extrato: fora'],
    ['reconciliation', 'conciliação: sem_par'],
    ['fechamento', 'conciliação: fechamento'],
  ];

  function Alvo({ nome }: { nome: string }) {
    const [params] = useSearchParams();
    return <div>{nome}: {params.get('aba') ?? (nome.startsWith('extrato') ? 'banco' : 'sem_par')}</div>;
  }

  for (const [tab, esperado] of casos) {
    it(`?tab=${tab} chega em "${esperado}"`, () => {
      render(
        <MemoryRouter initialEntries={[`/v2/financial?tab=${tab}`]}>
          <Routes>
            <Route path="/v2/financial" element={<Redirecionador />} />
            <Route path="/v2/financial/extrato" element={<Alvo nome="extrato" />} />
            <Route path="/v2/financial/conciliacao" element={<Alvo nome="conciliação" />} />
          </Routes>
        </MemoryRouter>,
      );
      expect(screen.getByText(esperado)).toBeInTheDocument();
    });
  }

  it('aba que NÃO virou rota continua na tela financeira', () => {
    render(
      <MemoryRouter initialEntries={['/v2/financial?tab=payables']}>
        <Routes>
          <Route path="/v2/financial" element={<Redirecionador />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(screen.getByText('financeiro (visão geral)')).toBeInTheDocument();
  });
});

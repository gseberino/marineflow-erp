// Smoke do menu lateral depois da reestruturação do Financeiro (30/07/2026).
//
// O menu tem uma função só: dizer para onde se vai e onde se está. Quando vários itens
// moram na mesma rota e se distinguem pela aba (/v2/financial?tab=inbox), comparar apenas
// o pathname acende todos ao mesmo tempo — e aí o menu deixa de cumprir a única coisa que
// faz. tsc e build passam com isso; só o render mostra.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import { AppLayout } from './AppLayout';

vi.mock('@/hooks/use-auth', () => ({
  // O papel vive DENTRO de user — o menu lê user?.role para filtrar grupos e itens.
  useAuth: () => ({
    user: { id: 'u1', email: 'gestor@hbr.test', role: 'admin' },
    signOut: vi.fn(),
  }),
}));
vi.mock('@/hooks/use-agenda', () => ({ useSuggestions: () => ({ data: [] }) }));
vi.mock('@/hooks/use-finance-review', () => ({ useFinanceReviewCount: () => ({ data: 7 }) }));
vi.mock('@/hooks/use-push-notifications', () => ({
  usePushNotifications: () => {},
  requestPushPermission: vi.fn(),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: () => Promise.resolve({ data: null }) }),
      }),
    }),
  },
}));

// Sinos e widgets fazem as próprias consultas e não são o objeto do teste.
vi.mock('@/components/NotificationBell', () => ({ NotificationBell: () => null }));
vi.mock('@/components/WhatsAppBell', () => ({ WhatsAppBell: () => null }));
vi.mock('@/components/ai/PendingActionsBell', () => ({ PendingActionsBell: () => null }));
vi.mock('@/components/ai/AIAgentWidget', () => ({ AIAgentWidget: () => null }));
vi.mock('@/components/PWAInstallPrompt', () => ({ PWAInstallPrompt: () => null }));
vi.mock('@/components/OfflineIndicator', () => ({ OfflineIndicator: () => null }));
vi.mock('@/components/DiagnosticExportButton', () => ({ DiagnosticExportButton: () => null }));

function renderMenu(rota: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={[rota]}>
          <AppLayout><div>conteúdo</div></AppLayout>
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

/** Itens marcados como "onde estou". */
function ativos() {
  return screen.queryAllByRole('link', { current: 'page' }).map((el) => el.textContent?.trim());
}

describe('menu lateral — Financeiro reestruturado', () => {
  it('o grupo não tem mais um item com o próprio nome', async () => {
    renderMenu('/v2/financial');
    // "Financeiro > Financeiro" não informava nada; a página é a Visão Geral.
    const links = await screen.findAllByRole('link');
    const rotulos = links.map((l) => l.textContent?.trim());
    expect(rotulos).toContain('Visão Geral');
    expect(rotulos.filter((r) => r === 'Financeiro')).toHaveLength(0);
  });

  it('o trabalho diário virou destino do menu', async () => {
    renderMenu('/v2/financial');
    const links = (await screen.findAllByRole('link')).map((l) => l.textContent?.trim());
    for (const esperado of ['Extrato', 'Conciliação', 'Contas a Receber', 'Contas a Pagar']) {
      expect(links.some((l) => l?.includes(esperado)), `faltou "${esperado}"`).toBe(true);
    }
  });

  it('o item do menu usa o MESMO nome da aba para onde aponta', async () => {
    // A classe de erro: renomeei a aba "Caixa de entrada" para "Extrato" e esqueci o menu.
    // Os dois nomes passaram a conviver para o MESMO destino (?tab=inbox) — exatamente a
    // confusão que a reorganização veio desfazer. Nome antigo não pode voltar.
    renderMenu('/v2/financial');
    const links = (await screen.findAllByRole('link')).map((l) => l.textContent?.trim() ?? '');
    expect(links.some((l) => /Caixa de Entrada/i.test(l)), 'o nome antigo voltou ao menu').toBe(false);
  });

  it('[F2-UI] marca só o item da rota em que estou', () => {
    // Extrato e Conciliação deixaram de ser abas e viraram rota própria. O acendimento
    // passa a ser por pathname — mas o risco continua o mesmo: sem tratar a distinção,
    // Visão Geral acenderia junto, e o menu deixaria de dizer onde a pessoa está.
    renderMenu('/v2/financial/extrato');
    expect(ativos().filter((r) => r?.includes('Extrato'))).toHaveLength(1);
    expect(ativos().some((r) => r === 'Visão Geral')).toBe(false);
  });

  it('sem aba na URL, quem representa a página é a Visão Geral', () => {
    renderMenu('/v2/financial');
    expect(ativos()).toContain('Visão Geral');
  });

  it('mostra quantas propostas esperam decisão', async () => {
    renderMenu('/v2/financial');
    // Uma fila de aprovação que ninguém vê é uma fila que ninguém trabalha.
    const link = (await screen.findAllByRole('link')).find((l) => l.textContent?.includes('Extrato'));
    expect(within(link!).getByText('7')).toBeInTheDocument();
  });
});

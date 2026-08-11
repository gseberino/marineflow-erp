// Smoke de render do Financeiro v2 depois da migração de 30/07/2026.
//
// O que este teste protege é justamente o que o usuário reportou como "página bugada":
// a aba de Recebíveis NAVEGAVA para outra rota em vez de trocar de aba, e o efeito para
// quem usa era a tela inteira sumir ao clicar numa aba. tsc e build passam com isso —
// só o render mostra.
//
// Protege também a paridade que autorizou a virada: Caixa de entrada, Regras e Contas
// bancárias existiam apenas na v1, e migrar sem elas faria o usuário perder o trabalho
// da semana.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import FinancialV2 from './FinancialV2';

const { navigateMock } = vi.hoisted(() => ({ navigateMock: vi.fn() }));

vi.mock('react-router-dom', async (importOriginal) => {
  const real = await importOriginal<typeof import('react-router-dom')>();
  return { ...real, useNavigate: () => navigateMock };
});

const vazio = { data: [], isLoading: false, error: null };
vi.mock('@/hooks/use-financial', () => ({
  useReceivables: () => vazio,
  usePayables: () => vazio,
  useFinancialSummary: () => ({ data: null, isLoading: false, error: null }),
  useCashFlow: () => vazio,
  useReceivablesDSO: () => ({ data: null, isLoading: false }),
}));
vi.mock('@/hooks/use-service-order-expenses', () => ({
  usePendingReimbursements: () => vazio,
}));

// Os painéis pesados não são o objeto do teste: o que importa é que a aba os alcança.
vi.mock('@/components/ConciliacaoPanel', () => ({ ConciliacaoPanel: () => <div>painel conciliação</div> }));
vi.mock('@/components/BankSourcesPanel', () => ({ BankSourcesPanel: () => <div>painel contas</div> }));
vi.mock('@/components/FinanceReviewInbox', () => ({ FinanceReviewInbox: () => <div>painel extrato</div> }));
vi.mock('@/components/FinanceRulesPanel', () => ({
  FinanceRulesPanel: () => <div>painel regras</div>,
  EditorDeRegra: () => null,
}));
vi.mock('@/components/DREPanel', () => ({ DREPanel: () => <div>painel dre</div> }));
vi.mock('@/components/AgingReportPanel', () => ({ AgingReportPanel: () => <div>painel aging</div> }));
// Diálogos ficam montados mesmo fechados e arrastam a cadeia de hooks deles; não são o
// objeto do teste.
vi.mock('@/components/PayableFormDialog', () => ({ PayableFormDialog: () => null }));
vi.mock('@/components/PaymentDialog', () => ({ PaymentDialog: () => null }));
vi.mock('@/components/ReimbursementsPanel', () => ({ ReimbursementsPanel: () => <div>painel reembolsos</div> }));

function renderFinanceiro() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={['/v2/financial']}>
          <FinancialV2 />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('FinancialV2 — paridade e navegação', () => {
  it('mantém as abas que são recorte do mesmo material', async () => {
    // Regras e Contas bancárias continuam aqui: são configuração do financeiro, não
    // destino próprio. Sem elas, migrar o menu tiraria do usuário o que ele ganhou na v1.
    renderFinanceiro();
    expect(await screen.findByRole('tab', { name: /^Regras$/i })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: /Contas bancárias/i })).toBeInTheDocument();
  });

  it('[F2-UI] Extrato e Conciliação NÃO são mais abas — viraram rota', async () => {
    // Manter a aba além da rota daria dois caminhos para o mesmo destino, que é a confusão
    // que o gestor pediu para desfazer ("não sei se clico na lateral ou em cima"). Quem
    // reintroduzir a aba aqui quebra este teste — e é isso que se quer.
    renderFinanceiro();
    await screen.findAllByRole('tab');
    expect(screen.queryByRole('tab', { name: /^Extrato$/i })).toBeNull();
    expect(screen.queryByRole('tab', { name: /Concilia|Reconcil/i })).toBeNull();
    expect(screen.queryByRole('tab', { name: /^Cartões$/i })).toBeNull();
    expect(screen.queryByRole('tab', { name: /Fora da fila/i })).toBeNull();
    expect(screen.queryByRole('tab', { name: /^Fechamento$/i })).toBeNull();
  });

  it('[F2-UI] a ordem do fluxo agora vive no menu lateral, não nas abas', async () => {
    // Triar o extrato vem antes de conferir o que foi lançado. Essa ordem passou a ser
    // responsabilidade do menu (Extrato acima de Conciliação, em AppLayout), porque as duas
    // deixaram de ser abas. Aqui só se garante que nenhuma das duas voltou para cá.
    renderFinanceiro();
    const abas = (await screen.findAllByRole('tab')).map((a) => a.textContent ?? '');
    expect(abas.some((r) => /^Extrato$/i.test(r.trim()))).toBe(false);
    expect(abas.some((r) => /Concilia|Reconcil/i.test(r))).toBe(false);
  });

  it('nenhuma aba abre em branco', async () => {
    // Esta é a lição de um erro real: ao tirar o navigate da aba "Contas a Receber", ela
    // ficou sem TabsContent nenhum e passou a abrir vazia. O teste anterior só verificava
    // que a navegação parara — e navegação parada com tela em branco é pior que antes.
    const user = userEvent.setup();
    const { container } = renderFinanceiro();

    const abas = await screen.findAllByRole('tab');
    for (const aba of abas) {
      await user.click(aba);
      const painel = container.querySelector('[role="tabpanel"][data-state="active"]');
      expect(painel, `aba "${aba.textContent}" não tem painel`).toBeTruthy();
      expect(painel!.textContent?.trim().length, `aba "${aba.textContent}" abre vazia`).toBeGreaterThan(0);
    }
  });

  it('clicar numa aba troca de aba, não de página', async () => {
    const user = userEvent.setup();
    renderFinanceiro();

    // A regressão original: uma aba disparava navigate() e trocava a tela inteira. Como
    // Extrato e Conciliação saíram, a verificação passa a usar uma aba que ficou.
    await user.click(await screen.findByRole('tab', { name: /^Regras$/i }));
    expect(navigateMock).not.toHaveBeenCalled();
  });

  it('cada aba alcança o próprio painel', async () => {
    const user = userEvent.setup();
    renderFinanceiro();

    await user.click(await screen.findByRole('tab', { name: /^Regras$/i }));
    expect(await screen.findByText('painel regras')).toBeInTheDocument();

    await user.click(screen.getByRole('tab', { name: /Contas bancárias/i }));
    expect(await screen.findByText('painel contas')).toBeInTheDocument();
  });

  it('oferece a saída para a versão anterior durante a transição', async () => {
    renderFinanceiro();
    const link = await screen.findByRole('link', { name: /versão anterior/i });
    // Sem o ?legacy=1 a rota antiga redirecionaria de volta para cá, em laço.
    expect(link).toHaveAttribute('href', '/financial?legacy=1');
  });
});

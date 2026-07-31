// Smoke test de RENDER da tela de aprovação de roteiros padrão.
// Existe porque tsc + vite build não pegam erro de render (incidente TDZ de
// 24/07/2026): compilar não basta, renderizar pega. Aqui o que importa é que
// a seção de blocos componíveis apareça com o rótulo do eixo, o alcance em
// número de serviços e os botões de decisão — é nesta tela que o dono assina.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import StepTemplatesPage from './StepTemplatesPage';

const { blocos, servicos, q, mut } = vi.hoisted(() => {
  const q = (data: any) => ({ data, isLoading: false, error: null });
  const mut = () => ({ mutate: () => {}, mutateAsync: async () => ({}), isPending: false });
  const base = {
    detail: null, kind: 'do', mode: 'do_confirm', standard_minutes: 10,
    is_killer: false, requires_photo: false, requires_measure: null,
    measure_unit: null, origin: 'ai' as const, approved_by: null,
    approved_at: null, active: false,
  };
  const blocos = [
    { ...base, id: 'b1', block_role: 'abertura' as const, applies_to_system: 'gas',
      applies_to_verb: null, seq: 1, title: 'Fechar o registro do cilindro e confirmar que fechou',
      kind: 'safety', mode: 'read_do', is_killer: true },
    { ...base, id: 'b2', block_role: 'abertura' as const, applies_to_system: 'gas',
      applies_to_verb: null, seq: 2, title: 'Despressurizar a linha antes de abrir qualquer conexão',
      kind: 'safety', mode: 'read_do', is_killer: true },
    { ...base, id: 'b3', block_role: 'corpo' as const, applies_to_system: null,
      applies_to_verb: 'instalacao', seq: 1, title: 'Conferir material contra a lista do orçamento' },
    { ...base, id: 'b4', block_role: 'fechamento' as const, applies_to_system: 'eletrico_dc',
      applies_to_verb: null, seq: 1, title: 'Conferir polaridade e aperto antes de energizar',
      kind: 'safety', mode: 'read_do', is_killer: true,
      requires_measure: 'torque_nm', measure_unit: 'N·m' },
  ];
  const servicos = [
    { service_verb: 'instalacao', service_system: 'gas' },
    { service_verb: 'instalacao', service_system: 'eletrico_dc' },
    { service_verb: 'reparo', service_system: 'gas' },
  ];
  return { blocos, servicos, q, mut };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => {
      const o: any = {};
      for (const k of ['select', 'order', 'eq', 'update', 'insert', 'delete']) o[k] = () => o;
      o.then = (res: any) =>
        Promise.resolve({
          data: tabela === 'service_step_blocks' ? blocos : tabela === 'services' ? servicos : [],
          error: null,
        }).then(res);
      return o;
    },
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
  },
}));

// A metade "roteiros por serviço" da tela não é o objeto deste teste.
vi.mock('@/hooks/use-step-templates', async (orig) => ({
  ...(await orig<any>()),
  useStepTemplates: () => q([]),
  useApproveTemplate: mut,
  useRejectTemplate: mut,
  useUpdateTemplate: mut,
}));

function renderPage() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <StepTemplatesPage />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('StepTemplatesPage — smoke de render dos blocos componíveis', () => {
  it('renderiza a página e agrupa os blocos por eixo, com o alcance no catálogo', async () => {
    renderPage();

    expect(screen.getByText('Roteiros padrão')).toBeTruthy();
    expect(await screen.findByText('Blocos componíveis')).toBeTruthy();

    // Um grupo por (papel × eixo), com o nome de exibição — não o slug do banco.
    expect(await screen.findByText('Gás GLP')).toBeTruthy();
    expect(screen.getByText('Instalação')).toBeTruthy();
    expect(screen.getByText('Elétrico DC (12/24V)')).toBeTruthy();

    // Alcance: 2 serviços de gás e 2 de instalação nos dados de teste.
    expect(screen.getAllByText('2 serviços').length).toBeGreaterThan(0);

    // Nada de IA entra em uso sem assinatura.
    expect(screen.getByText(/4 passo\(s\) de bloco aguardando sua revisão/)).toBeTruthy();
  });

  it('abre um bloco e mostra os passos com os marcadores de crítico e medição', async () => {
    const user = userEvent.setup();
    renderPage();

    await user.click(await screen.findByText('Elétrico DC (12/24V)'));
    expect(await screen.findByText('Conferir polaridade e aperto antes de energizar')).toBeTruthy();
    expect(screen.getByText('medir (N·m)')).toBeTruthy();
    expect(screen.getByText('crítico')).toBeTruthy();
    expect(screen.getByText('rascunho da IA — aguarda sua decisão')).toBeTruthy();
  });

  it('abre a edição de um passo de gás antes de aprovar', async () => {
    const user = userEvent.setup();
    renderPage();

    await user.click(await screen.findByText('Gás GLP'));
    const titulo = 'Fechar o registro do cilindro e confirmar que fechou';
    expect(await screen.findByText(titulo)).toBeTruthy();

    await user.click(screen.getAllByTitle('Editar antes de aprovar')[0]);
    expect(screen.getByDisplayValue(titulo)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Salvar e aprovar' })).toBeTruthy();
  });
});

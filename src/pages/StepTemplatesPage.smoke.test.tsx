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

const { blocos, servicos, perguntas, q, mut } = vi.hoisted(() => {
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
  // Serve aos dois hooks que leem `services`: o alcance dos blocos e a fila de
  // classificação a conferir.
  const servicos = [
    { id: 'sv1', name: 'CT - Instalação e Fixação', service_verb: 'instalacao',
      service_system: 'gas', classified_by: 'ai', classification_confidence: 0.3 },
    { id: 'sv2', name: 'Instalação de bateria', service_verb: 'instalacao',
      service_system: 'eletrico_dc', classified_by: 'keyword', classification_confidence: 0.9 },
    { id: 'sv3', name: 'Reparo de aquecedor', service_verb: 'reparo',
      service_system: 'gas', classified_by: 'ai', classification_confidence: 0.6 },
  ];
  const perguntas = [
    { id: 'q1', service_id: null, applies_to_system: 'gas', applies_to_verb: null, seq: 1,
      question: 'Onde fica o cilindro e como é o acesso até ele?', help_text: null,
      answer_type: 'texto', price_impact: 'alto', ask_remotely: false,
      origin: 'ai' as const, approved_by: null, approved_at: null, active: false },
    { id: 'q2', service_id: null, applies_to_system: 'gas', applies_to_verb: null, seq: 2,
      question: 'Foto do cilindro, do registro e da ligação atual do aparelho', help_text: null,
      answer_type: 'foto', price_impact: 'alto', ask_remotely: true,
      origin: 'ai' as const, approved_by: null, approved_at: null, active: false },
  ];
  return { blocos, servicos, perguntas, q, mut };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => {
      const o: any = {};
      for (const k of ['select', 'order', 'eq', 'lt', 'gt', 'is', 'not', 'in',
                       'update', 'insert', 'delete']) o[k] = () => o;
      o.then = (res: any) =>
        Promise.resolve({
          data: tabela === 'service_step_blocks' ? blocos
              : tabela === 'services' ? servicos
              : tabela === 'service_survey_templates' ? perguntas
              : [],
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

    expect(screen.getByText('Moldes do catálogo')).toBeTruthy();
    expect(await screen.findByText('Blocos componíveis')).toBeTruthy();

    // Um grupo por (papel × eixo), com o nome de exibição — não o slug do banco.
    // "Gás GLP" aparece duas vezes: no bloco de abertura e nas perguntas.
    expect((await screen.findAllByText('Gás GLP')).length).toBe(2);
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

  it('lista a classificação incerta para conferência, com a confiança à mostra', async () => {
    const user = userEvent.setup();
    renderPage();

    expect(await screen.findByText('Classificação a conferir')).toBeTruthy();
    await user.click(await screen.findByText(/serviço\(s\) para conferir/));

    // O mock não filtra por confiança (quem filtra é o banco), mas o que a tela
    // precisa mostrar é o nome e o quanto a IA duvidou.
    expect(await screen.findByText('CT - Instalação e Fixação')).toBeTruthy();
    expect(screen.getByText('confiança 0.3')).toBeTruthy();
    expect(screen.getAllByRole('button', { name: /Confirmar/ }).length).toBeGreaterThan(0);
  });

  it('mostra as perguntas de levantamento com o selo de quem pode responder', async () => {
    const user = userEvent.setup();
    renderPage();

    expect(await screen.findByText('Perguntas de levantamento')).toBeTruthy();
    // O grupo de gás aparece duas vezes: uma nos blocos, outra nas perguntas.
    await user.click((await screen.findAllByText('Gás GLP'))[1]);

    expect(await screen.findByText('Onde fica o cilindro e como é o acesso até ele?')).toBeTruthy();
    expect(screen.getByText('pode pedir ao cliente')).toBeTruthy();
    expect(screen.getAllByText('muda o preço').length).toBe(2);
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

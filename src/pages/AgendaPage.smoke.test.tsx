// Smoke test de RENDER da AgendaPage — existe porque um erro de TDZ
// ('Cannot access before initialization': applyTaskFilters usada em useMemo
// declarado acima da definição) derrubou a página inteira em produção em
// 24/07/2026 e passou por tsc + vite build. Compilar não basta: renderizar pega.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import AgendaPage from './AgendaPage';
import { AgendaV2 } from '@/v2/pages/wrapped';

// vi.mock é içado para o topo do módulo — helpers/fixtures precisam de vi.hoisted
const { queryBuilder, q, mut, liveTasks, doneTasks, suggestions, openLoops, contagem, semana, ordensDaSemana, agendarOs } = vi.hoisted(() => {
  const queryBuilder = (): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'order',
      'limit', 'is', 'not', 'like', 'update', 'insert', 'delete', 'upsert', 'filter']) {
      o[k] = () => o;
    }
    o.maybeSingle = async () => ({ data: null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: any) => Promise.resolve({ data: [], error: null }).then(res);
    return o;
  };
  const q = (data: any) => ({ data, isLoading: false, error: null });
  const mut = () => ({ mutate: () => {}, mutateAsync: async () => ({}), isPending: false });
  const liveTasks = [
    {
      id: 't1', title: 'Cobrar Cliente Alpha — R$ 500', kind: 'task', status: 'pending',
      priority: 'urgent', due_at: new Date(Date.now() - 86400000).toISOString(),
      scheduled_start_at: null, scheduled_end_at: null, source: 'automation',
      automation_key: 'r4:recv:x', related_entity_type: 'receivable', related_entity_id: 'rcv-1',
      assignee_user_id: 'u1', app_users: { id: 'u1', full_name: 'Gustavo' },
      clients: null, checklist: [], is_private: false, snoozed_until: null,
    },
    {
      id: 't2', title: 'Visita técnica na marina', kind: 'appointment', status: 'pending',
      priority: 'normal', due_at: null,
      scheduled_start_at: new Date().toISOString(),
      scheduled_end_at: new Date(Date.now() + 7200000).toISOString(),
      source: 'manual', automation_key: null, related_entity_type: null, related_entity_id: null,
      assignee_user_id: 'u2', app_users: { id: 'u2', full_name: 'Felipe' },
      clients: null, checklist: [{ text: 'levar peça', done: false }], is_private: false, snoozed_until: null,
    },
  ];
  const doneTasks = [{
    ...liveTasks[0], id: 't3', status: 'done', title: 'Tarefa concluída de teste',
    completed_at: new Date().toISOString(), completed_by: 'u1', created_at: new Date().toISOString(),
    completed_by_user: { id: 'u1', full_name: 'Gustavo' },
  }];
  const suggestions = [{
    id: 's1', title: 'Enviar orçamento do motor para o Carlos', kind: 'task',
    status: 'pending', priority: 'normal', detector: 'promise', origin: 'whatsapp',
    evidence: 'Vou te mandar o orçamento amanhã de manhã', evidence_at: new Date().toISOString(),
    confidence: 0.9, contact_label: 'Carlos Silva', suggested_due_at: new Date().toISOString(),
    suggested_start_at: null, client_id: null, target_user_id: 'u1',
  }, {
    id: 's2', title: 'Cobrar a marina sexta', kind: 'task', status: 'pending',
    priority: 'high', detector: 'voice_note', origin: 'voice_app',
    evidence: 'lembra de cobrar a marina sexta e agendar a revisão do Pedro',
    confidence: 0.95, contact_label: null, suggested_due_at: null,
    suggested_start_at: null, client_id: null, target_user_id: 'u1',
  }];
  // Fios que dependem de uma ação nossa — o material da visão "Depende de você".
  const openLoops = [
    {
      id: 'l1', kind: 'request', source: 'conversation', direction: 'ours',
      title: 'Enviar nota fiscal do serviço do fogão para Charline',
      detail: null, due_at: new Date(Date.now() - 172800000).toISOString(),
      priority: 'normal', service_order_id: null, service_order_number: null,
      mentions: 2, evidence: 'você consegue me mandar a nota do fogão?',
      opened_at: new Date().toISOString(), last_seen_at: new Date().toISOString(),
      atrasado: true, entity_type: 'client', entity_id: 'c-1', entity_name: 'Charline',
    },
    {
      id: 'l2', kind: 'receivable', source: 'erp', direction: 'ours',
      title: 'Título VENCIDO R$ 1.998,96',
      detail: null, due_at: null, priority: 'high',
      service_order_id: null, service_order_number: null, mentions: 1, evidence: null,
      opened_at: new Date().toISOString(), last_seen_at: new Date().toISOString(),
      atrasado: false, entity_type: 'client', entity_id: 'c-2', entity_name: 'Cliente Beta',
    },
  ];
  // Contagem do banco das sugestões pendentes (0 = igual ao tamanho da lista).
  const contagem = { total: 0 };

  // Dias da semana que a tela mostra (segunda = 0), no mesmo cálculo do startOfWeek da página.
  // As OS de teste ficam no meio do dia de Brasília (-03:00): o dia é o mesmo em qualquer fuso
  // em que o teste rodar (CI em UTC, máquina em Brasília).
  const inicio = new Date();
  inicio.setHours(0, 0, 0, 0);
  inicio.setDate(inicio.getDate() + (inicio.getDay() === 0 ? -6 : 1 - inicio.getDay()));
  const semana = (i: number) => {
    const d = new Date(inicio);
    d.setDate(d.getDate() + i);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  };
  const br = (i: number, hora: string) => `${semana(i)}T${hora}:00-03:00`;
  // Agenda de Produção, Fase 0 (D3/D4/D5): o que a grade deixava sumir ou somava errado.
  const ordensDaSemana = [
    {
      // D3: técnico com login INATIVO (fora de useTechnicians) — a OS sumia da grade.
      id: 'so-inativo', service_order_number: 'OS-00104', status: 'awaiting_parts',
      scheduled_start_at: br(1, '09:00'), scheduled_end_at: br(1, '11:00'),
      clients: { name: 'Cliente Nelson' }, vessels: null,
      service_order_technicians: [{ user_id: 'u9', app_users: { id: 'u9', full_name: 'Roberto Inativo' } }],
    },
    {
      // D4: três dias de serviço — aparecia só no primeiro.
      id: 'so-3dias', service_order_number: 'OS-00200', status: 'scheduled',
      scheduled_start_at: br(2, '08:00'), scheduled_end_at: br(4, '17:00'),
      clients: { name: 'Cliente Três Dias' }, vessels: null,
      service_order_technicians: [{ user_id: 'u7', app_users: { id: 'u7', full_name: 'Técnico Três Dias' } }],
    },
    {
      // D5: janela corrida de 72 h (sexta 08:00 → segunda 08:00) — virava "72h ⚠" num dia.
      id: 'so-72h', service_order_number: 'OS-00300', status: 'scheduled',
      scheduled_start_at: br(4, '08:00'), scheduled_end_at: br(7, '08:00'),
      clients: { name: 'Cliente Janela Longa' }, vessels: null,
      service_order_technicians: [{ user_id: 'u8', app_users: { id: 'u8', full_name: 'Técnico Janela' } }],
    },
  ];
  const agendarOs = vi.fn(async (_input: any) => ({ warning: null, mensagem: 'OS agendada', status: 'scheduled' }));
  return { queryBuilder, q, mut, liveTasks, doneTasks, suggestions, openLoops, contagem, semana, ordensDaSemana, agendarOs };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => queryBuilder(),
    rpc: async () => ({ data: [], error: null }),
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
    channel: () => ({ on() { return this; }, subscribe() { return this; } }),
    removeChannel: () => {},
  },
}));

// A visão "Depende de você" filtra fio financeiro por cargo (o banco não filtra), então
// precisa do usuário. Mesmo mock do agenda-components.smoke.test.tsx.
vi.mock('@/hooks/use-auth', () => ({ useAuth: () => ({ user: { id: 'u1', role: 'admin' } }) }));

vi.mock('@/hooks/use-agenda', () => ({
  useSuggestions: () => q(suggestions),
  useSuggestionsCount: () => q(contagem.total || suggestions.length),
  useAcceptSuggestion: mut,
  useDismissSuggestion: mut,
  useVoiceCapture: mut,
  useAutoCreated: () => q([]),
  useUndoAutoCreated: mut,
  useOpenLoops: () => q(openLoops),
  useAgendaOrders: () => q([{
    id: 'so-1', service_order_number: 'OS-100', status: 'scheduled',
    scheduled_start_at: new Date().toISOString(), scheduled_end_at: new Date(Date.now() + 3600000).toISOString(),
    clients: { name: 'Cliente Alpha' }, vessels: { name: 'Barco Alpha' },
    service_order_technicians: [{ user_id: 'u2', app_users: { id: 'u2', full_name: 'Felipe' } }],
  }, ...ordensDaSemana]),
  useAgendaTasks: () => q(liveTasks),
  useLiveTasks: () => q(liveTasks),
  useCompletedTasks: () => q(doneTasks),
  useTechnicians: () => q([{ id: 'u2', full_name: 'Felipe' }]),
  useActiveUsers: () => q([{ id: 'u1', full_name: 'Gustavo', role: 'admin' }, { id: 'u2', full_name: 'Felipe', role: 'technician' }]),
  useSchedulableOrders: () => q([{
    id: 'so-agendar', service_order_number: 'OS-00105', status: 'open',
    clients: { name: 'Cliente Sem Técnico' }, vessels: null,
  }]),
  useResponsaveisDaOs: () => q([{ id: 'u1', full_name: 'Gustavo' }, { id: 'u9', full_name: 'Roberto Inativo' }]),
  useEntityTasks: () => q([]),
  useTaskReminders: () => q([]),
  useQuickSchedule: () => ({ mutate: () => {}, mutateAsync: agendarOs, isPending: false }),
  useSaveAgendaTask: mut,
  useCompleteTask: mut,
  useRescheduleTask: mut,
  useSnoozeTask: mut,
  useUpdateAgendaTaskStatus: mut,
  useDeleteAgendaTask: mut,
}));
vi.mock('@/hooks/use-clients', () => ({ useClients: () => ({ data: [] }) }));
vi.mock('@/components/FilterPresets', () => ({ FilterPresets: () => null }));
vi.mock('@/components/PaymentDialog', () => ({ PaymentDialog: () => null }));

function renderPage() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <AgendaPage />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('AgendaPage — smoke de render (todas as visões)', () => {
  it('renderiza a visão Hoje sem lançar (regressão do TDZ de produção)', () => {
    renderPage();
    expect(screen.getByText('Cobrar Cliente Alpha — R$ 500')).toBeTruthy();
    expect(screen.getByText(/Modo foco|Foco/)).toBeTruthy();
  });

  it('renderiza Semana (com workload), Mês e Concluídas sem lançar', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByRole('button', { name: 'Semana' }));
    expect(screen.getAllByText('Felipe').length).toBeGreaterThan(0);
    await user.click(screen.getByRole('button', { name: 'Mês' }));
    await user.click(screen.getByRole('button', { name: 'Concluídas' }));
    expect(screen.getByText('Tarefa concluída de teste')).toBeTruthy();
  });

  it('renderiza a Caixa de entrada com evidência e ações (Fase 9)', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByRole('button', { name: /Caixa de entrada/ }));
    // sugestão de conversa + de voz, cada uma com sua evidência literal
    expect(screen.getByText('Enviar orçamento do motor para o Carlos')).toBeTruthy();
    expect(screen.getByText(/Vou te mandar o orçamento amanhã de manhã/)).toBeTruthy();
    expect(screen.getByText('Cobrar a marina sexta')).toBeTruthy();
    expect(screen.getAllByText('Aceitar').length).toBe(2);
    expect(screen.getByText('Seus recados (1)')).toBeTruthy();
    expect(screen.getByText('Detectado nas conversas (1)')).toBeTruthy();
  });

  it('com mais de 100 sugestões, o selo mostra o total do banco e a lista avisa o corte', async () => {
    // A lista para em 100; o selo contava a lista e travava em "100" (inventário 06/10/2026).
    contagem.total = 250;
    try {
      const user = userEvent.setup();
      renderPage();
      const aba = screen.getByRole('button', { name: /Caixa de entrada/ });
      expect(aba.textContent).toContain('250');
      await user.click(aba);
      expect(screen.getByTestId('sugestoes-cortadas').textContent).toContain('2 de maior confiança de 250');
    } finally {
      contagem.total = 0;
    }
  });

  it('a visão "Depende de você" lista os fios com contato, prazo e a frase original', async () => {
    // A pergunta que o sistema não respondia: "o que está parado esperando por mim".
    // Os fios existiam desde julho, mas só dentro da tela de cada cliente.
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <I18nProvider>
          <MemoryRouter><AgendaPage /></MemoryRouter>
        </I18nProvider>
      </QueryClientProvider>,
    );
    await userEvent.click(screen.getByRole('button', { name: /Depende de você/ }));

    expect(screen.getByText('Enviar nota fiscal do serviço do fogão para Charline')).toBeTruthy();
    expect(screen.getByText('Charline')).toBeTruthy();
    // a evidência é o que faz confiar no item — sem ela vira linha genérica
    expect(screen.getByText(/você consegue me mandar a nota do fogão/)).toBeTruthy();
    // o atrasado ganha seção própria, e o sem prazo também
    expect(screen.getByText('Atrasado (1)')).toBeTruthy();
    expect(screen.getByText('Sem prazo (1)')).toBeTruthy();
  });

  it('a visão Revisões (planos de manutenção, 07/10/2026) abre sem lançar', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByRole('button', { name: 'Revisões' }));
    // Banco falso sem planos: a tela explica onde criar, em vez de ficar em branco.
    expect(await screen.findByText(/Nenhum plano de manutenção ativo/)).toBeTruthy();
  });

  // ─── Agenda de Produção, Fase 0 (23/10/2026): nenhuma OS some, carga por dia, agendar sem técnico ───

  it('OS de técnico com login inativo aparece, numa linha com o nome dele (desktop e celular)', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByRole('button', { name: 'Semana' }));
    // A linha do técnico existe na grade, com o nome vindo do embed da própria OS.
    expect(screen.getByText('Roberto Inativo')).toBeTruthy();
    // E a OS aparece duas vezes: na grade (desktop) e nos dias empilhados (celular).
    // Antes: zero — sem linha para ele, a OS sumia das duas.
    expect(screen.getAllByText('OS-00104')).toHaveLength(2);
  });

  it('OS de 3 dias aparece nos 3 dias, com "desde dd/mm" fora do primeiro', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByRole('button', { name: 'Semana' }));
    // 3 dias × (desktop + celular).
    expect(screen.getAllByText('OS-00200')).toHaveLength(6);
    const [, mes, dia] = semana(2).split('-');
    // Nos dias 2 e 3 da janela, a hora do cartão dá lugar a "desde": 2 dias × 2 layouts.
    expect(screen.getAllByText(`desde ${dia}/${mes}`)).toHaveLength(4);
    // A carga do técnico nos três dias: 8h em cada um (09 h nas pontas e 24 h no meio, tudo
    // recortado à jornada).
    for (const i of [2, 3, 4]) {
      expect(screen.getByTestId(`carga-u7-${semana(i)}`).textContent).toBe('8h');
    }

    // No mês, o pino de OS aparece nos três dias também.
    await user.click(screen.getByRole('button', { name: 'Mês' }));
    for (const i of [2, 3, 4]) expect(screen.getByTestId(`mes-os-${semana(i)}`)).toBeTruthy();
  });

  it('OS de janela longa (72 h) mostra 8h por dia, sem "72h" e sem ⚠', async () => {
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByRole('button', { name: 'Semana' }));
    // Sexta, sábado e domingo da semana; a segunda seguinte fica fora da grade.
    for (const i of [4, 5, 6]) {
      const carga = screen.getByTestId(`carga-u8-${semana(i)}`);
      expect(carga.textContent).toBe('8h');
      expect(carga.textContent).not.toContain('⚠');
    }
    expect(screen.queryByText(/72h/)).toBeNull();
  });

  it('o diálogo "Agendar OS" agenda sem técnico', async () => {
    agendarOs.mockClear();
    const user = userEvent.setup();
    renderPage();
    await user.click(screen.getByRole('button', { name: 'Agendar' }));
    await user.click(await screen.findByRole('menuitem', { name: /Ordem de serviço/ }));
    const dialogo = await screen.findByRole('dialog');
    expect(within(dialogo).getByText('Técnico (opcional)')).toBeTruthy();
    // Escolhe só a OS; o técnico fica "Sem responsável".
    // O combobox não tira o nome do conteúdo (ARIA): o 1º do diálogo é o da OS.
    const [campoOs, campoTecnico] = within(dialogo).getAllByRole('combobox');
    expect(campoOs.textContent).toContain('Selecione uma OS');
    expect(campoTecnico.textContent).toContain('Sem responsável');
    await user.click(campoOs);
    await user.click(await screen.findByRole('option', { name: /OS-00105/ }));
    await user.click(within(dialogo).getByRole('button', { name: 'Agendar' }));
    expect(agendarOs).toHaveBeenCalledTimes(1);
    expect(agendarOs.mock.calls[0][0]).toMatchObject({
      service_order_id: 'so-agendar',
      technician_user_id: null,
    });
  });

  it('a rota /v2/agenda renderiza a MESMA agenda dentro da casca de tema', async () => {
    // A v2 da Agenda e casca, nao reescrita: se este teste divergir do de cima, alguem
    // duplicou a logica em vez de reaproveitar.
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <I18nProvider>
          <MemoryRouter><AgendaV2 /></MemoryRouter>
        </I18nProvider>
      </QueryClientProvider>,
    );
    // A tela é carregada sob demanda dentro da casca (04/10/2026): espera o pedaço chegar.
    expect(await screen.findByText('Cobrar Cliente Alpha — R$ 500', {}, { timeout: 5000 })).toBeTruthy();
  });
});

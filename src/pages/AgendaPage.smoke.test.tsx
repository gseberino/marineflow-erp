// Smoke test de RENDER da AgendaPage — existe porque um erro de TDZ
// ('Cannot access before initialization': applyTaskFilters usada em useMemo
// declarado acima da definição) derrubou a página inteira em produção em
// 24/07/2026 e passou por tsc + vite build. Compilar não basta: renderizar pega.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import AgendaPage from './AgendaPage';
import { AgendaV2 } from '@/v2/pages/wrapped';

// vi.mock é içado para o topo do módulo — helpers/fixtures precisam de vi.hoisted
const { queryBuilder, q, mut, liveTasks, doneTasks, suggestions } = vi.hoisted(() => {
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
  return { queryBuilder, q, mut, liveTasks, doneTasks, suggestions };
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

vi.mock('@/hooks/use-agenda', () => ({
  useSuggestions: () => q(suggestions),
  useAcceptSuggestion: mut,
  useDismissSuggestion: mut,
  useVoiceCapture: mut,
  useAutoCreated: () => q([]),
  useUndoAutoCreated: mut,
  useAgendaOrders: () => q([{
    id: 'so-1', service_order_number: 'OS-100', status: 'scheduled',
    scheduled_start_at: new Date().toISOString(), scheduled_end_at: new Date(Date.now() + 3600000).toISOString(),
    clients: { name: 'Cliente Alpha' }, vessels: { name: 'Barco Alpha' },
    service_order_technicians: [{ user_id: 'u2', app_users: { id: 'u2', full_name: 'Felipe' } }],
  }]),
  useAgendaTasks: () => q(liveTasks),
  useLiveTasks: () => q(liveTasks),
  useCompletedTasks: () => q(doneTasks),
  useTechnicians: () => q([{ id: 'u2', full_name: 'Felipe' }]),
  useActiveUsers: () => q([{ id: 'u1', full_name: 'Gustavo', role: 'admin' }, { id: 'u2', full_name: 'Felipe', role: 'technician' }]),
  useSchedulableOrders: () => q([]),
  useEntityTasks: () => q([]),
  useTaskReminders: () => q([]),
  useQuickSchedule: mut,
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

  it('a rota /v2/agenda renderiza a MESMA agenda dentro da casca de tema', () => {
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
    expect(screen.getByText('Cobrar Cliente Alpha — R$ 500')).toBeTruthy();
  });
});

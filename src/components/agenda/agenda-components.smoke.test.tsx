// Smoke de RENDER dos componentes da Agenda 2.0 embutidos em outras telas
// (Dashboard, OS, cliente, embarcação, Settings). Mesma motivação do
// AgendaPage.smoke.test.tsx: erro de inicialização não aparece em tsc/build.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DashboardTasksWidget } from './DashboardTasksWidget';
import { EntityTasksPanel } from './EntityTasksPanel';
import { MaintenancePlansPanel } from './MaintenancePlansPanel';
import { TaskAutomationSettings } from './TaskAutomationSettings';
import { FocusMode } from './FocusMode';

const { queryBuilder, q, mut, liveTasks } = vi.hoisted(() => {
  const queryBuilder = (): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'order',
      'limit', 'is', 'not', 'like', 'update', 'insert', 'delete', 'upsert', 'filter', 'or']) {
      o[k] = () => o;
    }
    o.maybeSingle = async () => ({ data: null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: any) => Promise.resolve({ data: [], error: null }).then(res);
    return o;
  };
  const q = (data: any) => ({ data, isLoading: false, error: null });
  const mut = () => ({ mutate: () => {}, mutateAsync: async () => ({}), isPending: false });
  const liveTasks = [{
    id: 't1', title: 'Tarefa vinculada de teste', kind: 'task', status: 'pending',
    priority: 'high', due_at: new Date().toISOString(), scheduled_start_at: null,
    scheduled_end_at: null, source: 'ai', automation_key: null,
    related_entity_type: 'service_order', related_entity_id: 'so-1',
    assignee_user_id: 'u1', app_users: { id: 'u1', full_name: 'Gustavo' },
    clients: null, checklist: [], is_private: false, snoozed_until: null,
  }];
  return { queryBuilder, q, mut, liveTasks };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => queryBuilder(),
    rpc: async () => ({ data: [], error: null }),
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
  },
}));
vi.mock('@/hooks/use-agenda', () => ({
  useLiveTasks: () => q(liveTasks),
  useEntityTasks: () => q(liveTasks),
  useActiveUsers: () => q([{ id: 'u1', full_name: 'Gustavo', role: 'admin' }]),
  useTaskReminders: () => q([]),
  useCompleteTask: mut,
  useSnoozeTask: mut,
  useSaveAgendaTask: mut,
  useDeleteAgendaTask: mut,
}));
vi.mock('@/hooks/use-clients', () => ({ useClients: () => ({ data: [] }) }));
vi.mock('@/components/PaymentDialog', () => ({ PaymentDialog: () => null }));

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>{ui}</MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('componentes da Agenda 2.0 — smoke de render', () => {
  it('DashboardTasksWidget renderiza contadores', () => {
    wrap(<DashboardTasksWidget />);
    expect(screen.getByText(/em aberto/)).toBeTruthy();
  });

  it('EntityTasksPanel renderiza tarefas vinculadas e o botão de nova tarefa', () => {
    wrap(<EntityTasksPanel entityType="service_order" entityId="so-1" />);
    expect(screen.getByText('Tarefa vinculada de teste')).toBeTruthy();
    expect(screen.getByText('Nova tarefa')).toBeTruthy();
  });

  it('MaintenancePlansPanel renderiza vazio com call-to-action', () => {
    wrap(<MaintenancePlansPanel vesselId="v-1" />);
    expect(screen.getByText('Planos de manutenção')).toBeTruthy();
    expect(screen.getByText('Novo plano')).toBeTruthy();
  });

  it('TaskAutomationSettings renderiza toggles e editor de modelos', () => {
    wrap(<TaskAutomationSettings />);
    expect(screen.getByText('Automações de tarefas')).toBeTruthy();
    expect(screen.getByText('Modelos de checklist')).toBeTruthy();
    expect(screen.getByText(/Pesquisa pós-serviço/)).toBeTruthy();
  });

  it('FocusMode renderiza a tarefa atual e os três botões', () => {
    wrap(<FocusMode open onOpenChange={() => {}} tasks={liveTasks} />);
    expect(screen.getByText('Modo foco')).toBeTruthy();
    expect(screen.getByText('Concluir')).toBeTruthy();
    expect(screen.getByText('Adiar 1h')).toBeTruthy();
  });
});

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

// vi.mock é içado para o topo do módulo — helpers/fixtures precisam de vi.hoisted
const { queryBuilder, q, mut, liveTasks, doneTasks } = vi.hoisted(() => {
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
  return { queryBuilder, q, mut, liveTasks, doneTasks };
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
});

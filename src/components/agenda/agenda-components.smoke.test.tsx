// Smoke de RENDER dos componentes da Agenda 2.0 embutidos em outras telas
// (Dashboard, OS, cliente, embarcação, Settings). Mesma motivação do
// AgendaPage.smoke.test.tsx: erro de inicialização não aparece em tsc/build.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DashboardTasksWidget } from './DashboardTasksWidget';
import { EntityTasksPanel } from './EntityTasksPanel';
import { MaintenancePlansPanel } from './MaintenancePlansPanel';
import { TaskAutomationSettings } from './TaskAutomationSettings';
import { FocusMode } from './FocusMode';
import { OpenLoopsPanel } from './OpenLoopsPanel';
import { InstallAgendaCard } from './InstallAgendaCard';

const { queryBuilder, q, mut, liveTasks, openLoops, loopsRef, roleRef, upsertSpy } = vi.hoisted(() => {
  // Espião de gravação: é o que prova que a confirmação BLOQUEIA o salvamento, e não
  // apenas aparece por cima de uma alteração que já aconteceu.
  const upsertSpy = vi.fn();
  const queryBuilder = (): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'order',
      'limit', 'is', 'not', 'like', 'update', 'insert', 'delete', 'filter', 'or']) {
      o[k] = () => o;
    }
    o.upsert = (...args: unknown[]) => { upsertSpy(...args); return o; };
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
  // Um fio de cada origem: o do ERP (atrasado) e o da conversa (com evidência e recobrança).
  const openLoops = [
    {
      id: 'l1', kind: 'service_order', source: 'erp',
      title: 'OS OS-1042 — aguardando peças', detail: 'Troca do banco de baterias',
      due_at: new Date(Date.now() - 86400000).toISOString(), priority: 'high',
      service_order_id: 'so-1', service_order_number: 'OS-1042', mentions: 1,
      evidence: null, opened_at: new Date().toISOString(),
      last_seen_at: new Date().toISOString(), atrasado: true,
    },
    {
      id: 'l2', kind: 'delivery', source: 'conversation',
      title: 'Acompanhar entrega dos materiais da OS-1042', detail: null,
      due_at: null, priority: 'normal', service_order_id: 'so-1',
      service_order_number: 'OS-1042', mentions: 3,
      evidence: 'as baterias chegam quarta', opened_at: new Date().toISOString(),
      last_seen_at: new Date().toISOString(), atrasado: false,
    },
    {
      id: 'l3', kind: 'receivable', source: 'erp',
      title: 'Título VENCIDO R$ 1.710,00', detail: null,
      due_at: new Date(Date.now() - 86400000).toISOString(), priority: 'urgent',
      service_order_id: null, service_order_number: null, mentions: 1,
      evidence: null, opened_at: new Date().toISOString(),
      last_seen_at: new Date().toISOString(), atrasado: true,
    },
  ];
  // Mutáveis para os testes trocarem o retorno dos hooks (estado vazio, cargo do usuário).
  const loopsRef = { current: openLoops as any[] };
  const roleRef = { current: { id: 'u1', role: 'admin' } as any };
  return { queryBuilder, q, mut, liveTasks, openLoops, loopsRef, roleRef, upsertSpy };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => queryBuilder(),
    rpc: async () => ({ data: [], error: null }),
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
  },
}));
vi.mock('@/hooks/use-agenda', () => ({
  useSuggestions: () => q([]),
  useAcceptSuggestion: mut,
  useDismissSuggestion: mut,
  useVoiceCapture: mut,
  useLiveTasks: () => q(liveTasks),
  useEntityTasks: () => q(liveTasks),
  useActiveUsers: () => q([{ id: 'u1', full_name: 'Gustavo', role: 'admin' }]),
  useTaskReminders: () => q([]),
  useCompleteTask: mut,
  useSnoozeTask: mut,
  useSaveAgendaTask: mut,
  useDeleteAgendaTask: mut,
  useEntityOpenLoops: () => q(loopsRef.current),
}));
vi.mock('@/hooks/use-clients', () => ({ useClients: () => ({ data: [] }) }));
vi.mock('@/hooks/use-auth', () => ({ useAuth: () => ({ user: roleRef.current }) }));
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

  it('OpenLoopsPanel mostra fio do ERP e da conversa, com atraso e recobrança', () => {
    wrap(<OpenLoopsPanel entityType="client" entityId="c-1" />);
    expect(screen.getByText('OS OS-1042 — aguardando peças')).toBeTruthy();
    expect(screen.getByText('Acompanhar entrega dos materiais da OS-1042')).toBeTruthy();
    // O que veio da conversa é marcado — é o que ainda não virou fato no ERP.
    expect(screen.getByText('combinado na conversa')).toBeTruthy();
    // Dois fios do fixture estão atrasados (a OS e o título), então há dois selos.
    expect(screen.getAllByText('atrasado').length).toBe(2);
    expect(screen.getByText('cobrado 3×')).toBeTruthy();
    // A frase literal precisa aparecer para conferir sem abrir a conversa.
    expect(screen.getByText(/as baterias chegam quarta/)).toBeTruthy();
  });

  it('ligar mensagem ao CLIENTE pede confirmação antes de salvar', async () => {
    const user = userEvent.setup();
    wrap(<TaskAutomationSettings />);

    // O interruptor da regra que envia ao cliente é o que fica ao lado do rótulo dela.
    // Regex, não texto exato: o rótulo já mudou uma vez e quebrou este teste à toa.
    const linha = screen.getByText(/Lembrete de agendamento ao CLIENTE/).closest('div')!.parentElement!;
    await user.click(within(linha).getByRole('switch'));

    // Não pode ter salvo nada ainda: primeiro o aviso.
    expect(await screen.findByText(/^Ligar “Lembrete de agendamento ao CLIENTE/)).toBeTruthy();
    expect(upsertSpy).not.toHaveBeenCalled();

    // Sem modo de teste, o botão só libera depois de digitar a palavra.
    const confirmar = screen.getByRole('button', { name: /Ligar e enviar a clientes/ });
    expect(confirmar).toBeDisabled();
    await user.type(screen.getByLabelText(/digite/i), 'LIGAR');
    expect(confirmar).not.toBeDisabled();
  });

  it('InstallAgendaCard aparece mesmo sem o evento do navegador', () => {
    // Era exatamente esta a falha do botão antigo: sem `beforeinstallprompt` ele retornava
    // null, então no iPhone nunca aparecia nada. Aqui o evento não é disparado e o cartão
    // ainda precisa se explicar.
    wrap(<InstallAgendaCard />);
    expect(screen.getByText('Agenda no celular')).toBeTruthy();
    // No jsdom não há evento nem iOS, então cai no ramo "navegador sem suporte" — que é o
    // ponto: sempre há uma explicação, nunca uma tela em branco.
    expect(screen.getByText(/não oferece instalação/)).toBeTruthy();
  });

  it('OpenLoopsPanel esconde fio de dinheiro do técnico', () => {
    const anterior = roleRef.current;
    roleRef.current = { id: 'u9', role: 'technician' };
    try {
      wrap(<OpenLoopsPanel entityType="client" entityId="c-1" />);
      // O trabalho ele vê; o valor do título, não.
      expect(screen.getByText('OS OS-1042 — aguardando peças')).toBeTruthy();
      expect(screen.queryByText('Título VENCIDO R$ 1.710,00')).toBeNull();
    } finally {
      roleRef.current = anterior;
    }
  });

  it('OpenLoopsPanel some quando não há nada em aberto', () => {
    // Ele fica acima da dobra na tela do cliente: card vazio ali seria só ruído.
    const anterior = loopsRef.current;
    loopsRef.current = [];
    try {
      const { container } = wrap(<OpenLoopsPanel entityType="client" entityId="c-1" />);
      expect(container.textContent).toBe('');
    } finally {
      loopsRef.current = anterior;
    }
  });

  it('FocusMode renderiza a tarefa atual e os três botões', () => {
    wrap(<FocusMode open onOpenChange={() => {}} tasks={liveTasks} />);
    expect(screen.getByText('Modo foco')).toBeTruthy();
    expect(screen.getByText('Concluir')).toBeTruthy();
    expect(screen.getByText('Adiar 1h')).toBeTruthy();
  });
});

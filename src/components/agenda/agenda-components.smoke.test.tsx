// Smoke de RENDER dos componentes da Agenda 2.0 embutidos em outras telas
// (Dashboard, OS, cliente, embarcação, Settings). Mesma motivação do
// AgendaPage.smoke.test.tsx: erro de inicialização não aparece em tsc/build.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DashboardTasksWidget } from './DashboardTasksWidget';
import { EntityTasksPanel } from './EntityTasksPanel';
import { MaintenancePlansPanel } from './MaintenancePlansPanel';
import { TaskAutomationSettings } from './TaskAutomationSettings';
import { FocusMode } from './FocusMode';
import { OpenLoopsPanel } from './OpenLoopsPanel';
import { InstallAgendaCard } from './InstallAgendaCard';
import { TaskCard } from './TaskCard';

const { queryBuilder, q, mut, liveTasks, openLoops, loopsRef, roleRef, upsertSpy } = vi.hoisted(() => {
  // Espião de gravação: prova que o interruptor salva direto (sem diálogo de envio ao cliente).
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
  useSuggestionsCount: () => q(0),
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

  it('EntityTasksPanel monta para embarcação — a aba nova da VesselDetail', () => {
    // A R14 ("Propor revisão") grava related_entity_type 'vessel', então esta aba nasce
    // com conteúdo real. O painel é agnóstico de tipo; o que faltava era onde ancorá-lo.
    wrap(<EntityTasksPanel entityType="vessel" entityId="v-1" title="Tarefas desta embarcação" />);
    expect(screen.getByText('Tarefas desta embarcação')).toBeTruthy();
    expect(screen.getByText('Nova tarefa')).toBeTruthy();
  });

  it('EntityTasksPanel some quando não há entidade, em vez de renderizar vazio', () => {
    // Guarda do `if (!entityId) return null`: uma tela que ainda está carregando o id
    // não pode piscar um painel órfão com botão de criar tarefa sem vínculo.
    const { container } = wrap(<EntityTasksPanel entityType="vessel" entityId={undefined} />);
    expect(container.textContent).toBe('');
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
    expect(screen.getByText('OS aprovada sem agendamento')).toBeTruthy();
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

  // O número da OS já vem com o prefixo ("OS-1042"). Até 11/10/2026 o rodapé do fio dizia
  // "OS OS-1042". O título "OS OS-1042 — aguardando peças" vem do SQL (entity_open_loops) e
  // fica para o lote do banco.
  it('OpenLoopsPanel mostra o número da OS no rodapé do fio, sem "OS " repetido', () => {
    wrap(<OpenLoopsPanel entityType="client" entityId="c-1" />);
    // Os dois fios da OS-1042 (o do ERP e o da conversa) trazem o número no rodapé.
    expect(screen.getAllByText('OS-1042').length).toBe(2);
    expect(screen.queryByText('OS OS-1042')).toBeNull();
  });

  // R9 (lembrete automático de agendamento) e R13 (pesquisa pós-serviço) aposentadas em 23/10/2026
  // (decisão d13): nenhuma regra da tela manda mensagem a cliente, então nenhum interruptor pede o
  // "digite LIGAR" — e o que ele guardava sumiu junto.
  it('R9 e R13 saíram da tela; os interruptores salvam direto', async () => {
    const user = userEvent.setup();
    upsertSpy.mockClear();
    wrap(<TaskAutomationSettings />);
    expect(screen.queryByText(/Lembrete de agendamento ao CLIENTE/)).toBeNull();
    expect(screen.queryByText(/Pesquisa pós-serviço/)).toBeNull();
    expect(screen.queryByText(/\(envio automático\)/)).toBeNull();
    await user.click(screen.getByRole('switch', { name: 'OS aprovada sem agendamento' }));
    expect(screen.queryByText(/digite/i)).toBeNull();
    expect(upsertSpy).toHaveBeenCalledWith({ key: 'task_rule_r1_enabled', value: 'false' }, { onConflict: 'key' });
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

// O botão do cartão da R1 depende da chave (23/10/2026): a OS ganha "Agendar OS"; o orçamento
// aprovado sem sinal (r1:orc) ganha "Abrir orçamento", porque o passo dele é o sinal, não a data.
describe('TaskCard da R1 — botão por chave', () => {
  const tarefaR1 = (automation_key: string, title: string, osId: string) => ({
    ...liveTasks[0], id: automation_key, title, source: 'automation', automation_key,
    related_entity_type: 'service_order', related_entity_id: osId,
  });

  it('r1:so mostra "Agendar OS" e entrega a tarefa ao agendamento', async () => {
    const user = userEvent.setup();
    const onScheduleOs = vi.fn();
    const t = tarefaR1('r1:so:so-69', 'Agendar OS-00069 — Vanderlei Andrade', 'so-69');
    wrap(<TaskCard task={t} onScheduleOs={onScheduleOs} />);
    expect(screen.queryByRole('button', { name: 'Abrir orçamento' })).toBeNull();
    await user.click(screen.getByRole('button', { name: 'Agendar OS' }));
    expect(onScheduleOs).toHaveBeenCalledWith(t);
  });

  it('r1:orc mostra "Abrir orçamento" (nunca "Agendar OS") e leva à tela do orçamento', async () => {
    const user = userEvent.setup();
    const onScheduleOs = vi.fn();
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const t = tarefaR1('r1:orc:so-83', 'ORÇ-00083 aprovado sem sinal — receber o sinal e converter para agendar (ROBSON)', 'so-83');
    render(
      <QueryClientProvider client={qc}>
        <MemoryRouter initialEntries={['/agenda']}>
          <Routes>
            <Route path="/agenda" element={<TaskCard task={t} onScheduleOs={onScheduleOs} />} />
            <Route path="/v2/service-orders/so-83" element={<p>tela do ORÇ-00083</p>} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>,
    );
    expect(screen.queryByRole('button', { name: 'Agendar OS' })).toBeNull();
    await user.click(screen.getByRole('button', { name: 'Abrir orçamento' }));
    expect(screen.getByText('tela do ORÇ-00083')).toBeTruthy();
    expect(onScheduleOs).not.toHaveBeenCalled();
  });
});

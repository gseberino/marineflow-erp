// Smoke de RENDER + comportamento das telas dos planos de manutenção (07/10/2026): painel da
// embarcação, aba Revisões, cartão da R14, lembrete com o "sim" do dono, interruptores e a aba
// Revisões preventivas da Prospecção. O banco falso responde por TABELA, e as chamadas ficam
// gravadas: é o que prova que "Serviço feito" vai pela RPC (com a data de Brasília), que apagar
// pede confirmação ANTES de apagar e que o lembrete só sai no "Confirmar".
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const banco = vi.hoisted(() => {
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  const estado = {
    tabelas: {} as Record<string, unknown[]>,
    erros: {} as Record<string, { message: string }>,
    rpcs: [] as Array<{ nome: string; args: any }>,
    escritas: [] as Array<{ tabela: string; op: string; valor?: unknown }>,
    invokes: [] as Array<{ nome: string; body: any }>,
    respostaDoAgente: null as any,
    hoje,
  };
  const builder = (tabela: string): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'order', 'limit', 'is', 'not', 'like', 'filter', 'or']) {
      o[k] = () => o;
    }
    for (const op of ['update', 'insert', 'delete', 'upsert']) {
      o[op] = (valor?: unknown) => { estado.escritas.push({ tabela, op, valor }); return o; };
    }
    o.maybeSingle = async () => ({ data: null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: any) => Promise.resolve(
      estado.erros[tabela] ? { data: null, error: estado.erros[tabela] } : { data: estado.tabelas[tabela] ?? [], error: null },
    ).then(res);
    return o;
  };
  return { estado, builder };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (t: string) => banco.builder(t),
    rpc: async (nome: string, args: unknown) => { banco.estado.rpcs.push({ nome, args }); return { data: { ok: true }, error: null }; },
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
    functions: {
      invoke: async (nome: string, opts: { body: any }) => {
        banco.estado.invokes.push({ nome, body: opts.body });
        if (opts.body?.type === 'confirm_action') return { data: { message: { content: '✅ Lembrete — executado.' } }, error: null };
        return { data: banco.estado.respostaDoAgente, error: null };
      },
    },
    channel: () => ({ on() { return this; }, subscribe() { return this; } }),
    removeChannel: () => {},
  },
}));
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), info: vi.fn(), warning: vi.fn() } }));
vi.mock('@/hooks/use-agenda', () => ({ useSnoozeTask: () => ({ mutate: () => {}, isPending: false }) }));
vi.mock('@/components/PaymentDialog', () => ({ PaymentDialog: () => null }));

import { MaintenancePlansPanel } from './MaintenancePlansPanel';
import { RevisoesPanel } from './RevisoesPanel';
import { RevisoesPreventivas } from './RevisoesPreventivas';
import { TaskAutomationSettings } from './TaskAutomationSettings';
import { TaskCard } from './TaskCard';
import { planoDaChaveR14 } from './PlanoDialogs';
import { TIPO_DO_BANCO } from '@/hooks/use-notifications';

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><MemoryRouter>{ui}</MemoryRouter></QueryClientProvider>);
}

const PLANO = {
  id: 'p1', vessel_id: 'v1', name: 'Revisão de motor', interval_months: 12, scope: 'óleo, filtros', estimated_value: 1200,
  last_service_at: '2025-10-20', advance_days: 14, active: true, notes: null, created_at: '2025-01-01T00:00:00Z',
  service_system: 'mecanico', service_verb: null, match_keywords: ['motor'], last_service_order_id: null,
  snoozed_until: null, client_reminder_enabled: true, source: 'manual',
};
const DUE = (over: Record<string, unknown> = {}) => ({
  plan_id: 'p1', vessel_id: 'v1', vessel_name: 'Mar Azul', client_id: 'c1', client_name: 'Carlos', client_phone: '5511999999999',
  opt_out: false, name: 'Revisão de motor', scope: null, estimated_value: 1200, interval_months: 12, last_service_at: '2025-10-20',
  last_service_order_id: null, next_due_on: '2026-10-20', window_opens_on: '2026-09-29', snoozed_until: null,
  dias_para_vencer: 13, situacao: 'na_janela', tem_os_agendada: false, ultimo_toque: null, respondeu_no_ciclo: false, ...over,
});

beforeEach(() => {
  banco.estado.tabelas = {};
  banco.estado.erros = {};
  banco.estado.rpcs = [];
  banco.estado.escritas = [];
  banco.estado.invokes = [];
  banco.estado.respostaDoAgente = null;
});

describe('MaintenancePlansPanel (aba Manutenção da embarcação)', () => {
  it('mostra vencimento e situação lidos da view, critério e lembrete', async () => {
    banco.estado.tabelas = { maintenance_plans: [PLANO], v_maintenance_plans_due: [DUE()] };
    wrap(<MaintenancePlansPanel vesselId="v1" />);
    expect(await screen.findByText('Revisão de motor')).toBeTruthy();
    expect(screen.getByText('na janela')).toBeTruthy();
    expect(screen.getByText(/Próxima: 20\/10\/2026 \(vence em 13 dias\)/)).toBeTruthy();
    expect(screen.getByText(/Conta como feito: Mecânico · “motor” · avisar 14 dias antes/)).toBeTruthy();
    expect(screen.getByText('Sugerir planos')).toBeTruthy();
  });

  it('"Serviço feito" vai pela RPC registrar_servico_do_plano com a data de Brasília', async () => {
    const user = userEvent.setup();
    banco.estado.tabelas = { maintenance_plans: [PLANO], v_maintenance_plans_due: [DUE()] };
    wrap(<MaintenancePlansPanel vesselId="v1" />);
    await user.click(await screen.findByRole('button', { name: /Serviço feito/ }));
    await user.click(await screen.findByRole('button', { name: 'Registrar serviço' }));
    await waitFor(() => expect(banco.estado.rpcs).toEqual([
      { nome: 'registrar_servico_do_plano', args: { p_plano: 'p1', p_data: banco.estado.hoje, p_os: null } },
    ]));
    // Nada de gravar last_service_at direto na tabela (era o bug da data UTC).
    expect(banco.estado.escritas.filter((e) => e.tabela === 'maintenance_plans')).toEqual([]);
  });

  it('apagar pede confirmação antes de apagar', async () => {
    const user = userEvent.setup();
    banco.estado.tabelas = { maintenance_plans: [PLANO], v_maintenance_plans_due: [DUE()] };
    wrap(<MaintenancePlansPanel vesselId="v1" />);
    await user.click(await screen.findByRole('button', { name: /Mais ações para plano Revisão de motor/ }));
    await user.click(await screen.findByText('Apagar plano'));
    expect(await screen.findByText('Apagar o plano “Revisão de motor”?')).toBeTruthy();
    expect(banco.estado.escritas.some((e) => e.op === 'delete')).toBe(false);
    await user.click(screen.getByRole('button', { name: 'Apagar' }));
    await waitFor(() => expect(banco.estado.escritas).toContainEqual({ tabela: 'maintenance_plans', op: 'delete', valor: undefined }));
  });

  it('falha da view não some com os planos: avisa que o vencimento não pôde ser lido', async () => {
    banco.estado.tabelas = { maintenance_plans: [PLANO] };
    banco.estado.erros = { v_maintenance_plans_due: { message: 'relation "v_maintenance_plans_due" does not exist' } };
    wrap(<MaintenancePlansPanel vesselId="v1" />);
    expect(await screen.findByText('Revisão de motor')).toBeTruthy();
    expect(screen.getByText(/Não deu para calcular os vencimentos agora/)).toBeTruthy();
  });

  it('"Sugerir planos" propõe a partir das OS concluídas e "Usar" abre o formulário preenchido', async () => {
    const user = userEvent.setup();
    banco.estado.tabelas = {
      maintenance_plans: [],
      service_orders: [{
        id: 'os1', service_order_number: 'OS-00042', check_out_at: '2026-03-10T15:00:00Z', scheduled_end_at: null, updated_at: null,
        service_order_services: [{ name_snapshot: 'REPARO DE CONVERSOR E CARREGADOR', service_system: null, line_total: 480 }],
        service_order_parts: [],
      }],
    };
    wrap(<MaintenancePlansPanel vesselId="v1" />);
    await user.click(await screen.findByRole('button', { name: /Sugerir planos/ }));
    expect(await screen.findByText(/Revisão de inversor e carregador · a cada 12 meses/)).toBeTruthy();
    expect(screen.getByText(/Último: 10\/03\/2026 \(OS-00042\)/)).toBeTruthy();
    await user.click(screen.getByRole('button', { name: 'Usar' }));
    expect(await screen.findByDisplayValue('Revisão de inversor e carregador')).toBeTruthy();
    expect(screen.getByDisplayValue('2026-03-10')).toBeTruthy();
  });
});

describe('RevisoesPanel (aba Revisões da Agenda)', () => {
  it('mostra a receita prevista e os recortes, em cartões', async () => {
    const user = userEvent.setup();
    banco.estado.tabelas = {
      v_maintenance_plans_due: [
        DUE(),
        DUE({ plan_id: 'p2', vessel_name: 'Vento Sul', name: 'Baterias', situacao: 'vencida', dias_para_vencer: -4, next_due_on: '2026-10-03', estimated_value: 800 }),
        DUE({ plan_id: 'p3', vessel_name: 'Brisa', situacao: 'adiada', snoozed_until: '2026-12-01', dias_para_vencer: 5 }),
      ],
    };
    wrap(<RevisoesPanel />);
    expect((await screen.findByTestId('receita-prevista')).textContent).toMatch(/2\.000,00/);
    expect(screen.getByText('Mar Azul')).toBeTruthy();
    await user.click(screen.getByRole('button', { name: /Vencidas \(1\)/ }));
    expect(screen.getByText('Vento Sul')).toBeTruthy();
    expect(screen.getByText(/venceu há 4 dias/)).toBeTruthy();
    await user.click(screen.getByRole('button', { name: /Adiadas \(1\)/ }));
    expect(screen.getByText(/até 01\/12\/2026/)).toBeTruthy();
  });

  it('erro de leitura aparece como erro, não como "nenhuma revisão"', async () => {
    banco.estado.erros = { v_maintenance_plans_due: { message: 'permission denied' } };
    wrap(<RevisoesPanel />);
    expect(await screen.findByText(/Não deu para ler as revisões: permission denied/)).toBeTruthy();
  });

  it('"Pedir lembrete agora" pede ao assistente e só envia no Confirmar', async () => {
    const user = userEvent.setup();
    banco.estado.tabelas = { v_maintenance_plans_due: [DUE()] };
    banco.estado.respostaDoAgente = {
      proposal: { pending_action_id: 'pa-1', title: 'Lembrete de revisão para Carlos (Mar Azul)', summary_markdown: 'Oi, Carlos! Aqui é da HBR Marine…', risk_level: 'medium' },
    };
    wrap(<RevisoesPanel />);
    await user.click(await screen.findByRole('button', { name: /Mais ações para revisão Revisão de motor de Mar Azul/ }));
    await user.click(await screen.findByText('Pedir lembrete agora'));
    await user.click(await screen.findByRole('button', { name: 'Preparar lembrete' }));
    expect(await screen.findByText('Lembrete de revisão para Carlos (Mar Azul)')).toBeTruthy();
    expect(banco.estado.invokes).toHaveLength(1);
    expect(banco.estado.invokes[0].body.messages[0].content).toMatch(/send_maintenance_reminder_now com plan_id p1/);
    // Ainda não houve decisão: nada foi enviado.
    expect(banco.estado.invokes.some((i) => i.body.type === 'confirm_action')).toBe(false);
    await user.click(screen.getByRole('button', { name: /Confirmar/ }));
    await waitFor(() => expect(banco.estado.invokes[1].body).toEqual({ type: 'confirm_action', pending_action_id: 'pa-1', decision: 'approve', note: undefined }));
  });

  it('cliente com PARAR não chega a chamar o assistente', async () => {
    const user = userEvent.setup();
    banco.estado.tabelas = { v_maintenance_plans_due: [DUE({ opt_out: true })] };
    wrap(<RevisoesPanel />);
    await user.click(await screen.findByRole('button', { name: /Mais ações para revisão/ }));
    await user.click(await screen.findByText('Pedir lembrete agora'));
    expect(await screen.findByText(/pediu para não receber WhatsApp/)).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Preparar lembrete' })).toBeNull();
  });
});

describe('TaskCard da R14', () => {
  it('a chave r14 dá o plano e o cartão ganha "Serviço feito" e "Adiar"', async () => {
    expect(planoDaChaveR14('r14:plan:abc-123:2025-10-20')).toBe('abc-123');
    expect(planoDaChaveR14('r15:os:x')).toBeNull();
    const user = userEvent.setup();
    wrap(<TaskCard task={{
      id: 't1', title: 'Propor revisão: Revisão de motor — Mar Azul', status: 'pending', priority: 'normal',
      due_at: null, scheduled_start_at: null, source: 'automation', automation_key: 'r14:plan:p1:2025-10-20',
      related_entity_type: 'vessel', related_entity_id: 'v1', checklist: [],
    }} />);
    expect(screen.getByRole('button', { name: 'Serviço feito' })).toBeTruthy();
    await user.click(screen.getByRole('button', { name: 'Adiar' }));
    expect(await screen.findByText('Adiar revisão')).toBeTruthy();
    await user.click(screen.getByRole('button', { name: '1 mês' }));
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Adiar' }));
    await waitFor(() => expect(banco.estado.rpcs[0]?.nome).toBe('adiar_plano'));
    expect(banco.estado.rpcs[0].args.p_plano).toBe('p1');
  });
});

describe('Configurações › Automações', () => {
  it('interruptores de revisão ligados por padrão; desligar grava "off"', async () => {
    const user = userEvent.setup();
    wrap(<TaskAutomationSettings />);
    const sw = await screen.findByRole('switch', { name: 'Lembretes de revisão ao cliente (com seu sim)' });
    expect(sw.getAttribute('aria-checked')).toBe('true');
    expect(screen.getByRole('switch', { name: 'Campanha de temporada set–out (com seu sim)' })).toBeTruthy();
    expect(screen.getByText(/Fecha sozinha quando o serviço é registrado/)).toBeTruthy();
    await user.click(sw);
    await waitFor(() => expect(banco.estado.escritas).toContainEqual({
      tabela: 'app_settings', op: 'upsert', valor: { key: 'lembretes_revisao_ativo', value: 'off' },
    }));
  });
});

describe('Prospecção › Revisões preventivas', () => {
  it('planos vencendo + embarcações sem plano; nada de envio direto', async () => {
    banco.estado.tabelas = {
      v_maintenance_plans_due: [DUE()],
      service_orders: [{
        vessel_id: 'v9', status: 'completed', created_at: '2025-01-01T12:00:00Z', check_out_at: '2025-12-01T12:00:00Z',
        scheduled_end_at: null, updated_at: '2025-12-02T12:00:00Z', vessels: { name: 'Sem Plano I' }, clients: { name: 'Ana', opt_out_whatsapp: false },
      }],
    };
    wrap(<RevisoesPreventivas />);
    expect(await screen.findByText('Mar Azul')).toBeTruthy();
    expect(screen.getByRole('button', { name: /Preparar lembrete \(com seu sim\)/ })).toBeTruthy();
    expect(screen.getByText('Sem Plano I')).toBeTruthy();
    expect(screen.getByRole('button', { name: /Criar plano/ })).toBeTruthy();
    expect(banco.estado.invokes).toEqual([]);
  });
});

describe('sino', () => {
  it('resposta à revisão, SIM do agendamento e missão da IA têm tipo próprio', () => {
    expect(TIPO_DO_BANCO.revisao_resposta).toBe('REVISAO_RESPOSTA');
    expect(TIPO_DO_BANCO.agendamento_confirmado).toBe('AGENDAMENTO_CONFIRMADO');
    expect(TIPO_DO_BANCO.followup_mission).toBe('FOLLOWUP_MISSION');
  });
});

// Smoke de RENDER das telas mexidas nos defeitos de 07/10/2026 — e o comportamento que falhava:
//   2. Nova Cobrança da OS com várias parcelas: pede a parcela e grava receivable_id;
//   4. Ordens de Compra: OC recebida não oferece cancelar/excluir/editar; rascunho exclui com confirmação;
//   5. Tarefa recorrente: salvar sem mexer conserva INTERVAL e BYDAY (antes virava "FREQ=X");
//   6. Sugestão: descartar oferece motivo e o grava;
//   7. Marina: o bairro aparece e é gravado.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';

const m = vi.hoisted(() => {
  const respostas: Record<string, unknown> = {};
  const queryBuilder = (tabela: string): any => {
    const o: any = {};
    for (const k of ['select', 'eq', 'neq', 'in', 'gte', 'lte', 'lt', 'gt', 'order', 'limit', 'is', 'not',
      'like', 'ilike', 'update', 'insert', 'delete', 'upsert', 'filter', 'or', 'range']) {
      o[k] = () => o;
    }
    o.maybeSingle = async () => ({ data: null, error: null });
    o.single = async () => ({ data: null, error: null });
    o.then = (res: any) => Promise.resolve({ data: respostas[tabela] ?? [], error: null }).then(res);
    return o;
  };
  const q = (data: any) => ({ data, isLoading: false, error: null });
  return {
    respostas, queryBuilder, q,
    criarCobranca: vi.fn(async () => ({})),
    salvarTarefa: vi.fn(async () => ({})),
    descartar: vi.fn(),
    excluirOC: vi.fn(),
    mudarOC: vi.fn(),
    criarMarina: vi.fn(async () => ({})),
    atualizarMarina: vi.fn(async () => ({})),
    ordens: [] as any[],
  };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (t: string) => m.queryBuilder(t),
    rpc: async () => ({ data: null, error: null }),
    auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) },
  },
}));
vi.mock('@/hooks/use-clients', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-clients')>()),
  useClients: () => ({ data: [{ id: 'c1', name: 'MP Motor Homes', phone: '47999990000', whatsapp: '47999990000' }] }),
}));
vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrders: () => ({
    data: [{ id: 'so1', service_order_number: 'OS-00112', status: 'completed', client_id: 'c1', grand_total: 3000, client: { name: 'MP Motor Homes' } }],
  }),
}));
vi.mock('@/hooks/use-collections', () => ({
  useCollectionTemplates: () => ({ data: [] }),
  useCreateCollection: () => ({ mutateAsync: m.criarCobranca, isPending: false }),
}));
vi.mock('@/hooks/use-agenda', () => ({
  useSaveAgendaTask: () => ({ mutateAsync: m.salvarTarefa, isPending: false }),
  useDeleteAgendaTask: () => ({ mutateAsync: async () => ({}), isPending: false }),
  useActiveUsers: () => m.q([]),
  useTaskReminders: () => m.q([]),
  useAcceptSuggestion: () => ({ mutate: () => {}, isPending: false }),
  useDismissSuggestion: () => ({ mutate: m.descartar, isPending: false }),
}));
vi.mock('@/components/followups/FollowupMissionDialog', () => ({ FollowupMissionButton: () => null }));
vi.mock('@/hooks/use-purchase-orders', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-purchase-orders')>();
  const mut = (fn: any) => () => ({ mutate: fn, mutateAsync: async () => ({}), isPending: false });
  return {
    ...real,
    usePurchaseOrders: () => ({ data: m.ordens, isLoading: false, error: null }),
    useCreatePurchaseOrder: mut(vi.fn()),
    useUpdatePurchaseOrder: mut(m.mudarOC),
    useDeletePurchaseOrder: mut(m.excluirOC),
    useAddPOItem: mut(vi.fn()),
    useRemovePOItem: mut(vi.fn()),
  };
});
vi.mock('@/hooks/use-suppliers', () => ({ useSuppliers: () => ({ data: [{ id: 'f1', name: 'Victron' }] }) }));
vi.mock('@/hooks/use-marinas', () => ({
  useCreateMarina: () => ({ mutateAsync: m.criarMarina, isPending: false }),
  useUpdateMarina: () => ({ mutateAsync: m.atualizarMarina, isPending: false }),
}));

import { CreateCollectionDialog } from './collections/CreateCollectionDialog';
import { AgendaTaskDialog } from './AgendaTaskDialog';
import { SuggestionCard } from './agenda/SuggestionCard';
import { MarinaFormDialog } from './MarinaFormDialog';
import PurchaseOrdersV2 from '@/v2/pages/PurchaseOrdersV2';

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider><MemoryRouter>{ui}</MemoryRouter></I18nProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  for (const k of Object.keys(m.respostas)) delete m.respostas[k];
  vi.clearAllMocks();
});

describe('2 · Nova Cobrança ligada à conta a receber', () => {
  it('OS com duas parcelas em aberto: pede qual e grava o receivable_id dela', async () => {
    m.respostas.receivables = [
      { id: 'r1', description: 'Sinal', amount: 1000, balance_amount: 1000, due_date: '2026-10-10', status: 'overdue' },
      { id: 'r2', description: 'Saldo na entrega', amount: 2000, balance_amount: 2000, due_date: '2026-10-25', status: 'pending' },
    ];
    m.respostas.collections = [];
    const user = userEvent.setup();
    wrap(<CreateCollectionDialog open onOpenChange={() => {}} />);
    await user.click(screen.getByText('Selecionar OS...').closest('button')!);
    await user.click(await screen.findByRole('option', { name: /OS-00112/ }));
    const parcela = await screen.findByText(/2 parcelas em aberto/);
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeDisabled();
    await user.click(parcela.closest('button')!);
    await user.click(await screen.findByRole('option', { name: /Saldo na entrega/ }));
    await waitFor(() => expect(screen.getByRole('button', { name: 'Salvar' })).toBeEnabled());
    await user.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(m.criarCobranca).toHaveBeenCalledWith(expect.objectContaining({
      service_order_id: 'so1', receivable_id: 'r2', amount: 2000, due_date: '2026-10-25', client_id: 'c1',
    }));
  });

  it('OS com uma conta só: liga sozinha; já cobrada: não deixa criar outra', async () => {
    m.respostas.receivables = [{ id: 'r1', description: 'Total', amount: 3000, balance_amount: 3000, due_date: '2026-10-20', status: 'pending' }];
    m.respostas.collections = [{ id: 'col9', amount: 3000, due_date: '2026-10-20' }];
    const user = userEvent.setup();
    wrap(<CreateCollectionDialog open onOpenChange={() => {}} />);
    await user.click(screen.getByText('Selecionar OS...').closest('button')!);
    await user.click(await screen.findByRole('option', { name: /OS-00112/ }));
    expect(await screen.findByText(/Cobra «Total»/)).toBeInTheDocument();
    expect(await screen.findByText(/Já existe cobrança aberta para esta parcela/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeDisabled();
  });
});

describe('4 · Ordens de Compra travadas pela situação', () => {
  const OC = (id: string, numero: string, status: string, recebido: number) => ({
    id, po_number: numero, status, supplier_id: 'f1', suppliers: { name: 'Victron' }, total_amount: 100,
    expected_date: null, notes: null, service_order_id: null, service_orders: null,
    purchase_order_items: [{ id: `${id}-i`, description: 'Bateria', quantity: 2, unit_cost: 50, received_qty: recebido }],
  });

  it('OC recebida: sem editar, cancelar nem excluir; rascunho: exclui depois de confirmar', async () => {
    m.ordens = [OC('o1', 'OC-00001', 'received', 2), OC('o2', 'OC-00002', 'draft', 0)];
    const user = userEvent.setup();
    wrap(<PurchaseOrdersV2 />);
    expect((await screen.findAllByText('OC-00001')).length).toBeGreaterThan(0);
    expect(screen.queryByRole('button', { name: /mais ações para ordem de compra OC-00001/i })).not.toBeInTheDocument();

    await user.click(screen.getAllByRole('button', { name: /mais ações para ordem de compra OC-00002/i })[0]);
    expect(await screen.findByRole('menuitem', { name: /Cancelar a OC/ })).toBeInTheDocument();
    await user.click(screen.getByRole('menuitem', { name: /Excluir/ }));
    expect(m.excluirOC).not.toHaveBeenCalled();
    await user.click(await screen.findByRole('button', { name: 'Excluir' }));
    expect(m.excluirOC).toHaveBeenCalledWith('o2');
  });

  it('OC enviada: o menu não oferece "recebida" nem excluir', async () => {
    m.ordens = [OC('o3', 'OC-00003', 'sent', 0)];
    const user = userEvent.setup();
    wrap(<PurchaseOrdersV2 />);
    await user.click((await screen.findAllByRole('button', { name: /mais ações para ordem de compra OC-00003/i }))[0]);
    const itens = (await screen.findAllByRole('menuitem')).map((i) => i.textContent);
    expect(itens).toEqual(['Voltar para rascunho', 'Receber itens…', 'Cancelar a OC']);
  });
});

describe('5 · Tarefa recorrente do assistente', () => {
  const tarefa = (rrule: string) => ({
    id: 't1', title: 'Revisar bomba do porão', kind: 'task', assignee_user_id: null,
    scheduled_start_at: null, scheduled_end_at: null, due_at: '2026-10-12T11:00:00.000Z',
    priority: 'normal', status: 'pending', rrule, source: 'ai',
  });

  it('"toda segunda e quinta": mostra os dias e salva a regra inteira', async () => {
    const user = userEvent.setup();
    wrap(<AgendaTaskDialog open onOpenChange={() => {}} existing={tarefa('FREQ=WEEKLY;BYDAY=MO,TH')} />);
    expect(await screen.findByTestId('resumo-da-repeticao')).toHaveTextContent('Repete toda segunda e quinta');
    expect(screen.getByRole('button', { name: 'segunda' })).toHaveAttribute('aria-pressed', 'true');
    await user.click(screen.getByRole('button', { name: 'Salvar alterações' }));
    expect(m.salvarTarefa).toHaveBeenCalledWith(expect.objectContaining({ rrule: 'FREQ=WEEKLY;BYDAY=MO,TH' }));
  });

  it('"a cada 15 dias": o intervalo aparece e não se perde ao salvar', async () => {
    const user = userEvent.setup();
    wrap(<AgendaTaskDialog open onOpenChange={() => {}} existing={tarefa('FREQ=DAILY;INTERVAL=15;UNTIL=20261231')} />);
    expect(await screen.findByLabelText(/A cada \(dias\)/)).toHaveValue(15);
    await user.click(screen.getByRole('button', { name: 'Salvar alterações' }));
    expect(m.salvarTarefa).toHaveBeenCalledWith(expect.objectContaining({ rrule: 'FREQ=DAILY;INTERVAL=15;UNTIL=20261231' }));
  });
});

describe('6 · Descartar sugestão com motivo', () => {
  it('o X abre o motivo; o motivo escolhido vai para o descarte', async () => {
    const user = userEvent.setup();
    wrap(<SuggestionCard suggestion={{
      id: 's1', title: 'Ligar para o Miguel', kind: 'task', detector: 'promise', origin: 'whatsapp',
      evidence: 'te ligo amanhã', contact_label: 'Miguel', suggested_due_at: null, suggested_start_at: null,
    }} />);
    await user.click(screen.getByRole('button', { name: 'Descartar esta sugestão' }));
    expect(m.descartar).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: 'Já resolvido' }));
    await user.click(screen.getByRole('button', { name: 'Descartar' }));
    expect(m.descartar).toHaveBeenCalledWith({ id: 's1', reason: 'Já resolvido' }, expect.anything());
  });
});

describe('7 · Marina guarda o bairro', () => {
  it('mostra o bairro gravado e grava o editado', async () => {
    const user = userEvent.setup();
    const marina = {
      id: 'm1', name: 'Marina Porto Belo', contact_name: null, phone: null, email: null, postal_code: null,
      address_line_1: 'Av. Gov. Celso Ramos, 100', neighborhood: 'Centro', city: 'Porto Belo', state: 'SC', country: 'Brazil',
      latitude: null, longitude: null, access_notes: null, billing_notes: null, active: true, created_at: '', updated_at: '',
    };
    wrap(<MarinaFormDialog open onOpenChange={() => {}} marina={marina as any} />);
    const bairro = await screen.findByDisplayValue('Centro');
    await user.clear(bairro);
    await user.type(bairro, 'Perequê');
    await user.click(screen.getByRole('button', { name: /Salvar/ }));
    await waitFor(() => expect(m.atualizarMarina).toHaveBeenCalledWith(expect.objectContaining({ id: 'm1', neighborhood: 'Perequê' })));
  });
});

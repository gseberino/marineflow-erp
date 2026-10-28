// Lista v2 com agrupamento de OS (28/10/2026): a origem de OS agrupada fica na aba de OS (selo "Agrupada em
// OS-X", fora da contagem, sem trocar situação), a de orçamento continua na aba de orçamentos, e a barra de
// seleção da aba de OS abre a janela de agrupar OS com as escolhidas e a mais antiga como principal.
import { describe, it, expect, vi, beforeEach, beforeAll, afterAll } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import OrdersListV2 from './OrdersListV2';

const estado = vi.hoisted(() => ({
  linhas: [] as unknown[],
  vazio: [] as unknown[],
  mapaVazio: new Map(),
  ajustes: {} as Record<string, string>,
  auth: { user: { id: 'u-1', role: 'admin' } } as unknown,
  dialogoOs: [] as Array<{ clientId: string; vesselId: string; preSelecionados: string[]; principalSugerido?: string }>,
  dialogoOrc: 0,
  erros: [] as string[],
}));

vi.mock('@/hooks/use-auth', () => ({ useOptionalAuth: () => estado.auth }));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: estado.ajustes }) }));
vi.mock('@/hooks/use-pdf', () => ({ usePDFData: () => ({ data: null, error: null }), fetchPDFData: async () => null }));
const mutacao = { mutate: () => {}, mutateAsync: async () => ({}), isPending: false };
vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrders: () => ({ data: estado.linhas, isLoading: false, error: null }),
  useDuplicateServiceOrder: () => mutacao,
  useUpdateServiceOrderStatus: () => mutacao,
}));
vi.mock('@/hooks/use-agenda', () => ({ useTechnicians: () => ({ data: estado.vazio, isLoading: false }) }));
vi.mock('@/hooks/use-whatsapp-send-log', () => ({ useWhatsAppSendStatusMap: () => ({ data: estado.mapaVazio }) }));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: async () => {} }));
vi.mock('@/lib/diagnostics', () => ({ recordWhatsAppEvent: () => {} }));
vi.mock('sonner', () => ({
  toast: { success: () => {}, error: (m: string) => { estado.erros.push(m); }, info: () => {}, loading: () => 't' },
}));
vi.mock('@/integrations/supabase/client', () => {
  const resposta = { data: [], error: null };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const q: any = new Proxy({}, {
    get: (_alvo, prop) => (prop === 'then' ? (ok: (v: unknown) => void) => ok(resposta) : () => q),
  });
  return { supabase: { from: () => q, rpc: async () => resposta, functions: { invoke: async () => resposta } } };
});
vi.mock('@/components/PDFOptionsDialog', () => ({ PDFOptionsDialog: () => null }));
vi.mock('@/components/WhatsAppSendHistoryDialog', () => ({ WhatsAppSendHistoryDialog: () => null }));
vi.mock('@/components/SendViaWhatsAppDialog', () => ({ SendViaWhatsAppDialog: () => null }));
vi.mock('@/components/fiscal/FaturarOsDialog', () => ({ FaturarOsDialog: () => null }));
vi.mock('@/components/purchasing/PurchaseNeedsDialog', () => ({ PurchaseNeedsDialog: () => null }));
vi.mock('@/components/QuoteStatusQuickChange', () => ({ QuoteStatusQuickChange: () => null }));
vi.mock('@/components/StatusQuickChange', () => ({
  StatusQuickChange: ({ orderId }: { orderId: string }) => <span>troca-situacao-{orderId}</span>,
}));
vi.mock('@/components/orcamento-tecnico/OrcamentoTecnicoIADialog', () => ({ OrcamentoTecnicoIADialog: () => null }));
vi.mock('@/components/service-order/AgruparOsDialog', () => ({
  AgruparOsDialog: (p: { clientId: string; vesselId: string; preSelecionados: string[]; principalSugerido?: string }) => {
    estado.dialogoOs.push(p);
    return <div>janela-agrupar-os</div>;
  },
}));
vi.mock('@/components/service-order/AgruparOrcamentosDialog', () => ({
  AgruparOrcamentosDialog: () => {
    estado.dialogoOrc += 1;
    return <div>janela-agrupar-orcamentos</div>;
  },
}));

const linha = (over: Record<string, unknown>) => ({
  id: 'x', service_order_number: 'OS-0000X', status: 'approved', quote_status: 'approved', priority: 'normal',
  service_type: 'maintenance', grand_total: 100, share_token: null, scheduled_start_at: null, payment_status: 'paid',
  created_at: '2026-10-01T12:00:00.000Z', client_id: 'cli-1', vessel_id: 'ves-1', merged_into_id: null,
  converted_to_os_at: '2026-10-01T13:00:00.000Z', clients: { name: 'Giancarlo' }, vessels: { name: 'Vitória Star' },
  ...over,
});

const NOVA = linha({ id: 'nova', service_order_number: 'OS-00140', created_at: '2026-10-27T12:00:00.000Z' });
const ORIGEM_OS = linha({ id: 'o1', service_order_number: 'OS-00100', status: 'cancelled', merged_into_id: 'nova', created_at: '2026-10-02T12:00:00.000Z' });
const OS_A = linha({ id: 'a', service_order_number: 'OS-00101', created_at: '2026-10-05T12:00:00.000Z' });
const OS_B = linha({ id: 'b', service_order_number: 'OS-00102', created_at: '2026-10-03T12:00:00.000Z' });
const OUTRO_BARCO = linha({ id: 'c', service_order_number: 'OS-00103', vessel_id: 'ves-2' });
const ORC_AGRUPADO = linha({ id: 'q', service_order_number: 'ORÇ-00200', status: 'draft', quote_status: 'draft', converted_to_os_at: null });
const ORIGEM_ORC = linha({
  id: 'q1', service_order_number: 'ORÇ-00190', status: 'cancelled', quote_status: 'draft', converted_to_os_at: null, merged_into_id: 'q',
});

function montar(mode: 'orders' | 'quotes') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>
          <OrdersListV2 mode={mode} />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

const linhaDaTabela = (numero: string) =>
  screen.getAllByText(numero).map((el) => el.closest('tr')).find((tr): tr is HTMLTableRowElement => !!tr);

// A tabela decide as colunas pela largura medida; no jsdom ela é 0 e só a do número caberia. Com tela
// larga, a coluna de situação (o selo, a troca de situação) e a de pagamento aparecem de verdade.
const larguraOriginal = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'clientWidth');
beforeAll(() => {
  Object.defineProperty(HTMLElement.prototype, 'clientWidth', { configurable: true, get: () => 1600 });
});
afterAll(() => {
  if (larguraOriginal) Object.defineProperty(HTMLElement.prototype, 'clientWidth', larguraOriginal);
});

beforeEach(() => {
  estado.linhas = [NOVA, ORIGEM_OS, OS_A, OS_B, OUTRO_BARCO, ORC_AGRUPADO, ORIGEM_ORC];
  estado.auth = { user: { id: 'u-1', role: 'admin' } };
  estado.dialogoOs = [];
  estado.dialogoOrc = 0;
  estado.erros = [];
});

describe('OrdersListV2 · agrupar OS', () => {
  it('a origem de OS agrupada fica na aba de OS com o selo, sem trocar situação nem pagamento, e fora da contagem', () => {
    montar('orders');
    const tr = linhaDaTabela('OS-00100');
    expect(tr).toBeTruthy();
    expect(within(tr!).getByText('Agrupada em OS-00140')).toBeInTheDocument();
    expect(within(tr!).queryByText('troca-situacao-o1')).not.toBeInTheDocument();
    expect(within(tr!).queryByText('Pago')).not.toBeInTheDocument();
    // a de orçamento não aparece aqui
    expect(screen.queryAllByText('ORÇ-00190')).toHaveLength(0);
    // as outras OS seguem com a troca de situação e o pagamento
    expect(within(linhaDaTabela('OS-00101')!).getByText('troca-situacao-a')).toBeInTheDocument();
    expect(within(linhaDaTabela('OS-00101')!).getByText('Pago')).toBeInTheDocument();
    // contagem da aba de orçamentos (link): só o rascunho ORÇ-00200; a da de OS (ativa): nova + a + b + c
    expect(screen.getByRole('link', { name: /Orçamentos/ })).toHaveTextContent(/Orçamentos\s*1$/);
    expect(screen.getAllByText((_, el) => el?.tagName === 'SPAN' && el.textContent === 'Ordens de Serviço4').length).toBeGreaterThan(0);
  });

  it('a origem de orçamento agrupado continua na aba de orçamentos, no masculino', () => {
    montar('quotes');
    const tr = linhaDaTabela('ORÇ-00190');
    expect(within(tr!).getByText('Agrupado em ORÇ-00200')).toBeInTheDocument();
    expect(screen.queryAllByText('OS-00100')).toHaveLength(0);
  });

  it('a barra de seleção da aba de OS abre a janela de agrupar OS, com a mais antiga como principal', async () => {
    montar('orders');
    await userEvent.click(screen.getByRole('checkbox', { name: 'Selecionar a' }));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Selecionar b' }));
    await userEvent.click(screen.getByRole('button', { name: 'Agrupar OS' }));
    expect(await screen.findByText('janela-agrupar-os')).toBeInTheDocument();
    expect(estado.dialogoOrc).toBe(0);
    expect(estado.dialogoOs.at(-1)).toMatchObject({ clientId: 'cli-1', vesselId: 'ves-1', preSelecionados: ['a', 'b'], principalSugerido: 'b' });
  });

  it('embarcações diferentes: recusa antes de abrir, com a frase de OS', async () => {
    montar('orders');
    await userEvent.click(screen.getByRole('checkbox', { name: 'Selecionar a' }));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Selecionar c' }));
    await userEvent.click(screen.getByRole('button', { name: 'Agrupar OS' }));
    expect(estado.erros).toContain('Para agrupar, escolha OS do mesmo cliente e da mesma embarcação ou veículo.');
    expect(screen.queryByText('janela-agrupar-os')).not.toBeInTheDocument();
  });

  it('técnico não vê o Agrupar OS', async () => {
    estado.auth = { user: { id: 'u-2', role: 'technician' } };
    montar('orders');
    await userEvent.click(screen.getByRole('checkbox', { name: 'Selecionar a' }));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Selecionar b' }));
    expect(screen.queryByRole('button', { name: 'Agrupar OS' })).not.toBeInTheDocument();
  });
});

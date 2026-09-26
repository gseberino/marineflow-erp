// A validade no PDF que sai das LISTAS (v1 de orçamentos, v1 de OS e v2 de orçamentos).
//
// Até 26/09/2026 o "Baixar Orçamento" direto das listas e o "Baixar N PDFs" em lote da v2
// passavam DEFAULT_PDF_OPTIONS puro, sem validade: o gerador caía no literal e todo arquivo
// dizia "Válido por 15 dias" — inclusive os de 3 e de 7. E o diálogo "Imprimir Orçamento"
// abria com o padrão da empresa, não com a validade do orçamento clicado.
//
// O teste monta cada lista de verdade, clica no menu da linha e entrega ao gerador REAL
// (buildHTMLDocument) o que a lista mandou baixar. Os mocks devolvem sempre a mesma
// referência: objeto novo a cada render faz os useEffect das telas entrarem em laço.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { buildHTMLDocument, type PDFData, type PDFOptions } from '@/lib/pdf-generator';
import { ORCAMENTO } from '../../supabase/functions/_shared/pdf/amostras';
import QuoteList from './QuoteList';
import ServiceOrderList from './ServiceOrderList';
import OrdersListV2 from '@/v2/pages/OrdersListV2';

type Baixado = { data: PDFData; options: PDFOptions };

const estado = vi.hoisted(() => ({
  baixados: [] as Baixado[],
  // O padrão da empresa em produção hoje é 3 (app_settings.quote_validity_days).
  ajustes: { quote_validity_days: '3' } as Record<string, string>,
  pdfPorId: {} as Record<string, unknown>,
  dialogo: null as null | { open: boolean; documentType: string; initialValidityDays?: number },
  linhas: [] as unknown[],
  vazio: [] as unknown[],
  mapaVazio: new Map(),
}));

vi.mock('@/hooks/use-pdf', () => ({
  usePDFData: (id?: string) => ({ data: id ? estado.pdfPorId[id] ?? null : null, error: null }),
  fetchPDFData: async (id: string) => estado.pdfPorId[id] ?? null,
}));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: estado.ajustes }) }));
vi.mock('@/lib/pdf-generator', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/lib/pdf-generator')>();
  return {
    ...real,
    downloadPDF: async (data: PDFData, options: PDFOptions) => {
      estado.baixados.push({ data, options });
    },
  };
});
vi.mock('@/lib/pdf-print', () => ({ printPDF: () => {} }));
vi.mock('@/components/PDFOptionsDialog', () => ({
  PDFOptionsDialog: (props: { open: boolean; documentType: string; initialValidityDays?: number }) => {
    estado.dialogo = { open: props.open, documentType: props.documentType, initialValidityDays: props.initialValidityDays };
    return null;
  },
}));

const mutacao = { mutate: () => {}, mutateAsync: async () => ({}), isPending: false };
vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrders: () => ({ data: estado.linhas, isLoading: false, error: null }),
  useDuplicateServiceOrder: () => mutacao,
  useUpdateServiceOrderStatus: () => mutacao,
  useCancelServiceOrder: () => mutacao,
  useReopenServiceOrder: () => mutacao,
  STATUS_TRANSITIONS: {},
  STATUS_BACKWARD_TRANSITIONS: {},
}));
vi.mock('@/hooks/use-agenda', () => ({ useTechnicians: () => ({ data: estado.vazio, isLoading: false }) }));
vi.mock('@/hooks/use-whatsapp-send-log', () => ({
  useWhatsAppSendStatusMap: () => ({ data: estado.mapaVazio }),
  useWhatsAppSendHistory: () => ({ data: estado.vazio, isLoading: false }),
}));
vi.mock('@/hooks/use-audit-log', () => ({ writeAuditLog: async () => {} }));
vi.mock('@/lib/diagnostics', () => ({ recordWhatsAppEvent: () => {} }));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {}, loading: () => 't' } }));
vi.mock('@/integrations/supabase/client', () => {
  const resposta = { data: [], error: null };
  // Qualquer cadeia (.select().eq()...) termina numa resposta vazia, sem rede.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const q: any = new Proxy({}, {
    get: (_alvo, prop) => (prop === 'then' ? (ok: (v: unknown) => void) => ok(resposta) : () => q),
  });
  return { supabase: { from: () => q, rpc: async () => resposta, functions: { invoke: async () => resposta } } };
});
// Diálogos e seletores que não entram na conta da validade.
vi.mock('@/components/WhatsAppSendHistoryDialog', () => ({ WhatsAppSendHistoryDialog: () => null }));
vi.mock('@/components/SendViaWhatsAppDialog', () => ({ SendViaWhatsAppDialog: () => null }));
vi.mock('@/components/fiscal/FaturarOsDialog', () => ({ FaturarOsDialog: () => null }));
vi.mock('@/components/purchasing/PurchaseNeedsDialog', () => ({ PurchaseNeedsDialog: () => null }));
vi.mock('@/components/QuoteStatusQuickChange', () => ({ QuoteStatusQuickChange: () => null }));
vi.mock('@/components/StatusQuickChange', () => ({ StatusQuickChange: () => null }));

/** Linha da lista; `quote_validity_days` é o que o orçamento tem gravado. */
const linha = (id: string, numero: string, status: string) => ({
  id,
  service_order_number: numero,
  status,
  quote_status: 'sent',
  priority: 'normal',
  service_type: 'maintenance',
  grand_total: 18450.5,
  share_token: null,
  scheduled_start_at: null,
  created_at: '2026-09-25T02:30:00.000Z',
  clients: { name: `Cliente ${numero}` },
  vessels: { name: 'Barco' },
});

/** Os dados do PDF do ORÇAMENTO de amostra (criado às 23h30 de 24/09), com a validade dada. */
const dadosDoPdf = (numero: string, dias: number | undefined): PDFData => ({
  ...ORCAMENTO,
  serviceOrder: { ...ORCAMENTO.serviceOrder, service_order_number: numero, quote_validity_days: dias },
});

const documento = (b: Baixado) => buildHTMLDocument(b.data, b.options);

function montar(tela: JSX.Element) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter>{tela}</MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

/**
 * Abre o menu ⋯ da linha (da TABELA) do número dado e clica no item. A v2 também desenha o
 * cartão do celular no jsdom, então o número aparece duas vezes: vale o que está numa <tr>.
 */
async function clicarNoMenu(numero: string, item: RegExp) {
  const user = userEvent.setup();
  const celulas = await screen.findAllByText(numero);
  const linhaDaTabela = celulas.map((c) => c.closest('tr')).find(Boolean)!;
  const botoes = within(linhaDaTabela).getAllByRole('button');
  await user.click(botoes[botoes.length - 1]);
  await user.click(await screen.findByRole('menuitem', { name: item }));
}

beforeEach(() => {
  estado.baixados.length = 0;
  estado.dialogo = null;
  estado.pdfPorId = {
    'q-7': dadosDoPdf('ORÇ-00107', 7),
    'q-sem': dadosDoPdf('ORÇ-00108', undefined),
    'os-7': dadosDoPdf('OS-00107', 7),
  };
});

describe('Orçamentos (v1) — Baixar Orçamento direto e Imprimir Orçamento', () => {
  beforeEach(() => {
    estado.linhas = [linha('q-7', 'ORÇ-00107', 'draft'), linha('q-sem', 'ORÇ-00108', 'draft')];
  });

  it('o arquivo sai com a validade DO orçamento (7), não o literal 15', async () => {
    montar(<QuoteList />);
    await clicarNoMenu('ORÇ-00107', /Baixar Orçamento/i);
    await waitFor(() => expect(estado.baixados).toHaveLength(1));
    expect(estado.baixados[0].options.validity).toEqual({ mode: 'days', days: 7 });
    expect(documento(estado.baixados[0])).toContain('Válido por 7 dias (até 01/10/2026)');
  });

  it('orçamento sem validade própria sai com o padrão da empresa (3)', async () => {
    montar(<QuoteList />);
    await clicarNoMenu('ORÇ-00108', /Baixar Orçamento/i);
    await waitFor(() => expect(estado.baixados).toHaveLength(1));
    expect(documento(estado.baixados[0])).toContain('Válido por 3 dias (até 27/09/2026)');
  });

  it('o diálogo de Imprimir abre com a validade do orçamento clicado', async () => {
    montar(<QuoteList />);
    await clicarNoMenu('ORÇ-00107', /Imprimir Orçamento/i);
    await waitFor(() => expect(estado.dialogo?.open).toBe(true));
    expect(estado.dialogo?.initialValidityDays).toBe(7);
  });
});

describe('Ordens de Serviço (v1) — Baixar Orçamento de uma OS', () => {
  beforeEach(() => {
    estado.linhas = [linha('os-7', 'OS-00107', 'in_progress')];
  });

  it('o orçamento baixado da OS sai com a validade dele; a OS, sem validade', async () => {
    montar(<ServiceOrderList />);
    await clicarNoMenu('OS-00107', /Baixar Orçamento/i);
    await waitFor(() => expect(estado.baixados).toHaveLength(1));
    expect(estado.baixados[0].options.validity).toEqual({ mode: 'days', days: 7 });
    expect(documento(estado.baixados[0])).toContain('Válido por 7 dias (até 01/10/2026)');

    await clicarNoMenu('OS-00107', /Baixar OS/i);
    await waitFor(() => expect(estado.baixados).toHaveLength(2));
    expect(estado.baixados[1].options.validity).toBeUndefined();
  });

  it('o diálogo de Imprimir Orçamento abre com a validade do orçamento', async () => {
    montar(<ServiceOrderList />);
    await clicarNoMenu('OS-00107', /Imprimir Orçamento/i);
    await waitFor(() => expect(estado.dialogo?.open).toBe(true));
    expect(estado.dialogo?.initialValidityDays).toBe(7);
  });
});

describe('Orçamentos (v2) — Baixar em lote e Imprimir / Baixar', () => {
  beforeEach(() => {
    estado.linhas = [linha('q-7', 'ORÇ-00107', 'draft'), linha('q-sem', 'ORÇ-00108', 'draft')];
  });

  it('cada orçamento do lote sai com a validade DELE (7 e o padrão 3)', async () => {
    const user = userEvent.setup();
    montar(<OrdersListV2 mode="quotes" />);
    await user.click(await screen.findByLabelText('Selecionar q-7'));
    await user.click(screen.getByLabelText('Selecionar q-sem'));
    await user.click(screen.getByRole('button', { name: /Baixar 2 PDFs/i }));
    await waitFor(() => expect(estado.baixados).toHaveLength(2), { timeout: 4000 });

    const porNumero = (n: string) => estado.baixados.find((b) => b.data.serviceOrder.service_order_number === n)!;
    expect(documento(porNumero('ORÇ-00107'))).toContain('Válido por 7 dias (até 01/10/2026)');
    expect(documento(porNumero('ORÇ-00108'))).toContain('Válido por 3 dias (até 27/09/2026)');
  });

  it('o diálogo abre com a validade do orçamento clicado', async () => {
    montar(<OrdersListV2 mode="quotes" />);
    await clicarNoMenu('ORÇ-00107', /Imprimir \/ Baixar/i);
    await waitFor(() => expect(estado.dialogo?.open).toBe(true));
    expect(estado.dialogo?.documentType).toBe('quote');
    expect(estado.dialogo?.initialValidityDays).toBe(7);
  });
});

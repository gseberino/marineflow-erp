// A validade que vai no PDF anexado pelo "Enviar via WhatsApp".
//
// Até 26/09/2026 o diálogo montava as opções só com resolvePdfOptions, que descarta
// `validity` de propósito (descreve um padrão, não um documento). O gerador caía no literal
// e TODO orçamento enviado pela tela dizia "Válido por 15 dias" — inclusive os de 3 dias,
// que a rotina de expiração rejeitava no 7º. Agora a validade vem de validadeDoOrcamento, a
// mesma função do Baixar do formulário, do portal e do assistente.
//
// O teste renderiza o diálogo de verdade, clica em Enviar e passa ao gerador REAL
// (buildHTMLDocument) exatamente o que o diálogo entregou ao envio. Os mocks devolvem sempre
// a mesma referência: objeto novo a cada render faz os useEffect do diálogo entrarem em laço.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { buildHTMLDocument, type PDFData, type PDFDocumentType, type PDFOptions } from '@/lib/pdf-generator';
import { ORCAMENTO } from '../../supabase/functions/_shared/pdf/amostras';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from './SendViaWhatsAppDialog';

type Envio = { pdfData: PDFData; pdfOptions: PDFOptions; documentType: PDFDocumentType; mode: string; link_title?: string; filename?: string };

const estado = vi.hoisted(() => ({
  enviados: [] as Envio[],
  /** Os pedidos de texto à IA ("Gerar com IA"), para conferir como a OS é citada. */
  pedidosAIA: [] as { body: { messages: { content: string }[] } }[],
  pdfData: null as unknown,
  // O padrão da empresa em produção hoje é 3 (app_settings.quote_validity_days).
  ajustes: { quote_validity_days: '3', company_name: 'HBR' } as Record<string, string>,
  vazio: [] as unknown[],
}));

vi.mock('@/hooks/use-pdf', () => ({ usePDFData: () => ({ data: estado.pdfData }) }));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: estado.ajustes }) }));
vi.mock('@/hooks/use-whatsapp-templates', () => ({
  useWhatsAppTemplates: () => ({ data: estado.vazio }),
  applyTemplateVariables: (corpo: string) => corpo,
}));
vi.mock('@/hooks/use-client-whatsapp-settings', () => ({
  useClientWhatsAppSettings: () => ({ data: estado.vazio }),
  pickClientSetting: () => null,
}));
const enviar = vi.hoisted(() => async (payload: unknown) => {
  estado.enviados.push(payload as Envio);
  return true;
});
vi.mock('@/hooks/use-whatsapp-send', () => ({
  useWhatsAppSend: () => ({ send: enviar, sending: false, attemptInfo: null }),
}));
vi.mock('@/hooks/use-scheduled-sends', () => ({
  useCreateScheduledSend: () => ({ mutateAsync: async () => {}, isPending: false }),
}));
vi.mock('@/integrations/supabase/client', () => {
  const linha = { data: { whatsapp: '5547999990000', phone: null }, error: null };
  const q = { select: () => q, eq: () => q, maybeSingle: async () => linha };
  const invoke = async (_nome: string, opcoes: { body: { messages: { content: string }[] } }) => {
    estado.pedidosAIA.push(opcoes);
    return { data: null, error: null };
  };
  return { supabase: { from: () => q, functions: { invoke } } };
});
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {}, loading: () => 't' } }));

// Sem shareToken não há link público: o diálogo abre direto no modo "PDF anexado".
const orcamentoAlvo: SendViaWhatsAppTarget = {
  kind: 'service_order',
  serviceOrderId: 'os-1',
  serviceOrderNumber: 'ORÇ-00100',
  shareToken: null,
  clientId: 'c-1',
  clientName: 'Cliente Exemplo',
  clientPhone: '5547999990000',
  documentType: 'quote',
};
const osAlvo: SendViaWhatsAppTarget = { ...orcamentoAlvo, serviceOrderNumber: 'OS-00100', documentType: 'service_order' };

async function enviarPeloDialogo(alvo: SendViaWhatsAppTarget): Promise<Envio> {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <SendViaWhatsAppDialog open onOpenChange={() => {}} target={alvo} />
    </QueryClientProvider>,
  );
  fireEvent.click(await screen.findByRole('button', { name: /Enviar agora/i }));
  await waitFor(() => expect(estado.enviados).toHaveLength(1));
  const envio = estado.enviados[0];
  expect(envio.mode).toBe('document');
  return envio;
}

/** O HTML que o gerador monta com o que o diálogo entregou — o mesmo caminho do generatePDFBlob. */
const documentoGerado = (e: Envio) => buildHTMLDocument({ ...e.pdfData, documentType: e.documentType }, e.pdfOptions);

beforeEach(() => {
  estado.enviados.length = 0;
  estado.pedidosAIA.length = 0;
  estado.pdfData = ORCAMENTO; // quote_validity_days: 7, criado às 23h30 de 24/09 (Brasília)
});

describe('Enviar via WhatsApp — validade no PDF anexado', () => {
  it('o orçamento sai com a validade DELE (7), não a da empresa (3) nem o literal (15)', async () => {
    const envio = await enviarPeloDialogo(orcamentoAlvo);
    expect(envio.pdfOptions.validity).toEqual({ mode: 'days', days: 7 });
    expect(documentoGerado(envio)).toContain('Válido por 7 dias (até 01/10/2026)');
  });

  it('orçamento sem validade própria usa o padrão da empresa', async () => {
    estado.pdfData = { ...ORCAMENTO, serviceOrder: { ...ORCAMENTO.serviceOrder, quote_validity_days: undefined } };
    const envio = await enviarPeloDialogo(orcamentoAlvo);
    expect(envio.pdfOptions.validity).toEqual({ mode: 'days', days: 3 });
    expect(documentoGerado(envio)).toContain('Válido por 3 dias (até 27/09/2026)');
  });

  it('OS não recebe validade de orçamento', async () => {
    const envio = await enviarPeloDialogo(osAlvo);
    expect(envio.pdfOptions.validity).toBeUndefined();
    expect(documentoGerado(envio)).not.toContain('Válido por');
  });

  // A R19 avisa do vencimento pela data fixa (quote_validity_date); o PDF anexado dizia
  // "Válido por 7 dias (até 01/10)" do mesmo orçamento (até 26/09/2026).
  it('orçamento com data fixa sai com "Válido até" a data — a mesma da R19', async () => {
    estado.pdfData = { ...ORCAMENTO, serviceOrder: { ...ORCAMENTO.serviceOrder, quote_validity_date: '2026-10-10' } };
    const envio = await enviarPeloDialogo(orcamentoAlvo);
    expect(envio.pdfOptions.validity).toEqual({ mode: 'date', date: '2026-10-10', days: 7 });
    expect(documentoGerado(envio)).toContain('Válido até 10/10/2026');
    expect(documentoGerado(envio)).not.toContain('Válido por');
  });
});

// O número da OS já vem com o prefixo ("OS-00100"). Até 11/10/2026 o título do diálogo — que
// também é o título do link que vai ao cliente — dizia "OS OS-00100", e o pedido à IA,
// "sobre a OS OS-00100".
describe('Enviar via WhatsApp — número da OS sem "OS " repetido', () => {
  it('o título do diálogo e o do envio são "OS-00100"', async () => {
    const envio = await enviarPeloDialogo(osAlvo);
    expect(screen.getByText('OS-00100')).toBeInTheDocument();
    expect(screen.queryByText(/OS OS-/)).not.toBeInTheDocument();
    expect(envio.link_title).toBe('OS-00100');
  });

  it('o orçamento segue "Orçamento ORÇ-00100"', async () => {
    const envio = await enviarPeloDialogo(orcamentoAlvo);
    expect(envio.link_title).toBe('Orçamento ORÇ-00100');
  });

  // O nome do PDF anexado punha "OS-" na frente do número que já o traz: "OS-OS-00100.pdf"
  // (até 12/10/2026). O orçamento segue com "Orcamento-" na frente: "Orcamento-ORÇ-00100.pdf".
  it('o PDF da OS se chama "OS-00100.pdf", não "OS-OS-00100.pdf"', async () => {
    const envio = await enviarPeloDialogo(osAlvo);
    expect(envio.filename).toBe('OS-00100.pdf');
  });

  it('o PDF do orçamento segue "Orcamento-ORÇ-00100.pdf"', async () => {
    const envio = await enviarPeloDialogo(orcamentoAlvo);
    expect(envio.filename).toBe('Orcamento-ORÇ-00100.pdf');
  });

  it('o pedido de texto à IA cita "a OS-00100", sem "OS OS-"', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <SendViaWhatsAppDialog open onOpenChange={() => {}} target={osAlvo} />
      </QueryClientProvider>,
    );
    fireEvent.click(await screen.findByRole('button', { name: /Gerar com IA/i }));
    await waitFor(() => expect(estado.pedidosAIA).toHaveLength(1));
    const pedido = estado.pedidosAIA[0].body.messages[0].content;
    expect(pedido).toContain('sobre a OS-00100.');
    expect(pedido).not.toContain('OS OS-');
  });
});

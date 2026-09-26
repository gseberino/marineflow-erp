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

type Envio = { pdfData: PDFData; pdfOptions: PDFOptions; documentType: PDFDocumentType; mode: string };

const estado = vi.hoisted(() => ({
  enviados: [] as Envio[],
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
  return { supabase: { from: () => q, functions: { invoke: async () => ({ data: null, error: null }) } } };
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
});

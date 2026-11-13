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

type Envio = { pdfData: PDFData; pdfOptions: PDFOptions; documentType: PDFDocumentType; mode: string; link_title?: string; filename?: string; caption?: string; message?: string };

const estado = vi.hoisted(() => ({
  enviados: [] as Envio[],
  /** Os pedidos de texto à IA ("Gerar com IA"), para conferir como a OS é citada. */
  pedidosAIA: [] as { body: { messages: { content: string }[] } }[],
  pdfData: null as unknown,
  // O padrão da empresa em produção hoje é 3 (app_settings.quote_validity_days).
  ajustes: { quote_validity_days: '3', company_name: 'HBR' } as Record<string, string>,
  vazio: [] as unknown[],
  /** Retorno F5 (P12.5): as chamadas de orcamento_validade_do_envio e a resposta de cada uma (padrão: a chave desligada). */
  rpcs: [] as Array<{ fn: string; args: Record<string, unknown> }>,
  respostaDaRpc: null as null | ((args: Record<string, unknown>) => { data: unknown; error: unknown }),
  agendados: [] as Array<Record<string, unknown>>,
  avisos: [] as string[],
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
  useCreateScheduledSend: () => ({ mutateAsync: async (v: Record<string, unknown>) => { estado.agendados.push(v); }, isPending: false }),
}));
vi.mock('@/integrations/supabase/client', () => {
  const linha = { data: { whatsapp: '5547999990000', phone: null }, error: null };
  const q = { select: () => q, eq: () => q, maybeSingle: async () => linha };
  const invoke = async (_nome: string, opcoes: { body: { messages: { content: string }[] } }) => {
    estado.pedidosAIA.push(opcoes);
    return { data: null, error: null };
  };
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    estado.rpcs.push({ fn, args });
    return estado.respostaDaRpc ? estado.respostaDaRpc(args) : { data: { ok: true, fixou: false, motivo: 'desligada' }, error: null };
  };
  return { supabase: { from: () => q, functions: { invoke }, rpc } };
});
vi.mock('sonner', () => ({ toast: { success: () => {}, error: (m: string) => { estado.avisos.push(m); }, loading: () => 't' } }));

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
  estado.rpcs.length = 0;
  estado.respostaDaRpc = null;
  estado.agendados.length = 0;
  estado.avisos.length = 0;
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

// ═══ Retorno F5 (P12.5): a validade contada do envio na tela ════════════════════════════════════════════════════════
// Ao abrir, a prévia (p_gravar falso, não grava); ao "Enviar agora", a gravação com a data que a tela mostrou (p_esperada).
// A data da F5 vale só para "Enviar agora": o agendado nunca a leva. A linha O22 vai só no PDF, numa 2ª linha da legenda,
// fora da caixa editável. A data é inventada: a resposta do banco é simulada.
const LINHA = 'Ele vale até sexta (20/11).';
const PREVIA = { data: { ok: true, fixou: false, data: '2026-11-20', dias: 7, motivo: 'previa', legenda: 'Segue o ORÇ-00100, conforme solicitado. Ele vale até sexta (20/11). Qualquer dúvida, estamos à disposição.', linha: LINHA }, error: null };
const FIXOU = { data: { ok: true, fixou: true, data: '2026-11-20', dias: 7, linha: LINHA }, error: null };
const pelaGravacao = (previa: { data: unknown; error: unknown }, envio: { data: unknown; error: unknown }) =>
  (a: Record<string, unknown>) => (a.p_gravar ? envio : previa);
const caixa = () => (document.getElementById('msg-whatsapp') as HTMLTextAreaElement).value;

function abrirOrcamento() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <SendViaWhatsAppDialog open onOpenChange={() => {}} target={orcamentoAlvo} />
    </QueryClientProvider>,
  );
}

async function irParaResumo() {
  fireEvent.click(screen.getByRole('radio', { name: /Resumo escrito/i }));
  await waitFor(() => expect(caixa()).toContain('*Orçamento ORÇ-00100*'));
}

describe('Enviar via WhatsApp — a validade do envio (F5)', () => {
  it('ao abrir, a prévia é pedida uma vez, sem gravar', async () => {
    estado.respostaDaRpc = pelaGravacao(PREVIA, FIXOU);
    abrirOrcamento();
    await screen.findByRole('button', { name: /Enviar agora/i });
    await waitFor(() => expect(estado.rpcs).toHaveLength(1));
    expect(estado.rpcs[0]).toEqual({ fn: 'orcamento_validade_do_envio', args: { p_os: 'os-1', p_gravar: false } });
  });

  it('com data: o PDF, o resumo e a linha "Vai junto" dizem a mesma data; a caixa editável não tem a linha', async () => {
    estado.respostaDaRpc = pelaGravacao(PREVIA, FIXOU);
    abrirOrcamento();
    expect(await screen.findByText(`Vai junto na legenda: '${LINHA}'`)).toBeInTheDocument();
    expect(caixa()).not.toContain('vale até');
    await irParaResumo();
    await waitFor(() => expect(caixa()).toContain('⏳ Proposta válida até 20/11/2026.'));
    expect(caixa()).not.toContain('válida por');
    expect(caixa().split('⏳').length).toBe(2);
    // no resumo, nenhuma O22: a data já está na linha do resumo
    expect(screen.queryByText(/Vai junto na legenda/)).not.toBeInTheDocument();
  });

  it('no envio do PDF: a legenda é a mensagem + a O22 numa 2ª linha, o PDF com a data do envio, e a gravação com p_esperada', async () => {
    estado.respostaDaRpc = pelaGravacao(PREVIA, FIXOU);
    abrirOrcamento();
    await screen.findByText(`Vai junto na legenda: '${LINHA}'`);
    const mensagem = caixa();
    fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
    await waitFor(() => expect(estado.enviados).toHaveLength(1));
    const envio = estado.enviados[0];
    expect(envio.caption).toBe(`${mensagem}\n${LINHA}`);
    expect(envio.pdfOptions.validity).toEqual({ mode: 'date', date: '2026-11-20' });
    expect(documentoGerado(envio)).toContain('Válido até 20/11/2026');
    expect(estado.rpcs.map((c) => c.args)).toEqual([
      { p_os: 'os-1', p_gravar: false },
      { p_os: 'os-1', p_gravar: true, p_esperada: '2026-11-20' },
    ]);
  });

  it('a mensagem que já traz o dd/mm da data vai sem a O22', async () => {
    estado.respostaDaRpc = pelaGravacao(PREVIA, FIXOU);
    abrirOrcamento();
    await screen.findByText(`Vai junto na legenda: '${LINHA}'`);
    fireEvent.change(document.getElementById('msg-whatsapp')!, { target: { value: 'Segue o orçamento, vale até 20/11.' } });
    await waitFor(() => expect(screen.queryByText(/Vai junto na legenda/)).not.toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
    await waitFor(() => expect(estado.enviados).toHaveLength(1));
    expect(estado.enviados[0].caption).toBe('Segue o orçamento, vale até 20/11.');
  });

  it("'mudou' (abriu antes da meia-noite e mandou depois): nada é enviado, a data é refeita e a tela avisa", async () => {
    const MUDOU = { data: { ok: true, fixou: false, data: '2026-11-21', antes: '2026-11-20', motivo: 'mudou' }, error: null };
    const NOVA = { data: { ...PREVIA.data, data: '2026-11-21', linha: 'Ele vale até sábado (21/11).' }, error: null };
    let previas = 0;
    estado.respostaDaRpc = (a) => (a.p_gravar ? MUDOU : (++previas === 1 ? PREVIA : NOVA));
    abrirOrcamento();
    await screen.findByText(`Vai junto na legenda: '${LINHA}'`);
    fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
    expect(await screen.findByText('A validade mudou de dia desde que você abriu: confira o texto e mande de novo.')).toBeInTheDocument();
    expect(estado.enviados).toHaveLength(0);
    expect(await screen.findByText("Vai junto na legenda: 'Ele vale até sábado (21/11).'")).toBeInTheDocument();
  });

  it('vencida: nenhuma linha de validade (nem a O22, nem a do resumo) e o aviso na tela', async () => {
    estado.respostaDaRpc = () => ({ data: { ok: true, fixou: false, data: '2026-11-10', motivo: 'vencida' }, error: null });
    abrirOrcamento();
    expect(await screen.findByText('Este orçamento venceu em 10/11: o PDF sai com essa data. Para renovar, mude a validade antes de mandar.')).toBeInTheDocument();
    expect(screen.queryByText(/Vai junto na legenda/)).not.toBeInTheDocument();
    await irParaResumo();
    await waitFor(() => expect(caixa()).not.toContain('⏳ Proposta válida'));
    fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
    await waitFor(() => expect(estado.enviados).toHaveLength(1));
    expect(estado.enviados[0].message).not.toContain('⏳ Proposta válida');
  });

  it('erro ao gravar: envia com a validade do cadastro, sem a linha, e avisa', async () => {
    estado.respostaDaRpc = pelaGravacao(PREVIA, { data: null, error: { code: '57014', message: 'tempo esgotado' } });
    abrirOrcamento();
    await screen.findByText(`Vai junto na legenda: '${LINHA}'`);
    const mensagem = caixa();
    fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
    await waitFor(() => expect(estado.enviados).toHaveLength(1));
    expect(estado.enviados[0].pdfOptions.validity).toEqual({ mode: 'days', days: 7 });
    expect(estado.enviados[0].caption).toBe(mensagem);
    expect(estado.avisos).toContain('Não consegui fixar a validade do envio; o PDF sai com a validade do cadastro.');
  });

  it.each(['funil', 'cargo'])("%s ao gravar: envia como desligada (validade do cadastro, sem a linha)", async (motivo) => {
    const resposta = motivo === 'cargo' ? { data: { ok: false, motivo }, error: null } : { data: { ok: true, fixou: false, motivo }, error: null };
    estado.respostaDaRpc = pelaGravacao(PREVIA, resposta);
    abrirOrcamento();
    await screen.findByText(`Vai junto na legenda: '${LINHA}'`);
    const mensagem = caixa();
    fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
    await waitFor(() => expect(estado.enviados).toHaveLength(1));
    expect(estado.enviados[0].pdfOptions.validity).toEqual({ mode: 'days', days: 7 });
    expect(estado.enviados[0].caption).toBe(mensagem);
    expect(estado.avisos).toEqual([]);
  });

  it('agendado: sem gravar, o resumo agendado com a validade do cadastro e o aviso; desligar volta à data da F5', async () => {
    estado.respostaDaRpc = pelaGravacao(PREVIA, FIXOU);
    abrirOrcamento();
    await screen.findByText(`Vai junto na legenda: '${LINHA}'`);
    await irParaResumo();
    await waitFor(() => expect(caixa()).toContain('⏳ Proposta válida até 20/11/2026.'));
    fireEvent.click(screen.getByRole('checkbox', { name: /Agendar envio/i }));
    expect(await screen.findByText('O envio agendado não fixa a validade de 7 dias: para isso, envie agora.')).toBeInTheDocument();
    await waitFor(() => expect(caixa()).toContain('⏳ Proposta válida por 7 dias.'));
    fireEvent.click(screen.getByRole('button', { name: /^Agendar envio$/i }));
    await waitFor(() => expect(estado.agendados).toHaveLength(1));
    expect(String(estado.agendados[0].message)).toContain('⏳ Proposta válida por 7 dias.');
    expect(String(estado.agendados[0].message)).not.toContain('20/11/2026');
    // só a prévia da abertura: nenhuma gravação
    expect(estado.rpcs.map((c) => c.args.p_gravar)).toEqual([false]);
    // desligar o agendamento de novo: o resumo volta à data da F5
    fireEvent.click(screen.getByRole('checkbox', { name: /Agendar envio/i }));
    await waitFor(() => expect(caixa()).toContain('⏳ Proposta válida até 20/11/2026.'));
  });

  it('com a chave desligada: o diálogo é o de antes (sem "Vai junto", sem aviso, a validade do cadastro)', async () => {
    abrirOrcamento();
    await screen.findByRole('button', { name: /Enviar agora/i });
    await waitFor(() => expect(estado.rpcs).toHaveLength(1));
    expect(screen.queryByText(/Vai junto na legenda/)).not.toBeInTheDocument();
    const mensagem = caixa();
    fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
    await waitFor(() => expect(estado.enviados).toHaveLength(1));
    expect(estado.enviados[0].pdfOptions.validity).toEqual({ mode: 'days', days: 7 });
    expect(estado.enviados[0].caption).toBe(mensagem);
    fireEvent.click(screen.getByRole('checkbox', { name: /Agendar envio/i }));
    expect(screen.queryByText(/O envio agendado não fixa a validade/)).not.toBeInTheDocument();
  });

  it('OS: nem pergunta ao banco', async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <SendViaWhatsAppDialog open onOpenChange={() => {}} target={osAlvo} />
      </QueryClientProvider>,
    );
    fireEvent.click(await screen.findByRole('button', { name: /Enviar agora/i }));
    await waitFor(() => expect(estado.enviados).toHaveLength(1));
    expect(estado.rpcs).toEqual([]);
  });
});

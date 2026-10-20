// "Enviar via WhatsApp" — o link só vai quando o dono pede, e a saudação é escolha dele.
//
// Pedido do dono (20/10/2026): "mesmo que eu deselecione a opção de enviar o link na interface
// do sistema, o link acaba sendo enviado". O diálogo abria no modo Link; o Resumo viajava como
// 'link' (a Evolution colava a URL no fim — caso real de 15/10, 15:37); e os modelos do banco
// punham o link no TEXTO ("Acesso: {link}") com a caixa desmarcada. E: "para saudações ao
// cliente, também coloque um campo de seleção, senão, o padrão deve ser algo como 'Segue
// ORÇ-00555 conforme solicitado…'".
//
// O teste renderiza o diálogo de verdade e confere o que ele ENTREGA ao envio (imediato e
// agendado). Os mocks devolvem sempre a mesma referência: objeto novo a cada render faz os
// useEffect do diálogo entrarem em laço.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ORCAMENTO } from '../../supabase/functions/_shared/pdf/amostras';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from './SendViaWhatsAppDialog';

type Envio = { mode: string; message: string; caption?: string; publicUrl?: string };
type Agendado = { send_mode: string; message: string; caption?: string; include_link_in_caption?: boolean };

const estado = vi.hoisted(() => ({
  enviados: [] as Envio[],
  agendados: [] as Agendado[],
  pdfData: null as unknown,
  ajustes: { quote_validity_days: '3', company_name: 'HBR Marine' } as Record<string, string>,
  vazio: [] as unknown[],
  // Os modelos do banco (whatsapp_templates), com o texto real.
  modelos: [
    { id: 'tpl-orc', name: 'Orçamento enviado', category: 'quote', active: true, sort_order: 20, body: 'Olá {cliente}, segue o orçamento {os} no valor de {valor}. Acesso: {link}' },
  ] as unknown[],
}));

vi.mock('@/hooks/use-pdf', () => ({ usePDFData: () => ({ data: estado.pdfData }) }));
vi.mock('@/hooks/use-app-settings', () => ({ useAppSettings: () => ({ data: estado.ajustes }) }));
vi.mock('@/hooks/use-whatsapp-templates', async (original) => {
  // applyTemplateVariables é a REAL: é ela que deixa "{link}" no texto quando o link não vai.
  const real = await original<typeof import('@/hooks/use-whatsapp-templates')>();
  return { ...real, useWhatsAppTemplates: () => ({ data: estado.modelos }) };
});
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
const agendar = vi.hoisted(() => async (payload: unknown) => {
  estado.agendados.push(payload as Agendado);
});
vi.mock('@/hooks/use-scheduled-sends', () => ({
  useCreateScheduledSend: () => ({ mutateAsync: agendar, isPending: false }),
}));
vi.mock('@/integrations/supabase/client', () => {
  const linha = { data: { whatsapp: '5547999990000', phone: null }, error: null };
  const q = { select: () => q, eq: () => q, maybeSingle: async () => linha };
  return { supabase: { from: () => q, functions: { invoke: async () => ({ data: null, error: null }) } } };
});
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {}, loading: () => 't' } }));

const orcamento: SendViaWhatsAppTarget = {
  kind: 'service_order',
  serviceOrderId: 'os-1',
  serviceOrderNumber: 'ORÇ-00123',
  shareToken: 'tok-123',
  clientId: 'c-1',
  clientName: 'Sandro Roberto',
  clientPhone: '5547999990000',
  documentType: 'quote',
};
const cobranca: SendViaWhatsAppTarget = {
  kind: 'receivable',
  receivableId: 'r-1',
  description: 'Saldo da OS-00100',
  serviceOrderId: 'os-1',
  shareToken: 'tok-123',
  clientId: 'c-1',
  clientName: 'Sandro Roberto',
  clientPhone: '5547999990000',
  amount: 1500,
  dueDate: '2026-10-30',
};
const urlPublica = () => `${window.location.origin}/view/tok-123`;

function abrir(alvo: SendViaWhatsAppTarget) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <SendViaWhatsAppDialog open onOpenChange={() => {}} target={alvo} />
    </QueryClientProvider>,
  );
}

const caixaDoLink = () => screen.getByRole('checkbox', { name: /Enviar também o link online/i });
const campoSaudacao = () => screen.getByLabelText('Saudação') as HTMLSelectElement;
const textoDaMensagem = () => (document.getElementById('msg-whatsapp') as HTMLTextAreaElement).value;

async function clicarEnviar(): Promise<Envio> {
  fireEvent.click(screen.getByRole('button', { name: /Enviar agora/i }));
  await waitFor(() => expect(estado.enviados).toHaveLength(1));
  return estado.enviados[0];
}

async function irParaResumo() {
  fireEvent.click(screen.getByRole('radio', { name: /Resumo escrito/i }));
  await waitFor(() => expect(textoDaMensagem()).toContain('*Orçamento ORÇ-00123*'));
}

beforeEach(() => {
  estado.enviados.length = 0;
  estado.agendados.length = 0;
  estado.pdfData = ORCAMENTO; // grand_total 18.450,50
  try { localStorage.clear(); } catch { /* sem storage no ambiente: o diálogo cai no padrão */ }
});
afterEach(() => {
  vi.useRealTimers();
});

describe('o padrão: PDF, sem link, sem saudação', () => {
  it('abre no PDF, com a caixa do link desmarcada e "Sem saudação"', async () => {
    abrir(orcamento);
    expect(await screen.findByRole('radio', { name: /PDF anexado/i })).toHaveAttribute('aria-checked', 'true');
    expect(screen.getByRole('radio', { name: /Link com preview/i })).toHaveAttribute('aria-checked', 'false');
    expect(caixaDoLink()).toHaveAttribute('aria-checked', 'false');
    expect(campoSaudacao().value).toBe('nenhuma');
    expect(within(campoSaudacao()).getByRole('option', { selected: true })).toHaveTextContent('Sem saudação');
  });

  it('a mensagem padrão é a frase curta, com o número como ele é', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    expect(textoDaMensagem()).toBe('Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.');
  });

  it('envia o PDF com a legenda SEM link', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    const envio = await clicarEnviar();
    expect(envio.mode).toBe('document');
    expect(envio.caption).toBe('Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.');
    expect(envio.caption).not.toContain('/view/');
  });

  it('com a caixa marcada, a legenda ganha "Link online: …"', async () => {
    abrir(orcamento);
    fireEvent.click(await screen.findByRole('checkbox', { name: /Enviar também o link online/i }));
    const envio = await clicarEnviar();
    expect(envio.mode).toBe('document');
    expect(envio.caption).toBe(`Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.\n\nLink online: ${urlPublica()}`);
  });
});

describe('Resumo escrito', () => {
  it('vai como TEXTO, sem link e sem a linha "Olá" (sem saudação)', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    await irParaResumo();
    expect(textoDaMensagem().split('\n')[1]).not.toMatch(/^Olá/);
    const envio = await clicarEnviar();
    expect(envio.mode).toBe('text');
    expect(envio.message).toContain('*Valores*');
    expect(envio.message).not.toContain('/view/');
  });

  it('com a caixa marcada vai como link, como era', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    await irParaResumo();
    fireEvent.click(caixaDoLink());
    const envio = await clicarEnviar();
    expect(envio.mode).toBe('link');
  });

  it('a saudação escolhida vira a linha abaixo do cabeçalho', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    fireEvent.change(campoSaudacao(), { target: { value: 'ola' } });
    await irParaResumo();
    expect(textoDaMensagem().split('\n')[1]).toBe('Olá, Sandro!');
    fireEvent.change(campoSaudacao(), { target: { value: 'nenhuma' } });
    await waitFor(() => expect(textoDaMensagem()).not.toContain('Olá'));
    expect(textoDaMensagem()).toContain('*Valores*');
  });
});

describe('link no texto com a caixa desmarcada', () => {
  it('o modelo "Orçamento enviado" sai sem "Acesso: {link}" — e com o valor do orçamento', async () => {
    abrir(orcamento);
    fireEvent.change(await screen.findByDisplayValue('— mensagem livre —'), { target: { value: 'tpl-orc' } });
    expect(textoDaMensagem()).toBe('Olá Sandro Roberto, segue o orçamento ORÇ-00123 no valor de 18.450,50.');
    const envio = await clicarEnviar();
    expect(envio.caption).toBe('Olá Sandro Roberto, segue o orçamento ORÇ-00123 no valor de 18.450,50.');
  });

  it('URL colada no texto: a tela avisa e ela sai ao enviar', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    fireEvent.change(document.getElementById('msg-whatsapp')!, {
      target: { value: `Segue o ORÇ-00123. Acesso: ${urlPublica()}` },
    });
    expect(screen.getByText(/O link não vai: ele sai da mensagem ao enviar/)).toBeInTheDocument();
    const envio = await clicarEnviar();
    expect(envio.caption).toBe('Segue o ORÇ-00123.');
  });

  it('com a caixa marcada o aviso some e o texto vai como está', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    fireEvent.change(document.getElementById('msg-whatsapp')!, {
      target: { value: `Segue o ORÇ-00123. Acesso: ${urlPublica()}` },
    });
    fireEvent.click(caixaDoLink());
    expect(screen.queryByText(/O link não vai/)).not.toBeInTheDocument();
    const envio = await clicarEnviar();
    expect(envio.caption).toBe(`Segue o ORÇ-00123. Acesso: ${urlPublica()}`);
  });
});

describe('saudação', () => {
  it('Boa tarde às 14h (Brasília): troca só a abertura, e o corpo editado fica', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-20T17:00:00Z')); // 14h em Brasília
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    fireEvent.change(document.getElementById('msg-whatsapp')!, { target: { value: 'Segue o ORÇ-00123 com a troca do inversor.' } });

    fireEvent.change(campoSaudacao(), { target: { value: 'periodo' } });
    await waitFor(() => expect(textoDaMensagem()).toBe('Boa tarde, Sandro! Segue o ORÇ-00123 com a troca do inversor.'));
    fireEvent.change(campoSaudacao(), { target: { value: 'ola' } });
    await waitFor(() => expect(textoDaMensagem()).toBe('Olá, Sandro! Segue o ORÇ-00123 com a troca do inversor.'));
    fireEvent.change(campoSaudacao(), { target: { value: 'nenhuma' } });
    await waitFor(() => expect(textoDaMensagem()).toBe('Segue o ORÇ-00123 com a troca do inversor.'));
  });

  it('lembra a última escolha de quem usa', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-20T17:00:00Z'));
    const primeira = abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    fireEvent.change(campoSaudacao(), { target: { value: 'periodo' } });
    primeira.unmount();

    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    expect(campoSaudacao().value).toBe('periodo');
    expect(textoDaMensagem()).toBe('Boa tarde, Sandro! Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.');
  });

  it('no agendamento, o período é o da hora marcada', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-21T01:00:00Z')); // 22h em Brasília
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    fireEvent.change(campoSaudacao(), { target: { value: 'periodo' } });
    await waitFor(() => expect(textoDaMensagem()).toMatch(/^Boa noite, Sandro! /));
    fireEvent.click(screen.getByRole('checkbox', { name: /Agendar envio/i }));
    const quando = document.querySelector('input[type="datetime-local"]') as HTMLInputElement;
    // A hora marcada é a do computador de quem envia — o teste roda em qualquer fuso; 08h em
    // Brasília é 11h UTC.
    const marcada = new Date('2026-10-21T11:00:00Z');
    const pad = (n: number) => String(n).padStart(2, '0');
    act(() => {
      fireEvent.change(quando, {
        target: { value: `${marcada.getFullYear()}-${pad(marcada.getMonth() + 1)}-${pad(marcada.getDate())}T${pad(marcada.getHours())}:${pad(marcada.getMinutes())}` },
      });
    });
    await waitFor(() => expect(textoDaMensagem()).toMatch(/^Bom dia, Sandro! /));
  });
});

describe('agendamento', () => {
  it('PDF agendado com a caixa desmarcada não sai (o servidor mandaria o link no lugar)', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    fireEvent.click(screen.getByRole('checkbox', { name: /Agendar envio/i }));
    expect(screen.getByRole('button', { name: /^Agendar envio$/i })).toBeDisabled();
    expect(screen.getByText(/O envio agendado ainda não anexa o PDF/)).toBeInTheDocument();
  });

  it('Resumo agendado vai como texto', async () => {
    abrir(orcamento);
    await screen.findByRole('button', { name: /Enviar agora/i });
    await irParaResumo();
    fireEvent.click(screen.getByRole('checkbox', { name: /Agendar envio/i }));
    const botao = screen.getByRole('button', { name: /^Agendar envio$/i });
    expect(botao).toBeEnabled();
    fireEvent.click(botao);
    await waitFor(() => expect(estado.agendados).toHaveLength(1));
    expect(estado.agendados[0]).toMatchObject({ send_mode: 'text', include_link_in_caption: false });
    expect(estado.agendados[0].message).not.toContain('/view/');
  });
});

describe('cobrança', () => {
  it('sem seletor de modo; vai como texto, sem link, com a frase da cobrança', async () => {
    abrir(cobranca);
    await screen.findByRole('button', { name: /Enviar agora/i });
    expect(screen.queryByRole('radio')).not.toBeInTheDocument();
    expect(textoDaMensagem()).toBe('Segue a cobrança referente a Saldo da OS-00100. Qualquer dúvida, estamos à disposição.');
    const envio = await clicarEnviar();
    expect(envio.mode).toBe('text');
    expect(envio.message).not.toContain('/view/');
  });

  it('com a caixa marcada vai o link (como ia sempre, antes da caixa existir)', async () => {
    abrir(cobranca);
    fireEvent.click(await screen.findByRole('checkbox', { name: /Enviar também o link online/i }));
    const envio = await clicarEnviar();
    expect(envio.mode).toBe('link');
  });
});

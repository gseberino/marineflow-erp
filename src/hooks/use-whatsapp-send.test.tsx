// O PDF que a tela manda pelo WhatsApp passa pelo bucket 'documents' só pelo tempo de a
// Evolution baixá-lo (26/09/2026). Antes ficava para sempre, num bucket PÚBLICO, com CPF,
// telefone e endereço de clientes e o PIX da HBR — 41 arquivos que um visitante anônimo
// conseguia listar.
//
// O que estes testes protegem:
//  1. a URL que vai para a Evolution é ASSINADA e curta — nunca a pública;
//  2. o arquivo é apagado quando a função de envio RESPONDE (deu certo, deu erro ou "já enviado");
//  3. o arquivo NÃO é apagado em erro de rede: a função pode ainda estar enviando, e apagar
//     tiraria o arquivo debaixo dela (o cliente não receberia nada).
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const chamadas = vi.hoisted(() => ({
  upload: [] as string[],
  assinadas: [] as Array<{ path: string; s: number }>,
  removidos: [] as string[],
  publicas: 0,
  invocacoes: [] as Record<string, unknown>[],
  resposta: { data: { success: true } as unknown, error: null as unknown },
  /** Respostas em sequência, uma por tentativa; vazia = usa `resposta`. */
  fila: [] as Array<{ data: unknown; error: unknown }>,
  avisos: { sucesso: [] as string[], erro: [] as string[] },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    storage: {
      from: (bucket: string) => ({
        upload: async (path: string) => { chamadas.upload.push(`${bucket}/${path}`); return { error: null }; },
        createSignedUrl: async (path: string, s: number) => {
          chamadas.assinadas.push({ path, s });
          return { data: { signedUrl: `https://sb.example/storage/v1/object/sign/${bucket}/${path}?token=t` }, error: null };
        },
        getPublicUrl: () => { chamadas.publicas++; return { data: { publicUrl: 'https://sb.example/public' } }; },
        remove: async (paths: string[]) => { chamadas.removidos.push(...paths.map((p) => `${bucket}/${p}`)); return { error: null }; },
      }),
    },
    functions: {
      invoke: async (_nome: string, { body }: { body: Record<string, unknown> }) => {
        chamadas.invocacoes.push(body);
        return chamadas.fila.shift() ?? chamadas.resposta;
      },
    },
  },
}));
vi.mock('@/lib/pdf-generator', () => ({
  generatePDFBlob: async () => new Blob(['%PDF-1.7'], { type: 'application/pdf' }),
  DEFAULT_PDF_OPTIONS: {},
}));
vi.mock('sonner', () => ({
  toast: {
    loading: () => 't',
    success: (m: string) => { chamadas.avisos.sucesso.push(m); },
    error: (m: string) => { chamadas.avisos.erro.push(m); },
  },
}));

import { useWhatsAppSend } from './use-whatsapp-send';

function montar() {
  const qc = new QueryClient();
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
  return renderHook(() => useWhatsAppSend(), { wrapper }).result;
}

const payload = {
  phone: '5547999159654', message: 'Segue o orçamento', mode: 'document' as const,
  context: 'quote', service_order_id: '11111111-1111-4111-8111-111111111111',
  pdfData: { serviceOrder: {} }, documentType: 'quote' as const, filename: 'Orcamento-ORC-00108.pdf',
};

async function enviar(resposta: { data: unknown; error: unknown }, retry = { autoRetry: false, maxAttempts: 1 }) {
  chamadas.resposta = resposta;
  const hook = montar();
  let ok = false;
  await act(async () => { ok = await hook.current.send(payload, retry); });
  return ok;
}

/** O erro que o supabase-js entrega quando a função responde não-2xx: o corpo fica em `context`. */
function erroDaFuncao(status: number, corpo: Record<string, unknown>) {
  return Object.assign(new Error('Edge Function returned a non-2xx status code'), {
    name: 'FunctionsHttpError',
    context: new Response(JSON.stringify(corpo), { status }),
  });
}
const erroDeRede = () => Object.assign(new Error('Failed to send a request to the Edge Function'), { name: 'FunctionsFetchError' });

beforeEach(() => {
  chamadas.upload = []; chamadas.assinadas = []; chamadas.removidos = []; chamadas.publicas = 0; chamadas.invocacoes = [];
  chamadas.fila = []; chamadas.avisos = { sucesso: [], erro: [] };
});

describe('PDF enviado pela tela', () => {
  it('vai para a Evolution por link ASSINADO e curto, nunca pelo público', async () => {
    expect(await enviar({ data: { success: true }, error: null })).toBe(true);
    expect(chamadas.publicas).toBe(0);
    expect(chamadas.assinadas).toHaveLength(1);
    expect(chamadas.assinadas[0].s).toBeLessThanOrEqual(300);
    expect(String(chamadas.invocacoes[0].document_url)).toContain('/object/sign/documents/');
  });

  it('é apagado depois que a função confirma o envio', async () => {
    await enviar({ data: { success: true }, error: null });
    expect(chamadas.upload).toHaveLength(1);
    expect(chamadas.removidos).toEqual(chamadas.upload);
  });

  it('é apagado quando a função responde com erro (a Evolution já desistiu)', async () => {
    const erroHttp = Object.assign(new Error('Edge Function returned a non-2xx status code'), { name: 'FunctionsHttpError' });
    expect(await enviar({ data: null, error: erroHttp })).toBe(false);
    expect(chamadas.removidos).toEqual(chamadas.upload);
  });

  it('é apagado quando a função diz que já tinha enviado (deduplicado)', async () => {
    await enviar({ data: { success: true, deduplicated: true }, error: null });
    expect(chamadas.removidos).toEqual(chamadas.upload);
  });

  it('NÃO é apagado em erro de rede: a função pode ainda estar enviando', async () => {
    const erroRede = Object.assign(new Error('Failed to send a request to the Edge Function'), { name: 'FunctionsFetchError' });
    expect(await enviar({ data: null, error: erroRede })).toBe(false);
    expect(chamadas.upload).toHaveLength(1);
    expect(chamadas.removidos).toEqual([]);
  });
});

// O defeito de 29/09/2026 (Diário de Bordo): depois de um erro de rede, a repetição automática
// ouvia "já enviado" da função enquanto a primeira tentativa ainda esperava a Evolution — e a
// tela dizia "Enviado" mesmo quando a primeira falhava. A função agora só diz "já enviado"
// quando a anterior CONCLUIU, e responde 409 em_andamento quando não sabe; a tela tem de
// ler as duas respostas sem mentir.
describe('reenvio depois de erro', () => {
  const comRepeticao = { autoRetry: true, maxAttempts: 3 };

  it('"não confirmou" (409 em_andamento): não diz Enviado, não repete e manda conferir', async () => {
    const ok = await enviar(
      { data: null, error: erroDaFuncao(409, { error: 'A tentativa anterior desta mesma mensagem ainda não confirmou se saiu. Confira no WhatsApp antes de mandar de novo.', em_andamento: true }) },
      comRepeticao,
    );
    expect(ok).toBe(false);
    expect(chamadas.invocacoes).toHaveLength(1);
    expect(chamadas.avisos.sucesso).toEqual([]);
    expect(chamadas.avisos.erro).toEqual([expect.stringContaining('Confira no WhatsApp')]);
  });

  it('rede caiu e a anterior de fato chegou: diz que foi a anterior, não este clique', async () => {
    chamadas.fila = [
      { data: null, error: erroDeRede() },
      { data: { success: true, deduplicated: true }, error: null },
    ];
    const ok = await enviar({ data: null, error: null }, comRepeticao);
    expect(ok).toBe(true);
    expect(chamadas.invocacoes).toHaveLength(2);
    expect(chamadas.avisos.sucesso).toEqual(['Enviado: a tentativa anterior já tinha chegado, não mandei de novo.']);
  }, 10_000);

  it('clique duplo: "já tinha sido enviada", sem fingir um envio novo', async () => {
    await enviar({ data: { success: true, deduplicated: true }, error: null });
    expect(chamadas.avisos.sucesso).toEqual(['Esta mensagem já tinha sido enviada há pouco; não mandei de novo.']);
  });

  it('erro da função mostra o motivo que ela escreveu, não "non-2xx status code"', async () => {
    await enviar({ data: null, error: erroDaFuncao(400, { error: 'Telefone inválido (precisa incluir DDI+DDD)' }) });
    expect(chamadas.avisos.erro).toEqual(['Falha após 1 tentativa: Telefone inválido (precisa incluir DDI+DDD)']);
  });

  it('o PDF desta tentativa sai do bucket quando a função responde "não confirmou"', async () => {
    await enviar({ data: null, error: erroDaFuncao(409, { error: 'x', em_andamento: true }) });
    expect(chamadas.removidos).toEqual(chamadas.upload);
  });
});

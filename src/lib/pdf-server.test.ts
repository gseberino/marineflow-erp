import { describe, it, expect, vi } from 'vitest';
import { renderizarNoServidor, servidorDesligadoPeloUsuario } from './pdf-server';

/**
 * O contrato que importa aqui é UM: `null` significa "use o navegador", e nunca uma
 * exceção. Se esta função lançasse, o botão Baixar morreria junto com o servidor — e o
 * servidor existe para melhorar o documento, não para virar ponto único de falha.
 */
const pdfFalso = () => new Blob([new Uint8Array(3000)], { type: 'application/pdf' });

const resposta = (ok: boolean, status: number, blob: Blob) =>
  ({ ok, status, blob: async () => blob }) as unknown as Response;

describe('renderizarNoServidor', () => {
  it('sem credencial nem tenta: portal sem token e usuário deslogado ficam no navegador', async () => {
    const fetchFn = vi.fn();
    expect(await renderizarNoServidor('<p>x</p>', 'a.pdf', null, fetchFn as unknown as typeof fetch)).toBeNull();
    expect(fetchFn).not.toHaveBeenCalled();
  });

  it('com sessão manda o JWT; com token de link manda x-share-token', async () => {
    const fetchFn = vi.fn(async () => resposta(true, 200, pdfFalso()));
    await renderizarNoServidor('<p>x</p>', 'a.pdf', { jwt: 'tok' }, fetchFn as unknown as typeof fetch);
    await renderizarNoServidor('<p>x</p>', 'a.pdf', { shareToken: 'share' }, fetchFn as unknown as typeof fetch);
    const [, init1] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    const [url2, init2] = fetchFn.mock.calls[1] as unknown as [string, RequestInit];
    expect((init1.headers as Record<string, string>).Authorization).toBe('Bearer tok');
    expect((init2.headers as Record<string, string>)['x-share-token']).toBe('share');
    expect(url2).toBe('/api/pdf');
    expect(JSON.parse(String(init2.body))).toEqual({ html: '<p>x</p>', filename: 'a.pdf' });
  });

  it('devolve o Blob quando o servidor responde um PDF de verdade', async () => {
    const fetchFn = vi.fn(async () => resposta(true, 200, pdfFalso()));
    const blob = await renderizarNoServidor('<p>x</p>', 'a.pdf', { jwt: 'tok' }, fetchFn as unknown as typeof fetch);
    expect(blob?.type).toBe('application/pdf');
    expect(blob?.size).toBe(3000);
  });

  it.each([401, 413, 500, 503])('status %i vira null, não exceção', async (status) => {
    const fetchFn = vi.fn(async () => resposta(false, status, new Blob(['{"error":"x"}'], { type: 'application/json' })));
    expect(await renderizarNoServidor('<p>x</p>', 'a.pdf', { jwt: 'tok' }, fetchFn as unknown as typeof fetch)).toBeNull();
  });

  it('resposta 200 que não é PDF (página de erro, corpo vazio) também vira null', async () => {
    const html = vi.fn(async () => resposta(true, 200, new Blob(['<html>erro</html>'], { type: 'text/html' })));
    const vazio = vi.fn(async () => resposta(true, 200, new Blob([new Uint8Array(10)], { type: 'application/pdf' })));
    expect(await renderizarNoServidor('<p>x</p>', 'a.pdf', { jwt: 'tok' }, html as unknown as typeof fetch)).toBeNull();
    expect(await renderizarNoServidor('<p>x</p>', 'a.pdf', { jwt: 'tok' }, vazio as unknown as typeof fetch)).toBeNull();
  });

  it('rede fora do ar vira null', async () => {
    const fetchFn = vi.fn(async () => { throw new TypeError('Failed to fetch'); });
    expect(await renderizarNoServidor('<p>x</p>', 'a.pdf', { jwt: 'tok' }, fetchFn as unknown as typeof fetch)).toBeNull();
  });
});

describe('chave de escape', () => {
  it('mf_pdf_local=1 no localStorage força o caminho do navegador', () => {
    localStorage.setItem('mf_pdf_local', '1');
    expect(servidorDesligadoPeloUsuario()).toBe(true);
    localStorage.removeItem('mf_pdf_local');
    expect(servidorDesligadoPeloUsuario()).toBe(false);
  });
});

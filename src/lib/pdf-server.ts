/**
 * Renderização do PDF no servidor (/api/pdf, Chromium no Vercel) — com o navegador de reserva.
 *
 * `generatePDFBlob` tenta aqui primeiro. Qualquer coisa que não seja um PDF de verdade
 * (sem sessão, offline, função desligada, timeout, erro) devolve `null`, e o chamador cai
 * no html2pdf de sempre. O usuário não vê a diferença além da qualidade: o documento
 * sempre sai.
 *
 * Fica separado de pdf-generator.ts porque aquele é lib pura (testada sem browser e sem
 * Supabase); o cliente do Supabase entra aqui por import dinâmico, só quando é usado.
 */

export type CredencialPdf = { jwt: string } | { shareToken: string } | null;

/** Chave de escape para diagnóstico: `localStorage.mf_pdf_local = '1'` força o caminho antigo. */
export function servidorDesligadoPeloUsuario(): boolean {
  try {
    return typeof localStorage !== 'undefined' && localStorage.getItem('mf_pdf_local') === '1';
  } catch {
    return false;
  }
}

/** JWT da sessão atual, ou null se não há ninguém logado (portal público, por exemplo). */
export async function credencialDaSessao(): Promise<CredencialPdf> {
  try {
    const { supabase } = await import('@/integrations/supabase/client');
    const { data } = await supabase.auth.getSession();
    const jwt = data.session?.access_token;
    return jwt ? { jwt } : null;
  } catch {
    return null;
  }
}

const TIMEOUT_MS = 45_000;

/**
 * Pede o PDF ao servidor. `null` = use o navegador. Nunca lança.
 *
 * `fetchFn` é injetável para o teste; em produção é o fetch global.
 */
export async function renderizarNoServidor(
  html: string,
  filename: string,
  credencial: CredencialPdf,
  fetchFn: typeof fetch = globalThis.fetch,
): Promise<Blob | null> {
  if (!credencial) return null;
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if ('jwt' in credencial) headers.Authorization = `Bearer ${credencial.jwt}`;
  else headers['x-share-token'] = credencial.shareToken;

  const controle = new AbortController();
  const timer = setTimeout(() => controle.abort(), TIMEOUT_MS);
  try {
    const r = await fetchFn('/api/pdf', {
      method: 'POST',
      headers,
      body: JSON.stringify({ html, filename }),
      signal: controle.signal,
    });
    if (!r.ok) {
      console.warn(`[pdf-server] servidor respondeu ${r.status}; gerando no navegador.`);
      return null;
    }
    const blob = await r.blob();
    // Um PDF real tem cabeçalho e mais de 2 KB; qualquer outra coisa é erro disfarçado.
    if (!/^application\/pdf/.test(blob.type) || blob.size < 2000) {
      console.warn('[pdf-server] resposta não é um PDF; gerando no navegador.');
      return null;
    }
    return blob;
  } catch (e) {
    console.warn('[pdf-server] indisponível; gerando no navegador.', e);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Transforma o HTML do documento em PDF no mesmo servidor que a tela usa (/api/pdf, Chromium
 * no Vercel) — chamado de dentro de uma Edge Function.
 *
 * ═══ A CREDENCIAL ═══
 *
 * O /api/pdf aceita o JWT de um usuário OU o `x-share-token` do link público da ordem (que ele
 * confere contra a RLS). No canal WhatsApp não existe JWT de usuário: o assistente roda com a
 * chave de serviço. O token do link existe em toda ordem, e é o que se manda aqui.
 *
 * Só o token — nunca `Authorization` junto: o /api/pdf dá preferência ao Bearer e, com a chave
 * de serviço nele, recusaria (ela não é um usuário) sem nem olhar o token.
 *
 * O token não sai daqui: não vai para legenda, texto nem para o resultado que o modelo lê.
 */

const LIMITE_DE_ESPERA_MS = 30_000;
/** O mesmo critério da tela (pdf-server.ts): abaixo disso não é documento, é erro. */
const TAMANHO_MINIMO = 2_000;

export type ResultadoRender =
  | { ok: true; pdf: Uint8Array }
  | { ok: false; motivo: string };

export async function renderizarPdf(params: {
  /** app_settings.app_public_url — o endereço do ERP no Vercel. */
  baseUrl: string;
  html: string;
  filename: string;
  shareToken: string;
  /** Injetável para teste. */
  fetchFn?: typeof fetch;
  limiteMs?: number;
}): Promise<ResultadoRender> {
  const base = (params.baseUrl || '').replace(/\/+$/, '');
  if (!/^https:\/\//.test(base)) return { ok: false, motivo: 'endereço público do ERP (app_public_url) ausente ou inválido' };
  if (!params.shareToken) return { ok: false, motivo: 'a ordem não tem token de link' };

  const controle = new AbortController();
  const relogio = setTimeout(() => controle.abort(), params.limiteMs ?? LIMITE_DE_ESPERA_MS);
  try {
    const r = await (params.fetchFn ?? fetch)(`${base}/api/pdf`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-share-token': params.shareToken },
      body: JSON.stringify({ html: params.html, filename: params.filename }),
      signal: controle.signal,
    });
    if (!r.ok) {
      const corpo = await r.text().catch(() => '');
      return { ok: false, motivo: `servidor de PDF respondeu ${r.status}${corpo ? `: ${corpo.slice(0, 160)}` : ''}` };
    }
    const tipo = r.headers.get('content-type') || '';
    if (!tipo.includes('application/pdf')) return { ok: false, motivo: `servidor de PDF devolveu ${tipo || 'conteúdo sem tipo'}` };
    const pdf = new Uint8Array(await r.arrayBuffer());
    // "%PDF" no começo e tamanho mínimo: uma página de erro com o tipo certo não passa.
    const assinatura = String.fromCharCode(...pdf.subarray(0, 4));
    if (pdf.length < TAMANHO_MINIMO || assinatura !== '%PDF') {
      return { ok: false, motivo: `o servidor devolveu um PDF inválido (${pdf.length} bytes)` };
    }
    return { ok: true, pdf };
  } catch (e) {
    const abortado = e instanceof DOMException && e.name === 'AbortError';
    return { ok: false, motivo: abortado ? 'o servidor de PDF não respondeu em 30 s' : `falha ao chamar o servidor de PDF: ${e instanceof Error ? e.message : String(e)}` };
  } finally {
    clearTimeout(relogio);
  }
}

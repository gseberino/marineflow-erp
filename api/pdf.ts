/**
 * /api/pdf — renderiza o HTML de um documento (orçamento, OS, fatura, recibo) em PDF com
 * um Chromium de verdade, no servidor (Vercel Serverless Function, Node).
 *
 * ═══ POR QUE EXISTE ═══
 *
 * Até 16/09/2026 o botão Baixar, o anexo do WhatsApp e o download do portal passavam pelo
 * html2pdf.js no navegador: uma "foto" do documento fatiada em folhas A4. Texto virava
 * imagem (não seleciona, não busca, arquivo 5–10× maior), a nitidez dependia do canvas do
 * aparelho (o Safari do iPhone devolve canvas em branco acima de ~16 MP) e a paginação
 * tinha que ser refeita à mão. O botão Imprimir, pelo motor do navegador, sempre saiu
 * melhor — mas o navegador não devolve o arquivo ao sistema.
 *
 * Aqui os dois caminhos convergem: o mesmo HTML que a impressão usa é renderizado pelo
 * mesmo tipo de motor, e o PDF volta como arquivo. Texto real, `@page` respeitado,
 * quebras de página por CSS.
 *
 * ═══ CONTRATO ═══
 *
 *   POST /api/pdf            body: { html: string, filename?: string }
 *     Authorization: Bearer <JWT do Supabase>   (usuário logado)   — ou —
 *     x-share-token: <token do link público>    (portal do cliente)
 *     → 200 application/pdf | 401 | 400 | 500
 *
 *   GET /api/pdf?health=1    → um PDF mínimo, sem auth: prova que o Chromium sobe aqui.
 *
 * Qualquer resposta que não seja 200 faz o cliente cair no html2pdf (ver
 * src/lib/pdf-server.ts): a função pode falhar sem ninguém ficar sem documento.
 * `PDF_SERVER_DISABLED=1` nas variáveis do Vercel desliga tudo (503) sem deploy.
 *
 * ═══ SEGURANÇA ═══
 *
 * Só renderiza para quem o Supabase reconhece (JWT válido) ou para quem tem um token de
 * link público que a RLS aceita. O HTML roda com JavaScript DESLIGADO e o corpo é limitado
 * a ~3,5 MB (o Vercel corta em 4,5 MB). Nada é gravado: entra HTML, sai PDF.
 */
import type { IncomingMessage, ServerResponse } from 'node:http';
import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';

export const config = { maxDuration: 60 };

const LIMITE_HTML = 3_500_000;
const SUPABASE_URL = (process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SUPABASE_KEY = process.env.VITE_SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';

type Req = IncomingMessage & { body?: unknown };

function responderJson(res: ServerResponse, status: number, body: unknown): void {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

function enviarPdf(res: ServerResponse, pdf: Buffer, filename: string): void {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Length', String(pdf.length));
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Cache-Control', 'no-store');
  res.end(pdf);
}

/** Só letras, números, ponto, hífen e sublinhado — o nome vai num cabeçalho HTTP. */
function nomeSeguro(nome: string): string {
  const limpo = nome.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '');
  const base = limpo || 'documento.pdf';
  return /\.pdf$/i.test(base) ? base : `${base}.pdf`;
}

async function lerCorpo(req: Req): Promise<Record<string, unknown>> {
  // O Vercel já entrega `req.body` parseado quando o Content-Type é JSON; fora isso, lê o stream.
  if (req.body !== undefined && req.body !== null) {
    return (typeof req.body === 'string' ? JSON.parse(req.body) : req.body) as Record<string, unknown>;
  }
  const partes: Buffer[] = [];
  let total = 0;
  for await (const pedaco of req) {
    const buf = Buffer.isBuffer(pedaco) ? pedaco : Buffer.from(pedaco);
    total += buf.length;
    if (total > LIMITE_HTML + 200_000) throw Object.assign(new Error('Documento grande demais para renderizar no servidor.'), { status: 413 });
    partes.push(buf);
  }
  const texto = Buffer.concat(partes).toString('utf8');
  return texto ? (JSON.parse(texto) as Record<string, unknown>) : {};
}

async function usuarioValido(jwt: string): Promise<boolean> {
  if (!SUPABASE_URL || !SUPABASE_KEY) return false;
  const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${jwt}`, apikey: SUPABASE_KEY },
  });
  return r.ok;
}

/**
 * O token do link público vale se a RLS devolver a OS dele: a mesma regra que o portal
 * usa para ler (policy `to anon` comparando o cabeçalho `x-share-token`).
 */
async function shareTokenValido(token: string): Promise<boolean> {
  if (!SUPABASE_URL || !SUPABASE_KEY || token.length < 16) return false;
  const url = `${SUPABASE_URL}/rest/v1/service_orders?select=id&share_token=eq.${encodeURIComponent(token)}&limit=1`;
  const r = await fetch(url, {
    headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, 'x-share-token': token },
  });
  if (!r.ok) return false;
  const linhas = (await r.json()) as unknown;
  return Array.isArray(linhas) && linhas.length === 1;
}

async function renderizar(html: string): Promise<Buffer> {
  const browser = await puppeteer.launch({
    args: chromium.args,
    executablePath: await chromium.executablePath(),
    headless: true,
    // A4 a 96dpi: a mesma régua da impressão no navegador e do html2pdf (703px úteis).
    defaultViewport: { width: 794, height: 1123, deviceScaleFactor: 1 },
  });
  try {
    const page = await browser.newPage();
    // O documento é HTML estático; script nenhum precisa rodar para ele existir.
    await page.setJavaScriptEnabled(false);
    // Fontes (Google Fonts) e fotos de produto vêm da rede; se algo demorar, segue com o
    // que carregou — o CSS tem stack de fallback e a foto ausente não some com o texto.
    await page.setContent(html, { waitUntil: 'load', timeout: 15_000 }).catch(() => undefined);
    await page.waitForNetworkIdle({ idleTime: 400, timeout: 10_000 }).catch(() => undefined);
    await page.emulateMediaType('print');
    const pdf = await page.pdf({
      format: 'A4',
      printBackground: true,
      preferCSSPageSize: true,
      margin: { top: '12mm', right: '12mm', bottom: '12mm', left: '12mm' },
    });
    return Buffer.from(pdf);
  } finally {
    await browser.close();
  }
}

const HTML_DE_SAUDE = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>MarineFlow</title>
<style>body{font-family:system-ui,sans-serif;padding:24mm}h1{font-size:18px;margin:0 0 8px}p{font-size:12px;color:#444}</style></head>
<body><h1>MarineFlow · renderizador de PDF no servidor</h1><p>Chromium respondeu em ${new Date().toISOString()}.</p></body></html>`;

export default async function handler(req: Req, res: ServerResponse): Promise<void> {
  try {
    if (process.env.PDF_SERVER_DISABLED === '1') {
      return responderJson(res, 503, { error: 'Renderização no servidor desligada (PDF_SERVER_DISABLED).' });
    }
    const url = new URL(req.url || '/', 'http://localhost');
    if (req.method === 'GET' && url.searchParams.get('health') === '1') {
      return enviarPdf(res, await renderizar(HTML_DE_SAUDE), 'marineflow-pdf-health.pdf');
    }
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST');
      return responderJson(res, 405, { error: 'Use POST com { html, filename }.' });
    }

    const jwt = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
    const share = String(req.headers['x-share-token'] || '').trim();
    const autorizado = jwt ? await usuarioValido(jwt) : share ? await shareTokenValido(share) : false;
    if (!autorizado) return responderJson(res, 401, { error: 'Não autenticado.' });

    const corpo = await lerCorpo(req);
    const html = typeof corpo.html === 'string' ? corpo.html : '';
    if (!html.trim()) return responderJson(res, 400, { error: 'Faltou o html do documento.' });
    if (html.length > LIMITE_HTML) return responderJson(res, 413, { error: 'Documento grande demais para renderizar no servidor.' });

    const filename = nomeSeguro(typeof corpo.filename === 'string' ? corpo.filename : 'documento.pdf');
    const inicio = Date.now();
    const pdf = await renderizar(html);
    console.info(`[api/pdf] ${filename}: ${pdf.length} bytes em ${Date.now() - inicio} ms (html ${html.length} chars)`);
    return enviarPdf(res, pdf, filename);
  } catch (err) {
    const status = typeof (err as { status?: number })?.status === 'number' ? (err as { status: number }).status : 500;
    console.error('[api/pdf] falhou:', err);
    return responderJson(res, status, { error: err instanceof Error ? err.message : 'Falha ao gerar o PDF.' });
  }
}

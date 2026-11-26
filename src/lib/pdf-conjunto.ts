/**
 * PDF do "Agrupar para o cliente": uma CAPA (o que o conjunto reúne + o quadro de valores) seguida do PDF de cada
 * documento EXATAMENTE como ele sai hoje (generatePDFBlob, com as opções salvas para o tipo). O desenho dos documentos
 * não muda — só se juntam os arquivos (pdf-lib).
 *
 * A capa é HTML simples: servidor (/api/pdf, Chromium) primeiro, html2pdf de reserva — a mesma ordem do resto.
 */
import { carregarCssDasFontes, generatePDFBlob, opcoesPadraoDoDocumento, type PDFData } from '@/lib/pdf-generator';
import { comFontesDaMarca } from '../../supabase/functions/_shared/pdf/documento';
import { FIO_EM_DEGRADE, FONTE_DO_TEXTO, FONTE_DOS_TITULOS, SLOGAN } from '../../supabase/functions/_shared/pdf/marca';
import {
  type Conjunto,
  listaNatural,
  nomeDoArquivoDoConjunto,
  numerosDoConjunto,
  quadroDeValores,
  tipoDoPdf,
} from '@/lib/conjunto';

function esc(v: unknown): string {
  return String(v ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

export interface EmpresaDaCapa {
  name?: string;
  cnpj?: string;
  phone?: string;
  email?: string;
  logo_url?: string;
}

/**
 * HTML da capa (puro: testável sem navegador). `hoje` no formato dd/mm/aaaa. `cssDasFontes`: as fontes da marca
 * (carregarCssDasFontes); sem elas, a capa sai na fonte de reserva.
 *
 * Marca (26/11/2026, a opção 4 dos documentos): letras e cores das folhas novas, o fio em degradê sob o topo, o
 * cabeçalho da tabela claro e o slogan no pé. Texto pequeno nunca mais claro que o azul #274A6D (modo rascunho).
 */
export function htmlDaCapa(c: Conjunto, empresa: EmpresaDaCapa | null, hoje: string, cssDasFontes = ''): string {
  const q = quadroDeValores(c);
  const temSinal = q.aPagarAgora > 0;
  const temRecebido = q.recebido > 0;
  const linhas = q.linhas.map((l) => `
      <tr>
        <td><strong>${esc(l.numero)}</strong><br><span class="sit">${esc(l.tipo === 'orcamento' ? 'Orçamento' : 'Ordem de serviço')} · ${esc(l.situacao)}</span></td>
        <td class="v">${brl(l.total)}</td>
        ${temRecebido ? `<td class="v">${l.recebido > 0 ? brl(l.recebido) : '—'}</td>` : ''}
        ${temSinal ? `<td class="v">${l.aPagarAgora > 0 ? brl(l.aPagarAgora) : '—'}</td>` : ''}
        <td class="v">${brl(l.saldo)}</td>
      </tr>`).join('');
  const contato = [empresa?.cnpj ? `CNPJ ${esc(empresa.cnpj)}` : '', esc(empresa?.phone ?? ''), esc(empresa?.email ?? '')]
    .filter(Boolean).join(' · ');
  return comFontesDaMarca(`<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>${esc(c.nome)}</title>
<style>
  @page { size: A4; margin: 14mm 12mm; }
  @page { @bottom-left { content: "${SLOGAN}"; font-family: ${FONTE_DO_TEXTO}; font-weight: 600; font-size: 6.5pt; letter-spacing: .14em; color: #0D1B2A; } }
  * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  body { font-family: ${FONTE_DO_TEXTO}; color: #0D1B2A; font-size: 11pt; margin: 0; }
  .topo { display: flex; align-items: center; justify-content: space-between; padding-bottom: 8px; }
  .fio { height: 3.4px; border-radius: 4px; background: ${FIO_EM_DEGRADE}; }
  .topo img { max-height: 48px; max-width: 180px; }
  .empresa { font-family: ${FONTE_DOS_TITULOS}; font-size: 13pt; font-weight: 800; color: #0D1B2A; }
  .contato { font-size: 8.5pt; color: #274A6D; margin-top: 2px; }
  h1 { font-family: ${FONTE_DOS_TITULOS}; font-size: 16pt; font-weight: 800; color: #0D1B2A; margin: 18px 0 4px; }
  .sub { color: #274A6D; margin: 0 0 14px; }
  .dados { display: flex; gap: 24px; margin-bottom: 14px; font-size: 10pt; }
  .dados div span { display: block; color: #274A6D; font-size: 8.5pt; text-transform: uppercase; letter-spacing: .03em; }
  table { width: 100%; border-collapse: collapse; font-size: 10pt; }
  th { text-align: left; background: #EEF2F6; color: #274A6D; font-family: ${FONTE_DOS_TITULOS}; font-weight: 700; font-size: 8.5pt; text-transform: uppercase; letter-spacing: .03em; padding: 6px 8px; border-bottom: 1px solid #B9C6D3; }
  th.v, td.v { text-align: right; white-space: nowrap; }
  td { padding: 7px 8px; border-bottom: 1px solid #C3CFDA; vertical-align: top; }
  .sit { color: #274A6D; font-size: 8.5pt; }
  tfoot td { font-weight: bold; border-top: 2px solid #0D1B2A; border-bottom: none; }
  .nota { margin-top: 16px; font-size: 9pt; color: #274A6D; line-height: 1.45; }
</style></head>
<body>
  <div class="topo">
    <div>
      <div class="empresa">${esc(empresa?.name ?? '')}</div>
      ${contato ? `<div class="contato">${contato}</div>` : ''}
    </div>
    ${empresa?.logo_url ? `<img src="${esc(empresa.logo_url)}" alt="">` : ''}
  </div>
  <div class="fio"></div>
  <h1>${esc(c.nome)}</h1>
  <p class="sub">Este arquivo reúne ${esc(listaNatural(numerosDoConjunto(c)))}. Cada documento vem a seguir, completo, com as condições dele.</p>
  <div class="dados">
    ${c.cliente ? `<div><span>Cliente</span>${esc(c.cliente)}</div>` : ''}
    ${c.embarcacao ? `<div><span>Embarcação</span>${esc(c.embarcacao)}</div>` : ''}
    <div><span>Data</span>${esc(hoje)}</div>
  </div>
  <table>
    <thead><tr>
      <th>Documento</th><th class="v">Total</th>
      ${temRecebido ? '<th class="v">Já pago</th>' : ''}
      ${temSinal ? '<th class="v">Sinal a pagar</th>' : ''}
      <th class="v">Saldo</th>
    </tr></thead>
    <tbody>${linhas}</tbody>
    <tfoot><tr>
      <td>Total geral</td><td class="v">${brl(q.total)}</td>
      ${temRecebido ? `<td class="v">${brl(q.recebido)}</td>` : ''}
      ${temSinal ? `<td class="v">${brl(q.aPagarAgora)}</td>` : ''}
      <td class="v">${brl(q.saldo)}</td>
    </tr></tfoot>
  </table>
  <p class="nota">Cada documento mantém as próprias condições de pagamento${temSinal ? '; o sinal a pagar é só o dos documentos que ainda pedem sinal' : ''}.
  O que já foi aprovado e assinado continua valendo como está.</p>
</body></html>`, cssDasFontes);
}

/** O pedaço do html2pdf.js usado aqui (a lib não traz tipos). */
interface CadeiaHtml2Pdf {
  set(opcoes: Record<string, unknown>): CadeiaHtml2Pdf;
  from(origem: string, tipo: 'string'): CadeiaHtml2Pdf;
  outputPdf(tipo: 'blob'): Promise<Blob>;
}

async function capaEmPdf(html: string, nome: string): Promise<Blob> {
  try {
    const srv = await import('./pdf-server');
    if (!srv.servidorDesligadoPeloUsuario()) {
      const remoto = await srv.renderizarNoServidor(html, nome, await srv.credencialDaSessao());
      if (remoto) return remoto;
    }
  } catch (e) {
    console.warn('[pdf-conjunto] servidor indisponível para a capa, gerando no navegador', e);
  }
  const html2pdf = (await import('html2pdf.js')).default as unknown as () => CadeiaHtml2Pdf;
  return html2pdf()
    .set({ margin: [14, 12, 14, 12], filename: nome, html2canvas: { scale: 2 }, jsPDF: { unit: 'mm', format: 'a4' } })
    .from(html, 'string')
    .outputPdf('blob');
}

/** Os bytes de um Blob (Blob.arrayBuffer; FileReader onde ele não existe — Safari antigo, jsdom). */
export function bytesDoBlob(b: Blob): Promise<ArrayBuffer> {
  if (typeof (b as Blob & { arrayBuffer?: unknown }).arrayBuffer === 'function') return b.arrayBuffer();
  return new Promise((ok, falha) => {
    const r = new FileReader();
    r.onload = () => ok(r.result as ArrayBuffer);
    r.onerror = () => falha(r.error ?? new Error('Não consegui ler o PDF.'));
    r.readAsArrayBuffer(b);
  });
}

/** Junta PDFs na ordem (pdf-lib, carregado só aqui). */
export async function juntarPdfs(partes: Blob[]): Promise<Blob> {
  const { PDFDocument } = await import('pdf-lib');
  const final = await PDFDocument.create();
  for (const parte of partes) {
    const doc = await PDFDocument.load(await bytesDoBlob(parte));
    const paginas = await final.copyPages(doc, doc.getPageIndices());
    paginas.forEach((p) => final.addPage(p));
  }
  const bytes = await final.save();
  return new Blob([bytes], { type: 'application/pdf' });
}

export interface DependenciasDoPdf {
  carregar: (serviceOrderId: string) => Promise<PDFData | null>;
  gerar?: typeof generatePDFBlob;
  capa?: (html: string, nome: string) => Promise<Blob>;
  juntar?: (partes: Blob[]) => Promise<Blob>;
  hoje?: () => string;
  /** As fontes da marca para a capa (padrão: carregarCssDasFontes, sob demanda). */
  fontes?: () => Promise<string>;
}

/** O PDF inteiro do conjunto: capa + cada documento ativo, na ordem (principal primeiro). */
export async function gerarPdfDoConjunto(
  c: Conjunto,
  appSettings: Record<string, string> | undefined,
  dep: DependenciasDoPdf,
): Promise<{ blob: Blob; filename: string }> {
  const ativos = c.documentos.filter((d) => d.ativo);
  if (ativos.length < 2) throw new Error('O conjunto precisa de pelo menos 2 documentos.');
  const gerar = dep.gerar ?? generatePDFBlob;
  const filename = nomeDoArquivoDoConjunto(c);

  const partes: Blob[] = [];
  let empresa: EmpresaDaCapa | null = null;
  for (const d of ativos) {
    const dados = await dep.carregar(d.id);
    if (!dados) throw new Error(`Não consegui carregar ${d.numero} para o PDF. Tente de novo.`);
    empresa ??= (dados as PDFData).company ?? null;
    const tipo = tipoDoPdf(d);
    const opcoes = opcoesPadraoDoDocumento(appSettings, tipo, dados.serviceOrder);
    partes.push(await gerar({ ...dados, documentType: tipo } as PDFData, opcoes));
  }
  const hoje = dep.hoje ? dep.hoje() : new Date().toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
  const fontes = await (dep.fontes ?? carregarCssDasFontes)();
  const capa = await (dep.capa ?? capaEmPdf)(htmlDaCapa(c, empresa, hoje, fontes), filename);
  const blob = await (dep.juntar ?? juntarPdfs)([capa, ...partes]);
  return { blob, filename };
}

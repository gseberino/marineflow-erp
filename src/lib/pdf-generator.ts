import { avisarSeForAppAtualizado } from './app-atualizado';
import {
  buildOrderHTML,
  buildPaymentHistorySection,
  buildPaymentSection,
  buildPDFFilename,
  companyHeaderHTML,
  esc,
  fmtCurrency,
  fmtDate,
  pageWrapper,
  paragrafos,
  PAYMENT_METHOD_LABELS,
  PDF_ROOT_CLASS,
  tituloParaImpressao,
  type PDFData,
  type PDFOptions,
} from '../../supabase/functions/_shared/pdf/documento';

// O documento da ordem (tipos, opções, nome do arquivo e desenho) mora em
// supabase/functions/_shared/pdf/documento.ts, para o assistente do WhatsApp gerar o
// MESMO PDF que a tela. Aqui fica só o que depende do navegador — imprimir, baixar,
// capturar — e os dois documentos que só a tela gera: fatura e recibo.
export {
  buildPDFFilename,
  DEFAULT_PDF_OPTIONS,
  PDF_ROOT_CLASS,
  resolvePdfOptions,
  tituloParaImpressao,
  validadeDoOrcamento,
} from '../../supabase/functions/_shared/pdf/documento';
export type { PDFData, PDFDocumentType, PDFOptions } from '../../supabase/functions/_shared/pdf/documento';

export function generatePDF(data: PDFData, options: PDFOptions): void {
  // O título da janela é o nome que "Salvar como PDF" sugere. Com "ORÇAMENTO ORÇ-00100"
  // o arquivo salvo pela impressão não batia com o do botão Baixar; agora é o mesmo nome.
  const html = buildHTMLDocument(data, options).replace(
    /<title>[^<]*<\/title>/,
    `<title>${esc(tituloParaImpressao(data, options))}</title>`,
  );

  // Primary: open in a dedicated window so the OS always prints/saves from the
  // right context. The iframe approach causes iPadOS to save the main ERP page
  // instead of the generated PDF when the user taps "Save" in the share sheet.
  const win = window.open('', '_blank');
  if (win) {
    // A janela imprime A SI MESMA, por um script dentro do próprio documento.
    //
    // Antes o disparo vinha daqui de fora: `win.addEventListener('load', …)`
    // mais um `setTimeout(() => win.print(), 3000)`. Dois problemas nisso:
    //
    //  · `window.open('')` abre uma janela VAZIA que carrega na hora — o
    //    `load` já tinha disparado antes de o listener existir, então quem
    //    imprimia era sempre o timer;
    //  · chamar `print()` de fora, três segundos depois, atravessa contextos
    //    de janela. Se o documento foi reescrito nesse meio-tempo, o Chrome
    //    responde "Failed to execute 'print' on 'Window': The provided
    //    callback is no longer runnable" — o erro que aparecia na tela do ERP
    //    mesmo com a impressão funcionando.
    //
    // Com o script embutido não há chamada cruzada: o `load` é o da própria
    // janela, já com o conteúdo dentro, e imprime dali mesmo.
    const autoPrint =
      '<script>window.addEventListener("load",function(){' +
      // Um quadro depois do load, para o layout assentar antes do diálogo.
      'requestAnimationFrame(function(){setTimeout(function(){window.print();},50);});' +
      '});</script>';
    win.document.write(html.replace('</body>', `${autoPrint}</body>`));
    win.document.close();
    win.focus();
    return;
  }

  // Fallback (popup bloqueado): iframe invisível
  const iframe = document.createElement('iframe');
  iframe.style.cssText = 'position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;opacity:0;';
  document.body.appendChild(iframe);

  const doc = iframe.contentDocument || iframe.contentWindow?.document;
  if (!doc) {
    // Sair calado aqui deixava o usuário clicando em "Imprimir" sem nada
    // acontecer, sem meio de descobrir que a culpa era do bloqueador de popup.
    document.body.removeChild(iframe);
    throw new Error(
      'O navegador bloqueou a janela de impressão. Libere os pop-ups para este ' +
      'site, ou use o botão Baixar, que gera o arquivo sem abrir janela.',
    );
  }

  doc.open();
  doc.write(html);
  doc.close();

  requestAnimationFrame(() => {
    setTimeout(() => {
      try {
        iframe.contentWindow?.focus();
        iframe.contentWindow?.print();
      } catch (e) {
        console.error('Print failed:', e);
      } finally {
        setTimeout(() => {
          if (document.body.contains(iframe)) {
            document.body.removeChild(iframe);
          }
        }, 2000);
      }
    }, 500);
  });
}

/**
 * Import dinâmico de html2pdf.js com 1 nova tentativa automática.
 * "Failed to fetch dynamically imported module" costuma ser uma falha pontual
 * de rede/timing (o chunk existe, só não chegou a tempo) — tentar de novo
 * depois de uma pequena pausa resolve na maioria dos casos sem incomodar o
 * usuário com um erro final que some ao tentar de novo manualmente.
 */
async function importHtml2Pdf(): Promise<any> {
  try {
    return await import('html2pdf.js');
  } catch (err) {
    console.warn('[generatePDFBlob] import dinâmico de html2pdf.js falhou, tentando novamente', err);
    await new Promise((resolve) => setTimeout(resolve, 800));
    try {
      return await import('html2pdf.js');
    } catch (err2) {
      // Falhou duas vezes: não é rede lenta. Em 24/09/2026 16:05 o dono recebeu
      // exatamente isto ao pedir o PDF — a aba dele era de antes da publicação, e o
      // arquivo com aquele nome não existe mais. Tentar uma terceira vez busca a mesma
      // URL morta; o que resolve é recarregar, e é o que o aviso oferece.
      if (avisarSeForAppAtualizado(err2)) {
        throw new Error(
          'O sistema foi atualizado enquanto esta aba estava aberta. Recarregue a página e peça o PDF de novo.',
        );
      }
      throw err2;
    }
  }
}

/**
 * Gera o PDF como Blob (sem abrir janela de impressão).
 * Usa html2pdf.js (jsPDF + html2canvas) renderizando o HTML montado por buildHTMLDocument.
 */
export async function generatePDFBlob(
  data: PDFData,
  options: PDFOptions,
  ctx?: { shareToken?: string },
): Promise<Blob> {
  const html = buildHTMLDocument(data, options);

  // Primeiro o servidor (/api/pdf, Chromium): texto real, o mesmo motor da impressão, sem
  // limite de canvas do celular. Qualquer falha — sem sessão, offline, função desligada —
  // cai no html2pdf abaixo, em silêncio. O portal manda o token do link em vez de sessão.
  try {
    const srv = await import('./pdf-server');
    if (!srv.servidorDesligadoPeloUsuario()) {
      const credencial = ctx?.shareToken ? { shareToken: ctx.shareToken } : await srv.credencialDaSessao();
      const comTitulo = html.replace(/<title>[^<]*<\/title>/, `<title>${esc(tituloParaImpressao(data, options))}</title>`);
      const remoto = await srv.renderizarNoServidor(comTitulo, buildPDFFilename(data, options), credencial);
      if (remoto) return remoto;
    }
  } catch (e) {
    console.warn('[generatePDFBlob] servidor indisponível, gerando no navegador', e);
  }

  // html2canvas precisa do elemento renderizado on-screen para capturar certo —
  // a `left:-10000px` ele rende em branco. Usamos um wrapper `fixed` na origem,
  // atrás do conteúdo do app (z-index:-1), com o container em FLUXO NORMAL dentro
  // dele (NÃO `absolute`/`fixed`). Um container fora do fluxo não contribui para a
  // altura do documento, fazendo o html2canvas calcular altura 0 (PDF em branco) e
  // medir a largura errada (conteúdo encostado à esquerda → margem direita gigante).
  // LARGURA DO CONTEÚDO = 186mm (A4 menos 12mm de cada lado), NÃO os 210mm da folha.
  //
  // Até 16/09/2026 o container media 794px (210mm). O html2pdf recebia uma imagem mais
  // larga que a área útil e a ENCOLHIA para caber nos 186mm (×0,885) — era por isso que o
  // PDF baixado saía com letra menor que o mesmo documento impresso pelo navegador. E o
  // pior ficava escondido: ele fatia a imagem a cada `canvas.width × 273/186` px, o que a
  // 794px dá 1165px por folha, enquanto os espaçadores de quebra (abaixo) eram calculados
  // para 1031. A quebra caía no meio da folha (espaço em branco seguido de bloco cortado) e
  // o rodapé da última página saía decepado. A 703px as duas réguas coincidem e a
  // geometria é exatamente a da impressão: mesma largura, mesmo corpo de letra.
  const { LARGURA_UTIL_PX } = await import('./pdf-pagination');
  const wrapper = document.createElement('div');
  wrapper.style.cssText =
    `position:fixed;top:0;left:0;width:${LARGURA_UTIL_PX}px;z-index:-1;` +
    'pointer-events:none;background:#ffffff;';
  const container = document.createElement('div');
  container.style.cssText = `width:${LARGURA_UTIL_PX}px;background:#ffffff;`;
  container.innerHTML = html;
  // Override para a captura, replicando a geometria do caminho de impressão
  // (@media print: `.container { padding: 0 }` + `@page { margin: 12mm }`):
  //  - max-width/margin:auto removidos: senão o clone do html2canvas, mais largo
  //    que o container, centraliza o `.container` (~35px à esq) e corta a direita.
  //  - padding:0: a margem do PDF vem só dos 12mm do html2pdf (abaixo), evitando
  //    margem dupla (10mm + 40px de padding ≈ 20mm, grossa demais).
  const fix = document.createElement('style');
  // Preso à raiz do documento, como o resto do CSS: `.container` sem escopo
  // pegaria qualquer elemento de mesma classe na tela do app durante a captura.
  fix.textContent =
    `.${PDF_ROOT_CLASS} .container{max-width:none !important;margin:0 !important;` +
    'width:100% !important;padding:0 !important;}';
  container.insertBefore(fix, container.firstChild);
  wrapper.appendChild(container);
  document.body.appendChild(wrapper);

  // Esconde a barra de rolagem do body durante a captura. Senão a scrollbar
  // vertical (~15px) consome largura do viewport virtual do html2canvas e desloca
  // o conteúdo, gerando margem assimétrica. Restaurada no finally.
  const prevBodyOverflow = document.body.style.overflow;
  document.body.style.overflow = 'hidden';

  // Aguarda o browser calcular layout + carregar fontes antes da captura
  await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  if ((document as any).fonts?.ready) {
    try { await (document as any).fonts.ready; } catch { /* ignore */ }
  }

  try {
    // Paginação decidida AQUI, com as alturas já calculadas pelo navegador.
    //
    // O html2pdf fatia a imagem capturada em folhas A4, e imagem não respeita
    // `page-break-inside` — foi assim que o bloco "Informações para Pagamento"
    // saiu partido ao meio. Medindo cada bloco antes e marcando onde a página
    // deve virar, o corte deixa de cair no acaso.
    //
    // NOVO-007 — nós mesmos inserimos o ESPAÇO da quebra, aqui, antes de medir.
    //
    // Antes, quem inseria era o html2pdf no modo `legacy`: ele varre o DOM e põe uma div
    // de padding antes de cada `.html2pdf__page-break`. Só que isso roda em
    // `toContainer()` — DEPOIS de `container.scrollHeight` já ter sido medido e congelado
    // em `html2canvas.height`. O documento crescia, a captura não, e o fim ficava fora da
    // imagem: PDF truncado, sem condições de pagamento nem termos. E não era só o botão
    // Baixar — este mesmo pipeline gera o anexo do WhatsApp e o download do portal público,
    // então o CLIENTE vinha recebendo documento cortado, em silêncio.
    //
    // Com o espaço inserido aqui, a altura medida logo abaixo já inclui tudo, e o `legacy`
    // sai do `pagebreak.mode` — ninguém mais mexe no DOM depois da medição.
    const alvoDaPaginacao = container.querySelector('.container') ?? container;
    const filhos = Array.from(alvoDaPaginacao.children).filter(
      (el) => el instanceof HTMLElement && el.tagName !== 'STYLE',
    ) as HTMLElement[];

    if (filhos.length > 1) {
      const { planPageBreaks, alturaDoEspacador, alturasOcupadas } = await import('./pdf-pagination');

      // NOVO-lev-12: `indivisivel` era medido aqui (um querySelector por bloco em
      // toda geração) e NUNCA lido por planPageBreaks — todo bloco que não cabe
      // desce inteiro, card ou não. Só a altura decide.
      //
      // Texto corrido (objetivo, observações, conclusão técnica, termos) é a exceção,
      // marcada com `data-pdf-quebra="dentro"`: descer inteiro deixava meia folha em
      // branco (o card de Observações de um orçamento passa de uma página) e, maior que
      // a folha, ele era fatiado no meio de uma linha. Esses blocos entram na conta
      // linha a linha — o gerador emite um <p> por linha — e o espaçador vai antes da
      // linha que não cabe. Se for a primeira do card, vai antes do card, para a borda
      // e o título acompanharem o texto.
      //
      // E a altura é a OCUPADA, não a da caixa: `.height` do rect deixa a margem de
      // fora, e quase todo bloco de topo tem margin-bottom. Medida só pela caixa, a
      // conta de "quanto já usei da folha" ficava menor que a realidade e o último
      // bloco da página saía cortado ao meio.
      type BlocoDom = { el: HTMLElement; topoDe: HTMLElement };
      const blocosDom: BlocoDom[] = [];
      for (const filho of filhos) {
        const internos = filho.dataset.pdfQuebra === 'dentro'
          ? (Array.from(filho.children).filter((c) => c instanceof HTMLElement) as HTMLElement[])
          : [];
        if (internos.length === 0) { blocosDom.push({ el: filho, topoDe: filho }); continue; }
        internos.forEach((c, k) => blocosDom.push({ el: c, topoDe: k === 0 ? filho : c }));
      }

      const rectDoContainer = alvoDaPaginacao.getBoundingClientRect();
      const caixas = blocosDom.map((b) => ({
        top: b.topoDe.getBoundingClientRect().top,
        bottom: b.el.getBoundingClientRect().bottom,
      }));
      const blocos = alturasOcupadas(caixas, rectDoContainer.bottom).map((altura) => ({ altura }));

      // Em ordem CRESCENTE, medindo um por vez: cada espaçador desloca os blocos
      // seguintes, então o topo do próximo só é confiável depois que o anterior entrou.
      // (Ler todas as posições de uma vez e inserir depois é exatamente o defeito do
      // `legacy`, que invalida as próprias coordenadas enquanto insere.)
      const topoDoContainer = rectDoContainer.top;
      for (const i of planPageBreaks(blocos)) {
        const alvo = blocosDom[i].topoDe;
        const topoDoBloco = alvo.getBoundingClientRect().top - topoDoContainer;
        const altura = alturaDoEspacador(topoDoBloco);
        if (altura <= 0) continue;
        const espacador = document.createElement('div');
        espacador.className = 'mf-page-spacer';
        espacador.setAttribute('aria-hidden', 'true');
        espacador.style.cssText = `display:block;height:${altura}px;`;
        alvo.parentNode?.insertBefore(espacador, alvo);
      }
    }

    // Import dinâmico para não pesar o bundle inicial. Falha de rede/timing
    // ("Failed to fetch dynamically imported module") costuma ser passageira —
    // uma nova tentativa silenciosa evita expor o erro ao usuário sem necessidade.
    const html2pdfModule: any = await importHtml2Pdf();
    const html2pdf = html2pdfModule.default || html2pdfModule;

    // Altura real do conteúdo após layout. Forçar width E height (mais windowWidth/
    // windowHeight e scroll/x-y em 0) garante que o html2canvas capture o conteúdo
    // de largura cheia a partir da origem — sem clipping à direita nem vazio lateral.
    const captureHeight = container.scrollHeight;

    // Escala da captura, limitada pela ÁREA do canvas.
    //
    // O Safari do iPhone e do iPad recusa canvas acima de ~16,7 megapixels e
    // não avisa: devolve um canvas em branco, e o PDF sai vazio. Com escala 2
    // fixa, um documento de 8 páginas (≈6000px de altura) daria 1588 × 12000 =
    // 19 MP e estouraria — que é exatamente o caso de uma OS com muitos itens
    // e fotos, no celular, que é onde o técnico está.
    //
    // Teto de 12 MP com folga para o iOS. Documento curto continua em 2 (a
    // nitidez que se espera de proposta impressa); só o documento longo perde
    // resolução, que é melhor que sair em branco.
    const MAX_CANVAS_MP = 12_000_000;
    const scale = Math.max(
      1,
      Math.min(2, Math.sqrt(MAX_CANVAS_MP / (LARGURA_UTIL_PX * Math.max(captureHeight, 1)))),
    );
    if (scale < 2) {
      console.info(
        `[generatePDFBlob] documento longo (${captureHeight}px): escala reduzida para ${scale.toFixed(2)} ` +
        'para não estourar o limite de canvas do navegador.',
      );
    }

    const blob: Blob = await html2pdf()
      .from(container)
      .set({
        // 12mm em todos os lados = mesma margem do caminho de impressão
        // (@page { margin: 12mm }), o espaçamento padrão do navegador.
        margin: [12, 12, 12, 12],
        filename: 'documento.pdf',
        image: { type: 'jpeg', quality: 0.92 },
        html2canvas: {
          scale,
          useCORS: true,
          backgroundColor: '#ffffff',
          width: LARGURA_UTIL_PX,
          height: captureHeight,
          windowWidth: LARGURA_UTIL_PX,
          windowHeight: captureHeight,
          scrollX: 0,
          scrollY: 0,
          x: 0,
          y: 0,
        },
        jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' },
        // `avoid-all` saiu antes: ele adivinhava onde não partir, e era a adivinhação
        // que cortava o card de pagamento ao meio.
        //
        // Agora `legacy` sai também (NOVO-007). Ele era quem inseria o padding das
        // quebras — mas em `toContainer()`, DEPOIS de `captureHeight` estar congelado
        // em `html2canvas.height`. O documento crescia sem a captura acompanhar e o fim
        // do PDF era cortado. O espaço das quebras agora entra lá em cima, antes da
        // medição, então não há mais nada para o `legacy` fazer aqui — e deixá-lo ligado
        // faria ele inserir padding DE NOVO, em cima do nosso.
        //
        // `css` continua: honra o `page-break-*` declarado na folha de estilo, que não
        // muta o DOM.
        pagebreak: { mode: ['css'] },
      })
      .outputPdf('blob');

    // PDF em branco não pode ser entregue como sucesso.
    //
    // Antes isto era um console.warn: o arquivo vazio era baixado, o toast
    // dizia "PDF baixado com sucesso", e o problema só aparecia quando alguém
    // abria o anexo — muitas vezes o cliente. Falhar aqui é o certo: quem
    // chama já trata erro e mostra a mensagem.
    if (blob.size < 2000) {
      console.error('[generatePDFBlob] PDF saiu vazio:', {
        size: blob.size,
        scrollHeight: container.scrollHeight,
      });
      throw new Error(
        'O PDF saiu em branco. Costuma ser imagem de produto que não carregou ' +
        '(bloqueio de CORS) ou documento longo demais para o navegador. ' +
        'Tente pela opção de imprimir, que não depende da captura de tela.',
      );
    }
    return blob;
  } finally {
    document.body.style.overflow = prevBodyOverflow;
    if (document.body.contains(wrapper)) document.body.removeChild(wrapper);
  }
}

/**
 * Gera o PDF e dispara o download direto do arquivo, com nome adequado
 * (tipo do documento + número da OS + cliente + embarcação). Funciona
 * de forma idêntica em desktop, celular e tablet — não depende do diálogo
 * de impressão do navegador.
 */
export async function downloadPDF(data: PDFData, options: PDFOptions, ctx?: { shareToken?: string }): Promise<void> {
  const blob = await generatePDFBlob(data, options, ctx);
  const filename = buildPDFFilename(data, options);
  const url = URL.createObjectURL(blob);
  try {
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  } finally {
    // Libera a memória do object URL após o download iniciar
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
}


// ============= Number to words (pt-BR) =============
const _ones = ['', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez',
  'onze', 'doze', 'treze', 'quatorze', 'quinze', 'dezesseis', 'dezessete', 'dezoito', 'dezenove'];
const _tens = ['', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa'];
const _hundreds = ['', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos', 'seiscentos', 'setecentos', 'oitocentos', 'novecentos'];

function _under1000(n: number): string {
  if (n === 0) return '';
  if (n === 100) return 'cem';
  const h = Math.floor(n / 100);
  const rest = n % 100;
  const parts: string[] = [];
  if (h > 0) parts.push(_hundreds[h]);
  if (rest > 0) {
    if (rest < 20) parts.push(_ones[rest]);
    else {
      const t = Math.floor(rest / 10);
      const o = rest % 10;
      parts.push(o > 0 ? `${_tens[t]} e ${_ones[o]}` : _tens[t]);
    }
  }
  return parts.join(' e ');
}

function numberToWordsBRL(value: number): string {
  if (value < 0) return 'menos ' + numberToWordsBRL(-value);
  const intPart = Math.floor(value);
  const cents = Math.round((value - intPart) * 100);

  const intWords = (() => {
    if (intPart === 0) return 'zero';
    const millions = Math.floor(intPart / 1_000_000);
    const thousands = Math.floor((intPart % 1_000_000) / 1000);
    const rest = intPart % 1000;
    const parts: string[] = [];
    if (millions > 0) parts.push(millions === 1 ? 'um milhão' : `${_under1000(millions)} milhões`);
    if (thousands > 0) parts.push(thousands === 1 ? 'mil' : `${_under1000(thousands)} mil`);
    if (rest > 0) parts.push(_under1000(rest));
    return parts.join(' e ');
  })();

  const reaisLabel = intPart === 1 ? 'real' : 'reais';
  let result = `${intWords} ${reaisLabel}`;
  if (cents > 0) {
    const centWords = _under1000(cents);
    result += ` e ${centWords} ${cents === 1 ? 'centavo' : 'centavos'}`;
  }
  return result;
}

// Exportado para permitir testar a montagem do HTML sem browser (o
// html2pdf.js só é importado dinamicamente em generatePDFBlob).
export function buildHTMLDocument(data: PDFData, options: PDFOptions): string {
  if (data.documentType === 'receipt') return buildReceiptHTML(data, options);
  if (data.documentType === 'invoice') return buildInvoiceHTML(data, options);
  return buildOrderHTML(data, options);
}

// ============= INVOICE (FATURA) =============
function buildInvoiceHTML(data: PDFData, options: PDFOptions): string {
  const docNumber = `FAT-${esc(data.serviceOrder.service_order_number)}`;
  const dueDate = options.dueDate
    ? new Date(options.dueDate + 'T12:00:00').toLocaleDateString('pt-BR')
    : (() => {
        const d = new Date();
        d.setDate(d.getDate() + 15);
        return d.toLocaleDateString('pt-BR');
      })();

  const billingUnitLabel: Record<string, string> = {
    hour: 'hora', visit: 'visita', day: 'dia', unit: 'un.',
  };

  const serviceRows = data.services.map(s => `
    <tr>
      <td style="font-weight:600;">${esc(s.name)}${s.description ? `<div style="font-weight:400;color:var(--pdf-text-muted);font-size:9px;">${esc(s.description)}</div>` : ''}</td>
      <td style="text-align:center;">${s.quantity} ${esc(billingUnitLabel[s.billing_unit] || s.billing_unit)}</td>
      <td style="text-align:right;font-weight:600;">${fmtCurrency(s.line_total)}</td>
    </tr>
  `).join('');

  const partsRows = data.parts.map(p => `
    <tr>
      <td style="font-weight:600;">${esc(p.name)}</td>
      <td style="text-align:center;">${p.quantity}</td>
      <td style="text-align:right;font-weight:600;">${fmtCurrency(p.line_total)}</td>
    </tr>
  `).join('');

  const summaryRows = [
    data.services.length > 0 ? `<tr><td>Serviços Executados</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.labor_cost_total)}</td></tr>` : '',
    data.parts.length > 0 ? `<tr><td>Materiais e Peças</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.parts_cost_total)}</td></tr>` : '',
    options.showTravelCost && data.serviceOrder.travel_cost_total > 0 ? `<tr><td>Custos de Deslocamento</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.travel_cost_total)}</td></tr>` : '',
    (() => {
      if (!options.showDiscount || data.serviceOrder.discount_amount <= 0) return '';
      const sPct = data.serviceOrder.discount_services_pct ?? 0;
      const pPct = data.serviceOrder.discount_parts_pct ?? 0;
      const hasBreakdown = sPct > 0 || pPct > 0;
      if (hasBreakdown) {
        const dSvc = Math.round(data.serviceOrder.labor_cost_total * sPct / 100 * 100) / 100;
        const dPts = Math.round(data.serviceOrder.parts_cost_total * pPct / 100 * 100) / 100;
        return [
          dSvc > 0 ? `<tr><td style="color:#dc2626;padding-left:16px;">↳ Desc. Serviços (${sPct}%)</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(dSvc)}</td></tr>` : '',
          dPts > 0 ? `<tr><td style="color:#dc2626;padding-left:16px;">↳ Desc. Peças (${pPct}%)</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(dPts)}</td></tr>` : '',
          `<tr><td style="color:#dc2626;font-weight:600;">Total Desconto</td><td style="text-align:right;color:#dc2626;font-weight:600;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>`,
        ].filter(Boolean).join('');
      }
      return `<tr><td style="color:#dc2626;">Desconto Especial</td><td style="text-align:right;color:#dc2626;">− ${fmtCurrency(data.serviceOrder.discount_amount)}</td></tr>`;
    })(),
    options.showCardFee && (data.serviceOrder.card_fee_amount ?? 0) > 0
      ? `<tr><td>Taxa de cartão${data.serviceOrder.card_installments ? ` (${data.serviceOrder.card_installments}x)` : ''}</td><td style="text-align:right;">${fmtCurrency(data.serviceOrder.card_fee_amount!)}</td></tr>`
      : '',
  ].filter(Boolean).join('');

  const bank = data.bank || {};
  const hasBank = !!(bank.bank_name || bank.bank_agency || bank.bank_account || bank.pix_key);
  // Dois toggles, um card. "Dados bancários" é a coluna da esquerda (banco, agência,
  // conta, favorecido); "instruções de pagamento" é a da direita — como pagar (PIX) e
  // o que fazer depois (mandar o comprovante). Só o `false` explícito esconde: quem
  // monta as opções à mão (portal, WhatsApp) não pode perder a coluna por omissão.
  const mostraDadosBancarios = options.showBankDetails !== false;
  const mostraInstrucoes = options.showPaymentInstructions !== false;
  const duasColunas = mostraDadosBancarios && mostraInstrucoes;

  const body = `
${companyHeaderHTML(data.company, 'Fatura de Serviço', docNumber)}

<div class="grid">
  <div class="card" style="border-left:4px solid var(--pdf-secondary);">
    <div class="section-title">Resumo Financeiro</div>
    <div style="font-size:10px;color:var(--pdf-text-muted);">Vencimento:</div>
    <div style="font-size:16px;font-weight:800;color:#dc2626;margin-bottom:8px;">${dueDate}</div>
    <div style="font-size:10px;color:var(--pdf-text-muted);">Total a Pagar:</div>
    <div style="font-size:18px;font-weight:800;color:var(--pdf-primary);">${fmtCurrency(data.serviceOrder.grand_total)}</div>
  </div>
  <div class="card">
    <div class="section-title">Informações do Pagador</div>
    <div style="font-size:12px;font-weight:700;color:var(--pdf-primary);">${esc(data.client.name)}</div>
    <div style="font-size:10px;color:var(--pdf-text-muted);">
      ${data.client.cpf_cnpj ? `CPF/CNPJ: ${esc(data.client.cpf_cnpj)}<br/>` : ''}
      ${data.client.email || ''}
    </div>
  </div>
</div>

<div class="section-title">Detalhamento dos Itens</div>
<table>
  <thead>
    <tr>
      <th>Descrição do Serviço / Produto</th>
      <th style="text-align:center;width:100px;">Qtd</th>
      <th style="text-align:right;width:120px;">Subtotal</th>
    </tr>
  </thead>
  <tbody>
    ${serviceRows}
    ${partsRows}
  </tbody>
</table>

<div style="display:flex;justify-content:flex-end;margin-bottom:30px;">
  <div style="width:300px;">
    <table class="summary-table">
      <tbody>
        ${summaryRows}
        <tr class="total-row">
          <td>VALOR TOTAL</td>
          <td style="text-align:right;">${fmtCurrency(data.serviceOrder.grand_total)}</td>
        </tr>
      </tbody>
    </table>
  </div>
</div>

${buildPaymentSection(data.serviceOrder)}
${buildPaymentHistorySection(data.serviceOrder)}

${data.serviceOrder.deposit_paid && data.serviceOrder.deposit_paid > 0 ? `
<div class="card" style="border-left:4px solid #16a34a;background:#f0fdf4;">
  <div style="display:flex;justify-content:space-between;align-items:center;">
    <div>
      <div class="section-title" style="color:#16a34a;">Sinal Recebido</div>
      <div style="font-size:10px;color:#166534;">Pagamento antecipado registrado</div>
    </div>
    <div style="text-align:right;">
      <div style="font-size:14px;font-weight:800;color:#16a34a;">− ${fmtCurrency(data.serviceOrder.deposit_paid)}</div>
      <div style="font-size:11px;font-weight:700;color:var(--pdf-primary);">Saldo: ${fmtCurrency(data.serviceOrder.grand_total - data.serviceOrder.deposit_paid)}</div>
    </div>
  </div>
</div>
` : ''}

${data.serviceOrder.financial_notes ? `
<div class="card pdf-texto" data-pdf-quebra="dentro" style="border-left:4px solid var(--pdf-border);">
  <div class="section-title">Observações Financeiras</div>
  ${paragrafos(data.serviceOrder.financial_notes, 'font-size:10px;line-height:1.6;color:var(--pdf-text-main);')}
</div>
` : ''}

${options.showExtraNotes !== false && data.serviceOrder.extra_notes ? `
<div class="card pdf-texto" data-pdf-quebra="dentro" style="border-left:4px solid var(--pdf-primary);">
  <div class="section-title">Observações</div>
  ${paragrafos(data.serviceOrder.extra_notes, 'font-size:10.5px;line-height:1.6;color:var(--pdf-text-main);')}
</div>
` : ''}

${(mostraDadosBancarios || mostraInstrucoes) && hasBank ? `
<div class="card">
  <div class="section-title">Instruções para Pagamento${data.serviceOrder.payment_method_preferred ? ` — ${PAYMENT_METHOD_LABELS[data.serviceOrder.payment_method_preferred] || data.serviceOrder.payment_method_preferred}` : ''}</div>
  <div style="display:grid;grid-template-columns:${duasColunas ? '1fr 1fr' : '1fr'};gap:12px;font-size:10px;line-height:1.6;">
    ${mostraDadosBancarios ? `<div>
      <strong>Dados Bancários:</strong><br/>
      ${bank.bank_name ? `Banco: ${esc(bank.bank_name)}<br/>` : ''}
      ${bank.bank_agency ? `Agência: ${esc(bank.bank_agency)} · ` : ''}${bank.bank_account ? `Conta: ${esc(bank.bank_account)}` : ''}<br/>
      Favorecido: ${esc(data.company.name)}<br/>
      ${data.company.cnpj ? `CNPJ: ${esc(data.company.cnpj)}` : ''}
    </div>` : ''}
    ${mostraInstrucoes ? `<div style="${duasColunas ? 'border-left:1px solid var(--pdf-border);padding-left:12px;' : ''}">
      <strong>Pague via PIX:</strong><br/>
      Chave: <span style="font-size:11px;font-weight:700;color:var(--pdf-primary);">${esc(bank.pix_key || 'N/A')}</span><br/>
      <span style="font-size:9px;color:var(--pdf-text-muted);margin-top:4px;display:block;">Após o pagamento, envie o comprovante para ${data.company.email || 'nosso contato'}.</span>
    </div>` : ''}
  </div>
</div>
` : ''}

<footer style="margin-top:50px;text-align:center;font-size:9px;color:var(--pdf-text-muted);">
  Referente à Ordem de Serviço ${esc(data.serviceOrder.service_order_number)} · Gerado em ${new Date().toLocaleString('pt-BR')}
</footer>
`;

  return pageWrapper(`FATURA ${docNumber}`, body);
}


// ============= RECEIPT (RECIBO) =============
function buildReceiptHTML(data: PDFData, options: PDFOptions): string {
  const r = data.receipt || {
    amount: data.serviceOrder.grand_total,
    payment_date: new Date().toISOString(),
    payment_method: 'pix',
    reference: data.serviceOrder.service_order_number,
  };
  const docNumber = `REC-${esc(r.reference || data.serviceOrder.service_order_number)}`;
  const methodLabel = PAYMENT_METHOD_LABELS[r.payment_method] || r.payment_method;
  const amountWords = numberToWordsBRL(r.amount);

  const body = `
${companyHeaderHTML(data.company, 'Recibo de Quitação', docNumber)}

<div class="card" style="margin:30px 0;padding:30px;background:white;position:relative;overflow:hidden;">
  <div style="position:absolute;top:0;left:0;width:4px;height:100%;background:var(--pdf-secondary);"></div>
  <div style="text-align:right;margin-bottom:20px;">
    <div style="font-size:10px;color:var(--pdf-text-muted);text-transform:uppercase;">Valor Recebido</div>
    <div style="font-size:24px;font-weight:800;color:var(--pdf-primary);">${fmtCurrency(r.amount)}</div>
  </div>
  
  <div style="font-size:14px;line-height:2;text-align:justify;color:var(--pdf-text-main);">
    Recebemos de <strong>${esc(data.client.name).toUpperCase()}</strong>, 
    ${data.client.cpf_cnpj ? `inscrito(a) no CPF/CNPJ sob o nº <strong>${esc(data.client.cpf_cnpj)}</strong>, ` : ''}
    a importância líquida e certa de <strong>${fmtCurrency(r.amount)}</strong> 
    <span style="font-size:11px;color:var(--pdf-text-muted);">(${esc(amountWords)})</span>, 
    referente ao pagamento de <strong>${esc(r.reference || data.serviceOrder.service_order_number)}</strong>
    ${data.vessel ? ` (Ativo: ${esc(data.vessel.name)})` : ''}.
  </div>
  
  <div style="margin-top:20px;font-size:12px;color:var(--pdf-text-muted);">
    Forma de Pagamento: <strong>${esc(methodLabel)}</strong><br/>
    Data da Transação: <strong>${fmtDate(r.payment_date)}</strong>
  </div>
</div>

<div class="grid">
  <div class="card">
    <div class="section-title">Dados do Emissor</div>
    <div style="font-size:11px;">
      <strong>${esc(data.company.name)}</strong><br/>
      CNPJ: ${esc(data.company.cnpj || '—')}<br/>
      ${esc(data.company.city || '')} / ${esc(data.company.state || '')}
    </div>
  </div>
  <div style="text-align:center;padding-top:20px;">
    <div style="height:50px;"></div>
    <div style="border-top:1px solid var(--pdf-primary);padding-top:8px;">
      <div style="font-weight:700;font-size:11px;">${esc(data.company.name).toUpperCase()}</div>
      <div style="font-size:9px;color:var(--pdf-text-muted);">Assinatura Autorizada</div>
    </div>
  </div>
</div>

<footer style="margin-top:50px;text-align:center;font-size:9px;color:var(--pdf-text-muted);">
  Este recibo confirma a quitação do valor acima descrito para os fins de direito.
</footer>
`;

  return pageWrapper(`RECIBO ${docNumber}`, body);
}

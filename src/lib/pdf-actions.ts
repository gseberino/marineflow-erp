import { toast } from 'sonner';
import { generatePDFBlob, buildPDFHTML, type PDFData, type PDFOptions } from './pdf-generator';

export type PDFAction = 'print' | 'download';

function isLikelyMobileOrPWA(): boolean {
  return /iPhone|iPad|iPod|Android/i.test(navigator.userAgent)
    || window.matchMedia('(display-mode: standalone)').matches
    || (navigator as any).standalone === true;
}

/**
 * Fallback: abre uma nova aba com o HTML puro para impressão caso o PDF falhe.
 */
function openPrintableHTMLFallback(data: PDFData, options: PDFOptions) {
  const html = buildPDFHTML(data, options);
  const win = window.open('', '_blank');
  
  if (!win) {
    toast.error('O navegador bloqueou a abertura da nova aba. Por favor, habilite popups para imprimir.');
    return;
  }

  win.document.open();
  win.document.write(html);
  win.document.close();
  
  toast.info('Utilizando modo de compatibilidade (HTML imprimível).');
  
  // Aguarda renderização básica antes de sugerir Ctrl+P
  setTimeout(() => {
    try {
      win.focus();
      // Em alguns navegadores o .print() pode ser bloqueado se não houver interação,
      // mas como foi aberto por clique do usuário no ERP, costuma funcionar.
      win.print();
    } catch (e) {
      console.warn('[PDF] Auto-print failed', e);
    }
  }, 800);
}

export async function generateAndHandlePDF(
  data: PDFData,
  options: PDFOptions,
  action: PDFAction = 'print'
): Promise<void> {
  const filename = `${data.documentType === 'quote' ? 'orcamento' : 'ordem-servico'}-${data.serviceOrder.service_order_number}.pdf`;
  const mobile = isLikelyMobileOrPWA();

  // Em mobile/PWA a ação 'print' (abrir em nova aba) é pouco confiável.
  // Preferimos o fallback HTML imprimível que o usuário pode salvar/compartilhar.
  if (mobile && action === 'print') {
    toast.info('Seu navegador pode limitar a abertura de PDFs. Abrindo versão imprimível do documento.');
    openPrintableHTMLFallback(data, options);
    return;
  }

  try {
    const blob = await generatePDFBlob(data, options);

    // Sanity check para PDF em branco
    // Um PDF com conteúdo real dificilmente tem menos de 5KB (especialmente com escalas e imagens)
    if (blob.size < 5000) {
      console.warn('[PDF] Blob gerado é muito pequeno, possível página em branco. Acionando fallback.', { size: blob.size });
      openPrintableHTMLFallback(data, options);
      return;
    }

    const url = URL.createObjectURL(blob);

    if (action === 'download') {
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast.success('PDF baixado com sucesso!');
    } else {
      const win = window.open(url, '_blank');
      if (!win) {
        // Popup bloqueado — fallback automático para download
        toast.error('O navegador bloqueou a abertura da nova aba. O arquivo será baixado automaticamente.');
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      } else {
        win.focus();
        // Mantém a URL ativa por 10s para garantir o carregamento na nova aba
        setTimeout(() => URL.revokeObjectURL(url), 10000);
        toast.success('PDF gerado com sucesso!');
      }
    }
  } catch (error: any) {
    console.error('[PDF] Erro crítico na geração do Blob:', error);
    // Em mobile, o fallback HTML é mais confiável que tentar novamente
    if (mobile) {
      toast.info('Abrindo versão imprimível do documento (compatível com seu dispositivo).');
    } else {
      toast.error('Houve um erro ao gerar o arquivo PDF. Tentando modo de compatibilidade...');
    }
    openPrintableHTMLFallback(data, options);
  }
}

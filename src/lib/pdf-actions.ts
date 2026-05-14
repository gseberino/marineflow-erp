import { toast } from 'sonner';
import { generatePDFBlob, type PDFData, type PDFOptions } from './pdf-generator';

export type PDFAction = 'print' | 'download';

export async function generateAndHandlePDF(
  data: PDFData,
  options: PDFOptions,
  action: PDFAction = 'print'
): Promise<void> {
  const filename = `${data.documentType === 'quote' ? 'orcamento' : 'ordem-servico'}-${data.serviceOrder.service_order_number}.pdf`;
  
  try {
    const blob = await generatePDFBlob(data, options);

    if (blob.size < 2000) {
      throw new Error('O PDF gerado parece estar vazio. Tente novamente.');
    }

    const url = URL.createObjectURL(blob);

    if (action === 'download') {
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      // Revoke after a short delay to ensure the browser has started the download
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast.success('PDF baixado com sucesso!');
    } else {
      const win = window.open(url, '_blank');
      if (!win) {
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
        // Give the browser plenty of time to load the Blob into the new tab before revoking.
        // 10 seconds is usually enough even for slow systems.
        setTimeout(() => URL.revokeObjectURL(url), 10000);
        toast.success('PDF aberto em nova aba!');
      }
    }
  } catch (error: any) {
    console.error('Error generating PDF:', error);
    toast.error(`Erro ao gerar PDF: ${error.message || 'Erro desconhecido'}`);
    throw error;
  }
}

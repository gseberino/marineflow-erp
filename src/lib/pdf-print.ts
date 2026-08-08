import { toast } from 'sonner';
import { generatePDF, type PDFData, type PDFOptions } from './pdf-generator';

/**
 * Imprimir avisando quando não dá.
 *
 * `generatePDF` abre uma janela e manda imprimir. Quando o navegador bloqueia
 * o pop-up e o iframe de reserva também não vai, não havia o que fazer além de
 * um `return` mudo: o usuário clicava em Imprimir e a tela ficava igual. A
 * causa mais comum é o bloqueador de pop-up — coisa que se resolve em dois
 * cliques, desde que alguém diga qual é o problema.
 *
 * Fica separado de pdf-generator.ts porque aquele arquivo é lib pura, testada
 * sem browser e sem UI; o toast é decisão de interface.
 */
export function printPDF(data: PDFData, options: PDFOptions): void {
  try {
    generatePDF(data, options);
  } catch (e) {
    console.error('[printPDF] falhou:', e);
    toast.error(e instanceof Error ? e.message : 'Não deu para abrir a impressão.');
  }
}

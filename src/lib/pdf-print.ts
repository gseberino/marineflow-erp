import { toast } from 'sonner';
import {
  carregarCssDasFontes,
  comRevisaoSeFaltar,
  fontesDaMarcaCarregadas,
  generatePDF,
  type PDFData,
  type PDFOptions,
} from './pdf-generator';
import { precisaDeRevisao } from '../../supabase/functions/_shared/pdf/revisao';

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
 *
 * Revisão (17/11/2026): o documento de uma ordem leva a Rev. N, que vem do banco. A janela abre AQUI, ainda no
 * clique — `window.open` depois de esperar a resposta cairia no bloqueador de pop-up — e recebe o documento quando
 * a revisão chega. Sem resposta, o documento sai sem a revisão, como antes.
 *
 * Fontes da marca (26/11/2026): na primeira impressão da sessão elas ainda não chegaram (vêm sob demanda,
 * carregarCssDasFontes); a janela abre no clique, do mesmo jeito, e o documento entra quando elas chegam.
 */
export function printPDF(data: PDFData, options: PDFOptions): void {
  if (!precisaDeRevisao(data) && fontesDaMarcaCarregadas()) {
    imprimir(data, options);
    return;
  }
  const janela = window.open('', '_blank');
  if (janela) {
    janela.document.write(
      '<p style="font-family:system-ui,sans-serif;padding:24px;color:#64748B">Preparando o documento…</p>',
    );
  }
  const revisao = comRevisaoSeFaltar(data).catch(() => ({ ...data, revisao: null }));
  // carregarCssDasFontes nunca falha (sem as fontes, devolve '' e o documento sai na reserva).
  void Promise.all([revisao, carregarCssDasFontes()]).then(([pronto]) => imprimir(pronto, options, janela));
}

function imprimir(data: PDFData, options: PDFOptions, janela?: Window | null): void {
  try {
    generatePDF(data, options, janela);
  } catch (e) {
    console.error('[printPDF] falhou:', e);
    toast.error(e instanceof Error ? e.message : 'Não deu para abrir a impressão.');
  }
}

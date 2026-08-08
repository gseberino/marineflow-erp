/**
 * O jeito único de entregar um arquivo ao usuário.
 *
 * ═══ POR QUE ISTO EXISTE ═══
 *
 * O sistema tinha três jeitos diferentes de baixar arquivo, e um deles estava
 * errado em seis lugares:
 *
 *     link.click();
 *     URL.revokeObjectURL(url);   // ← corrida
 *
 * Revogar o object URL na linha seguinte ao clique é uma aposta em quem chega
 * primeiro. No Chrome costuma dar certo porque o download é enfileirado antes;
 * no Firefox e no Safari o URL morre antes de o arquivo começar a baixar, e o
 * download falha SEM ERRO NENHUM — o usuário clica, nada acontece, e não há o
 * que investigar depois.
 *
 * O elemento também precisa estar no documento antes do clique: link solto na
 * memória não dispara download em todos os navegadores.
 *
 * A frente fiscal já fazia certo (append → click → remove → revoke tardio).
 * Isto aqui é aquele padrão, num lugar só, para os outros pararem de divergir.
 */

/** Tempo até revogar o URL. Generoso de propósito: memória é barata, download perdido não. */
const REVOKE_DELAY_MS = 60_000;

/**
 * Baixa um Blob com o nome dado.
 *
 * Devolve o URL criado apenas para quem precisar revogá-lo antes (nenhum caso
 * hoje) — ignorá-lo é o uso normal.
 */
export function downloadBlob(blob: Blob, filename: string): string {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  // rel=noopener: se o navegador decidir abrir em vez de baixar (acontece no
  // Safari com alguns tipos), a aba nova não ganha referência a esta.
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), REVOKE_DELAY_MS);
  return url;
}

/** Baixa texto puro (CSV, XML, JSON) sem quem chama precisar montar o Blob. */
export function downloadText(
  content: string, filename: string, mime = 'text/plain;charset=utf-8;',
): void {
  downloadBlob(new Blob([content], { type: mime }), filename);
}

/**
 * CSV com BOM, para o Excel brasileiro não comer os acentos.
 *
 * Sem o ﻿ na frente, o Excel assume a codificação da máquina e "Instalação"
 * vira "InstalaÃ§Ã£o" na tela do contador.
 */
export function downloadCSV(content: string, filename: string): void {
  downloadBlob(new Blob([withBom(content)], { type: 'text/csv;charset=utf-8;' }), filename);
}

/**
 * Põe o BOM uma vez só.
 *
 * Vários chamadores já concatenavam o ﻿ por conta própria; sem esta guarda, o
 * arquivo sairia com dois e a primeira coluna do Excel viria com lixo na
 * frente. Separada para poder ser testada sem Blob — o jsdom não implementa
 * `Blob.text()`.
 */
export function withBom(content: string): string {
  return content.startsWith('﻿') ? content : `﻿${content}`;
}

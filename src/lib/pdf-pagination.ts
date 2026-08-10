/**
 * Onde o documento deve virar a página.
 *
 * ═══ POR QUE ISTO EXISTE ═══
 *
 * No caminho de IMPRIMIR, quem pagina é o navegador, e ele respeita
 * `page-break-inside: avoid` — bloco não parte no meio.
 *
 * No caminho de BAIXAR, não. O html2canvas rasteriza o documento inteiro numa
 * imagem e o html2pdf FATIA essa imagem em folhas A4. Imagem não tem CSS: o
 * corte cai onde calhar o pixel, e foi assim que o bloco "Informações para
 * Pagamento" saiu partido ao meio no PDF do dono — com os dados bancários numa
 * página e o resto na outra.
 *
 * A saída é não deixar o corte para o acaso: medir cada bloco antes da captura
 * e inserir quebra explícita onde ele não couber no que resta da folha. É o que
 * esta função decide — aritmética pura, sem DOM, para poder ser testada.
 */

/** A4 retrato a 96dpi, descontadas as margens de 12mm usadas na geração. */
export const ALTURA_UTIL_PX = Math.round(((297 - 24) / 25.4) * 96); // ≈ 1032

export interface Bloco {
  /** Altura renderizada, em pixels. */
  altura: number;
  /**
   * Bloco que não deve ser partido (um card, uma tabela curta). Bloco mais alto
   * que a folha é partido de qualquer jeito — não há onde colocá-lo inteiro.
   */
  indivisivel?: boolean;
}

/**
 * Índices dos blocos que devem COMEÇAR uma página nova.
 *
 * O primeiro bloco nunca entra: ele já começa a primeira página, e uma quebra
 * antes dele produziria uma folha em branco na frente do documento.
 */
export function planPageBreaks(
  blocos: Bloco[],
  alturaUtil: number = ALTURA_UTIL_PX,
): number[] {
  const quebras: number[] = [];
  let usado = 0;

  for (let i = 0; i < blocos.length; i++) {
    const { altura, indivisivel } = blocos[i];

    // Bloco maior que a folha inteira: não adianta empurrar para a próxima,
    // ele vai ser partido de todo jeito. Deixa seguir e recomeça a contagem
    // pelo que sobra do último pedaço.
    if (altura > alturaUtil) {
      usado = altura % alturaUtil;
      continue;
    }

    if (usado + altura <= alturaUtil) {
      usado += altura;
      continue;
    }

    // Não cabe no que resta. Bloco indivisível desce inteiro para a próxima
    // folha; bloco comum também — partir texto no meio de uma linha é pior que
    // um espaço em branco no pé da página.
    if (i > 0) quebras.push(i);
    usado = altura;
  }

  return quebras;
}

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

/**
 * A altura de página EXATAMENTE como o html2pdf a calcula.
 *
 * Ele faz `toPx(273mm, k) = Math.floor(273 * k / 72 * 96)` com `k = 72/25.4`, o que dá
 * **1031** — um pixel a menos que `ALTURA_UTIL_PX`, que arredonda. Um pixel não muda a
 * decisão de "cabe ou não cabe" (por isso o planejamento usa a constante acima), mas os
 * espaçadores PRECISAM bater com a régua dele: é a fatia do html2pdf que decide onde a
 * folha vira, e 1px de erro por página se acumula ao longo do documento.
 */
export const PX_PAGINA_HTML2PDF = Math.floor(((297 - 24) / 25.4) * 96); // = 1031

export interface Espacador {
  /** Índice do bloco que deve começar a página seguinte. */
  indice: number;
  /** Altura, em px, do espaçador a inserir ANTES desse bloco. */
  altura: number;
}

/**
 * Quanto de espaço inserir antes de cada bloco que começa página nova (NOVO-007).
 *
 * ═══ POR QUE ISTO EXISTE ═══
 *
 * Antes, quem inseria esse espaço era o próprio html2pdf, no modo `legacy`: ele varre o
 * DOM e insere uma div de padding antes de cada `.html2pdf__page-break`. O problema é
 * QUANDO isso acontece — dentro de `toContainer()`, ou seja, **depois** de já termos
 * medido `container.scrollHeight` e congelado esse valor em `html2canvas.height`. O
 * documento crescia, a captura não, e o fim do documento ficava fora da imagem: o PDF
 * saía truncado, sem condições de pagamento nem termos.
 *
 * Fazendo a conta aqui, os espaçadores entram no DOM ANTES da medição — a altura medida
 * já inclui tudo, e o `legacy` sai do `pagebreak.mode` para que ninguém mais mexa no DOM
 * depois que ele foi medido.
 *
 * `toposDosBlocos` são as posições do topo de cada bloco que inicia página, JÁ refletindo
 * os espaçadores anteriores — por isso o chamador mede um por vez, em ordem crescente, em
 * vez de medir todos de uma vez. Medir tudo antes seria repetir o defeito do `legacy`,
 * que lê `getBoundingClientRect()` enquanto insere e invalida as coordenadas seguintes.
 */
export function alturaDoEspacador(
  topoDoBloco: number,
  pxPagina: number = PX_PAGINA_HTML2PDF,
): number {
  const restoNaPagina = topoDoBloco % pxPagina;
  // Bloco já começa exatamente no topo de uma folha: não há o que empurrar.
  if (restoNaPagina === 0) return 0;
  return pxPagina - restoNaPagina;
}

export interface CaixaDoBloco {
  /** Topo da caixa do bloco (getBoundingClientRect), sem margem. */
  top: number;
  /** Fundo da caixa do bloco, sem margem. */
  bottom: number;
}

/**
 * Quanto cada bloco OCUPA na coluna — não quanto mede a caixa dele.
 *
 * `getBoundingClientRect().height` é só a caixa, sem margens, e quase todo bloco de
 * topo do documento tem margem embaixo (`.card` 20px, `table` 16px, `.grid` 20px).
 * Somar caixas dizia "cabe" para um bloco que terminava abaixo do pé da folha: cinco
 * cards de 200px somam 1000 e "cabem" em 1032, mas o quinto termina em 1080 — e o
 * html2pdf o corta ao meio, que é exatamente o corte que este módulo existe para
 * impedir.
 *
 * Somar `height + marginTop + marginBottom` também erraria: margens verticais de
 * irmãos COLAPSAM (20px embaixo de um e 16px em cima do outro viram 20px, não 36).
 * O que não erra é a distância do topo de um bloco ao topo do seguinte — o
 * navegador já resolveu o colapso ao posicioná-los. O último bloco vai até o fim do
 * container, que é onde a captura também termina.
 */
export function alturasOcupadas(caixas: CaixaDoBloco[], fimDoContainer: number): number[] {
  return caixas.map((caixa, i) => {
    const proximoTopo = i + 1 < caixas.length ? caixas[i + 1].top : fimDoContainer;
    // Piso na própria caixa: um irmão puxado para cima por margem negativa, ou um
    // container medido menor que o conteúdo, não pode fazer o bloco "encolher".
    return Math.max(proximoTopo - caixa.top, caixa.bottom - caixa.top);
  });
}

export interface Bloco {
  /** Altura OCUPADA, em pixels — ver `alturasOcupadas`. */
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
    const { altura } = blocos[i];

    // Bloco maior que a folha inteira: não adianta empurrar para a próxima,
    // ele vai ser partido de todo jeito. Deixa seguir e recomeça a contagem
    // pelo que sobra do último pedaço. NOVO-lev-11: o pedaço que sobra é de
    // (usado + altura) — o bloco começa DEPOIS do que já ocupava a folha. Contar
    // só `altura` errava o resto e produzia folha quase em branco no meio do
    // documento quando o bloco alto não era o primeiro.
    if (altura > alturaUtil) {
      usado = (usado + altura) % alturaUtil;
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

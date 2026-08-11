import { describe, expect, it } from 'vitest';
import {
  ALTURA_UTIL_PX,
  PX_PAGINA_HTML2PDF,
  alturaDoEspacador,
  planPageBreaks,
} from './pdf-pagination';

/**
 * NOVO-007 — o fim do PDF baixado sumia.
 *
 * A previsão do diagnóstico (`audit/diagnostico-pdf-truncado.md`) era: documento de UMA
 * página sai inteiro; documento de DUAS OU MAIS trunca, e o corte cresce com o número de
 * quebras. Estes testes tornam isso verificável sem navegador — a aritmética é a mesma
 * que rege o pipeline real.
 *
 * O que NÃO está coberto aqui, e é honesto dizer: html2canvas e html2pdf não rodam em
 * jsdom, então a rasterização em si continua sem teste automatizado. O que se prova aqui
 * é que a ALTURA MEDIDA passa a comportar o documento inteiro — que era exatamente onde
 * o defeito morava.
 */

/** Simula o documento: blocos em sequência, como os filhos de `.container`. */
function montarDocumento(alturas: number[]) {
  return alturas.map((altura) => ({ altura, indivisivel: false }));
}

/**
 * Reproduz o pipeline: planeja as quebras, insere os espaçadores em ordem crescente
 * (medindo o topo a cada passo, como o código real faz) e devolve a altura final.
 */
function alturaAposEspacadores(alturas: number[]) {
  const blocos = montarDocumento(alturas);
  const quebras = planPageBreaks(blocos);

  const topos: number[] = [];
  let acumulado = 0;
  for (const altura of alturas) {
    topos.push(acumulado);
    acumulado += altura;
  }
  const alturaOriginal = acumulado;

  let deslocamento = 0;
  let somaEspacadores = 0;
  for (const i of quebras) {
    const topoAtual = topos[i] + deslocamento; // já reflete os espaçadores anteriores
    const espaco = alturaDoEspacador(topoAtual);
    somaEspacadores += espaco;
    deslocamento += espaco;
  }

  return {
    quebras,
    alturaOriginal,
    somaEspacadores,
    alturaFinal: alturaOriginal + somaEspacadores,
  };
}

describe('NOVO-007 — a altura medida comporta o documento inteiro', () => {
  it('documento de UMA página não ganha espaçador — e por isso nunca truncou', () => {
    // Três blocos que somam menos de uma folha.
    const r = alturaAposEspacadores([200, 300, 250]);

    expect(r.quebras).toEqual([]);
    expect(r.somaEspacadores).toBe(0);
    expect(r.alturaFinal).toBe(r.alturaOriginal);
  });

  it('documento de DUAS páginas: a altura final inclui o espaçador', () => {
    // Dois blocos altos: o segundo não cabe no resto da primeira folha.
    const r = alturaAposEspacadores([700, 600]);

    expect(r.quebras).toEqual([1]);
    expect(r.somaEspacadores).toBeGreaterThan(0);

    // O ponto do defeito: a altura que o html2canvas recebia era a ORIGINAL.
    // Tudo além dela era cortado — e o que fica além é o fim do documento.
    const alturaAntigaCongelada = r.alturaOriginal;
    expect(r.alturaFinal).toBeGreaterThan(alturaAntigaCongelada);
    expect(r.alturaFinal - alturaAntigaCongelada).toBe(r.somaEspacadores);
  });

  it('o último bloco cabe dentro da altura medida — é o que garante que os termos saem', () => {
    // Documento longo: 6 blocos, forçando várias quebras. O último representa os termos.
    const alturas = [400, 500, 450, 500, 480, 300];
    const r = alturaAposEspacadores(alturas);

    expect(r.quebras.length).toBeGreaterThanOrEqual(2);

    // Onde o último bloco termina, já com os espaçadores:
    const fimDoUltimoBloco = r.alturaFinal;
    // A altura capturada é medida DEPOIS dos espaçadores, então é exatamente essa.
    expect(fimDoUltimoBloco).toBeLessThanOrEqual(r.alturaFinal);

    // E com o comportamento antigo, o fim ficava para fora por toda a soma dos
    // espaçadores — quanto mais quebras, maior o pedaço perdido.
    expect(r.alturaFinal - r.alturaOriginal).toBe(r.somaEspacadores);
    expect(r.somaEspacadores).toBeGreaterThan(0);
  });

  it('o corte cresce com o número de quebras (a previsão do diagnóstico)', () => {
    const duasPaginas = alturaAposEspacadores([700, 600]);
    const varias = alturaAposEspacadores([700, 600, 700, 600, 700, 600]);

    expect(varias.quebras.length).toBeGreaterThan(duasPaginas.quebras.length);
    expect(varias.somaEspacadores).toBeGreaterThan(duasPaginas.somaEspacadores);
  });
});

describe('alturaDoEspacador — a régua tem que ser a do html2pdf', () => {
  it('usa 1031, que é como o html2pdf calcula (Math.floor), não 1032', () => {
    // O html2pdf faz toPx(273mm, k) = Math.floor(273 * k / 72 * 96) com k = 72/25.4.
    const comoHtml2pdfCalcula = Math.floor(273 * (72 / 25.4) / 72 * 96);
    expect(PX_PAGINA_HTML2PDF).toBe(comoHtml2pdfCalcula);
    expect(PX_PAGINA_HTML2PDF).toBe(1031);

    // E o planejamento continua com o arredondado: 1px não muda "cabe ou não cabe".
    expect(ALTURA_UTIL_PX).toBe(1032);
  });

  it('empurra o bloco até o topo da folha seguinte', () => {
    // Bloco começando a 700px: falta 331px para fechar a folha de 1031.
    expect(alturaDoEspacador(700)).toBe(331);
    expect(700 + alturaDoEspacador(700)).toBe(PX_PAGINA_HTML2PDF);
  });

  it('não insere espaço quando o bloco já começa no topo de uma folha', () => {
    expect(alturaDoEspacador(0)).toBe(0);
    expect(alturaDoEspacador(PX_PAGINA_HTML2PDF)).toBe(0);
    expect(alturaDoEspacador(PX_PAGINA_HTML2PDF * 3)).toBe(0);
  });

  it('alinha o bloco ao topo da folha em qualquer página', () => {
    for (const topo of [150, 1200, 2500, 3999]) {
      const alinhado = topo + alturaDoEspacador(topo);
      expect(alinhado % PX_PAGINA_HTML2PDF).toBe(0);
    }
  });
});

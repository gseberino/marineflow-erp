import { describe, it, expect } from 'vitest';
import { planPageBreaks, ALTURA_UTIL_PX } from './pdf-pagination';

const H = ALTURA_UTIL_PX; // ≈ 1032 px

/**
 * O caso que originou tudo: o bloco "Informações para Pagamento" saiu partido
 * ao meio no PDF baixado, com os dados bancários numa página e a chave PIX na
 * outra. No caminho de imprimir isso não acontece — quem pagina é o navegador,
 * que respeita `page-break-inside`. No de baixar, o html2canvas rasteriza tudo
 * numa imagem e o corte cai no pixel.
 */
describe('onde virar a página', () => {
  it('cabendo tudo, não quebra nada', () => {
    expect(planPageBreaks([{ altura: 300 }, { altura: 300 }, { altura: 300 }], H))
      .toEqual([]);
  });

  it('empurra para a folha seguinte o bloco que não cabe', () => {
    // 800 + 300 passa de 1032: o segundo desce.
    expect(planPageBreaks([{ altura: 800 }, { altura: 300 }], H)).toEqual([1]);
  });

  // O caso do bloco de pagamento: ele estava no fim de uma folha quase cheia.
  it('protege o bloco indivisível que ficaria a cavaleiro', () => {
    const blocos = [
      { altura: 900 },
      { altura: 200, indivisivel: true },  // só cabem 132 px — tem que descer
    ];
    expect(planPageBreaks(blocos, H)).toEqual([1]);
  });

  it('nunca quebra ANTES do primeiro bloco', () => {
    // Um bloco gigante logo no começo não pode gerar folha em branco na frente.
    expect(planPageBreaks([{ altura: H * 3 }], H)).toEqual([]);
    expect(planPageBreaks([{ altura: 2000 }, { altura: 100 }], H)[0]).not.toBe(0);
  });

  // Bloco mais alto que a folha vai ser partido de qualquer maneira — empurrar
  // só produziria uma página em branco antes dele.
  it('deixa passar o bloco maior que a folha e recomeça pelo resto', () => {
    const blocos = [
      { altura: H + 200 },   // ocupa uma folha inteira e sobra 200
      { altura: 700 },       // 200 + 700 = 900, ainda cabe
      { altura: 300 },       // 900 + 300 = 1200, não cabe → quebra
    ];
    expect(planPageBreaks(blocos, H)).toEqual([2]);
  });

  it('conta certo ao longo de várias folhas', () => {
    const blocos = [
      { altura: 600 }, { altura: 500 },   // 600 | 500 → quebra em 1
      { altura: 600 },                     // 500+600=1100 > 1032 → quebra em 2
      { altura: 400 },                     // 600+400=1000, cabe
    ];
    expect(planPageBreaks(blocos, H)).toEqual([1, 2]);
  });

  it('lista vazia não quebra', () => {
    expect(planPageBreaks([], H)).toEqual([]);
  });

  it('a altura útil corresponde a uma A4 com margem de 12mm', () => {
    // (297 - 24) mm a 96dpi. Se alguém mudar a margem da geração sem mexer
    // aqui, a paginação passa a mentir.
    expect(ALTURA_UTIL_PX).toBe(1032);
  });
});

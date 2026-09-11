import { describe, it, expect } from 'vitest';
import { planPageBreaks, alturasOcupadas, ALTURA_UTIL_PX } from './pdf-pagination';

const H = ALTURA_UTIL_PX; // ≈ 1032 px

/**
 * NOVO-lev-10 — o planejador media a caixa de cada bloco e ignorava a margem.
 *
 * O CSS do documento dá margem embaixo de quase todo bloco de topo (`.card` 20px,
 * `table` 16px, `.grid` 20px). Medido só pela caixa, cinco cards de 200 px somavam
 * 1000, "cabiam" em 1032 e não quebravam — mas o quinto terminava em 1080 e o
 * html2pdf o cortava ao meio.
 */
describe('a ocupação de cada bloco inclui a margem', () => {
  // Cinco cards de 200 px com margin-bottom de 20 px, como o navegador os posiciona.
  const caixas = [0, 220, 440, 660, 880].map((top) => ({ top, bottom: top + 200 }));
  // A margem do último colapsa para fora do container: ele termina onde o card termina.
  const fimDoContainer = 1080;

  it('vai do topo de um bloco ao topo do seguinte; o último, até o fim do container', () => {
    expect(alturasOcupadas(caixas, fimDoContainer)).toEqual([220, 220, 220, 220, 200]);
  });

  it('com a ocupação real, o quinto card desce para a folha seguinte', () => {
    const blocos = alturasOcupadas(caixas, fimDoContainer).map((altura) => ({ altura }));
    expect(planPageBreaks(blocos, H)).toEqual([4]);
  });

  it('contraprova: medindo só a caixa, não quebrava — e o quinto card saía cortado', () => {
    const soCaixas = caixas.map((c) => ({ altura: c.bottom - c.top }));
    expect(planPageBreaks(soCaixas, H)).toEqual([]);
    expect(caixas[4].bottom).toBeGreaterThan(H);
  });

  it('bloco sem margem ocupa exatamente a própria caixa', () => {
    expect(alturasOcupadas([{ top: 0, bottom: 300 }, { top: 300, bottom: 450 }], 450))
      .toEqual([300, 150]);
  });

  it('nunca devolve menos que a própria caixa', () => {
    // Irmão puxado para cima (margem negativa) ou container medido curto demais.
    expect(alturasOcupadas([{ top: 0, bottom: 300 }, { top: 290, bottom: 400 }], 380))
      .toEqual([300, 110]);
  });

  it('lista vazia', () => {
    expect(alturasOcupadas([], 0)).toEqual([]);
  });
});

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

  // NOVO-lev-11: o caso que o teste acima evitava. O bloco alto NÃO é o primeiro —
  // começa depois de 500 px já ocupados. O resto na última folha é de
  // (500 + H + 200), não de (H + 200): a conta antiga dizia "sobram 200" quando
  // sobravam 700, e o bloco seguinte de 400 px era desenhado atravessando o corte
  // — folha quase em branco no meio do documento.
  it('bloco alto em SEGUNDO lugar recomeça a conta pelo que já estava ocupado', () => {
    const blocos = [
      { altura: 500 },
      { altura: H + 200 },   // termina a (500 + H + 200) → resto 700 na folha nova
      { altura: 400 },       // 700 + 400 = 1100 > 1032 → tem que quebrar
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

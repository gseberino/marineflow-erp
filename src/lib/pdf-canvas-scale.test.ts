import { describe, it, expect } from 'vitest';
import { LARGURA_UTIL_PX, PX_PAGINA_HTML2PDF } from './pdf-pagination';

/**
 * A escala da captura, replicada aqui para travar o comportamento.
 *
 * O html2canvas rodava sempre em escala 2. O Safari do iPhone e do iPad recusa
 * canvas acima de ~16,7 megapixels e NÃO avisa: devolve um canvas em branco, e
 * o PDF sai vazio. Uma OS longa (muitos itens, fotos de produto) passa disso
 * fácil — e é justamente no celular que o técnico gera o documento.
 *
 * A conta mora em generatePDFBlob; aqui ela é verificada isolada, porque
 * depender de html2canvas num teste exigiria browser.
 */
const A4_WIDTH_PX = LARGURA_UTIL_PX;
const MAX_CANVAS_MP = 12_000_000;

export function captureScale(contentHeightPx: number): number {
  return Math.max(
    1,
    Math.min(2, Math.sqrt(MAX_CANVAS_MP / (A4_WIDTH_PX * Math.max(contentHeightPx, 1)))),
  );
}

const megapixels = (altura: number) =>
  (A4_WIDTH_PX * captureScale(altura) * altura * captureScale(altura)) / 1e6;

/**
 * A geometria que os dois caminhos (Baixar e Imprimir) têm que compartilhar.
 *
 * O html2pdf fatia a imagem a cada `canvas.width × (273/186)` px. Com o container nos
 * 794px da FOLHA (210mm), isso dava 1165px por página enquanto os espaçadores de quebra
 * eram calculados para 1031 — quebra no meio da folha e rodapé decepado — e a imagem
 * ainda era encolhida ×0,885 para caber nos 186mm, de onde vinha a letra menor do PDF
 * baixado em relação ao impresso. Com a largura ÚTIL (186mm) as duas réguas coincidem.
 */
describe('largura da captura', () => {
  it('é a área útil de 186mm (A4 menos 12mm de cada lado), não os 210mm da folha', () => {
    expect(LARGURA_UTIL_PX).toBe(Math.round(((210 - 24) / 25.4) * 96));
    expect(LARGURA_UTIL_PX).toBe(703);
  });

  it('a fatia de página do html2pdf, nessa largura, bate com a régua dos espaçadores', () => {
    expect(Math.floor(LARGURA_UTIL_PX * (273 / 186))).toBe(PX_PAGINA_HTML2PDF);
  });
});

describe('escala da captura do PDF', () => {
  it('documento curto mantém escala 2 — nitidez de proposta impressa', () => {
    expect(captureScale(1200)).toBe(2);   // ~1 página
    expect(captureScale(3000)).toBe(2);   // ~3 páginas
  });

  it('documento longo reduz a escala em vez de estourar', () => {
    expect(captureScale(8000)).toBeLessThan(2);
    expect(captureScale(20000)).toBeLessThan(1.5);
  });

  // O teto é o que impede o canvas em branco no iOS. Vale enquanto a escala
  // tem margem para descer — ou seja, até ~17.000px (≈16 páginas A4).
  it.each([1000, 3000, 6000, 10000, 15000])(
    'nunca passa de 12 MP (altura %ipx)',
    (altura) => {
      expect(megapixels(altura)).toBeLessThanOrEqual(12.01);
    },
  );

  /**
   * O limite físico, dito na cara.
   *
   * Abaixo de escala 1 o texto fica ilegível, então a conta trava em 1 — e um
   * documento acima de ~17.000px (≈16 páginas) volta a estourar os 12 MP mesmo
   * assim. Isso NÃO é resolvido pela escala: é o tamanho do documento. O
   * caminho nesse caso é a impressão, que não passa por captura de tela, e é
   * o que a mensagem de erro do PDF vazio sugere.
   */
  it('trava em 1 e admite que documento gigante não cabe', () => {
    expect(captureScale(50_000)).toBe(1);
    expect(megapixels(50_000)).toBeGreaterThan(12);
  });

  // Capturando os 186mm úteis (703px) em vez dos 210mm da folha (794px), cabem mais
  // pixels de altura antes de bater nos 12 MP: a fronteira subiu de ~15.000 para
  // ~17.000px (12M / 703 ≈ 17.070), cerca de 16 páginas A4.
  it('a fronteira fica em torno de 17.000px', () => {
    expect(megapixels(17_000)).toBeLessThanOrEqual(12.01);
    expect(megapixels(18_000)).toBeGreaterThan(12);
  });

  it('altura zero não quebra a conta', () => {
    expect(captureScale(0)).toBe(2);
    expect(Number.isFinite(captureScale(0))).toBe(true);
  });
});

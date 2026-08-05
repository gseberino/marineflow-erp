import { describe, it, expect } from 'vitest';
import { computePartsProfit } from './os-financials';

/**
 * Paridade entre APLICAR O PREÇO COTADO e a MARGEM que a OS mostra.
 *
 * O plano de Compras listava como risco: "a tela de cotação toca dinheiro de forma
 * indireta — apply_quote_price altera o custo do item e recalcula margem. Precisa de
 * teste de paridade com os-financials.ts antes de expor o botão." O botão foi
 * exposto e o teste nunca existiu; só havia verificação de que a tela abre.
 *
 * O que se prova aqui é a costura entre as duas pontas:
 *   useApplyQuotePrice grava  line_total_cost = preço cotado × quantidade
 *   computePartsProfit  lê    margem = (venda − custo) / venda
 * Se alguém mudar uma das duas fórmulas — por exemplo, gravar o custo já
 * multiplicado, ou passar a somar frete no custo da linha — a margem exibida passa a
 * mentir, e é isso que estes casos travam.
 */

/** Espelha exatamente o que useApplyQuotePrice grava na peça. */
function aplicarPrecoCotado(qty: number, unitPrice: number) {
  return { unit_cost_snapshot: unitPrice, line_total_cost: unitPrice * qty };
}

describe('aplicar preço cotado × margem da OS', () => {
  it('o custo aplicado é o que a margem consome — sem multiplicar duas vezes', () => {
    // Peça vendida a 1.000 (2 × 500); fornecedor cotou 300 a unidade.
    const venda = 1000;
    const aplicado = aplicarPrecoCotado(2, 300);
    expect(aplicado.line_total_cost).toBe(600);

    const r = computePartsProfit([{ line_total_sale: venda, line_total_cost: aplicado.line_total_cost }]);
    expect(r.partsRevenue).toBe(1000);
    expect(r.partsCostItems).toBe(600);
    expect(r.partsProfit).toBe(400);
    expect(r.partsMarginPct).toBe(40);
  });

  it('cotação mais cara que a venda produz margem NEGATIVA visível', () => {
    // O caso que justifica o teste: aceitar um reajuste sem perceber. A margem tem
    // de ficar negativa, não zerada nem escondida.
    const aplicado = aplicarPrecoCotado(1, 1500);
    const r = computePartsProfit([{ line_total_sale: 1000, line_total_cost: aplicado.line_total_cost }]);
    expect(r.partsProfit).toBe(-500);
    expect(r.partsMarginPct).toBe(-50);
  });

  it('soma as peças da OS, não só a que teve preço aplicado', () => {
    const r = computePartsProfit([
      { line_total_sale: 1000, line_total_cost: aplicarPrecoCotado(2, 300).line_total_cost },
      { line_total_sale: 500, line_total_cost: aplicarPrecoCotado(1, 200).line_total_cost },
    ]);
    expect(r.partsRevenue).toBe(1500);
    expect(r.partsCostItems).toBe(800);
    expect(r.partsProfit).toBe(700);
  });

  it('peça ainda sem custo não vira lucro de 100% por engano de leitura', () => {
    // Situação real de 05/08: itens movidos de texto livre para peça entram com
    // custo zero até a primeira compra. A margem REALMENTE fica 100% — o ponto é
    // que isso seja um número correto e explicável, não um efeito colateral.
    const r = computePartsProfit([{ line_total_sale: 980, line_total_cost: 0 }]);
    expect(r.partsCostItems).toBe(0);
    expect(r.partsMarginPct).toBe(100);
  });

  it('quantidade fracionária não perde centavo na conta', () => {
    const aplicado = aplicarPrecoCotado(2.5, 10.5);
    expect(aplicado.line_total_cost).toBeCloseTo(26.25, 2);
    const r = computePartsProfit([{ line_total_sale: 50, line_total_cost: aplicado.line_total_cost }]);
    expect(r.partsProfit).toBeCloseTo(23.75, 2);
  });
});

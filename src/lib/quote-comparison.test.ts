import { describe, expect, it } from 'vitest';
import {
  agingLevel, buildQuoteComparison, businessDaysSince, computeBasketTotal,
  suggestBestBasket, OUTLIER_THRESHOLD,
  type ComparisonItemInput, type ComparisonResponseInput, type ComparisonSupplierInput,
} from './quote-comparison';

const A = 'sup-a', B = 'sup-b', C = 'sup-c';
const I1 = 'item-1', I2 = 'item-2';

const items: ComparisonItemInput[] = [
  { id: I1, position: 1, description: 'Fusível MIDI 200A', quantity: 6, product_id: 'p1' },
  { id: I2, position: 2, description: 'Porta-fusível MIDI', quantity: 2, product_id: null },
];

const suppliers: ComparisonSupplierInput[] = [
  { id: A, name: 'Anderson Eletrônica' },
  { id: B, name: 'Souper Peças' },
  { id: C, name: 'Terceiro' },
];

function resp(over: Partial<ComparisonResponseInput> & { supplier_id: string; quote_request_item_id: string }): ComparisonResponseInput {
  return {
    id: `${over.supplier_id}-${over.quote_request_item_id}`,
    unit_price: 100, lead_time_days: 5, confirmed: false, source: 'text',
    ...over,
  };
}

describe('buildQuoteComparison', () => {
  it('monta linha por item com uma oferta por fornecedor', () => {
    const c = buildQuoteComparison(items, [
      resp({ supplier_id: A, quote_request_item_id: I1, unit_price: 50 }),
      resp({ supplier_id: B, quote_request_item_id: I1, unit_price: 60 }),
    ], suppliers);

    expect(c.rows).toHaveLength(2);
    expect(c.rows[0].offerCount).toBe(2);
    expect(c.rows[0].bestUnitPrice).toBe(50);
    expect(c.rows[0].offers[A].isBestPrice).toBe(true);
    expect(c.rows[0].offers[B].isBestPrice).toBe(false);
    expect(c.rows[0].offers[A].lineTotal).toBe(300); // 50 × 6
  });

  it('respeita a ordem de position, não a ordem de chegada', () => {
    const c = buildQuoteComparison(
      [items[1], items[0]],
      [resp({ supplier_id: A, quote_request_item_id: I1 })],
      suppliers,
    );
    expect(c.rows.map(r => r.position)).toEqual([1, 2]);
  });

  it('marca item que ninguém cotou', () => {
    const c = buildQuoteComparison(items, [
      resp({ supplier_id: A, quote_request_item_id: I1, unit_price: 50 }),
    ], suppliers);
    expect(c.rows[1].unquoted).toBe(true);
    expect(c.unquotedCount).toBe(1);
  });

  it('ignora resposta sem preço ou sem item (ex.: "bom dia" do fornecedor)', () => {
    const c = buildQuoteComparison(items, [
      resp({ supplier_id: A, quote_request_item_id: I1, unit_price: null }),
      { id: 'x', supplier_id: B, quote_request_item_id: null, unit_price: 90, lead_time_days: null, confirmed: false, source: 'text' },
    ], suppliers);
    expect(c.rows[0].offerCount).toBe(0);
    expect(c.respondedSupplierIds).toEqual([]);
    expect(c.packages).toHaveLength(0);
  });

  it('sinaliza desvio acima do limite, mas não com uma única oferta', () => {
    // média de 100 e 200 = 150; 200 está 33% acima ⇒ outlier.
    const c = buildQuoteComparison(items, [
      resp({ supplier_id: A, quote_request_item_id: I1, unit_price: 100 }),
      resp({ supplier_id: B, quote_request_item_id: I1, unit_price: 200 }),
      resp({ supplier_id: A, quote_request_item_id: I2, unit_price: 999 }),
    ], suppliers);

    expect(c.rows[0].offers[B].isOutlier).toBe(true);
    expect(c.rows[0].offers[B].deviationFromMean).toBeGreaterThan(OUTLIER_THRESHOLD);
    expect(c.rows[0].offers[A].isOutlier).toBe(false);
    // oferta solta na linha 2: não há do que desviar
    expect(c.rows[1].offers[A].isOutlier).toBe(false);
  });
});

describe('pacote do fornecedor', () => {
  const full: ComparisonResponseInput[] = [
    resp({ supplier_id: A, quote_request_item_id: I1, unit_price: 50, lead_time_days: 3 }),
    resp({ supplier_id: A, quote_request_item_id: I2, unit_price: 100, lead_time_days: 10 }),
    resp({ supplier_id: B, quote_request_item_id: I1, unit_price: 40, lead_time_days: 7 }),
    resp({ supplier_id: B, quote_request_item_id: I2, unit_price: 120, lead_time_days: 7 }),
  ];

  it('soma itens, aplica desconto e frete no total do pacote', () => {
    const c = buildQuoteComparison(items, full, [
      { id: A, name: 'A', freight: 50, discount: 20 },
      { id: B, name: 'B' },
    ]);
    const a = c.packages.find(p => p.supplierId === A)!;
    // (50×6) + (100×2) = 500; −20 +50 = 530
    expect(a.itemsTotal).toBe(500);
    expect(a.packageTotal).toBe(530);
  });

  it('frete alto pode derrubar quem tem item barato', () => {
    const c = buildQuoteComparison(items, full, [
      { id: A, name: 'A' },                    // 500
      { id: B, name: 'B', freight: 300 },      // (40×6)+(120×2)=480 +300 = 780
    ]);
    expect(c.packages[0].supplierId).toBe(A);
    expect(c.packages[0].isBestPackage).toBe(true);
    expect(c.bestPackageTotal).toBe(500);
  });

  it('usa o MAIOR prazo entre os itens cotados', () => {
    const c = buildQuoteComparison(items, full, suppliers);
    expect(c.packages.find(p => p.supplierId === A)!.maxLeadTimeDays).toBe(10);
  });

  it('pacote incompleto perde para completo mesmo sendo mais barato', () => {
    const c = buildQuoteComparison(items, [
      ...full.filter(r => r.supplier_id === A),
      resp({ supplier_id: C, quote_request_item_id: I1, unit_price: 1 }), // só 1 item, barato
    ], suppliers);

    expect(c.packages[0].supplierId).toBe(A);
    expect(c.packages[0].isComplete).toBe(true);
    const parcial = c.packages.find(p => p.supplierId === C)!;
    expect(parcial.isComplete).toBe(false);
    expect(parcial.isBestPackage).toBe(false);
    expect(c.bestPackageTotal).toBe(500);
  });

  it('sem pacote completo não há melhor pacote nem economia de divisão', () => {
    const c = buildQuoteComparison(items, [
      resp({ supplier_id: A, quote_request_item_id: I1, unit_price: 50 }),
    ], suppliers);
    expect(c.bestPackageTotal).toBeNull();
    expect(c.splitSavings).toBe(0);
  });

  it('calcula a economia de dividir a compra entre fornecedores', () => {
    const c = buildQuoteComparison(items, full, suppliers);
    // melhor por linha: 40×6 + 100×2 = 440; melhor pacote único: 480 (B)
    expect(c.bestPerLineTotal).toBe(440);
    expect(c.bestPackageTotal).toBe(480);
    expect(c.splitSavings).toBe(40);
  });

  it('fornecedor que não respondeu não vira coluna', () => {
    const c = buildQuoteComparison(items, full, suppliers);
    expect(c.packages.map(p => p.supplierId).sort()).toEqual([A, B].sort());
  });
});

describe('cesta escolhida', () => {
  const full: ComparisonResponseInput[] = [
    resp({ supplier_id: A, quote_request_item_id: I1, unit_price: 50 }),
    resp({ supplier_id: A, quote_request_item_id: I2, unit_price: 100 }),
    resp({ supplier_id: B, quote_request_item_id: I1, unit_price: 40 }),
    resp({ supplier_id: B, quote_request_item_id: I2, unit_price: 120 }),
  ];

  it('sugere o melhor preço de cada linha, dividindo entre fornecedores', () => {
    const c = buildQuoteComparison(items, full, suppliers);
    const basket = suggestBestBasket(c);
    expect(basket[I1]).toBe(B); // 40
    expect(basket[I2]).toBe(A); // 100
    const totals = computeBasketTotal(c, basket);
    expect(totals.total).toBe(440);
    expect(totals.supplierCount).toBe(2);
    expect(totals.chosenCount).toBe(2);
  });

  it('cesta parcial soma só o que foi escolhido', () => {
    const c = buildQuoteComparison(items, full, suppliers);
    const totals = computeBasketTotal(c, { [I1]: A });
    expect(totals.total).toBe(300);
    expect(totals.chosenCount).toBe(1);
  });

  it('escolha em fornecedor que não cotou aquela linha é ignorada', () => {
    const c = buildQuoteComparison(items, full, suppliers);
    const totals = computeBasketTotal(c, { [I1]: C });
    expect(totals.chosenCount).toBe(0);
    expect(totals.total).toBe(0);
  });
});

describe('aging em dias úteis', () => {
  it('não conta sábado e domingo', () => {
    // sexta 24/07/2026 → segunda 27/07/2026 = 1 dia útil
    expect(businessDaysSince('2026-07-24T10:00:00Z', new Date('2026-07-27T10:00:00Z'))).toBe(1);
  });

  it('conta a semana cheia', () => {
    // segunda 20/07 → sexta 24/07 = 4 dias úteis
    expect(businessDaysSince('2026-07-20T09:00:00Z', new Date('2026-07-24T09:00:00Z'))).toBe(4);
  });

  it('mesmo dia é zero e data inválida não explode', () => {
    expect(businessDaysSince('2026-07-24T09:00:00Z', new Date('2026-07-24T18:00:00Z'))).toBe(0);
    expect(businessDaysSince('não é data')).toBe(0);
  });

  it('classifica a janela de resposta do mercado (3-5 dias úteis)', () => {
    expect(agingLevel(0)).toBe('fresh');
    expect(agingLevel(2)).toBe('fresh');
    expect(agingLevel(3)).toBe('due');
    expect(agingLevel(4)).toBe('due');
    expect(agingLevel(5)).toBe('late');
    expect(agingLevel(12)).toBe('late');
  });
});

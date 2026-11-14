import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, DEFAULT_PDF_OPTIONS, type PDFData, type PDFOptions } from './pdf-generator';
import { ORCAMENTO } from '../../supabase/functions/_shared/pdf/amostras';

/**
 * Valores do orçamento/OS como o cliente confere (14/11/2026).
 *
 * O desconto de cada item vinha do banco e era descartado no caminho: a linha dizia
 * "2 × R$ 500,00 = R$ 900,00" sem mostrar os R$ 100,00. E o quadro de valores não fechava —
 * impostos e serviços de terceiros entravam no total sem linha. A regra que este arquivo trava:
 * cada linha fecha, cada tabela termina com o seu total e a soma dos descontos, e o quadro soma
 * exatamente o VALOR TOTAL.
 */

// Monta uma ordem cujo grand_total segue a fórmula de calc_so_totals:
// serviços + peças + despesas + deslocamento faturável + terceiros − desconto + impostos + taxa.
function ordem(over: Partial<PDFData['serviceOrder']> = {}, itens: Partial<Pick<PDFData, 'services' | 'parts'>> = {}): PDFData {
  const services = itens.services ?? [
    { name: 'Instalação do inversor', billing_unit: 'hour', quantity: 2, unit_price: 500, discount_amount: 100, discount_pct: 10, line_total: 900 },
    { name: 'Comissionamento', billing_unit: 'visit', quantity: 1, unit_price: 300, line_total: 300 },
  ];
  const parts = itens.parts ?? [
    { name: 'Cabo 35 mm²', quantity: 10, unit_price: 40, discount_amount: 50, discount_pct: 12.5, line_total: 350 },
    { name: 'Disjuntor', quantity: 2, unit_price: 80, line_total: 160 },
  ];
  const labor = services.reduce((s, i) => s + i.line_total, 0);
  const pecas = parts.reduce((s, i) => s + i.line_total, 0);
  const so = {
    ...ORCAMENTO.serviceOrder,
    labor_cost_total: labor,
    parts_cost_total: pecas,
    travel_cost_total: 200,
    is_travel_billable: true,
    operational_cost_total: 0,
    subcontract_cost_total: 0,
    discount_amount: 0,
    discount_services_pct: 0,
    discount_parts_pct: 0,
    tax_amount: 0,
    card_fee_amount: 0,
    payment_condition_installments: null,
    payment_conditions: undefined,
    ...over,
  };
  const deslocamento = so.is_travel_billable === false ? 0 : so.travel_cost_total;
  so.grand_total = Math.round((labor + pecas + (so.operational_cost_total ?? 0) + deslocamento
    + (so.subcontract_cost_total ?? 0) - so.discount_amount + so.tax_amount + (so.card_fee_amount ?? 0)) * 100) / 100;
  return { ...ORCAMENTO, survey: undefined, serviceOrder: so, services, parts };
}

const OPCOES: PDFOptions = { ...DEFAULT_PDF_OPTIONS, validity: { mode: 'days', days: 7 } };

/** "R$ 1.234,56" → 1234.56 */
const valor = (texto: string) => Number(texto.replace(/[^\d,]/g, '').replace(',', '.'));

/** As linhas do quadro de valores, com sinal: o que vem com "−" subtrai. */
function linhasDoQuadro(html: string): Array<{ rotulo: string; valor: number }> {
  const quadro = html.split('<table class="summary-table">')[1].split('</table>')[0];
  const linhas = [...quadro.matchAll(/<tr>\s*<td[^>]*>([^<]*)<\/td>\s*<td[^>]*>([^<]*)<\/td>\s*<\/tr>/g)];
  return linhas.map(([, rotulo, v]) => ({ rotulo: rotulo.trim(), valor: (v.includes('−') ? -1 : 1) * valor(v) }));
}

function totalDoQuadro(html: string): number {
  const m = html.match(/<td>VALOR TOTAL<\/td>\s*<td[^>]*>([^<]*)<\/td>/);
  return valor(m![1]);
}

describe('desconto por item no PDF', () => {
  it('a linha mostra unitário, desconto (com %) e total — e fecha', () => {
    const html = buildHTMLDocument(ordem(), OPCOES);
    expect(html).toContain('>Desconto</th>');
    // 2 × R$ 500,00 − R$ 100,00 = R$ 900,00
    expect(html).toMatch(/Instalação do inversor[\s\S]*?R\$\s500,00[\s\S]*?− R\$\s100,00<div style="font-size:8px;">\(10%\)<\/div>[\s\S]*?R\$\s900,00/);
    // percentual quebrado sai com vírgula, calculado do valor: 50 / 400 = 12,5%
    expect(html).toContain('(12,5%)');
  });

  it('cada tabela termina com o total e a soma dos descontos', () => {
    const html = buildHTMLDocument(ordem(), OPCOES);
    expect(html).toMatch(/Total dos serviços<\/td>\s*<td[^>]*>− R\$\s100,00<\/td>\s*<td[^>]*>R\$\s1\.200,00<\/td>/);
    expect(html).toMatch(/Total das peças e materiais<\/td>\s*<td[^>]*>− R\$\s50,00<\/td>\s*<td[^>]*>R\$\s510,00<\/td>/);
  });

  it('tabela sem desconto não ganha a coluna', () => {
    const html = buildHTMLDocument(ordem({}, {
      parts: [{ name: 'Disjuntor', quantity: 2, unit_price: 80, line_total: 160 }],
    }), OPCOES);
    const pecas = html.split('Peças, Equipamentos e Materiais')[1].split('</table>')[0];
    expect(pecas).not.toContain('>Desconto</th>');
    // e com um item só, sem desconto, não repete a linha num "Total das peças"
    expect(pecas).not.toContain('Total das peças');
  });

  it('desconto oculto: sem coluna, unitário efetivo — a linha continua fechando', () => {
    const html = buildHTMLDocument(ordem(), { ...OPCOES, showDiscount: false });
    expect(html).not.toContain('>Desconto</th>');
    expect(html).not.toContain('descontos concedidos');
    // 900 ÷ 2 = 450 por hora
    expect(html).toMatch(/Instalação do inversor[\s\S]*?R\$\s450,00[\s\S]*?R\$\s900,00/);
  });

  it('o resumo de descontos soma itens e desconto adicional', () => {
    const html = buildHTMLDocument(ordem({ discount_amount: 60 }), OPCOES);
    expect(html).toContain('Desconto adicional');
    expect(html).toMatch(/Total de descontos concedidos: R\$\s210,00/);
    expect(html).toMatch(/nos itens R\$\s150,00 \+ adicional R\$\s60,00/);
  });

  it('só desconto geral: a linha chama "Desconto" e não há resumo de descontos', () => {
    const html = buildHTMLDocument(ordem({ discount_amount: 60 }, {
      services: [{ name: 'Revisão', billing_unit: 'unit', quantity: 1, unit_price: 1000, line_total: 1000 }],
      parts: [],
    }), OPCOES);
    expect(linhasDoQuadro(html).map(l => l.rotulo)).toContain('Desconto');
    expect(html).not.toContain('Desconto adicional');
    expect(html).not.toContain('descontos concedidos');
  });
});

describe('o quadro de valores soma o VALOR TOTAL', () => {
  const casos: Array<[string, Partial<PDFData['serviceOrder']>]> = [
    ['só itens e deslocamento', {}],
    ['com impostos (9 documentos reais tinham imposto sem linha)', { tax_amount: 87.35 }],
    ['com serviços de terceiros', { subcontract_cost_total: 450 }],
    ['com outras despesas e taxa de cartão', { operational_cost_total: 75, card_fee_amount: 42.1, card_installments: 3 }],
    ['com desconto adicional', { discount_amount: 60 }],
    ['deslocamento não faturável fica fora da folha e do total', { is_travel_billable: false }],
    ['tudo junto', { tax_amount: 30, subcontract_cost_total: 100, operational_cost_total: 20, discount_amount: 60, card_fee_amount: 15 }],
  ];
  for (const [nome, over] of casos) {
    it(nome, () => {
      const dados = ordem(over);
      const html = buildHTMLDocument(dados, OPCOES);
      const soma = Math.round(linhasDoQuadro(html).reduce((s, l) => s + l.valor, 0) * 100) / 100;
      expect(soma).toBe(dados.serviceOrder.grand_total);
      expect(totalDoQuadro(html)).toBe(dados.serviceOrder.grand_total);
    });
  }

  it('os rótulos novos aparecem quando há valor', () => {
    const html = buildHTMLDocument(ordem({ tax_amount: 30, subcontract_cost_total: 100 }), OPCOES);
    const rotulos = linhasDoQuadro(html).map(l => l.rotulo);
    expect(rotulos).toEqual(['Serviços', 'Peças e materiais', 'Deslocamento / logística', 'Serviços de terceiros', 'Impostos']);
  });

  it('"Impostos" desmarcado tira a linha (o total continua o do banco)', () => {
    const html = buildHTMLDocument(ordem({ tax_amount: 30 }), { ...OPCOES, showTax: false });
    expect(linhasDoQuadro(html).map(l => l.rotulo)).not.toContain('Impostos');
  });

  it('deslocamento não faturável não sai impresso', () => {
    const html = buildHTMLDocument(ordem({ is_travel_billable: false }), OPCOES);
    expect(html).not.toContain('Deslocamento / logística');
  });

  it('a fatura usa o mesmo quadro e explica o desconto do item', () => {
    const dados = { ...ordem({ tax_amount: 30 }), documentType: 'invoice' as const };
    const html = buildHTMLDocument(dados, OPCOES);
    expect(html).toContain('Impostos');
    expect(html).toMatch(/R\$\s1\.000,00 com desconto de R\$\s100,00 \(10%\)/);
    const soma = Math.round(linhasDoQuadro(html).reduce((s, l) => s + l.valor, 0) * 100) / 100;
    expect(soma).toBe(dados.serviceOrder.grand_total);
  });

  it('a via de execução continua sem número nenhum', () => {
    const dados = { ...ordem({ tax_amount: 30, discount_amount: 60 }), documentType: 'service_order' as const };
    const html = buildHTMLDocument(dados, { ...OPCOES, hideFinancials: true });
    expect(html).not.toMatch(/R\$/);
    expect(html).not.toContain('>Desconto</th>');
    expect(html).not.toContain('Total dos serviços');
  });
});

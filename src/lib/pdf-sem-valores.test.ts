import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, DEFAULT_PDF_OPTIONS, type PDFData } from './pdf-generator';

/**
 * Dá para gerar um documento SEM valor nenhum?
 *
 * Antes não dava. O dono desmarcou todas as caixas de valor para imprimir a OS
 * dos técnicos e o documento saiu com os números assim mesmo: a opção
 * "Preço unitário dos serviços" tirava só a coluna Unitário, e o TOTAL de cada
 * linha, o subtotal e o total geral continuavam na folha.
 *
 * Estes testes provam pelo HTML final, procurando os valores formatados.
 */
const dados: PDFData = {
  documentType: 'service_order',
  company: { name: 'HBR', address: '', city: '', state: '', postal_code: '', phone: '', email: '', cnpj: '' },
  bank: {},
  serviceOrder: {
    service_order_number: 'OS-00077', status: 'in_progress', created_at: '2026-08-01',
    grand_total: 7654.32, labor_cost_total: 1234.56, parts_cost_total: 6419.76,
    travel_cost_total: 0, discount_amount: 0, tax_amount: 0, operational_cost_total: 0,
  },
  client: { name: 'Cliente' },
  services: [{
    name: 'Instalação LiFePO4', billing_unit: 'unit', quantity: 1,
    unit_price: 1234.56, line_total: 1234.56,
  }],
  parts: [{
    name: 'Cabo flexível 70 mm²', quantity: 11,
    unit_price: 583.61, line_total: 6419.76,
  }],
  expenses: [], photos: [],
};

const SEM_VALORES = {
  ...DEFAULT_PDF_OPTIONS,
  showServicePrices: false,
  showPartsPrices: false,
  showTravelCost: false,
  showDiscount: false,
  showTax: false,
  showCardFee: false,
  showCommission: false,
};

describe('documento sem valores', () => {
  const html = buildHTMLDocument(dados, SEM_VALORES);

  // Cada um destes números aparecia mesmo com as caixas desmarcadas.
  it.each([
    ['unitário do serviço', '1.234,56'],
    ['unitário da peça', '583,61'],
    ['total da peça', '6.419,76'],
    ['total geral', '7.654,32'],
  ])('não mostra o %s', (_nome, valor) => {
    expect(html).not.toContain(valor);
  });

  it('não mostra o quadro de somatório', () => {
    expect(html).not.toContain('VALOR TOTAL');
  });

  it('mas mantém o que o técnico precisa', () => {
    expect(html).toContain('Instalação LiFePO4');
    expect(html).toContain('Cabo flexível 70 mm²');
    expect(html).toContain('OS-00077');
    // A quantidade fica: sem ela o técnico não sabe quanto instalar.
    expect(html).toContain('11');
  });

  // A tabela não pode ficar com cabeçalho a mais que as linhas.
  it('cabeçalho de valor some junto com a coluna', () => {
    expect(html).not.toContain('>Unitário<');
    expect(html).not.toContain('>Subtotal<');
  });
});

describe('documento do cliente (o uso normal) segue completo', () => {
  const html = buildHTMLDocument(dados, DEFAULT_PDF_OPTIONS);

  it('mostra unitário, total e somatório', () => {
    expect(html).toContain('1.234,56');
    expect(html).toContain('583,61');
    expect(html).toContain('7.654,32');
    expect(html).toContain('VALOR TOTAL');
  });

  // Meia opção também precisa funcionar: esconder peça e manter serviço.
  it('esconder só as peças mantém os serviços e o resumo', () => {
    const meio = buildHTMLDocument(dados, { ...DEFAULT_PDF_OPTIONS, showPartsPrices: false });
    expect(meio).toContain('1.234,56');   // serviço continua
    expect(meio).not.toContain('583,61'); // peça some
    expect(meio).toContain('VALOR TOTAL'); // ainda há o que somar
  });
});

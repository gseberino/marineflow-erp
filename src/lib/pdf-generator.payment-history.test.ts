import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, DEFAULT_PDF_OPTIONS, type PDFData } from './pdf-generator';

// Base mínima de PDFData (campos obrigatórios) — dados reais da OS-00034,
// que tem 1 recebível ("saldo final", R$29.000, saldo R$4.000, parcial) e
// 1 pagamento confirmado (R$25.000 via PIX). Usado para verificar que o
// resumo financeiro de fato sai no documento gerado — a classe de bug
// (dados no nível errado do objeto) que compilava mas não renderizava.
function baseData(overrides: Partial<PDFData['serviceOrder']>): PDFData {
  return {
    documentType: 'service_order',
    company: {
      name: 'HBR', address: '', city: '', state: '', postal_code: '',
      phone: '', email: '', cnpj: '',
    },
    serviceOrder: {
      service_order_number: 'OS-00034',
      status: 'approved',
      created_at: '2026-05-01',
      grand_total: 29000,
      labor_cost_total: 20000,
      parts_cost_total: 9000,
      travel_cost_total: 0,
      discount_amount: 0,
      tax_amount: 0,
      payment_conditions: '50% mão de obra + 100% materiais antecipados',
      payment_condition_label: '50% mão de obra + 100% materiais antecipados',
      ...overrides,
    },
    client: { name: 'Cliente Teste' },
    services: [],
    parts: [],
  };
}

describe('buildPaymentHistorySection / Situação de Pagamento no PDF', () => {
  it('mostra a situação real (valor pago, saldo, forma) e esconde o plano quando há pagamento', () => {
    const html = buildHTMLDocument(baseData({
      receivables: [{
        id: 'r1', description: 'OS-00034 — saldo final', amount: 29000,
        balance_amount: 4000, status: 'partially_paid', is_deposit: false,
      }],
      payments: [{
        receivable_id: 'r1', payment_date: '2026-05-20', amount: 25000, payment_method: 'pix',
      }],
    }), DEFAULT_PDF_OPTIONS);

    // A seção real aparece com os valores certos.
    expect(html).toContain('Situação de Pagamento');
    expect(html).toContain('25.000,00'); // pago
    expect(html).toContain('4.000,00');  // saldo em aberto
    expect(html).toContain('PIX');       // forma de pagamento
    expect(html).toContain('Parcialmente pago'); // selo de status

    // O plano (Programação de Pagamento) some quando já há pagamento.
    expect(html).not.toContain('Programação de Pagamento');
  });

  it('mostra o plano (Programação de Pagamento) e não a situação real quando NÃO há pagamento', () => {
    const html = buildHTMLDocument(baseData({
      receivables: [{
        id: 'r1', description: 'OS-00034 — saldo final', amount: 29000,
        balance_amount: 29000, status: 'pending', is_deposit: false,
      }],
      payments: [],
    }), DEFAULT_PDF_OPTIONS);

    expect(html).toContain('Programação de Pagamento');
    expect(html).not.toContain('Situação de Pagamento');
  });
});

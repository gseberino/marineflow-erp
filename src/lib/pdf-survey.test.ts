// O levantamento no documento do cliente.
//
// Vai para o PDF porque é o que sustenta o preço numa conversa: "medi a
// distância do banco ao quadro, são 14 metros — daí a bitola e o valor do
// cabo". Sem isso o orçamento é um número sem defesa.
//
// As regras testadas aqui são de conteúdo, não de layout: o que NÃO pode ir
// para um documento assinado que circula por e-mail.
import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, DEFAULT_PDF_OPTIONS, type PDFData } from './pdf-generator';

const base: PDFData = {
  documentType: 'quote',
  company: {
    name: 'HBR Marine Solutions', address: 'Rua X', city: 'Itajaí', state: 'SC',
    postal_code: '88301-000', phone: '', email: '', cnpj: '',
  },
  serviceOrder: {
    service_order_number: 'ORÇ-00074',
    status: 'draft',
    created_at: new Date().toISOString(),
    problem_description: 'Substituir baterias para LiFePO4',
    grand_total: 3760,
    labor_cost_total: 3760,
    parts_cost_total: 0,
    travel_cost_total: 0,
    discount_amount: 0,
  } as any,
  client: { name: 'Cliente Final' } as any,
  services: [],
  parts: [],
  expenses: [],
};

describe('PDF do orçamento — levantamento técnico', () => {
  it('mostra o que foi verificado e a constatação', () => {
    const html = buildHTMLDocument({
      ...base,
      survey: {
        answered_at: '2026-08-05T12:00:00Z',
        rationale: 'Sei o acesso e a distância; falta confirmar o alternador.',
        answers: [
          { question: 'Qual a distância entre o banco e o quadro?', answer: '14 metros' },
          { question: 'Onde entra o banco de baterias?', answer: 'Compartimento sob a cama' },
        ],
      },
    }, DEFAULT_PDF_OPTIONS);

    expect(html).toContain('Levantamento Técnico no Local');
    expect(html).toContain('Qual a distância entre o banco e o quadro?');
    expect(html).toContain('14 metros');
    expect(html).toContain('falta confirmar o alternador');
  });

  it('diz quando não foi possível verificar, em vez de deixar vazio', () => {
    const html = buildHTMLDocument({
      ...base,
      survey: {
        answers: [
          { question: 'Há inversor no barramento?', skipped: 'painel lacrado' },
        ],
      },
    }, DEFAULT_PDF_OPTIONS);

    expect(html).toContain('não foi possível verificar');
    expect(html).toContain('painel lacrado');
  });

  it('omite a seção inteira quando não houve levantamento', () => {
    const html = buildHTMLDocument(base, DEFAULT_PDF_OPTIONS);
    expect(html).not.toContain('Levantamento Técnico no Local');
  });

  it('escapa o texto do levantamento — resposta digitada não vira marcação', () => {
    const html = buildHTMLDocument({
      ...base,
      survey: {
        answers: [{ question: 'Observação', answer: '<script>alert(1)</script>' }],
      },
    }, DEFAULT_PDF_OPTIONS);

    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });
});

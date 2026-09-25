/**
 * Duas ordens de exemplo para os testes de paridade do documento.
 *
 * Os horários foram escolhidos para cair na janela em que o dia de Brasília e o do UTC
 * divergem (entre 21h e meia-noite em Brasília). É nessa janela que um servidor em UTC
 * imprimiria a data errada: um orçamento criado às 23h30 do dia 24 sairia "emitido em 25".
 * Se o documento só é testado ao meio-dia, a diferença nunca aparece.
 *
 * `AGORA` congela o relógio dos testes: o rodapé "Emitido em" usa o instante da geração.
 */
import type { PDFData } from './documento.ts';

/** 25/09/2026 às 23h45 em Brasília = 26/09/2026 às 02h45 em UTC. */
export const AGORA = '2026-09-26T02:45:00.000Z';

const empresa: PDFData['company'] = {
  name: 'HBR Marine Solutions',
  address: 'Rua das Marinas, 100',
  city: 'Itajaí',
  state: 'SC',
  postal_code: '88300-000',
  phone: '(47) 3333-0000',
  email: 'contato@hbr.example',
  cnpj: '00.000.000/0001-00',
};

const banco: PDFData['bank'] = {
  bank_name: 'Banco Exemplo',
  bank_agency: '0001',
  bank_account: '12345-6',
  pix_key: '00.000.000/0001-00',
};

/** Orçamento em rascunho, criado às 23h30 de Brasília (02h30 UTC do dia seguinte). */
export const ORCAMENTO: PDFData = {
  documentType: 'quote',
  company: empresa,
  bank: banco,
  survey: {
    // 23/09 às 22h10 em Brasília; 24/09 em UTC.
    answered_at: '2026-09-24T01:10:00.000Z',
    rationale: 'Distância do banco de baterias ao quadro medida em 14 m.',
    answers: [
      { question: 'Distância do banco ao quadro (m)', answer: '14', hasPhoto: true },
      { question: 'Tensão do sistema', answer: '24 V' },
      { question: 'Espaço para o inversor', skipped: 'compartimento trancado' },
    ],
  },
  serviceOrder: {
    service_order_number: 'ORÇ-00086',
    status: 'draft',
    created_at: '2026-09-25T02:30:00.000Z',
    problem_description: 'Instalar sistema de energia solar.\n\nINVERSOR\nInversor 3000 W com carregador integrado.',
    grand_total: 18_450.5,
    labor_cost_total: 6_000,
    parts_cost_total: 13_000,
    travel_cost_total: 350,
    discount_amount: 899.5,
    discount_services_pct: 5,
    discount_parts_pct: 4.6,
    tax_amount: 0,
    operational_cost_total: 0,
    extra_notes: 'Prazo de execução: 5 dias úteis após a aprovação.',
    payment_conditions: '50% na aprovação, 50% na entrega',
    payment_condition_label: 'Metade na aprovação, metade na entrega',
    payment_condition_installments: [
      { tipo: 'aprovacao', services_pct: 50, parts_pct: 100, expenses_pct: 100 },
      { tipo: 'entrega', services_pct: 50, parts_pct: 0, expenses_pct: 0 },
    ],
    financial_notes: 'Materiais faturados em nome do cliente.',
    payment_method_preferred: 'pix',
    quote_validity_days: 7,
    receivables: [],
    payments: [],
  },
  client: {
    name: 'Cliente Exemplo Ltda',
    cpf_cnpj: '11.111.111/0001-11',
    phone: '(47) 99999-0000',
    email: 'cliente@example.com',
    address: 'Av. Beira Mar, 50, Balneário Camboriú, SC',
  },
  vessel: { name: 'Lancha Azul', manufacturer: 'Schaefer', model: 'V33', year: 2021, registration: 'SC-1234' },
  marina: { name: 'Marina Exemplo', city: 'Itajaí' },
  services: [
    { name: 'Instalação elétrica', description: 'Passagem de cabos e montagem do quadro', billing_unit: 'hour', quantity: 20, unit_price: 200, line_total: 4_000 },
    { name: 'Comissionamento', billing_unit: 'visit', quantity: 1, unit_price: 2_000, line_total: 2_000 },
  ],
  parts: [
    { name: 'Inversor 3000 W', sku: 'INV-3000', quantity: 1, unit_price: 9_000, line_total: 9_000, image_url: 'https://example.com/inv.png' },
    { name: 'Cabo 35 mm²', sku: 'CAB-35', quantity: 20, unit_price: 200, line_total: 4_000 },
  ],
  terms: 'CONDIÇÕES GERAIS\nGarantia de 90 dias sobre a mão de obra.\n\nGARANTIA\nEquipamentos conforme o fabricante.',
  photos: [],
};

/**
 * OS com pagamento registrado e agendada para 21h30 de Brasília (00h30 UTC do dia
 * seguinte). `payment_date` é coluna `date` no banco: chega como 'aaaa-mm-dd', sem hora.
 */
export const OS_COM_PAGAMENTO: PDFData = {
  documentType: 'service_order',
  company: empresa,
  bank: banco,
  serviceOrder: {
    service_order_number: 'OS-00075',
    status: 'in_progress',
    created_at: '2026-09-10T13:00:00.000Z',
    scheduled_start_at: '2026-09-26T00:30:00.000Z',
    problem_description: 'Banco de baterias não segura carga.',
    technical_notes: 'Substituídas 4 baterias AGM. Recomenda-se revisão em 12 meses.',
    grand_total: 5_000,
    labor_cost_total: 1_000,
    parts_cost_total: 4_000,
    travel_cost_total: 0,
    discount_amount: 0,
    tax_amount: 0,
    payment_condition_installments: [
      { due_date: '2026-10-05', amount: 2_500 },
      { due_date: '2026-11-05', amount: 2_500 },
    ],
    receivables: [
      { id: 'r1', description: 'Sinal', amount: 2_500, balance_amount: 0, status: 'paid', is_deposit: true },
      { id: 'r2', description: 'Saldo', amount: 2_500, balance_amount: 2_500, status: 'pending', is_deposit: false },
    ],
    payments: [{ receivable_id: 'r1', payment_date: '2026-09-20', amount: 2_500, payment_method: 'pix' }],
  },
  client: { name: 'Cliente Exemplo Ltda' },
  vessel: { name: 'Lancha Azul' },
  services: [{ name: 'Troca de baterias', billing_unit: 'unit', quantity: 1, unit_price: 1_000, line_total: 1_000 }],
  parts: [{ name: 'Bateria AGM 105 Ah', quantity: 4, unit_price: 1_000, line_total: 4_000 }],
  photos: [],
};

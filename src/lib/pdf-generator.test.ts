import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, buildPDFFilename, DEFAULT_PDF_OPTIONS, type PDFData } from './pdf-generator';

/** `Partial` só afrouxa o primeiro nível: um override de `serviceOrder` continuava
 *  exigindo os ~30 campos do tipo cheio, e era daí que vinha o TS2740 deste arquivo.
 *  Os testes daqui montam só o que a asserção usa — o tipo tem que permitir isso. */
type DeepPartial<T> = { [K in keyof T]?: T[K] extends object ? DeepPartial<T[K]> : T[K] };

function makeData(overrides: DeepPartial<PDFData> = {}): PDFData {
  return {
    documentType: 'service_order',
    company: {
      name: '', address: '', city: '', state: '',
      postal_code: '', phone: '', email: '', cnpj: '',
    },
    serviceOrder: {
      service_order_number: 'OS-00123',
      status: 'open',
      created_at: '2026-01-01',
    },
    client: { name: 'João da Silva' },
    vessel: { name: 'Lancha Azul' },
    ...overrides,
  } as PDFData;
}

describe('buildPDFFilename', () => {
  it('monta nome com tipo, número, cliente e embarcação, sem acentos', () => {
    expect(buildPDFFilename(makeData())).toBe('OrdemServico_OS-00123_Joao-da-Silva_Lancha-Azul.pdf');
  });

  it('usa o rótulo correto por tipo de documento', () => {
    expect(buildPDFFilename(makeData({ documentType: 'quote' }))).toMatch(/^Orcamento_/);
    expect(buildPDFFilename(makeData({ documentType: 'invoice' }))).toMatch(/^Fatura_/);
    expect(buildPDFFilename(makeData({ documentType: 'receipt' }))).toMatch(/^Recibo_/);
  });

  it('omite partes ausentes sem deixar separadores soltos', () => {
    const data = makeData({
      client: { name: '' },
      vessel: undefined,
      serviceOrder: { service_order_number: '', status: 'open', created_at: '2026-01-01' },
    });
    expect(buildPDFFilename(data)).toBe('OrdemServico.pdf');
  });

  it('sanitiza caracteres especiais e barras', () => {
    const data = makeData({
      client: { name: 'Empresa A/B & Cia.' },
      vessel: { name: 'Motorhome #1 (2024)' },
    });
    const name = buildPDFFilename(data);
    expect(name.endsWith('.pdf')).toBe(true);
    const base = name.replace(/\.pdf$/, '');
    expect(base).not.toMatch(/[/\\#&()]/);
  });
});

/** Documento completo o bastante para as duas tabelas, a assinatura e o card de pagamento. */
function documentoCompleto(overrides: DeepPartial<PDFData> = {}): PDFData {
  return {
    documentType: 'service_order',
    company: {
      name: 'HBR Marine', address: '', city: '', state: '',
      postal_code: '', phone: '', email: 'financeiro@hbr.com', cnpj: '00.000.000/0001-00',
    },
    bank: { bank_name: 'Banco do Brasil', bank_agency: '1234-5', bank_account: '67890-1', pix_key: 'pix@hbr.com' },
    serviceOrder: {
      service_order_number: 'OS-00900', status: 'in_progress', created_at: '2026-09-01',
      grand_total: 300, labor_cost_total: 100, parts_cost_total: 200,
      travel_cost_total: 0, discount_amount: 0, tax_amount: 0,
    },
    client: { name: 'Cliente Teste' },
    services: [{ name: 'Serviço', billing_unit: 'unit', quantity: 1, unit_price: 100, line_total: 100 }],
    parts: [{ name: 'Peça', quantity: 2, unit_price: 100, line_total: 200 }],
    expenses: [], photos: [],
    ...overrides,
  } as PDFData;
}

/**
 * NOVO-022 — toggles que não faziam o que o rótulo prometia.
 *
 * "Campo de assinatura" e "Mostrar instruções de pagamento" existiam no diálogo, eram
 * gravados como padrão da empresa e o gerador nunca os lia: marcar ou desmarcar não
 * mudava um byte. O padrão de fábrica de ambos é ligado, então o documento de quem nunca
 * mexeu nas opções continua igual — o que a contraprova de cada bloco garante.
 */
describe('campo de assinatura obedece showSignature', () => {
  it('com o padrão de fábrica, a OS sai com as duas linhas de assinatura', () => {
    expect(DEFAULT_PDF_OPTIONS.showSignature).toBe(true);
    const html = buildHTMLDocument(documentoCompleto(), DEFAULT_PDF_OPTIONS);
    expect(html).toContain('Responsável Técnico');
    expect(html).toContain('Aceite do Serviço Realizado');
  });

  it('desmarcado, o bloco some da OS', () => {
    const html = buildHTMLDocument(documentoCompleto(), { ...DEFAULT_PDF_OPTIONS, showSignature: false });
    expect(html).not.toContain('Responsável Técnico');
    expect(html).not.toContain('Aceite do Serviço Realizado');
    // o resto do documento continua lá
    expect(html).toContain('OS-00900');
    expect(html).toContain('VALOR TOTAL');
  });

  it('e do orçamento', () => {
    const ligado = buildHTMLDocument(documentoCompleto({ documentType: 'quote' }), DEFAULT_PDF_OPTIONS);
    const desligado = buildHTMLDocument(documentoCompleto({ documentType: 'quote' }), { ...DEFAULT_PDF_OPTIONS, showSignature: false });
    expect(ligado).toContain('Aprovação do Orçamento');
    expect(desligado).not.toContain('Aprovação do Orçamento');
  });
});

describe('fatura: dados bancários e instruções de pagamento são toggles separados', () => {
  const fatura = (opts: Partial<typeof DEFAULT_PDF_OPTIONS>) =>
    buildHTMLDocument(documentoCompleto({ documentType: 'invoice' }), { ...DEFAULT_PDF_OPTIONS, ...opts });

  it('com o padrão de fábrica, o card sai com as duas colunas', () => {
    expect(DEFAULT_PDF_OPTIONS.showBankDetails).toBe(true);
    expect(DEFAULT_PDF_OPTIONS.showPaymentInstructions).toBe(true);
    const html = fatura({});
    expect(html).toContain('Instruções para Pagamento');
    expect(html).toContain('Dados Bancários:');
    expect(html).toContain('Banco do Brasil');
    expect(html).toContain('Pague via PIX:');
    expect(html).toContain('pix@hbr.com');
    expect(html).toContain('grid-template-columns:1fr 1fr;');
  });

  // A regressão exata: este toggle não mudava nada.
  it('desmarcar instruções tira o PIX e o pedido de comprovante, e mantém os dados bancários', () => {
    const html = fatura({ showPaymentInstructions: false });
    expect(html).not.toContain('Pague via PIX:');
    expect(html).not.toContain('pix@hbr.com');
    expect(html).not.toContain('envie o comprovante');
    expect(html).toContain('Dados Bancários:');
    expect(html).toContain('Banco do Brasil');
    expect(html).toContain('67890-1');
  });

  it('desmarcar dados bancários tira banco, agência e conta, e mantém as instruções', () => {
    const html = fatura({ showBankDetails: false });
    expect(html).not.toContain('Dados Bancários:');
    expect(html).not.toContain('Banco do Brasil');
    expect(html).not.toContain('67890-1');
    expect(html).toContain('Pague via PIX:');
    expect(html).toContain('pix@hbr.com');
  });

  // Coluna sozinha não pode ficar com a borda e o recuo que a separavam da vizinha.
  it('uma coluna só ocupa o card inteiro', () => {
    const html = fatura({ showBankDetails: false });
    expect(html).toContain('grid-template-columns:1fr;');
    expect(html).not.toContain('border-left:1px solid var(--pdf-border);padding-left:12px;');
  });

  it('com os dois desmarcados o card some inteiro', () => {
    const html = fatura({ showBankDetails: false, showPaymentInstructions: false });
    expect(html).not.toContain('Instruções para Pagamento');
    expect(html).not.toContain('Banco do Brasil');
    expect(html).not.toContain('pix@hbr.com');
  });
});

/**
 * NOVO-lev-35 — as larguras das colunas de itens somavam 85% com uma coluna de valor só.
 * Imprimir e baixar redistribuíam a sobra de jeitos diferentes, e a tabela mudava de forma
 * entre uma via e outra.
 */
describe('as colunas da tabela de itens somam 100% em qualquer combinação de toggles', () => {
  /** Soma dos `width:N%` de cada cabeçalho de tabela do documento. */
  const somasPorCabecalho = (html: string): number[] =>
    [...html.matchAll(/<thead>([\s\S]*?)<\/thead>/g)].map((m) =>
      [...m[1].matchAll(/width:(\d+)%/g)].reduce((soma, w) => soma + Number(w[1]), 0));

  it.each([
    ['tudo marcado', {}],
    ['só serviços', { showPartsPrices: false }],
    ['só peças', { showServicePrices: false }],
    ['nada marcado', { showServicePrices: false, showPartsPrices: false }],
    ['via de execução', { hideFinancials: true }],
  ])('%s', (_nome, opts) => {
    const html = buildHTMLDocument(documentoCompleto(), { ...DEFAULT_PDF_OPTIONS, ...opts });
    const somas = somasPorCabecalho(html);
    expect(somas).toHaveLength(2); // serviços e peças
    for (const soma of somas) expect(soma).toBe(100);
  });

  it('o documento do cliente mantém a divisão de sempre', () => {
    const html = buildHTMLDocument(documentoCompleto(), DEFAULT_PDF_OPTIONS);
    expect(html).toContain('<th style="width:55%;">Descrição Técnica</th>');
    expect(html).toContain('<th style="width:15%;text-align:center;">Qtd/Unid</th>');
    expect(html).toContain('<th style="width:15%;text-align:right;">Unitário</th>');
    expect(html).toContain('<th style="width:15%;text-align:right;">Subtotal</th>');
  });

  it('sem preço das peças, a descrição da peça absorve a sobra e a de serviço não muda', () => {
    const html = buildHTMLDocument(documentoCompleto(), { ...DEFAULT_PDF_OPTIONS, showPartsPrices: false });
    expect(html).toContain('<th style="width:80%;">Item / Especificação</th>');
    expect(html).toContain('<th style="width:55%;">Descrição Técnica</th>');
  });
});

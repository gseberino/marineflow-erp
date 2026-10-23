import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, buildPDFFilename, tituloParaImpressao, DEFAULT_PDF_OPTIONS, type PDFData } from './pdf-generator';

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

/**
 * "Observações para impressão" (extra_notes). Até 16/09/2026 o formulário gravava, o hook
 * entregava ao gerador e o template ignorava: o texto nunca saiu em documento nenhum. Este
 * bloco existe para o campo não voltar a sumir em silêncio.
 */
describe('Observações para impressão (extra_notes)', () => {
  const texto = 'Garantia de 90 dias. Valores válidos até o fim do mês.';
  const comNota = (documentType: PDFData['documentType'] = 'service_order'): PDFData => {
    // documentoCompleto faz spread raso: sobrescrever serviceOrder inteiro apagaria o resto.
    const base = documentoCompleto({ documentType });
    return { ...base, serviceOrder: { ...base.serviceOrder, extra_notes: texto } };
  };

  it('aparece no orçamento, na OS e na fatura quando preenchido', () => {
    for (const tipo of ['quote', 'service_order', 'invoice'] as const) {
      const html = buildHTMLDocument(comNota(tipo), DEFAULT_PDF_OPTIONS);
      expect(html, tipo).toContain('Garantia de 90 dias');
      expect(html, tipo).toContain('<div class="section-title">Observações</div>');
    }
  });

  it('some com o toggle showExtraNotes desligado e não deixa título órfão quando está vazio', () => {
    const desligado = buildHTMLDocument(comNota(), { ...DEFAULT_PDF_OPTIONS, showExtraNotes: false });
    expect(desligado).not.toContain('Garantia de 90 dias');
    const vazio = buildHTMLDocument(documentoCompleto(), DEFAULT_PDF_OPTIONS);
    expect(vazio).not.toContain('<div class="section-title">Observações</div>');
  });

  it('não vai na via de execução (sem valores): a observação é escrita para o cliente', () => {
    const html = buildHTMLDocument(comNota(), { ...DEFAULT_PDF_OPTIONS, hideFinancials: true });
    expect(html).not.toContain('Garantia de 90 dias');
  });
});

/**
 * Baixar e Imprimir têm que produzir o MESMO documento. O que diferia (16/09/2026):
 * texto corrido num bloco só (partia no meio da linha no Baixar, ou descia inteiro e
 * deixava meia folha em branco no Imprimir) e o nome do arquivo salvo pela impressão.
 */
describe('paridade entre Baixar e Imprimir', () => {
  it('linha em branco separa parágrafos; quebra de linha dentro do parágrafo fica', () => {
    const base = documentoCompleto();
    const html = buildHTMLDocument(
      { ...base, serviceOrder: { ...base.serviceOrder, extra_notes: 'linha 1\nlinha 2\n\n\nlinha 4' } },
      DEFAULT_PDF_OPTIONS,
    );
    const inicio = html.indexOf('<div class="section-title">Observações</div>');
    const bloco = html.slice(inicio, html.indexOf('</div>', inicio + 60));
    expect(bloco.match(/<p /g)?.length).toBe(2);
    expect(bloco).toContain('linha 1\nlinha 2</p>');
    expect(bloco).toContain('white-space:pre-wrap');
    expect(html).toMatch(/class="card pdf-texto" data-pdf-quebra="dentro"[^>]*>\s*<div class="section-title">Observações<\/div>/);
  });

  it('subtítulo em caixa alta gruda no parágrafo seguinte; texto comum não', () => {
    const base = documentoCompleto();
    const html = buildHTMLDocument(
      { ...base, serviceOrder: { ...base.serviceOrder, extra_notes: 'GARANTIA\n\nOs produtos têm 90 dias.\n\nFIM.' } },
      DEFAULT_PDF_OPTIONS,
    );
    expect(html).toMatch(/<p style="[^"]*break-after:avoid[^"]*">GARANTIA<\/p>/);
    expect(html).toMatch(/<p style="(?:(?!break-after)[^"])*">Os produtos têm 90 dias\.<\/p>/);
    // "FIM." termina com ponto: é frase, não título.
    expect(html).toMatch(/<p style="(?:(?!break-after)[^"])*">FIM\.<\/p>/);
  });

  it('título de seção e título dos termos nunca ficam sozinhos no pé da página', () => {
    const html = buildHTMLDocument(documentoCompleto({ terms: 'a\n\nb' }), DEFAULT_PDF_OPTIONS);
    expect(html).toMatch(/\.section-title\s*\{[^}]*break-after:\s*avoid/);
    expect(html).toMatch(/break-after:avoid;page-break-after:avoid;">Condições Gerais e Garantia</);
  });

  it('logo é fundo, não <img>: se a URL morrer, não sobra texto alternativo no cabeçalho', () => {
    const html = buildHTMLDocument(
      documentoCompleto({ company: { name: 'HBR', logo_url: 'https://x/logo.png' } } as never),
      DEFAULT_PDF_OPTIONS,
    );
    expect(html).toContain("background:url('https://x/logo.png')");
    expect(html).not.toMatch(/<img[^>]*logo\.png/);
  });

  it('objetivo, conclusão técnica, observações financeiras e termos também partem entre linhas', () => {
    const base = documentoCompleto({ documentType: 'service_order' });
    const html = buildHTMLDocument(
      {
        ...base,
        terms: 'primeira cláusula\nsegunda cláusula',
        serviceOrder: { ...base.serviceOrder, technical_notes: 'ok', financial_notes: 'à vista' },
      },
      DEFAULT_PDF_OPTIONS,
    );
    // objetivo + conclusão + financeiras + termos
    expect((html.match(/data-pdf-quebra="dentro"/g) ?? []).length).toBe(4);
    expect(html).toContain('.pdf-texto { page-break-inside: auto; break-inside: auto; }');
  });

  it('o título da janela de impressão é o nome do arquivo sem a extensão', () => {
    expect(tituloParaImpressao(makeData())).toBe('OrdemServico_OS-00123_Joao-da-Silva_Lancha-Azul');
    expect(buildPDFFilename(makeData())).toBe(`${tituloParaImpressao(makeData())}.pdf`);
  });
});

/**
 * Decisão 9 (21/10/2026), pedido do dono: "Embarcação: Iveco Daily" não faz sentido, e 61% das
 * OS são de motorhome. Com a unidade à vista, o rótulo é o próprio tipo; sem o tipo (o link
 * público não lê asset_type), o termo geral "Embarcação ou veículo". Conferido no HTML final.
 */
describe('a unidade no documento leva o tipo como rótulo', () => {
  const motorhome = {
    name: 'Iveco Daily', type: 'Motorhome', manufacturer: 'Iveco', model: 'Daily', year: 2019, registration: 'ABC1D23',
  };

  it('OS e orçamento: "Motorhome: Iveco Daily" e a placa com o nome certo', () => {
    for (const documentType of ['service_order', 'quote'] as const) {
      const html = buildHTMLDocument(documentoCompleto({ documentType, vessel: motorhome }), DEFAULT_PDF_OPTIONS);
      expect(html).toContain('Embarcação ou veículo e local');
      expect(html).toContain('Motorhome: Iveco Daily</div>');
      expect(html).toContain('Placa: ABC1D23');
      expect(html).not.toMatch(/Ativo|Embarcação: |Registro:/);
    }
  });

  it('lancha: o rótulo é "Lancha" e a identificação é a inscrição', () => {
    const html = buildHTMLDocument(
      documentoCompleto({ vessel: { name: 'Netuno II', type: 'Lancha', registration: '4410123456' } }),
      DEFAULT_PDF_OPTIONS,
    );
    expect(html).toContain('Lancha: Netuno II</div>');
    expect(html).toContain('Inscrição: 4410123456');
  });

  it('cadastro sem tipo: o termo geral', () => {
    const html = buildHTMLDocument(
      documentoCompleto({ vessel: { name: 'Iveco Daily', registration: 'ABC1D23' } }),
      DEFAULT_PDF_OPTIONS,
    );
    expect(html).toContain('Embarcação ou veículo: Iveco Daily</div>');
    expect(html).toContain('Inscrição / placa: ABC1D23');
  });

  it('recibo: "(Motorhome: Iveco Daily · placa ABC1D23)", nunca "(Ativo: …)"', () => {
    const html = buildHTMLDocument(documentoCompleto({ documentType: 'receipt', vessel: motorhome }), DEFAULT_PDF_OPTIONS);
    expect(html).toContain('(Motorhome: Iveco Daily · placa ABC1D23)');
    expect(html).not.toContain('Ativo');
    const semUnidade = buildHTMLDocument(documentoCompleto({ documentType: 'receipt' }), DEFAULT_PDF_OPTIONS);
    expect(semUnidade).not.toMatch(/Embarcação ou veículo|Ativo/);
  });
});

/**
 * Leva 8 (22/10/2026), decisão do dono: quando um terceiro pagou (cônjuge, empresa do cliente, marina…), o recibo diz
 * "Recebemos de X, CPF ***.456.789-**, por conta de Y". CPF de terceiro sai MASCARADO mesmo que chegue inteiro;
 * CNPJ sai inteiro. Sem payer, o texto de sempre.
 */
describe('recibo: quem pagou por conta do cliente', () => {
  const recibo = (receipt: DeepPartial<NonNullable<PDFData['receipt']>>, client: DeepPartial<PDFData['client']> = { name: 'Cliente Teste', cpf_cnpj: '98.765.432/0001-10' }) =>
    buildHTMLDocument(
      documentoCompleto({
        documentType: 'receipt',
        client,
        receipt: { amount: 1500, payment_date: '2026-10-20', payment_method: 'pix', reference: 'OS-00900', ...receipt },
      }),
      DEFAULT_PDF_OPTIONS,
    ).replace(/\s+/g, ' ');

  it('com payer de CPF: "Recebemos de X, CPF mascarado, por conta de Y, inscrito(a) no …"', () => {
    const html = recibo({ payer: { name: 'Maria Souza', cpf_cnpj: '12345678901' } });
    expect(html).toContain(
      'Recebemos de <strong>MARIA SOUZA</strong>, CPF <strong>***.456.789-**</strong>, por conta de <strong>CLIENTE TESTE</strong>, '
      + 'inscrito(a) no CPF/CNPJ sob o nº <strong>98.765.432/0001-10</strong>, a importância líquida e certa de',
    );
    expect(html).not.toMatch(/12345678901|123\.456\.789-01/);
  });

  it('CPF formatado que chega inteiro também sai mascarado; o que já chega mascarado passa como veio', () => {
    expect(recibo({ payer: { name: 'Maria', cpf_cnpj: '123.456.789-01' } })).toContain('CPF <strong>***.456.789-**</strong>');
    expect(recibo({ payer: { name: 'Maria', cpf_cnpj: '***.456.789-**' } })).toContain('CPF <strong>***.456.789-**</strong>');
    expect(recibo({ payer: { name: 'Maria', cpf_cnpj: '123.456.789-01' } })).not.toContain('123.456.789-01');
  });

  it('o NOME que o banco escreveu com o CPF dentro também sai mascarado no HTML final', () => {
    const html = recibo({ payer: { name: '12345678901-Maria Souza', cpf_cnpj: '12345678901' } });
    expect(html).toContain('Recebemos de <strong>***.456.789-**-MARIA SOUZA</strong>, CPF <strong>***.456.789-**</strong>, por conta de');
    expect(html).not.toMatch(/12345678901|123\.456\.789-01/);
    const doMei = recibo({ payer: { name: 'JOAO SILVA 123.456.789-01' } });
    expect(doMei).toContain('Recebemos de <strong>JOAO SILVA ***.456.789-**</strong>, por conta de');
    expect(doMei).not.toContain('123.456.789-01');
    // CNPJ no nome (a razão social com o CNPJ) fica inteiro, como o documento.
    expect(recibo({ payer: { name: 'ACME 04754513000149' } })).toContain('Recebemos de <strong>ACME 04754513000149</strong>');
  });

  it('com payer de CNPJ: o CNPJ sai inteiro e formatado', () => {
    const html = recibo({ payer: { name: 'Acme Náutica Ltda', cpf_cnpj: '04754513000149' } });
    expect(html).toContain('Recebemos de <strong>ACME NÁUTICA LTDA</strong>, CNPJ <strong>04.754.513/0001-49</strong>, por conta de <strong>CLIENTE TESTE</strong>');
  });

  it('payer sem documento, ou com um número que não é CPF nem CNPJ: só o nome', () => {
    expect(recibo({ payer: { name: 'Maria' } })).toContain('Recebemos de <strong>MARIA</strong>, por conta de <strong>CLIENTE TESTE</strong>');
    const lixo = recibo({ payer: { name: 'Maria', cpf_cnpj: '1234' } });
    expect(lixo).toContain('Recebemos de <strong>MARIA</strong>, por conta de');
    expect(lixo).not.toContain('1234');
  });

  it('cliente sem documento: "por conta de Y," sem o "inscrito(a)"', () => {
    const html = recibo({ payer: { name: 'Maria', cpf_cnpj: '12345678901' } }, { name: 'Cliente Teste' });
    expect(html).toContain('por conta de <strong>CLIENTE TESTE</strong>, a importância líquida e certa de');
    expect(html).not.toContain('inscrito(a)');
  });

  it('sem payer (ou com nome vazio): o texto de sempre, sem "por conta de"', () => {
    for (const receipt of [{}, { payer: { name: '  ' } }]) {
      const html = recibo(receipt);
      expect(html).toContain(
        'Recebemos de <strong>CLIENTE TESTE</strong>, inscrito(a) no CPF/CNPJ sob o nº <strong>98.765.432/0001-10</strong>, a importância líquida e certa de',
      );
      expect(html).not.toContain('por conta de');
    }
  });
});

/**
 * Revisão de 23/10/2026, 4ª rodada: a REFERÊNCIA do recibo (o número REC-…, o título e o "referente ao pagamento de")
 * é, sem OS, a descrição da conta — na receita que nasce da fila do Extrato, o nome que o banco escreveu, às vezes com o
 * CPF de quem pagou dentro. O HTML final nunca leva o CPF inteiro, com ou sem payer; o CNPJ e o número da OS ficam.
 */
describe('recibo: a referência sem o CPF inteiro', () => {
  const recibo = (reference: string, numero = reference, payer?: { name: string; cpf_cnpj?: string }) => buildHTMLDocument(
    documentoCompleto({
      documentType: 'receipt',
      serviceOrder: { service_order_number: numero },
      client: { name: 'Cliente Teste' },
      receipt: { amount: 1500, payment_date: '2026-10-20', payment_method: 'pix', reference, ...(payer ? { payer } : {}) },
    }),
    DEFAULT_PDF_OPTIONS,
  ).replace(/\s+/g, ' ');

  it.each([
    ['12345678901-MARIA SOUZA', '***.456.789-**-MARIA SOUZA'],
    ['MARIA SOUZA 123.456.789-01', 'MARIA SOUZA ***.456.789-**'],
    ['PIX RECEBIDO 12345678901', 'PIX RECEBIDO ***.456.789-**'],
  ])('referência "%s": REC-…, título e "referente ao pagamento de" mascarados', (bruto, mascarado) => {
    for (const html of [recibo(bruto), recibo(bruto, bruto, { name: 'Maria Souza', cpf_cnpj: '12345678901' })]) {
      expect(html).not.toMatch(/12345678901|123\.456\.789-01/);
      expect(html).toContain(`REC-${mascarado}`);
      expect(html).toContain(`<title>RECIBO REC-${mascarado}</title>`);
      expect(html).toContain(`referente ao pagamento de <strong>${mascarado}</strong>`);
    }
  });

  it('sem referência, o número do documento também passa pela máscara', () => {
    const html = recibo('', '12345678901-MARIA SOUZA');
    expect(html).not.toMatch(/12345678901/);
    expect(html).toContain('referente ao pagamento de <strong>***.456.789-**-MARIA SOUZA</strong>');
  });

  it('número da OS e CNPJ na referência ficam como vieram', () => {
    expect(recibo('OS-00900')).toContain('referente ao pagamento de <strong>OS-00900</strong>');
    expect(recibo('ACME LTDA 04754513000149')).toContain('referente ao pagamento de <strong>ACME LTDA 04754513000149</strong>');
  });
});

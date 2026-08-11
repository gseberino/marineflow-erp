// NOVO-006b — a via de execução da OS não pode conter valor nenhum.
//
// Por que este teste é escrito olhando o HTML inteiro, e não bloco a bloco: o documento tem
// pelo menos oito lugares onde dinheiro aparece (unitário e subtotal de serviço, unitário e
// subtotal de peça, os subtotais do resumo, o total, a programação de pagamento, o histórico
// de pagamentos, as observações financeiras, os dados bancários e o PIX). Testar cada um por
// nome deixaria o próximo bloco novo passar batido — a asserção que segura isso é a varredura
// por "R$" e pelos números do caso, que pega qualquer valor que apareça de qualquer jeito.
//
// O contraprova está no fim do arquivo: o MESMO documento sem a opção mostra tudo. Sem ele,
// um gerador que devolvesse página em branco também passaria.
import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, buildPDFFilename, DEFAULT_PDF_OPTIONS, type PDFData, type PDFOptions } from './pdf-generator';

type DeepPartial<T> = { [K in keyof T]?: T[K] extends object ? DeepPartial<T[K]> : T[K] };

/** Valores escolhidos para serem inconfundíveis no HTML: nenhum deles aparece por acaso. */
const VALORES = {
  unitarioServico: 1234.56,
  totalServico: 2469.12,
  unitarioPeca: 987.65,
  totalPeca: 1975.30,
  maoDeObra: 2469.12,
  pecas: 1975.30,
  deslocamento: 333.33,
  desconto: 444.44,
  total: 4333.31,
  pagamentoFeito: 1500.00,
};

function makeData(overrides: DeepPartial<PDFData> = {}): PDFData {
  return {
    documentType: 'service_order',
    company: {
      name: 'HBR Marine', address: 'Rua X, 1', city: 'Itajaí', state: 'SC',
      postal_code: '88300-000', phone: '(47) 3000-0000', email: 'contato@hbr.com', cnpj: '00.000.000/0001-00',
    },
    bank: { bank_name: 'Banco do Brasil', bank_agency: '1234-5', bank_account: '67890-1', pix_key: 'pix@hbr.com' },
    serviceOrder: {
      service_order_number: 'OS-00777',
      status: 'in_progress',
      created_at: '2026-08-01',
      problem_description: 'Painel elétrico desarmando com o gerador ligado.',
      technical_notes: 'Substituído disjuntor geral; testado sob carga.',
      financial_notes: 'Cliente pediu boleto para a segunda parcela.',
      labor_cost_total: VALORES.maoDeObra,
      parts_cost_total: VALORES.pecas,
      travel_cost_total: VALORES.deslocamento,
      operational_cost_total: 0,
      discount_amount: VALORES.desconto,
      tax_amount: 0,
      card_fee_amount: 0,
      grand_total: VALORES.total,
      payment_conditions: '50% na aprovação, 50% na entrega',
      payments: [
        { amount: VALORES.pagamentoFeito, payment_date: '2026-08-05', payment_method: 'pix' },
      ],
    },
    client: { name: 'Charline Souza', phone: '(47) 99999-0000' },
    vessel: { name: 'Lancha Azul', manufacturer: 'Schaefer', model: '375', year: 2019 },
    marina: { name: 'Marina Itajaí', city: 'Itajaí' },
    services: [
      { name: 'Revisão do painel elétrico', description: 'Inclui teste sob carga', quantity: 2, billing_unit: 'hour', unit_price: VALORES.unitarioServico, line_total: VALORES.totalServico },
    ],
    parts: [
      { name: 'Disjuntor 63A', sku: 'DJ-63', quantity: 2, unit_price: VALORES.unitarioPeca, line_total: VALORES.totalPeca },
    ],
    terms: 'Garantia de 90 dias sobre a mão de obra.',
    ...overrides,
  } as PDFData;
}

const viaDeExecucao: PDFOptions = { ...DEFAULT_PDF_OPTIONS, hideFinancials: true };

/** Cada valor do caso, nas formas em que poderia escapar: "1.234,56", "1234.56" e "1234,56". */
function formasDoNumero(valor: number): string[] {
  return [
    valor.toLocaleString('pt-BR', { minimumFractionDigits: 2 }),
    valor.toFixed(2),
    valor.toFixed(2).replace('.', ','),
  ];
}

describe('via de execução — nenhum valor no documento', () => {
  const html = buildHTMLDocument(makeData(), viaDeExecucao);

  it('não imprime cifrão em lugar nenhum', () => {
    expect(html).not.toContain('R$');
  });

  it('não imprime nenhum dos valores da OS, em nenhuma formatação', () => {
    for (const [nome, valor] of Object.entries(VALORES)) {
      for (const forma of formasDoNumero(valor)) {
        expect(html, `valor ${nome} (${forma}) vazou para a via de execução`).not.toContain(forma);
      }
    }
  });

  it('não traz o quadro de totais nem a linha do total', () => {
    expect(html).not.toContain('VALOR TOTAL');
    expect(html).not.toContain('Subtotal Serviços');
    expect(html).not.toContain('Subtotal Peças');
    expect(html).not.toContain('Deslocamento / Logística');
  });

  it('não traz condição de pagamento, histórico de pagamentos nem observação financeira', () => {
    expect(html).not.toContain('50% na aprovação');
    expect(html).not.toContain('Observações Financeiras');
    expect(html).not.toContain('boleto para a segunda parcela');
  });

  it('não traz dados bancários nem PIX', () => {
    expect(html).not.toContain('DADOS BANCÁRIOS');
    expect(html).not.toContain('pix@hbr.com');
    expect(html).not.toContain('Banco do Brasil');
    expect(html).not.toContain('67890-1');
  });

  it('não deixa cabeçalho de coluna de preço órfão nas tabelas', () => {
    expect(html).not.toContain('>Unitário<');
    expect(html).not.toContain('>Subtotal<');
  });

  it('se identifica como via de execução, para não ser confundida com a via do cliente', () => {
    expect(html).toContain('Via de execução');
    expect(html).toContain('Ordem de Serviço — Via de Execução');
  });

  it('mantém tudo que quem executa precisa', () => {
    expect(html).toContain('Revisão do painel elétrico');
    expect(html).toContain('Inclui teste sob carga');
    expect(html).toContain('Disjuntor 63A');
    expect(html).toContain('DJ-63');
    expect(html).toContain('Painel elétrico desarmando');   // relato do problema
    expect(html).toContain('Substituído disjuntor geral');  // conclusão técnica
    expect(html).toContain('Charline Souza');
    expect(html).toContain('Lancha Azul');
    expect(html).toContain('Marina Itajaí');
    expect(html).toContain('OS-00777');
    expect(html).toContain('2 hora');                        // quantidade do serviço
  });

  it('mantém o levantamento técnico, que é instrução de trabalho', () => {
    const comLevantamento = buildHTMLDocument(
      makeData({
        survey: {
          answered_at: '2026-08-02',
          answers: [{ question: 'Onde fica o quadro de disjuntores?', answer: 'Sob o console, a bombordo' }],
        },
      }),
      viaDeExecucao,
    );
    expect(comLevantamento).toContain('Onde fica o quadro de disjuntores?');
    expect(comLevantamento).toContain('Sob o console, a bombordo');
    expect(comLevantamento).not.toContain('R$');
  });

  it('não se aplica a orçamento — um orçamento sem preço não é documento', () => {
    const orcamento = buildHTMLDocument(makeData({ documentType: 'quote' }), viaDeExecucao);
    expect(orcamento).toContain('R$');
    expect(orcamento).toContain('VALOR TOTAL');
    expect(orcamento).not.toContain('Via de execução');
  });
});

describe('contraprova — a MESMA OS sem a opção continua mostrando tudo', () => {
  // Sem isto, um gerador que devolvesse página em branco passaria em todos os testes acima.
  const html = buildHTMLDocument(makeData(), { ...DEFAULT_PDF_OPTIONS, hideFinancials: false });

  it('mostra os valores, o total e os dados de pagamento', () => {
    expect(html).toContain('R$');
    expect(html).toContain('VALOR TOTAL');
    expect(html).toContain(VALORES.total.toLocaleString('pt-BR', { minimumFractionDigits: 2 }));
    expect(html).toContain(VALORES.unitarioServico.toLocaleString('pt-BR', { minimumFractionDigits: 2 }));
    expect(html).toContain('DADOS BANCÁRIOS');
    expect(html).toContain('pix@hbr.com');
    expect(html).toContain('Observações Financeiras');
  });

  it('e não se anuncia como via de execução', () => {
    expect(html).not.toContain('Via de execução');
  });
});

describe('nome do arquivo — as duas vias não podem se confundir na pasta de downloads', () => {
  it('a via de execução se identifica no nome', () => {
    const nome = buildPDFFilename(makeData(), viaDeExecucao);
    expect(nome).toContain('Via-Execucao');
    expect(nome).toContain('OS-00777');
  });

  it('a via completa mantém o nome de sempre', () => {
    expect(buildPDFFilename(makeData(), DEFAULT_PDF_OPTIONS)).not.toContain('Via-Execucao');
    expect(buildPDFFilename(makeData())).not.toContain('Via-Execucao');
  });

  it('não marca orçamento, onde a opção não se aplica', () => {
    expect(buildPDFFilename(makeData({ documentType: 'quote' }), viaDeExecucao)).not.toContain('Via-Execucao');
  });
});

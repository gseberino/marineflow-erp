import { describe, it, expect } from 'vitest';
import { buildHTMLDocument, DEFAULT_PDF_OPTIONS, PDF_ROOT_CLASS, type PDFData } from './pdf-generator';

/**
 * O documento montado não pode carregar regra que valha fora dele.
 *
 * Para baixar o PDF, o html2canvas exige o conteúdo desenhado no DOM, e o
 * `<style>` do documento ia junto para dentro da página do ERP. Regras globais
 * — `* { margin: 0 }`, `body { font-size: 11px }`, `h1 { text-transform:
 * uppercase }` — passavam a valer para o app inteiro durante a captura: a tela
 * perdia margens, encolhia e virava caixa-alta por um segundo. O dono chamou
 * de "gambiarra que distorce tudo e depois baixa", e era exatamente isso.
 *
 * Aqui se verifica o HTML final, não a função de escopo (essa tem teste
 * próprio): o que sai de `buildHTMLDocument` é o que vai para o DOM.
 */
const dados: PDFData = {
  documentType: 'quote',
  company: { name: 'HBR', address: '', city: '', state: '', postal_code: '', phone: '', email: '', cnpj: '' },
  bank: {},
  serviceOrder: {
    service_order_number: 'ORÇ-00074', status: 'draft', created_at: '2026-08-01',
    grand_total: 1000, labor_cost_total: 500, parts_cost_total: 500,
    travel_cost_total: 0, discount_amount: 0, tax_amount: 0, operational_cost_total: 0,
  },
  client: { name: 'Cliente' },
  services: [], parts: [], expenses: [], photos: [],
};

describe('isolamento do documento gerado', () => {
  const html = buildHTMLDocument(dados, DEFAULT_PDF_OPTIONS);
  const css = html.slice(html.indexOf('<style>'), html.indexOf('</style>'));

  it('o conteúdo vive dentro da raiz do documento', () => {
    expect(html).toContain(`class="${PDF_ROOT_CLASS}"`);
  });

  // As três que mais estragavam a tela do app.
  it('a regra universal está presa à raiz', () => {
    expect(css).toContain(`.${PDF_ROOT_CLASS} *`);
    // `* {` solto, no começo de uma regra, é o que vazava.
    expect(css).not.toMatch(/(^|[};])\s*\*\s*\{/);
  });

  it('não sobra regra de body ou :root sem escopo', () => {
    expect(css).not.toMatch(/(^|[};])\s*body\s*\{/);
    expect(css).not.toMatch(/(^|[};])\s*:root\s*\{/);
  });

  it('não sobra seletor de elemento sem escopo', () => {
    // h1/h2/h3, table, th, td, p — todos precisam do prefixo.
    for (const tag of ['h1', 'h2', 'h3', 'table', 'th', 'td', 'p', 'tr', 'thead']) {
      expect(css, `"${tag}" sem escopo`).not.toMatch(
        new RegExp(`(^|[};])\\s*${tag}\\s*[,{]`),
      );
    }
  });

  // @page descreve a folha de papel, não um elemento: escopá-la mataria a
  // margem de 12mm do documento impresso.
  it('@page continua sem escopo', () => {
    expect(css).toMatch(/@page\s*\{/);
    expect(css).not.toMatch(new RegExp(`\\.${PDF_ROOT_CLASS}\\s+@page`));
  });

  it('mantém as regras de quebra de página', () => {
    expect(css).toContain('page-break-inside: avoid');
    expect(css).toContain('display: table-header-group');
    expect(css).toContain('orphans: 3');
  });

  // Sem isto o navegador remove os fundos ao imprimir para poupar tinta, e o
  // cabeçalho azul e o total em destaque saem brancos no papel.
  it('força a impressão das cores', () => {
    expect(css).toContain('print-color-adjust: exact');
  });
});

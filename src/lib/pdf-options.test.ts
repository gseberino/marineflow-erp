// MF-AUD-014 — o padrão da empresa e o catálogo de toggles.
//
// `resolvePdfOptions` é a única porta entre o que está gravado em app_settings e o que o
// gerador de PDF recebe. Ela alimenta três caminhos, dois deles sem ninguém olhando: o
// diálogo de Baixar/Imprimir, o envio por WhatsApp e o link público. Um valor estranho
// gravado na chave não pode virar um `PDFOptions` estranho — precisa virar o padrão de
// fábrica, que é sempre um documento válido.
import { describe, it, expect } from 'vitest';
import { DEFAULT_PDF_OPTIONS, resolvePdfOptions } from './pdf-generator';
import { PDF_OPTION_CATALOG, PDF_OPTION_KEYS, pdfOptionItems } from './pdf-options-catalog';
import { en } from '@/i18n/en';
import { ptBR } from '@/i18n/pt-BR';

const labels = {
  showServicePrices: 'Preço unitário dos serviços',
  showTerms: 'Termos e condições',
};

describe('resolvePdfOptions — padrão da empresa', () => {
  it('sem nada gravado, entrega o padrão de fábrica', () => {
    expect(resolvePdfOptions(undefined, 'quote')).toEqual(DEFAULT_PDF_OPTIONS);
    expect(resolvePdfOptions({}, 'quote')).toEqual(DEFAULT_PDF_OPTIONS);
  });

  it('aplica o que está gravado por cima do padrão de fábrica', () => {
    const settings = { pdf_options_quote: JSON.stringify({ showTerms: false, showCommission: true }) };
    const opts = resolvePdfOptions(settings, 'quote');
    expect(opts.showTerms).toBe(false);
    expect(opts.showCommission).toBe(true);
    // o que não foi gravado continua vindo do padrão de fábrica
    expect(opts.showServicePrices).toBe(DEFAULT_PDF_OPTIONS.showServicePrices);
  });

  it('lê a chave do tipo de documento pedido, e só ela', () => {
    const settings = {
      pdf_options_quote: JSON.stringify({ showTerms: false }),
      pdf_options_invoice: JSON.stringify({ showBankDetails: false }),
    };
    expect(resolvePdfOptions(settings, 'quote').showTerms).toBe(false);
    expect(resolvePdfOptions(settings, 'quote').showBankDetails).toBe(DEFAULT_PDF_OPTIONS.showBankDetails);
    expect(resolvePdfOptions(settings, 'invoice').showBankDetails).toBe(false);
    expect(resolvePdfOptions(settings, 'invoice').showTerms).toBe(DEFAULT_PDF_OPTIONS.showTerms);
    expect(resolvePdfOptions(settings, 'service_order')).toEqual(DEFAULT_PDF_OPTIONS);
  });

  it('JSON quebrado cai no padrão de fábrica em vez de derrubar a geração', () => {
    expect(resolvePdfOptions({ pdf_options_quote: '{isto não é json' }, 'quote')).toEqual(DEFAULT_PDF_OPTIONS);
    expect(resolvePdfOptions({ pdf_options_quote: '' }, 'quote')).toEqual(DEFAULT_PDF_OPTIONS);
  });

  it('JSON válido mas que não é objeto também cai no padrão', () => {
    // Um `JSON.parse('"texto"')` espalhado com spread viraria { 0: 't', 1: 'e', ... } — um
    // PDFOptions com chaves numéricas que o gerador leria como undefined em tudo.
    for (const lixo of ['"texto"', '123', 'null', 'true', '[{"showTerms":false}]']) {
      expect(resolvePdfOptions({ pdf_options_quote: lixo }, 'quote')).toEqual(DEFAULT_PDF_OPTIONS);
    }
  });

  it('descarta chave desconhecida e valor que não é booleano', () => {
    const settings = {
      pdf_options_quote: JSON.stringify({
        showTerms: 'sim',        // string, não booleano — não é para valer
        showSignature: 0,        // idem
        opcaoQueNaoExisteMais: true,
        showDiscount: false,     // este é legítimo
      }),
    };
    const opts = resolvePdfOptions(settings, 'quote');
    expect(opts.showTerms).toBe(DEFAULT_PDF_OPTIONS.showTerms);
    expect(opts.showSignature).toBe(DEFAULT_PDF_OPTIONS.showSignature);
    expect(opts.showDiscount).toBe(false);
    expect(Object.keys(opts).sort()).toEqual(Object.keys(DEFAULT_PDF_OPTIONS).sort());
  });

  it('ignora validity e dueDate, que descrevem um documento e não um padrão', () => {
    const settings = {
      pdf_options_quote: JSON.stringify({
        validity: { mode: 'date', date: '2020-01-01' },
        dueDate: '2020-01-01',
      }),
    };
    const opts = resolvePdfOptions(settings, 'quote');
    expect(opts.validity).toBeUndefined();
    expect(opts.dueDate).toBeUndefined();
  });

  it('devolve cópia nova — mexer no resultado não contamina o padrão de fábrica', () => {
    const opts = resolvePdfOptions({}, 'quote');
    opts.showTerms = false;
    expect(DEFAULT_PDF_OPTIONS.showTerms).toBe(true);
  });
});

describe('catálogo de opções de PDF', () => {
  it('cobre exatamente as chaves booleanas de PDFOptions', () => {
    // Se alguém acrescentar um toggle em DEFAULT_PDF_OPTIONS e esquecer do catálogo, a opção
    // existiria no gerador e não apareceria em tela nenhuma — nem no diálogo, nem no padrão.
    expect([...PDF_OPTION_KEYS].sort()).toEqual(Object.keys(DEFAULT_PDF_OPTIONS).sort());
  });

  it('não repete chave', () => {
    expect(new Set(PDF_OPTION_KEYS).size).toBe(PDF_OPTION_KEYS.length);
  });

  it('orçamento e OS oferecem as mesmas opções, exceto a via de execução', () => {
    const orcamento = pdfOptionItems('quote', labels).map(i => i.key);
    const os = pdfOptionItems('service_order', labels).map(i => i.key);
    // via de execução (NOVO-006b) é só da OS: orçamento sem preço não é documento
    expect(os).toContain('hideFinancials');
    expect(orcamento).not.toContain('hideFinancials');
    expect(os.filter(k => k !== 'hideFinancials')).toEqual(orcamento);
  });

  it('a via de execução não aparece como padrão da empresa — é escolha de um documento', () => {
    const noDialogo = pdfOptionItems('service_order', labels).map(i => i.key);
    const noPadrao = pdfOptionItems('service_order', labels, { includeConditional: false }).map(i => i.key);
    expect(noDialogo).toContain('hideFinancials');
    expect(noPadrao).not.toContain('hideFinancials');
  });

  it('marca quem anula as outras opções — e é uma só', () => {
    const anulam = PDF_OPTION_CATALOG.filter(e => e.overridesOthers).map(e => e.key);
    expect(anulam).toEqual(['hideFinancials']);
    expect(pdfOptionItems('service_order', labels).find(i => i.key === 'hideFinancials')?.overridesOthers).toBe(true);
    expect(pdfOptionItems('service_order', labels).find(i => i.key === 'showTerms')?.overridesOthers).toBe(false);
  });

  it('fatura tem dados bancários e instruções; orçamento não', () => {
    const fatura = pdfOptionItems('invoice', labels).map(i => i.key);
    expect(fatura).toContain('showBankDetails');
    expect(fatura).toContain('showPaymentInstructions');
    const orcamento = pdfOptionItems('quote', labels).map(i => i.key);
    expect(orcamento).not.toContain('showBankDetails');
    expect(orcamento).not.toContain('showPaymentInstructions');
    // e o que é de orçamento não vaza para a fatura
    expect(fatura).not.toContain('showCommission');
    expect(fatura).not.toContain('showSignature');
  });

  it('recibo não tem opção nenhuma', () => {
    expect(pdfOptionItems('receipt', labels)).toEqual([]);
  });

  it('fotos de produto só aparecem no diálogo quando o documento tem foto', () => {
    const semFoto = pdfOptionItems('quote', labels, { hasProductImages: false }).map(i => i.key);
    const comFoto = pdfOptionItems('quote', labels, { hasProductImages: true }).map(i => i.key);
    expect(semFoto).not.toContain('showProductImages');
    expect(comFoto).toContain('showProductImages');
    // na tela de padrão da empresa não há documento — a opção aparece sempre
    const padrao = pdfOptionItems('quote', labels, { includeConditional: false }).map(i => i.key);
    expect(padrao).toContain('showProductImages');
  });

  it('usa o rótulo traduzido quando existe e o texto fixo quando a chave falta', () => {
    const itens = pdfOptionItems('quote', { showTerms: 'Terms and conditions' });
    expect(itens.find(i => i.key === 'showTerms')?.label).toBe('Terms and conditions');
    // sem a chave no dicionário passado, cai na rede de segurança do catálogo
    expect(itens.find(i => i.key === 'showCardFee')?.label).toBe('Mostrar taxa de cartão');
  });

  it('toda opção tem tradução nos DOIS idiomas — nenhuma sobra com texto fixo em português', () => {
    // As cinco que viviam com string pt-BR dentro do componente não apareciam em varredura
    // de i18n nenhuma: não faltava chave no dicionário, faltava a chave existir.
    for (const entrada of PDF_OPTION_CATALOG) {
      expect(ptBR.pdf, `pt-BR.pdf.${entrada.i18nKey} não existe`).toHaveProperty(entrada.i18nKey);
      expect(en.pdf, `en.pdf.${entrada.i18nKey} não existe`).toHaveProperty(entrada.i18nKey);
    }
  });

  it('os rótulos saem no idioma escolhido', () => {
    const emIngles = pdfOptionItems('service_order', en.pdf as unknown as Record<string, string>);
    const emPortugues = pdfOptionItems('service_order', ptBR.pdf as unknown as Record<string, string>);
    expect(emIngles.find(i => i.key === 'hideFinancials')?.label).toBe('Execution copy (no prices)');
    expect(emPortugues.find(i => i.key === 'hideFinancials')?.label).toBe('Via de execução (sem valores)');
  });

  it('sem i18n nenhum, todo item ainda tem rótulo legível', () => {
    for (const tipo of ['quote', 'service_order', 'invoice'] as const) {
      for (const item of pdfOptionItems(tipo, undefined)) {
        expect(item.label.trim().length).toBeGreaterThan(0);
      }
    }
  });

  it('toda entrada do catálogo vale para pelo menos um documento', () => {
    for (const entrada of PDF_OPTION_CATALOG) {
      expect(entrada.docTypes.length).toBeGreaterThan(0);
    }
  });
});

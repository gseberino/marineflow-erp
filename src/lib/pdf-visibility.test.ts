import { describe, it, expect } from 'vitest';
import { valueVisibility, itemColumnCount, itemColumnWidths, isFinancialOption } from './pdf-visibility';
import { DEFAULT_PDF_OPTIONS, type PDFOptions } from './pdf-generator';

/**
 * O dono desmarcou todas as caixas de valor para imprimir a OS dos técnicos, e
 * o documento saiu com os valores assim mesmo: a opção controlava só a coluna
 * "Unitário" e deixava o total da linha, o subtotal e o total geral.
 *
 * Não existia combinação de caixas que produzisse um documento sem valores.
 */
describe('o que aparece de valor no documento', () => {
  it('com tudo marcado, mostra tudo', () => {
    const v = valueVisibility({ showServicePrices: true, showPartsPrices: true });
    expect(v).toEqual({
      servicoUnitario: true, servicoTotal: true,
      pecaUnitario: true, pecaTotal: true,
      resumoFinanceiro: true,
    });
  });

  // A regressão exata: desmarcar tem que levar o TOTAL junto.
  it('desmarcar serviço esconde unitário E total do serviço', () => {
    const v = valueVisibility({ showServicePrices: false, showPartsPrices: true });
    expect(v.servicoUnitario).toBe(false);
    expect(v.servicoTotal).toBe(false);
  });

  it('desmarcar peça esconde unitário E total da peça', () => {
    const v = valueVisibility({ showServicePrices: true, showPartsPrices: false });
    expect(v.pecaUnitario).toBe(false);
    expect(v.pecaTotal).toBe(false);
  });

  it('uma seção com preço mantém o resumo financeiro', () => {
    expect(valueVisibility({ showServicePrices: true, showPartsPrices: false }).resumoFinanceiro).toBe(true);
    expect(valueVisibility({ showServicePrices: false, showPartsPrices: true }).resumoFinanceiro).toBe(true);
  });

  // O objetivo de tudo isto: um documento realmente sem valores.
  it('sem preço em nenhuma seção, o resumo financeiro some', () => {
    const v = valueVisibility({ showServicePrices: false, showPartsPrices: false });
    expect(v).toEqual({
      servicoUnitario: false, servicoTotal: false,
      pecaUnitario: false, pecaTotal: false,
      resumoFinanceiro: false,
    });
  });

  // Opção ausente é opção ligada: o documento do cliente, que é o uso normal,
  // não pode perder valores porque alguém esqueceu de passar a preferência.
  it('opção ausente vale como marcada', () => {
    expect(valueVisibility({})).toEqual({
      servicoUnitario: true, servicoTotal: true,
      pecaUnitario: true, pecaTotal: true,
      resumoFinanceiro: true,
    });
  });
});

describe('colunas da tabela de itens', () => {
  // Se este número não bater com os <td> de cada linha, o colspan do rodapé
  // desalinha a tabela — defeito que só aparece depois de impresso.
  it('conta descrição, quantidade e as colunas de valor visíveis', () => {
    expect(itemColumnCount(true, true)).toBe(4);
    expect(itemColumnCount(false, true)).toBe(3);
    expect(itemColumnCount(true, false)).toBe(3);
    expect(itemColumnCount(false, false)).toBe(2);
  });

  // NOVO-lev-35: as larguras eram literais (55 + 15 + 15 por coluna de valor). Com uma
  // coluna só somavam 85%, e imprimir e baixar redistribuíam a sobra de jeitos diferentes.
  describe('as larguras fecham em 100% em qualquer combinação', () => {
    const soma = ({ descricao, quantidade, valor }: ReturnType<typeof itemColumnWidths>, colunasDeValor: number) =>
      descricao + quantidade + valor * colunasDeValor;

    it.each([
      [true, true, 2],
      [true, false, 1],
      [false, true, 1],
      [false, false, 0],
    ])('unitário=%s total=%s', (unitario, total, colunasDeValor) => {
      expect(soma(itemColumnWidths(unitario, total), colunasDeValor)).toBe(100);
    });

    // O documento do cliente, que é o uso normal, não pode mudar de forma.
    it('com as duas colunas de valor mantém a divisão de sempre', () => {
      expect(itemColumnWidths(true, true)).toEqual({ descricao: 55, quantidade: 15, valor: 15 });
    });

    // A sobra vai para a descrição: quantidade e valor ficam iguais nas duas tabelas,
    // mesmo quando só uma delas mostra preço.
    it('com uma coluna de valor, a descrição absorve a sobra', () => {
      expect(itemColumnWidths(true, false)).toEqual({ descricao: 70, quantidade: 15, valor: 15 });
      expect(itemColumnWidths(false, true)).toEqual({ descricao: 70, quantidade: 15, valor: 15 });
    });

    it('sem coluna de valor usa a divisão que a via de execução já usava', () => {
      expect(itemColumnWidths(false, false)).toMatchObject({ descricao: 80, quantidade: 20 });
    });
  });
});

/**
 * NOVO-022: o diálogo desabilitava TODOS os outros toggles com a via de execução marcada,
 * inclusive termos e fotos — que o gerador continua lendo. Quem queria a folha de campo
 * sem termos não conseguia desmarcar.
 */
describe('quais toggles a via de execução esvazia', () => {
  it('os de valor, sim', () => {
    for (const key of ['showServicePrices', 'showPartsPrices', 'showTravelCost', 'showDiscount',
      'showTax', 'showCardFee', 'showCommission', 'showBankDetails', 'showPaymentInstructions'] as const) {
      expect(isFinancialOption(key), key).toBe(true);
    }
  });

  it('termos, assinatura e fotos, não — e nem ela mesma', () => {
    for (const key of ['showTerms', 'showSignature', 'showProductImages', 'hideFinancials'] as const) {
      expect(isFinancialOption(key), key).toBe(false);
    }
  });

  // Toggle novo tem que ser classificado de propósito: sem isto ele nasceria "não financeiro"
  // e ficaria clicável na via de execução mesmo decidindo valor.
  it('toda opção do gerador está classificada', () => {
    const naoFinanceiras: ReadonlySet<keyof PDFOptions> = new Set(['showTerms', 'showSignature', 'showProductImages', 'hideFinancials']);
    for (const key of Object.keys(DEFAULT_PDF_OPTIONS) as Array<keyof PDFOptions>) {
      expect(isFinancialOption(key) || naoFinanceiras.has(key), `${key} não foi classificada`).toBe(true);
    }
  });
});

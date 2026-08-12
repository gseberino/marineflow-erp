import { describe, it, expect } from 'vitest';
import { valueVisibility, itemColumnCount } from './pdf-visibility';

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
});

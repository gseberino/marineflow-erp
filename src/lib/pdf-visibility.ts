import type { PDFOptions } from './pdf-generator';

/**
 * O que aparece de valor no documento.
 *
 * ═══ POR QUE ISTO EXISTE ═══
 *
 * As caixas do diálogo prometiam mais do que entregavam. "Preço unitário dos
 * serviços" desmarcado tirava a coluna Unitário — e deixava o TOTAL de cada
 * linha, o subtotal e o total geral. O dono desmarcou tudo para imprimir a OS
 * dos técnicos e o documento saiu com os valores assim mesmo.
 *
 * Não havia combinação de caixas que produzisse um documento sem valores.
 *
 * A regra agora é a que o nome da caixa sempre sugeriu: desmarcar o preço de
 * uma seção esconde o preço daquela seção INTEIRO — unitário e total. E quando
 * nem serviço nem peça mostram preço, o resumo financeiro não tem o que
 * resumir: some junto, com desconto, imposto, taxa e o total geral.
 */

export interface ValueVisibility {
  /** Coluna de preço unitário do serviço. */
  servicoUnitario: boolean;
  /** Total por linha de serviço. */
  servicoTotal: boolean;
  pecaUnitario: boolean;
  pecaTotal: boolean;
  /** O quadro de somatório: subtotal, desconto, imposto, total geral. */
  resumoFinanceiro: boolean;
}

export function valueVisibility(options: Partial<PDFOptions>): ValueVisibility {
  const servico = options.showServicePrices !== false;
  const peca = options.showPartsPrices !== false;

  return {
    servicoUnitario: servico,
    servicoTotal: servico,
    pecaUnitario: peca,
    pecaTotal: peca,
    // Sem preço em nenhuma das duas seções, o resumo mostraria um total que não
    // corresponde a nada visível na folha — e é exatamente o número que se
    // queria esconder ao desmarcar as caixas.
    resumoFinanceiro: servico || peca,
  };
}

/**
 * Quantas colunas a tabela de itens terá.
 *
 * Precisa bater com o número de `<td>` de cada linha, senão o `colspan` do
 * rodapé desalinha a tabela inteira — o tipo de defeito que só aparece no papel.
 */
export function itemColumnCount(mostraUnitario: boolean, mostraTotal: boolean): number {
  return 2 + (mostraUnitario ? 1 : 0) + (mostraTotal ? 1 : 0); // descrição + qtd
}

export interface ItemColumnWidths {
  /** Descrição do item, em % da tabela. */
  descricao: number;
  quantidade: number;
  /** Cada coluna de valor visível (unitário, subtotal) tem esta largura. */
  valor: number;
}

/**
 * Larguras das colunas da tabela de itens, somando sempre 100%.
 *
 * Eram literais no gerador: 55% descrição + 15% quantidade + 15% por coluna de valor.
 * Com as duas colunas de valor dá 100; com uma só dava 85, e a sobra ficava por conta
 * do navegador — a tabela saía estreita numa via e redistribuída na outra, porque o
 * caminho de imprimir e o de baixar (rasterizado) resolvem `width` de forma diferente.
 *
 * A sobra vai para a descrição, que é a coluna que quebra linha; quantidade e valor
 * ficam com a mesma largura em todas as combinações, para que a tabela de serviços e
 * a de peças alinhem entre si mesmo quando uma mostra preço e a outra não.
 */
export function itemColumnWidths(mostraUnitario: boolean, mostraTotal: boolean): ItemColumnWidths {
  const colunasDeValor = itemColumnCount(mostraUnitario, mostraTotal) - 2;
  const valor = 15;
  // Sem valor nenhum a quantidade ganha um pouco mais: é o que a via de execução já usava.
  const quantidade = colunasDeValor > 0 ? 15 : 20;
  return { descricao: 100 - quantidade - valor * colunasDeValor, quantidade, valor };
}

/**
 * Toggles que decidem VALOR no documento — os que a via de execução esvazia.
 *
 * O diálogo desabilita estes quando "Via de execução" está marcada, e SÓ estes: os
 * demais (termos, assinatura, fotos dos produtos) continuam valendo na folha de
 * campo, e o gerador continua lendo cada um deles.
 */
const FINANCIAL_OPTION_KEYS: ReadonlySet<keyof PDFOptions> = new Set<keyof PDFOptions>([
  'showServicePrices',
  'showPartsPrices',
  'showTravelCost',
  'showDiscount',
  'showTax',
  'showCardFee',
  'showCommission',
  'showBankDetails',
  'showPaymentInstructions',
]);

export function isFinancialOption(key: keyof PDFOptions): boolean {
  return FINANCIAL_OPTION_KEYS.has(key);
}

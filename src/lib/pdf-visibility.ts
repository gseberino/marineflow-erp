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

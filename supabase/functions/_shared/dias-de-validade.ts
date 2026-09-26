// Quantos dias vale um orçamento: a regra que decide se um número serve.
//
// POR QUE ISTO EXISTE: até 26/09/2026 havia duas contas para a mesma pergunta.
//
//   · _shared/ai/validade-orcamento.ts (o assistente, ao CRIAR o orçamento) aceitava só
//     número finito maior que zero, arredondado para baixo;
//   · _shared/pdf/documento.ts (o "Válido por N dias" do PDF e o dia do aviso de vencimento
//     da R19) usava `Number(x) || próximo`, que deixa passar -1 e 2.5: um orçamento com
//     validade -1 saía "Válido por -1 dias" e a R19 o dava por vencido já no dia da emissão.
//
// Agora as duas perguntam aqui. Este arquivo não importa nada de propósito: a tela (Vite) e
// as Edge Functions (Deno) o carregam do mesmo lugar.

/**
 * Último recurso, quando nenhum nível tem um número que sirva.
 *
 * 15 e não 30: é o DEFAULT da coluna service_orders.quote_validity_days e o que o gerador
 * de PDF sempre usou, então a falta de configuração mantém o comportamento antigo.
 */
export const VALIDADE_PADRAO_DE_RESERVA = 15;

/**
 * Um número de dias de validade utilizável, ou null se o valor não serve.
 *
 * Serve: número (ou texto numérico) finito cujo inteiro, arredondado para baixo, seja pelo
 * menos 1. `2.5` vira 2 (a mesma conta que o assistente já fazia). Não servem: vazio, null,
 * texto que não é número, 0, negativo e o que arredonda para 0 (`0.5`) — antes o assistente
 * devolvia 0 para `0.5`.
 */
export function diasDeValidade(valor: unknown): number | null {
  if (valor === null || valor === undefined || typeof valor === 'boolean') return null;
  if (typeof valor === 'string' && valor.trim() === '') return null;
  const n = Number(valor);
  if (!Number.isFinite(n)) return null;
  const dias = Math.floor(n);
  return dias >= 1 ? dias : null;
}

/**
 * O primeiro nível com validade utilizável, na ordem dada; nenhum → 15.
 *
 * A ordem é de quem chama: no PDF é orçamento → padrão da empresa; no assistente é o valor
 * pedido naquela conversa → padrão da empresa. Um nível inválido não "ganha" com 0 ou -1:
 * passa a vez para o seguinte.
 */
export function primeiraValidade(...niveis: unknown[]): number {
  for (const nivel of niveis) {
    const dias = diasDeValidade(nivel);
    if (dias !== null) return dias;
  }
  return VALIDADE_PADRAO_DE_RESERVA;
}

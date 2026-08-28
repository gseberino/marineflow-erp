/**
 * Os tipos de entidade que uma tarefa ou sugestão da agenda pode apontar, em um lugar só.
 *
 * ═══ POR QUE ISTO EXISTE ═══
 * `related_entity_type` é um CHECK de lista fechada. Quando uma regra nova do motor grava
 * um tipo fora da lista, o INSERT falha com 23514, o `catch` por regra do task-automations
 * engole o erro e segue para a próxima — o cron responde 200, as outras regras funcionam, e
 * a regra nova fica silenciosamente sem efeito. Foi exatamente o que aconteceu com a R17 em
 * 30/07/2026 (`quote_request`): o deploy passou, o tick rodou, e ela criou zero tarefas.
 *
 * A lista também vivia copiada em quatro lugares (as duas tabelas, o tipo do frontend e o
 * mapa de rótulos do TaskCard), livres para divergir — e divergiram: em 28/08/2026 o CHECK
 * de `agenda_tasks` tinha 11 valores e o de `agenda_suggestions` ainda tinha 10.
 *
 * Este arquivo mora em `_shared/` porque precisa ser alcançável pelos dois lados: as Edge
 * Functions importam direto e o frontend importa por caminho relativo — mesmo precedente de
 * `_shared/service-order-status.ts`, criado para esta mesma classe de bug. São constantes
 * puras, sem nada do Deno, de propósito, para poder atravessar essa fronteira.
 *
 * ⚠️ A fonte da verdade é o CHECK das tabelas. `agenda-entity-types_test.ts` lê a migration
 * mais recente que define cada um dos dois CHECKs e falha se esta lista divergir de
 * qualquer um deles. Ao mudar um CHECK, mude aqui — e mude os DOIS. O teste cobra.
 */

/** Todos os valores aceitos por `related_entity_type` (espelha o CHECK das duas tabelas). */
export const RELATED_ENTITY_TYPES = [
  "service_order",
  "quote",
  "external_quote",
  "client",
  "vessel",
  "receivable",
  "payable",
  "purchase_order",
  "collection",
  "stock_item",
  /** cotação a fornecedor (COT-) — usada pelas regras R17 e R18 */
  "quote_request",
] as const;

export type RelatedEntityType = (typeof RELATED_ENTITY_TYPES)[number];

/** Rótulos em pt-BR, na mesma redação que o TaskCard já mostra ao usuário. */
export const ROTULOS_ENTIDADE: Record<RelatedEntityType, string> = {
  service_order: "OS",
  quote: "Orçamento",
  external_quote: "Orçamento",
  client: "Cliente",
  vessel: "Embarcação",
  receivable: "Recebível",
  payable: "Pagável",
  purchase_order: "OC",
  collection: "Cobrança",
  stock_item: "Estoque",
  quote_request: "Cotação",
};

/** Aceita o que o CHECK aceitaria — inclusive `null`, que significa "sem vínculo". */
export function ehTipoDeEntidadeValido(valor: unknown): valor is RelatedEntityType | null {
  return valor === null || valor === undefined ||
    (RELATED_ENTITY_TYPES as readonly string[]).includes(valor as string);
}

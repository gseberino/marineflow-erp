// Cadastro de produto pelo agente — o que entra na tabela e por quanto o produto é vendido.
//
// O BUG QUE ISTO CORRIGE (NOVO-agente-06): `create_product` fazia `insert(args)` cru. Duas
// consequências, ambas medidas em produção:
//
//   1. O `input_schema` anuncia `profit_margin` ("Margem em %"). O modelo obedece e manda
//      `cost_price: 28, profit_margin: 30` — e NADA calculava o preço de venda. O produto nascia
//      valendo R$ 0,00. Havia 39 produtos ativos assim, todos com margem informada. Foi o que o
//      dono viu ao perguntar "a maioria dos materiais está sem preço, por quê?".
//      E o efeito em cadeia é pior que a linha zerada: produto sem preço é inútil para orçar, então
//      o agente voltava a casar com um produto ERRADO do catálogo — que ao menos tem preço.
//
//   2. Sem allowlist, um campo alucinado pelo modelo ia direto ao Postgres e o erro do banco
//      voltava cru para o modelo, que não tem como agir sobre "malformed array literal".
//
// Fica em módulo próprio (e não dentro da tool) para ter teste sem subir banco: o cálculo de preço
// é a regra que decide quanto a HBR cobra, e regra de dinheiro se testa.

/** Colunas de `public.products` que o agente pode preencher. Espelha o input_schema de
 *  `create_product`; qualquer outra chave é descartada em silêncio (e contada, para o retorno
 *  poder dizer que houve descarte — campo inventado é sinal de descrição de tool ruim). */
export const COLUNAS_DE_PRODUTO = [
  "name", "sku", "brand", "category", "unit",
  "sale_price", "cost_price", "minimum_stock", "barcode", "notes",
  "ncm", "cfop", "csosn", "fiscal_origin", "profit_margin", "supplier_id",
] as const;

export interface LinhaDeProduto {
  [coluna: string]: unknown;
}

/** Filtra os argumentos do modelo para as colunas que existem de fato. */
export function camposDeProduto(args: Record<string, unknown>): { linha: LinhaDeProduto; ignorados: string[] } {
  const linha: LinhaDeProduto = {};
  const ignorados: string[] = [];
  for (const [chave, valor] of Object.entries(args || {})) {
    if (valor === undefined) continue;
    if ((COLUNAS_DE_PRODUTO as readonly string[]).includes(chave)) linha[chave] = valor;
    else ignorados.push(chave);
  }
  return { linha, ignorados };
}

/**
 * Preço de venda a gravar, ou `null` quando não há como calcular.
 *
 * Regra: preço informado MANDA (o dono pode ter negociado um valor que não sai de conta nenhuma).
 * Sem preço informado, custo × (1 + margem/100). Sem custo ou sem margem, não inventa — devolve
 * null e o produto entra sem preço, agora com aviso explícito de que falta.
 */
export function precoDeVenda(args: { sale_price?: unknown; cost_price?: unknown; profit_margin?: unknown }): number | null {
  const informado = Number(args.sale_price);
  if (Number.isFinite(informado) && informado > 0) return arredonda(informado);

  const custo = Number(args.cost_price);
  const margem = Number(args.profit_margin);
  if (!Number.isFinite(custo) || custo <= 0) return null;
  if (!Number.isFinite(margem) || margem <= 0) return null;

  return arredonda(custo * (1 + margem / 100));
}

function arredonda(n: number): number {
  return Math.round(n * 100) / 100;
}

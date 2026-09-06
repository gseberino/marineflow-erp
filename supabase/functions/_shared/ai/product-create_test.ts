import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { camposDeProduto, precoDeVenda, COLUNAS_DE_PRODUTO } from "./product-create.ts";

// Regra de dinheiro: é ela que decide por quanto a HBR vende. O bug que estes testes travam
// (NOVO-agente-06) criou 39 produtos ativos valendo R$ 0,00 porque a margem era aceita e ignorada.

Deno.test("custo + margem viram preço de venda — o caso que criava produto valendo zero", () => {
  assertEquals(precoDeVenda({ cost_price: 28, profit_margin: 30 }), 36.4);
  assertEquals(precoDeVenda({ cost_price: 180, profit_margin: 30 }), 234);
  assertEquals(precoDeVenda({ cost_price: 4.5, profit_margin: 30 }), 5.85);
});

Deno.test("preço informado MANDA sobre a conta — o dono pode ter negociado", () => {
  assertEquals(precoDeVenda({ sale_price: 42, cost_price: 28, profit_margin: 30 }), 42);
});

Deno.test("sem custo ou sem margem não inventa preço", () => {
  assertEquals(precoDeVenda({ cost_price: 28 }), null);
  assertEquals(precoDeVenda({ profit_margin: 30 }), null);
  assertEquals(precoDeVenda({}), null);
});

Deno.test("zero e negativo não são preço — entram como 'não sei'", () => {
  assertEquals(precoDeVenda({ sale_price: 0, cost_price: 28, profit_margin: 30 }), 36.4);
  assertEquals(precoDeVenda({ cost_price: 0, profit_margin: 30 }), null);
  assertEquals(precoDeVenda({ cost_price: -5, profit_margin: 30 }), null);
  assertEquals(precoDeVenda({ cost_price: 28, profit_margin: 0 }), null);
});

Deno.test("texto no lugar de número não vira NaN gravado no banco", () => {
  assertEquals(precoDeVenda({ cost_price: "muito", profit_margin: 30 }), null);
  assertEquals(precoDeVenda({ sale_price: "R$ 42" }), null);
});

Deno.test("arredonda a centavo — preço com dízima não vai para o orçamento", () => {
  assertEquals(precoDeVenda({ cost_price: 10, profit_margin: 33.333 }), 13.33);
});

Deno.test("allowlist deixa passar só coluna que existe na tabela", () => {
  const { linha, ignorados } = camposDeProduto({
    name: "Cabo 25mm²", cost_price: 28, profit_margin: 30,
    inventado_pelo_modelo: "x", corrente_maxima: ["a", "b"],
  });
  assertEquals(Object.keys(linha).sort(), ["cost_price", "name", "profit_margin"]);
  assertEquals(ignorados.sort(), ["corrente_maxima", "inventado_pelo_modelo"]);
});

Deno.test("undefined não vira coluna nula no insert", () => {
  const { linha } = camposDeProduto({ name: "X", sku: undefined });
  assertEquals(Object.keys(linha), ["name"]);
});

Deno.test("as 16 colunas do input_schema estão na allowlist", () => {
  // Se alguém acrescentar campo ao schema e esquecer daqui, o campo some em silêncio.
  for (const c of ["name", "sku", "brand", "category", "unit", "sale_price", "cost_price",
                   "minimum_stock", "barcode", "notes", "ncm", "cfop", "csosn",
                   "fiscal_origin", "profit_margin", "supplier_id"]) {
    assertEquals(COLUNAS_DE_PRODUTO.includes(c as never), true, `faltou ${c}`);
  }
});

Deno.test("REGRESSÃO: os 11 produtos de 31/08 agora nasceriam com preço", () => {
  // Argumentos reais da sessão 3ac5b84a, que geraram sale_price = 0.
  const reais = [
    { name: "Cabo de bateria flexível 50mm²", cost_price: 28, profit_margin: 30, esperado: 36.4 },
    { name: "Cabo de bateria flexível 70mm²", cost_price: 42, profit_margin: 30, esperado: 54.6 },
    { name: "Terminal a compressão (olhal)",  cost_price: 6,  profit_margin: 30, esperado: 7.8 },
    { name: "Fusível Classe T 300A",          cost_price: 180, profit_margin: 30, esperado: 234 },
    { name: "Quadro de distribuição 220V",    cost_price: 280, profit_margin: 30, esperado: 364 },
  ];
  for (const p of reais) assertEquals(precoDeVenda(p), p.esperado, p.name);
});

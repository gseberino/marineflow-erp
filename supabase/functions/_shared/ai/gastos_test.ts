// "Quanto gastei com X?" (02/10/2026) — o pedido vira categoria do plano, e a linha do banco ainda
// sem lançamento conta pela sugestão do Extrato, pelo ramo do cartão ou pelo texto.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  categoriaDaLinha, doMesmoRamoEmOutraCategoria, intervaloDoMes, linhaCasa, resolverCategorias, somar,
  type LinhaSemLancamento,
} from "./gastos.ts";

const PLANO = [
  "Combustível e deslocamento", "Veículo e Combustível", "Pedágio e estacionamento", "Alimentação de campo",
  "Impostos e taxas", "Peças e materiais", "Compras de mercadorias", "Pagamento de fatura de cartão",
];

Deno.test("combustível acha as duas categorias com a palavra", () => {
  const r = resolverCategorias("combustível", PLANO);
  assert("categorias" in r);
  assertEquals(r.categorias, ["Combustível e deslocamento", "Veículo e Combustível"]);
});

Deno.test("gasolina e posto, que não estão no nome, vão para Combustível e deslocamento", () => {
  for (const pedido of ["gasolina", "posto", "abastecimento", "diesel"]) {
    const r = resolverCategorias(pedido, PLANO);
    assert("categorias" in r, pedido);
    assertEquals(r.categorias, ["Combustível e deslocamento"], pedido);
  }
});

Deno.test("posto não acha Impostos e taxas (pedaço de palavra)", () => {
  const r = resolverCategorias("posto", PLANO);
  assert("categorias" in r && !r.categorias.includes("Impostos e taxas"));
});

Deno.test("frase com palavras vazias: 'gasto com peças' acha Peças e materiais", () => {
  const r = resolverCategorias("gasto com peças", PLANO);
  assert("categorias" in r);
  assertEquals(r.categorias, ["Peças e materiais"]);
});

Deno.test("almoço vai para Alimentação de campo", () => {
  const r = resolverCategorias("almoço", PLANO);
  assert("categorias" in r);
  assertEquals(r.categorias, ["Alimentação de campo"]);
});

Deno.test("nada casa: devolve nenhuma (o assistente pergunta), não uma categoria qualquer", () => {
  const r = resolverCategorias("viagem internacional", PLANO);
  assert("nenhuma" in r);
});

const linha = (p: Partial<LinhaSemLancamento>): LinhaSemLancamento => ({
  id: "x", data: "2026-09-22", valor: 70.98, quem: "POSTO PAULINHO", mcc: "5541", pendente: true, categoriaSugerida: null, ...p,
});

Deno.test("compra pendente no posto conta para combustível pelo ramo do cartão", () => {
  assertEquals(categoriaDaLinha(linha({}))?.categoria, "Combustível e deslocamento");
  assert(linhaCasa(linha({}), ["Combustível e deslocamento", "Veículo e Combustível"], null));
  assert(!linhaCasa(linha({}), ["Alimentação de campo"], null));
});

Deno.test("sem ramo do cartão, o nome do estabelecimento decide ('Posto Paulinho' → combustível)", () => {
  assertEquals(categoriaDaLinha(linha({ mcc: null, quem: "Posto Paulinho" }))?.categoria, "Combustível e deslocamento");
});

Deno.test("a sugestão do Extrato vale mais que o ramo", () => {
  assertEquals(categoriaDaLinha(linha({ categoriaSugerida: "Alimentação de campo" }))?.categoria, "Alimentação de campo");
});

Deno.test("busca pelo nome filtra as linhas", () => {
  assert(linhaCasa(linha({}), null, "paulinho"));
  assert(!linhaCasa(linha({}), null, "shell"));
});

Deno.test("compra no posto lançada como alimentação aparece à parte, sem entrar no total", () => {
  const l = { data: "2026-09-07", valor: 31.99, categoria: "Alimentação de campo", descricao: "POSTO PAULINHO", quem: "POSTO PAULINHO", mcc: "5541" };
  assert(doMesmoRamoEmOutraCategoria(l, ["Combustível e deslocamento"]));
  assert(!doMesmoRamoEmOutraCategoria({ ...l, categoria: "Combustível e deslocamento" }, ["Combustível e deslocamento"]));
  assert(!doMesmoRamoEmOutraCategoria({ ...l, mcc: null }, ["Combustível e deslocamento"]));
});

Deno.test("soma sem erro de centavo e intervalo do mês", () => {
  assertEquals(somar([3.5, 27.98, 70.98, 46.57, 19.99, 17.22, 23, 47.96, 17, 41.97, 40.34], (v) => v), 356.51);
  assertEquals(intervaloDoMes(2026, 9), ["2026-09-01", "2026-09-30"]);
  assertEquals(intervaloDoMes(2028, 2), ["2028-02-01", "2028-02-29"]);
});

Deno.test("Uber pendente no cartão ('DL*UBERRIDES') conta como deslocamento", () => {
  assertEquals(categoriaDaLinha({ categoriaSugerida: null, mcc: null, quem: "DL*UBERRIDES" })?.categoria, "Combustível e deslocamento");
  // Nome comum não vira categoria por acaso.
  assertEquals(categoriaDaLinha({ categoriaSugerida: null, mcc: null, quem: "KOCH HIPERMERCADO SA" }), null);
});

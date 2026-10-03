// Run: deno test supabase/functions/_shared/banking/parece-pagar_test.ts
//
// O que se protege: a sugestão só junta contas e pagamentos do cliente identificado cuja soma bate
// com o Pix (com a tolerância de R$ 10 do dono numa conta); uma conta só fica com a sugestão de
// vínculo da linha; pagamento à mão longe da data do Pix não entra; ambiguidade é dita.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type CandidatoDaEntrada, fraseDoParecePagar, parecePagar } from "./parece-pagar.ts";

const conta = (id: string, valor: number, data: string, rotulo = id): CandidatoDaEntrada => ({ tipo: "conta", id, valor, data, rotulo });
const pagamento = (id: string, valor: number, data: string, rotulo = id): CandidatoDaEntrada => ({ tipo: "pagamento", id, valor, data, rotulo });
const brl = (v: number) => `R$ ${v.toFixed(2).replace(".", ",")}`;

Deno.test("duas OS em aberto que somam o Pix (MP Motor Homes: OS-00045 + OS-00046)", () => {
  const r = parecePagar({ valor: 1670, data: "2026-10-10" }, [
    conta("os45", 1650, "2026-07-22", "OS-00045"),
    conta("os46", 20, "2026-07-22", "OS-00046"),
  ])!;
  assertEquals(r.itens.map((i) => [i.id, i.valor, i.quitar]), [["os45", 1650, false], ["os46", 20, false]]);
  assertEquals([r.diferenca, r.outraCombinacao, r.parcial], [0, false, false]);
  assertEquals(fraseDoParecePagar(r, brl), "Parece pagar OS-00045 (R$ 1650,00) + OS-00046 (R$ 20,00).");
});

Deno.test("Lenine: os dois sinais lançados à mão no dia são este Pix", () => {
  const r = parecePagar({ valor: 4800, data: "2026-08-11" }, [
    pagamento("p74", 2280, "2026-08-11", "Sinal — ORÇ-00074"),
    pagamento("p77", 2520, "2026-08-11", "Sinal — ORÇ-00077"),
  ])!;
  assertEquals(r.itens.map((i) => [i.tipo, i.id]).sort(), [["pagamento", "p74"], ["pagamento", "p77"]]);
  assertEquals(r.diferenca, 0);
});

Deno.test("pagamento à mão sem conta: só soma exata (a diferença não tem onde ir)", () => {
  assertEquals(parecePagar({ valor: 4805, data: "2026-08-11" }, [
    pagamento("p74", 2280, "2026-08-11"), pagamento("p77", 2520, "2026-08-11"),
  ]), null);
});

Deno.test("pagamento à mão longe da data do Pix não entra", () => {
  assertEquals(parecePagar({ valor: 4800, data: "2026-09-30" }, [
    pagamento("p74", 2280, "2026-08-11"), pagamento("p77", 2520, "2026-08-11"),
  ]), null);
});

Deno.test("até R$ 10 a mais vira receita da última conta; até R$ 10 a menos quita com desconto", () => {
  const mais = parecePagar({ valor: 1675, data: "2026-10-10" }, [
    conta("a", 1650, "2026-07-01"), conta("b", 20, "2026-07-22"),
  ])!;
  assertEquals(mais.itens.map((i) => [i.id, i.valor, i.quitar]), [["a", 1650, false], ["b", 25, false]]);
  assertEquals(mais.diferenca, 5);

  const menos = parecePagar({ valor: 1662, data: "2026-10-10" }, [
    conta("a", 1650, "2026-07-01"), conta("b", 20, "2026-07-22"),
  ])!;
  assertEquals(menos.itens.map((i) => [i.id, i.valor, i.quitar]), [["a", 1650, false], ["b", 12, true]]);
  assertEquals(menos.diferenca, -8);

  // Acima de R$ 10, nenhuma sugestão.
  assertEquals(parecePagar({ valor: 1700, data: "2026-10-10" }, [conta("a", 1650, "2026-07-01"), conta("b", 20, "2026-07-22")]), null);
});

Deno.test("uma conta só que bate é a sugestão de vínculo da linha, não esta", () => {
  assertEquals(parecePagar({ valor: 5237.99, data: "2026-10-16" }, [
    conta("p2", 5237.99, "2026-10-16", "NF-e 2/25 (parcela 2/3)"),
    conta("p3", 5238.02, "2026-11-13", "NF-e 2/25 (parcela 3/3)"),
  ]), null);
});

Deno.test("OS paga em mais de um Pix: a única conta em aberto recebe a parte", () => {
  const r = parecePagar({ valor: 1000, data: "2026-10-10" }, [conta("os51", 1710, "2026-07-27", "OS-00051")])!;
  assertEquals(r.parcial, true);
  assertEquals(r.itens.map((i) => [i.id, i.valor, i.saldo]), [["os51", 1000, 1710]]);
  assertEquals(fraseDoParecePagar(r, brl), "Parece ser parte de OS-00051 (R$ 1000,00): faltavam R$ 1710,00.");
  // Com duas contas que comportam o valor, não adivinha qual recebeu a parte.
  assertEquals(parecePagar({ valor: 1000, data: "2026-10-10" }, [conta("a", 1710, "2026-07-27"), conta("b", 3000, "2026-08-01")]), null);
});

Deno.test("parte de uma OS quando só ela comporta o Pix (MP Motor Homes, 11/08)", () => {
  const r = parecePagar({ valor: 1250, data: "2026-08-11" }, [
    conta("os45", 1650, "2026-07-22", "OS-00045"), conta("os46", 20, "2026-07-22", "OS-00046"),
  ])!;
  assertEquals([r.parcial, r.itens.map((i) => [i.id, i.valor])], [true, [["os45", 1250]]]);
});

Deno.test("ambígua: duas combinações dão o mesmo valor — sugere a mais antiga e avisa", () => {
  const r = parecePagar({ valor: 1000, data: "2026-10-10" }, [
    conta("a", 600, "2026-06-01"), conta("b", 400, "2026-06-15"),
    conta("c", 700, "2026-07-01"), conta("d", 300, "2026-07-15"),
  ])!;
  assertEquals(r.itens.map((i) => i.id), ["a", "b"]);
  assertEquals(r.outraCombinacao, true);
});

Deno.test("sem candidatos, ou entrada zero: nada", () => {
  assertEquals(parecePagar({ valor: 100, data: "2026-10-10" }, []), null);
  assertEquals(parecePagar({ valor: 0, data: "2026-10-10" }, [conta("a", 50, "2026-07-01"), conta("b", 50, "2026-07-01")]), null);
});

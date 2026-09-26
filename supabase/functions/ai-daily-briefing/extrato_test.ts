import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { linhasDoExtratoNoResumo } from "./extrato.ts";

const moeda = (v: number) => `R$ ${v.toFixed(2).replace(".", ",")}`;

Deno.test("nada a dizer: nenhuma linha, nenhuma ação", () => {
  const r = linhasDoExtratoNoResumo([], [], moeda);
  assertEquals(r.linhas, []);
  assertEquals(r.acoes, []);
});

Deno.test("lançados sozinhos: total, os 3 primeiros, o resto e como desfazer", () => {
  const l = (n: number, automatica = "confianca") => ({
    title: `Despesa: LOJA ${n}`, suggested_amount: 10 * n, suggested_category: "Combustível e deslocamento", automatica,
  });
  const r = linhasDoExtratoNoResumo([l(1, "regra"), l(2), l(3), l(4)], [], moeda);
  assertStringIncludes(r.linhas[0], "*4*");
  assertStringIncludes(r.linhas[0], "R$ 100,00");
  assertStringIncludes(r.linhas[1], "LOJA 1");
  assertStringIncludes(r.linhas[1], "sua regra");
  assert(!r.linhas.some((x) => x.includes("LOJA 4")), "só os 3 primeiros");
  assert(r.linhas.some((x) => x.includes("e mais 1")));
  assert(r.linhas.some((x) => x.includes("*desfazer*")));
  assertEquals(r.acoes.length, 1);
});

Deno.test("débito sem loja: pergunta com data e valor, o mais recente de exemplo", () => {
  const r = linhasDoExtratoNoResumo([], [
    { suggested_amount: 45, suggested_date: "2026-09-20" },
    { suggested_amount: 8.9, suggested_date: "2026-09-24" },
  ], moeda, { anoAtual: 2026 });
  assertStringIncludes(r.linhas[0], "*2*");
  assertStringIncludes(r.linhas[1], "24/09");
  assertStringIncludes(r.linhas[1], "R$ 8,90");
  assertStringIncludes(r.linhas[2], "20/09");
  // Valor com centavos e data inteira: é o que a anotação precisa para casar.
  assertStringIncludes(r.linhas[3], "o débito de R$ 8,90 de 24/09");
});

Deno.test("débito de outro ano leva o ano; os já respondidos são contados à parte", () => {
  const r = linhasDoExtratoNoResumo([], [{ suggested_amount: 49.95, suggested_date: "2025-08-30" }], moeda,
    { anoAtual: 2026, anotadosEsperando: 2 });
  assertStringIncludes(r.linhas[1], "30/08/2025");
  assertStringIncludes(r.linhas[2], "o débito de R$ 49,95 de 30/08/2025");
  assertStringIncludes(r.linhas[3], "2 que você já respondeu");
});

Deno.test("anotação que a varredura cancelou aparece com o motivo", () => {
  const r = linhasDoExtratoNoResumo([], [], moeda, { naoAplicadas: [
    { valor: 700, quem: "TSD", motivo: "chegaram 2 transações do mesmo valor; diga qual pela tela" },
  ] });
  assertStringIncludes(r.linhas[0], "não pude aplicar: *1*");
  assertStringIncludes(r.linhas[1], "R$ 700,00 · TSD — chegaram 2 transações");
});

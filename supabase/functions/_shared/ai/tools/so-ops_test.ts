import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseMinutes } from "./so-ops.ts";

/* Duração chega como o técnico fala, não como formulário aceita. Errar aqui grava
   hora errada na OS e o erro vira dinheiro: hora cobrável entra no total. */
Deno.test("parseMinutes: entende como se fala hora no campo", () => {
  // horas cheias
  assertEquals(parseMinutes("2h"), 120);
  assertEquals(parseMinutes("2hs"), 120);
  assertEquals(parseMinutes("2horas"), 120);
  // hora com minuto — as duas grafias que aparecem
  assertEquals(parseMinutes("1h30"), 90);
  assertEquals(parseMinutes("1h30min"), 90);
  assertEquals(parseMinutes("1:30"), 90);
  // meia hora escrita como fração
  assertEquals(parseMinutes("1,5h"), 90);
  assertEquals(parseMinutes("1.5h"), 90);
  // minutos
  assertEquals(parseMinutes("45min"), 45);
  assertEquals(parseMinutes("45m"), 45);
  assertEquals(parseMinutes("90"), 90);
  // com espaços e maiúscula
  assertEquals(parseMinutes(" 2 H "), 120);
  // número direto
  assertEquals(parseMinutes(30), 30);
});

Deno.test("parseMinutes: recusa o que não dá para afirmar", () => {
  // Devolver null faz a tool PERGUNTAR em vez de gravar um chute — hora inventada
  // vira cobrança indevida.
  assertEquals(parseMinutes("um pouco"), null);
  assertEquals(parseMinutes(""), null);
  assertEquals(parseMinutes(null), null);
  assertEquals(parseMinutes(undefined), null);
  assertEquals(parseMinutes(0), null);
  assertEquals(parseMinutes(-5), null);
  assertEquals(parseMinutes("a tarde toda"), null);
});

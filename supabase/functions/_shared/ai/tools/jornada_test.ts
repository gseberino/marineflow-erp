import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { minutosDeTexto, jornadaTools } from "./jornada.ts";

Deno.test("entende a duração do jeito que a pessoa fala no WhatsApp", () => {
  assertEquals(minutosDeTexto("8h"), 480);
  assertEquals(minutosDeTexto("1h30"), 90);
  assertEquals(minutosDeTexto("90min"), 90);
  assertEquals(minutosDeTexto("45 minutos"), 45);
  assertEquals(minutosDeTexto("2,5h"), 150);
  assertEquals(minutosDeTexto("8"), 480);       // número solto = horas
  assertEquals(minutosDeTexto("1 h 30"), 90);
});

Deno.test("recusa o que não dá para afirmar, em vez de chutar", () => {
  assertEquals(minutosDeTexto("um pouco"), null);
  assertEquals(minutosDeTexto("manhã toda"), null);
  assertEquals(minutosDeTexto(""), null);
});

Deno.test("registrar por outra pessoa sobe o risco — mexe no que ELA recebe", () => {
  const t = jornadaTools.find((x) => x.name === "registrar_jornada")!;
  assertEquals(t.computeRisk!({}), "low");
  assertEquals(t.computeRisk!({ pessoa: "Felipe" }), "medium");
});

Deno.test("as quatro ferramentas estão registradas e nomeadas em português", () => {
  const nomes = jornadaTools.map((t) => t.name).sort();
  assertEquals(nomes, ["apurar_pagamento", "fechar_jornada", "minhas_horas", "registrar_jornada"]);
});

Deno.test("apurar_pagamento é leitura: não pode ter risco alto nem gravar", () => {
  const t = jornadaTools.find((x) => x.name === "apurar_pagamento")!;
  assertEquals(t.risk, "low");
  // A descrição precisa deixar claro que é prévia — senão o dono acha que já pagou.
  assertEquals(t.description.includes("NÃO grava"), true);
});

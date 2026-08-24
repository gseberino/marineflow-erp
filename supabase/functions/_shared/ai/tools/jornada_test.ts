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

Deno.test("as cinco ferramentas estão registradas e nomeadas em português", () => {
  const nomes = jornadaTools.map((t) => t.name).sort();
  assertEquals(nomes, ["apurar_pagamento", "fechar_folha", "fechar_jornada", "minhas_horas", "registrar_jornada"]);
});

Deno.test("apurar_pagamento é leitura: não pode ter risco alto nem gravar", () => {
  const t = jornadaTools.find((x) => x.name === "apurar_pagamento")!;
  assertEquals(t.risk, "low");
  // A descrição precisa deixar claro que é prévia — senão o dono acha que já pagou.
  assertEquals(t.description.includes("NÃO grava"), true);
});

// ── fechar_folha: a única que gera dinheiro ────────────────────────────────────────────────────
// O que se protege aqui não é o cálculo (isso é calculo_test.ts) — é o contrato: quem pode chamar,
// se pede confirmação, e se a descrição avisa que o período fecha uma vez só. Um deslize em
// qualquer um dos três gera pagamento em duplicidade ou pagamento por quem não podia autorizar.

Deno.test("fechar_folha é ação de dinheiro: risco alto e confirmação obrigatória", () => {
  const t = jornadaTools.find((x) => x.name === "fechar_folha")!;
  assertEquals(t.risk, "high");
  // Sem computeRisk: NENHUM argumento pode rebaixar o risco desta ferramenta.
  assertEquals(t.computeRisk, undefined);
});

Deno.test("fechar_folha é só de gestor — técnico e vendedor nem veem a ferramenta", () => {
  const t = jornadaTools.find((x) => x.name === "fechar_folha")!;
  assertEquals(t.roles, ["admin", "financial"]);
  assertEquals(t.roles!.includes("technician" as never), false);
  assertEquals(t.roles!.includes("seller" as never), false);
});

Deno.test("fechar_folha avisa que gera conta a pagar e que fecha uma vez só", () => {
  const t = jornadaTools.find((x) => x.name === "fechar_folha")!;
  // Sem isto o modelo trata como mais uma prévia e o dono manda fechar duas vezes.
  assertEquals(/CONTA A PAGAR/i.test(t.description), true);
  assertEquals(/uma vez/i.test(t.description), true);
  assertEquals(/APROVADA/i.test(t.description), true);
});

Deno.test("fechar_folha não exige argumento: 'fecha a folha' basta", () => {
  const t = jornadaTools.find((x) => x.name === "fechar_folha")!;
  assertEquals((t.input_schema as any).required, []);
});

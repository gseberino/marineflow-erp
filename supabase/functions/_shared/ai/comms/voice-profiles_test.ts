import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { perfilDeVoz, perfilParaPrompt } from "./voice-profiles.ts";

Deno.test("fornecedor: enxuto, saudação neutra, proíbe razão social/aplicação/prazo/tutorial", () => {
  const p = perfilDeVoz("fornecedor", "whatsapp");
  assertEquals(p.saudacao, "neutra");
  assertEquals(p.proibicoes.includes("razao_social"), true);
  assertEquals(p.proibicoes.includes("prazo_estipulado"), true);
  assertEquals(p.proibicoes.includes("tutorial_resposta"), true);
});

Deno.test("cliente: saúda pelo nome, proíbe jargão e ameaça", () => {
  const p = perfilDeVoz("cliente", "whatsapp");
  assertEquals(p.saudacao, "nome");
  assertEquals(p.proibicoes.includes("jargao_tecnico"), true);
  assertEquals(p.proibicoes.includes("ameaca"), true);
});

Deno.test("tecnico: curto (3 linhas) e proíbe preço", () => {
  const p = perfilDeVoz("tecnico", "whatsapp");
  assertEquals(p.tetoLinhas, 3);
  assertEquals(p.proibicoes.includes("preco"), true);
});

Deno.test("painel não tem teto rígido de linhas", () => {
  assertEquals(perfilDeVoz("cliente", "panel").tetoLinhas, 0);
  assertEquals(perfilDeVoz("dono", "panel").tetoLinhas, 0);
});

Deno.test("perfilParaPrompt é compacto e cita as proibições", () => {
  const txt = perfilParaPrompt(perfilDeVoz("fornecedor", "whatsapp"));
  assertEquals(txt.includes("razao_social"), true);
  assertEquals(txt.length < 400, true);
});

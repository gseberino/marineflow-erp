import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  brl,
  ddmm,
  diaDaSemana,
  diasEntre,
  LETRAS,
  letraDoIndice,
  letraValida,
  nomeDoDia,
  paraBusca,
  proximaSegunda,
  quandoEmPalavras,
  somarDias,
  umaLinha,
} from "./base.ts";

Deno.test("letras: 21, sem N e S (não/sim), sem E (o 'É' sozinho), sem I e O (1 e 0)", () => {
  assertEquals(LETRAS.length, 21);
  for (const fora of ["E", "I", "N", "O", "S"]) assertEquals(LETRAS.includes(fora), false, fora);
  assertEquals(LETRAS.slice(0, 5), ["A", "B", "C", "D", "F"]);
  assertEquals(letraDoIndice(0), "A");
  assertEquals(letraDoIndice(3), "D");
  assertEquals(letraDoIndice(4), "F");
  assertEquals(letraDoIndice(20), "Z");
  assertEquals(letraDoIndice(21), null);
  assertEquals(letraDoIndice(-1), null);
});

Deno.test("letraValida: minúscula vira maiúscula; N, S, E, I, O e duas letras não são letra", () => {
  assertEquals(letraValida("a"), "A");
  assertEquals(letraValida(" b "), "B");
  for (const x of ["n", "s", "e", "i", "o", "ab", "", "1"]) assertEquals(letraValida(x), null, x);
});

Deno.test("paraBusca: sem acento, minúsculo, só letras e números (o nome_busca do banco)", () => {
  assertEquals(paraBusca("Flávio da Igreja"), "flavio da igreja");
  assertEquals(paraBusca("  João   Luiz\nHang! "), "joao luiz hang");
  assertEquals(paraBusca("ORÇ-00117"), "orc 00117");
  assertEquals(/^[a-z0-9 ]*$/.test(paraBusca("Eng.⁰ Rafael 🙏 Borges")), true);
});

Deno.test("umaLinha: quebra de linha vira espaço e corta com reticências", () => {
  assertEquals(umaLinha("Climatec Refrigeração — seu conforto\n\nClimatec", 20), "Climatec Refrigeraç…");
  assertEquals(umaLinha("Nelson"), "Nelson");
});

Deno.test("brl: R$ com espaço comum e centavos", () => {
  assertEquals(brl(16890), "R$ 16.890,00");
  assertEquals(brl("5237.99"), "R$ 5.237,99");
  assertEquals(brl(null), "R$ 0,00");
});

Deno.test("dias de calendário: dia da semana, soma, diferença e próxima segunda", () => {
  assertEquals(ddmm("2026-10-13"), "13/10");
  assertEquals(diaDaSemana("2026-10-15"), 4); // quinta
  assertEquals(nomeDoDia("2026-10-18"), "Domingo");
  assertEquals(somarDias("2026-10-31", 1), "2026-11-01");
  assertEquals(diasEntre("2026-07-22", "2026-10-15"), 85);
  assertEquals(proximaSegunda("2026-10-15"), "2026-10-19"); // quinta → segunda
  assertEquals(proximaSegunda("2026-10-19"), "2026-10-26"); // numa segunda, a da semana que vem
  assertEquals(proximaSegunda("2026-10-18"), "2026-10-19"); // domingo → amanhã
});

Deno.test("quandoEmPalavras: hoje, amanhã, dia da semana e data", () => {
  assertEquals(quandoEmPalavras("2026-10-15", "2026-10-15"), "hoje");
  assertEquals(quandoEmPalavras("2026-10-16", "2026-10-15"), "amanhã");
  assertEquals(quandoEmPalavras("2026-10-19", "2026-10-15"), "segunda (19/10)");
  assertEquals(quandoEmPalavras("2026-11-20", "2026-10-15"), "20/11");
});

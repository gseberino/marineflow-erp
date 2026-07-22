import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizarTermo, pontuaCandidato, tokenizar } from "./keyword-resolver.ts";

// Funções PURAS do resolvedor — a lógica de escolha que precisa ser estável.
// (A busca em si é testada por SQL contra o banco; aqui garantimos o normalizador e a
//  pontuação, que decidem qual candidato vence.)

Deno.test("normalizarTermo: minúsculo, sem acento, espaços colapsados", () => {
  assertEquals(normalizarTermo("  MultiPlus-II  Áçção "), "multiplus-ii accao");
  assertEquals(normalizarTermo("INVERSOR   Sen0idal"), "inversor sen0idal");
  assertEquals(normalizarTermo(""), "");
});

Deno.test("tokenizar: quebra em alfanuméricos, ignora hífen/barra e tokens de 1 char", () => {
  assertEquals(tokenizar("MultiPlus-II 12/3000"), ["multiplus", "ii", "12", "3000"]);
  assertEquals(tokenizar("MPPT 100/50"), ["mppt", "100", "50"]);
});

Deno.test("pontuaCandidato: mais tokens casados ganha", () => {
  const termo = "MultiPlus 12 3000";
  const certo = pontuaCandidato(termo, "MultiPlus 12/3000/120 - 50 220V", null);
  const errado = pontuaCandidato(termo, "MultiPlus 24/3000/70", null); // casa multiplus+3000, não 12
  assertEquals(certo > errado, true);
});

Deno.test("pontuaCandidato: com empate de tokens, nome mais curto vence (produto principal vs acessório)", () => {
  const termo = "Cerbo GX";
  const principal = pontuaCandidato(termo, "Central Cerbo GX", null);
  const acessorio = pontuaCandidato(termo, "Sensor de Temperatura para Cerbo GX Victron", null);
  assertEquals(principal > acessorio, true);
});

Deno.test("tokenizar não gera token vazio a partir de só pontuação", () => {
  assertEquals(tokenizar("--- / //"), []);
});

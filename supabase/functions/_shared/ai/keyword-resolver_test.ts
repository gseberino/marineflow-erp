import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { matchFraco, normalizarTermo, pontuaCandidato, tokenizar, tokensNumericos } from "./keyword-resolver.ts";

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

Deno.test("tokensNumericos extrai só os números do modelo", () => {
  assertEquals(tokensNumericos("MPPT 100/50"), ["100", "50"]);
  assertEquals(tokensNumericos("SmartShunt"), []);
});

Deno.test("matchFraco: modelo diferente (100/50 pedido, 250/100 achado) é fraco", () => {
  // Caso REAL do orçamento: pediu MPPT 100/50, catálogo só tinha 250/100.
  assertEquals(matchFraco("MPPT 100/50", "MPPT SmartSolar 250/100-Tr", null).fraco, true);
  // O modelo exato NÃO é fraco.
  assertEquals(matchFraco("MPPT 100/50", "MPPT SmartSolar 100/50", null).fraco, false);
});

Deno.test("matchFraco: acessório no lugar do equipamento é fraco", () => {
  // Caso REAL: pediu o carregador Orion, casou com o CABO remoto do Orion.
  assertEquals(matchFraco("carregador DC/DC Orion", "Cabo remoto Orion-Tr DC/DC", null).fraco, true);
  // Se o termo PEDE o acessório, não é fraco.
  assertEquals(matchFraco("cabo remoto orion", "Cabo remoto Orion-Tr DC/DC", null).fraco, false);
});

Deno.test("pontuaCandidato: modelo certo vence o modelo errado com número parecido", () => {
  const certo = pontuaCandidato("MPPT 100/50", "MPPT SmartSolar 100/50", null);
  const errado = pontuaCandidato("MPPT 100/50", "MPPT SmartSolar 250/100-Tr", null); // "100" casa, "50" não
  assertEquals(certo > errado, true);
});

Deno.test("pontuaCandidato: equipamento principal vence o acessório de mesmo nome", () => {
  const principal = pontuaCandidato("carregador Orion", "Carregador Orion-Tr Smart", null);
  const acessorio = pontuaCandidato("carregador Orion", "Cabo remoto Orion-Tr", null);
  assertEquals(principal > acessorio, true);
});

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  fracaoCasada, matchFraco, normalizarTermo, nucleoDoTermo, PISO_DE_CONFIANCA,
  pontuaCandidato, siglasFaltando, tokenizar, tokensNumericos,
} from "./keyword-resolver.ts";

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

// ── Piso de confiança (NOVO-agente-07) ───────────────────────────────────────────────────────
// Os casos abaixo são LINHAS REAIS de orçamentos de 31/08/2026. Cada um custou uma correção
// manual do dono, e dois deles entraram no total com o preço de outro produto.

Deno.test("nucleoDoTermo: o substantivo pedido, ignorando preposição e medida", () => {
  assertEquals(nucleoDoTermo("Terminal de olhal para cabo 25mm²"), "terminal");
  assertEquals(nucleoDoTermo("Fusível ANL 250A com porta-fusível"), "fusivel");
  // Sem substantivo próprio, o núcleo é o primeiro token sem dígito: "25mm" é medida, "preto" não.
  assertEquals(nucleoDoTermo("25mm² preto"), "preto");
  // Só números: não há núcleo, e a regra do núcleo não se aplica (as outras ainda valem).
  assertEquals(nucleoDoTermo("100/50"), null);
});

Deno.test("REGRESSÃO: terminal não casa com suporte, mesmo compartilhando '25mm'", () => {
  // ORÇ-00090: "Terminal de olhal 25mm²" virou "SUPORTE PARA FACHO HOLMES ... 40X22-25MM".
  // O 25mm do candidato era a medida de um suporte. Ambos contêm palavra de acessório, então
  // nenhum filtro antigo disparava.
  const r = matchFraco("Terminal de olhal para cabo 25mm²", "SUPORTE PARA FACHO HOLMES EM ACO INOX. - 40X22-25MM.", null);
  assertEquals(r.fraco, true);
  assertEquals(r.motivo.includes("terminal"), true);
});

Deno.test("REGRESSÃO: fusível ANL não casa com fusível Mega — a sigla é o tipo da peça", () => {
  // ORÇ-00086: "Fusível ANL 250A" virou "Fusível Mega 250A/32V Victron". Mesma palavra, mesmo
  // número; só a sigla separava — e ela não era comparada.
  const r = matchFraco("Fusível ANL 250A com porta-fusível", "Fusível Mega 250A/32V - 5 unidades - Victron Energy", null);
  assertEquals(r.fraco, true);
  assertEquals(r.motivo.includes("ANL"), true);
});

Deno.test("REGRESSÃO: cabo não casa com suporte", () => {
  assertEquals(matchFraco("Cabo 25mm² preto", "SUPORTE PARA FACHO HOLMES EM ACO INOX. - 40X22-25MM.", null).fraco, true);
});

Deno.test("siglasFaltando enxerga a sigla técnica ausente e ignora palavra comum", () => {
  assertEquals(siglasFaltando("Fusível ANL 250A", "Fusível Mega 250A", null), ["anl"]);
  assertEquals(siglasFaltando("Fusível ANL 250A", "Fusível ANL 250A com base", null), []);
  // "Fusível" começa com maiúscula mas não é sigla (tem minúsculas) — não conta.
  assertEquals(siglasFaltando("Fusível de vidro", "Base de vidro", null), []);
});

Deno.test("o piso barra o casamento por um token só", () => {
  // "shunt / busbar negativo" contra um produto que só compartilha "negativo".
  const r = matchFraco("shunt busbar negativo", "Cabo negativo 10mm", null);
  assertEquals(r.fraco, true);
  assertEquals(PISO_DE_CONFIANCA, 0.5);
});

Deno.test("fracaoCasada ignora preposição — 'de'/'para' não inflam o placar", () => {
  // Sem descartar as vazias, "terminal de olhal para cabo" teria 2 de 5 só pelas preposições.
  assertEquals(fracaoCasada("terminal de olhal para cabo", "Terminal de olhal para cabo 25mm", null), 1);
  assertEquals(fracaoCasada("terminal de olhal", "Suporte de facho", null) < 0.5, true);
});

Deno.test("PEDIDO EM CAIXA ALTA não vira uma lista de siglas — o dono escreve assim", () => {
  // Sem esta guarda, "PARA" e "DE" viravam "sigla técnica ausente" e o piso rejeitava o produto
  // CERTO. Rejeitar demais é tão ruim quanto casar errado: o catálogo deixa de ser usado e cada
  // orçamento cria produto novo.
  assertEquals(matchFraco("CABO PARA BATERIA 25MM", "Cabo de bateria 25mm vermelho", null).fraco, false);
  assertEquals(matchFraco("CABO DE BATERIA 25MM", "Cabo de bateria 25mm vermelho", null).fraco, false);
  assertEquals(matchFraco("TOMADA 220V 10A EMBUTIR", "Tomada 220V 10A de embutir branca", null).fraco, false);
  assertEquals(matchFraco("DISJUNTOR CC 200A", "Disjuntor CC 200A para banco de baterias 12V", null).fraco, false);
  // Num texto TODO em maiúsculas não há contraste, então nada ali é lido como sigla.
  assertEquals(siglasFaltando("FUSIVEL ANL 250A", "Fusível Mega 250A", null), []);
  // Com minúsculas ao redor, a sigla volta a ser sinal — que é o caso do bug real.
  assertEquals(siglasFaltando("Fusível ANL 250A", "Fusível Mega 250A", null), ["anl"]);
});

Deno.test("preposição em caixa alta nunca conta como sigla", () => {
  assertEquals(siglasFaltando("Cabo PARA bateria", "Cabo de bateria", null), []);
  assertEquals(siglasFaltando("Terminal DE olhal", "Terminal para olhal", null), []);
});

Deno.test("o piso NÃO estraga os casamentos legítimos que já funcionavam", () => {
  // Estes precisam continuar entrando como peça — senão o orçamento vira uma lista de provisórios.
  assertEquals(matchFraco("MPPT 100/50", "MPPT SmartSolar 100/50", null).fraco, false);
  assertEquals(matchFraco("cabo remoto orion", "Cabo remoto Orion-Tr DC/DC", null).fraco, false);
  assertEquals(matchFraco("Fusível Mega 250A", "Fusível Mega 250A/32V - 5 unidades - Victron Energy", null).fraco, false);
  assertEquals(matchFraco("Porta Fusível MIDI", "Porta Fusível MIDI Victron", null).fraco, false);
  assertEquals(matchFraco("Tomada 220V 10A embutir", "Tomada 220V 10A de embutir branca", null).fraco, false);
});

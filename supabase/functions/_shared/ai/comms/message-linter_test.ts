import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { revisarMensagem } from "./message-linter.ts";
import { perfilDeVoz } from "./voice-profiles.ts";

const forn = perfilDeVoz("fornecedor", "whatsapp");
const cli = perfilDeVoz("cliente", "whatsapp");

Deno.test("a mensagem de fornecedor ANTES (real) reprova em vários pontos", () => {
  const antes =
    "Olá ANDERSON DOS SANTOS ELETRONICA, tudo bem? Aqui é da HBR.\n" +
    "Gostaríamos de uma cotação (COT-00002):\n1. 8x Porta Fusível MIDI\n\n" +
    "Cotação para sistema elétrico LiFePO4 12V Victron. Prazo desejado: o mais breve possível.\n" +
    'Pode responder com o número do item, preço e prazo? Ex.: "1 - R$ 850 - 5 dias". Obrigado!';
  const r = revisarMensagem(antes, forn);
  assertEquals(r.ok, false);
  const cods = r.problemas.map((p) => p.codigo);
  assertEquals(cods.includes("razao_social"), true);
  assertEquals(cods.includes("aplicacao"), true);
  assertEquals(cods.includes("prazo_estipulado"), true);
  assertEquals(cods.includes("tutorial_resposta"), true);
});

Deno.test("a mensagem de fornecedor DEPOIS (enxuta) passa", () => {
  const depois =
    "Olá, tudo bem? Aqui é da HBR Marine Solutions.\n" +
    "Gostaríamos de uma cotação (COT-00002):\n1. 8x Porta Fusível MIDI c/ Capa\n2. 1x Fusível MIDI 50A\n\nObrigado!";
  const r = revisarMensagem(depois, forn);
  assertEquals(r.ok, true);
  assertEquals(r.problemas.length, 0);
});

Deno.test("cobrança fria/ameaça a cliente reprova", () => {
  const fria = "Prezado, consta em aberto R$ 1.480,00 vencido em 03/07. Regularize o quanto antes para evitar transtornos.";
  const r = revisarMensagem(fria, cli);
  const cods = r.problemas.map((p) => p.codigo);
  assertEquals(cods.includes("ameaca"), true);
});

Deno.test("cobrança empática a cliente passa", () => {
  const boa = "Oi, João, tudo certo? Passando pra lembrar da OS do seu barco: R$ 1.480,00, que venceu dia 03/07. Consigo te mandar o Pix ou a gente parcela — o que fica melhor?";
  // 'preco' não é proibido para cliente; ameaça não há. Passa.
  const r = revisarMensagem(boa, cli);
  assertEquals(r.problemas.some((p) => p.codigo === "ameaca"), false);
});

Deno.test("jargão técnico (100/50) para cliente é sinalizado", () => {
  const r = revisarMensagem("Segue o MPPT 100/50 do seu sistema.", cli);
  assertEquals(r.problemas.some((p) => p.codigo === "jargao_tecnico"), true);
});

Deno.test("teto de tamanho é respeitado (fornecedor curto)", () => {
  const curto = revisarMensagem("Olá, tudo bem?\nItem 1\nObrigado!", forn);
  assertEquals(curto.problemas.some((p) => p.codigo === "tamanho"), false);
});

Deno.test("nunca lança — entrada estranha vira ok", () => {
  // deno-lint-ignore no-explicit-any
  const r = revisarMensagem(undefined as any, forn);
  assertEquals(r.ok, true);
});

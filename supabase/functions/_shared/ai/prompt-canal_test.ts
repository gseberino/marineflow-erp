// O jeito de responder no WhatsApp (15/10/2026, secretário, Passo 0b). As regras do canal estavam no
// FIM do bloco volátil, depois de ~69k tokens, e perdiam para "formate em markdown" e "TERMINE COM UM
// PRÓXIMO PASSO" do bloco estável: respostas longas, duas perguntas, "Quer que eu…?" em toda consulta.
// O que se protege: a seção no TOPO do estável, o estável igual nos dois canais (cache compartilhado),
// e as frases antigas fora.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildSystemBlocks } from "./prompt.ts";

const blocos = (channel: "panel" | "whatsapp") => buildSystemBlocks({}, { userName: "Teste", userRole: "admin", channel });

Deno.test("o bloco estável é o mesmo nos dois canais (o cache é compartilhado)", () => {
  assertEquals(blocos("panel")[0].text, blocos("whatsapp")[0].text);
  assertEquals(blocos("panel")[0].cache_control, { type: "ephemeral" });
});

Deno.test("COMO RESPONDER NO WHATSAPP está no topo do bloco estável, com as 7 regras", () => {
  const estavel = blocos("whatsapp")[0].text;
  const onde = estavel.indexOf("COMO RESPONDER NO WHATSAPP");
  assert(onde >= 0 && onde < 1500, `a seção está em ${onde}`);
  const secao = estavel.slice(onde, estavel.indexOf("Diretrizes de comportamento:"));
  assertStringIncludes(secao, "A conclusão vem na 1ª linha");
  assertStringIncludes(secao, "No máximo 5 linhas");
  assertStringIncludes(secao, "No máximo 1 pergunta");
  assertStringIncludes(secao, "a confirmação já é a pergunta");
  assertStringIncludes(secao, "Sem bastidores");
  assertStringIncludes(secao, "Hora sempre de Brasília");
});

Deno.test("saíram 'formate em markdown', 'TERMINE COM UM PRÓXIMO PASSO' e o 'Quase toda resposta fecha com ofertas'", () => {
  const estavel = blocos("whatsapp")[0].text;
  for (const velha of ["formate em markdown", "TERMINE COM UM PRÓXIMO PASSO", "Quase toda resposta sua fecha", "Use listas markdown para múltiplos itens"]) {
    assertEquals(estavel.includes(velha), false, velha);
  }
  assertStringIncludes(estavel, "PRÓXIMO PASSO SÓ QUANDO HÁ DECISÃO");
});

Deno.test("volátil: WhatsApp aponta para as regras do início, sem '~10 linhas'; painel libera o markdown", () => {
  const whats = blocos("whatsapp")[1].text;
  assertStringIncludes(whats, "Canal: WhatsApp — valem as regras de COMO RESPONDER NO WHATSAPP do início.");
  assertEquals(whats.includes("~10 linhas"), false);
  assertEquals(whats.includes("markdown"), false);
  const painel = blocos("panel")[1].text;
  assertStringIncludes(painel, "Canal: painel — pode formatar em markdown e usar listas.");
  assertEquals(painel.includes("Canal: WhatsApp"), false);
});

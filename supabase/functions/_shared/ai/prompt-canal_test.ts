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

// C3 (24/11/2026): a função roda em UTC e a data do bloco saía sem fuso. Às 21:30 de terça, 24/11, o modelo lia
// "quarta-feira, 25 de novembro" e o ISO "2026-11-25T00:30:00.000Z": "hoje", "amanhã" e o dia da semana errados.
Deno.test("volátil: às 21:30 de terça em Brasília o modelo lê terça, 24/11, e o ISO com -03:00 (nos dois canais)", () => {
  for (const channel of ["panel", "whatsapp"] as const) {
    const volatil = buildSystemBlocks({}, { userName: "Teste", userRole: "admin", channel, agora: new Date("2026-11-25T00:30:00Z") })[1].text;
    assertStringIncludes(
      volatil,
      "- Hoje é terça-feira, 24 de novembro de 2026, 21:30 (horário de Brasília). Data/hora ISO: 2026-11-24T21:30:00-03:00\n",
    );
    assertEquals(volatil.includes("quarta-feira"), false, "o dia da semana é o de Brasília");
    assertEquals(volatil.includes("2026-11-25"), false, "o dia do ISO é o de Brasília");
    assertEquals(/Data\/hora ISO: \S*Z/.test(volatil), false, "o ISO não sai em UTC");
  }
});

Deno.test("volátil: sem `agora` (nenhum chamador passa) vale o relógio, no mesmo formato", () => {
  const linha = blocos("whatsapp")[1].text.split("\n").find((l) => l.startsWith("- Hoje é ")) ?? "";
  assert(
    /^- Hoje é [a-zçáàâãéêíóôõú-]+, \d{1,2} de [a-zç]+ de \d{4}, \d{2}:\d{2} \(horário de Brasília\)\. Data\/hora ISO: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-03:00$/.test(linha),
    linha,
  );
  const iso = linha.slice(linha.indexOf("ISO: ") + 5);
  assert(Math.abs(new Date(iso).getTime() - Date.now()) < 60_000, `longe do relógio: ${iso}`);
});

Deno.test("volátil: a data não entra no bloco estável (o cache não depende da hora)", () => {
  const em = (iso: string) => buildSystemBlocks({}, { userName: "Teste", userRole: "admin", channel: "whatsapp", agora: new Date(iso) });
  assertEquals(em("2026-11-25T00:30:00Z")[0].text, em("2026-06-01T15:00:00Z")[0].text);
  assert(em("2026-11-25T00:30:00Z")[1].text !== em("2026-06-01T15:00:00Z")[1].text);
});

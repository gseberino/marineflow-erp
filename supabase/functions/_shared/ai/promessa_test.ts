// Detector de promessas do dono (06/10/2026). O que se protege: acha as promessas comuns, ignora
// pergunta e conversa sem compromisso, e marca o lembrete dentro da janela (8h–20h, seg–sáb).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dentroDaJanela, detectarPromessa, quandoLembrar } from "./promessa.ts";

// Terça 06/10/2026, 18:40 em Brasília.
const TER_1840 = new Date("2026-10-06T21:40:00.000Z");
const iso = (d: Date | null | undefined) => d?.toISOString();

Deno.test("acha as promessas comuns e devolve a frase que promete", () => {
  const casos: Array<[string, string]> = [
    ["Beleza Nelson! Amanhã te mando o orçamento atualizado.", "Amanhã te mando o orçamento atualizado."],
    ["Vou ver com o fornecedor e te retorno", "Vou ver com o fornecedor e te retorno"],
    ["Fechado. Segunda envio as fotos", "Segunda envio as fotos"],
    ["Assim que a peça chegar te aviso!", "Assim que a peça chegar te aviso!"],
    ["Deixa comigo", "Deixa comigo"],
    ["Fico de te passar o valor do frete", "Fico de te passar o valor do frete"],
  ];
  for (const [texto, trecho] of casos) assertEquals(detectarPromessa(texto, TER_1840)?.trecho, trecho, texto);
});

Deno.test("não é promessa: pergunta, agradecimento, mídia, conversa sem compromisso", () => {
  for (const texto of ["Te mando amanhã?", "Obrigado, Miguel!", "[audio]", "O radar é da Raymarine", "Bom dia! Tudo bem?", "", null]) {
    assertEquals(detectarPromessa(texto as string, TER_1840), null, String(texto));
  }
});

Deno.test("quando lembrar: amanhã, dia da semana, mais tarde e o padrão de 24h", () => {
  // amanhã → quarta 09:00
  assertEquals(iso(quandoLembrar("amanhã te mando", TER_1840)), "2026-10-07T12:00:00.000Z");
  // sexta → sexta 09/10 09:00
  assertEquals(iso(quandoLembrar("sexta envio", TER_1840)), "2026-10-09T12:00:00.000Z");
  // "terça" dita numa terça → a PRÓXIMA terça
  assertEquals(iso(quandoLembrar("terça passo", TER_1840)), "2026-10-13T12:00:00.000Z");
  // mais tarde às 18:40 → +3h = 21:40, fora da janela → quarta 09:00
  assertEquals(iso(quandoLembrar("mais tarde te ligo", TER_1840)), "2026-10-07T12:00:00.000Z");
  // sem tempo → +24h (quarta 18:40, dentro da janela)
  assertEquals(iso(quandoLembrar("vou ver e te retorno", TER_1840)), "2026-10-07T21:40:00.000Z");
});

Deno.test("janela: madrugada, noite e domingo vão para 09:00 do próximo dia útil", () => {
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-07T08:00:00Z"))).toISOString(), "2026-10-07T12:00:00.000Z"); // 05:00 → 09:00
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-10T23:30:00Z"))).toISOString(), "2026-10-12T12:00:00.000Z"); // sáb 20:30 → seg 09:00
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-11T15:00:00Z"))).toISOString(), "2026-10-12T12:00:00.000Z"); // domingo → seg
  assertEquals(new Date(dentroDaJanela(Date.parse("2026-10-07T17:00:00Z"))).toISOString(), "2026-10-07T17:00:00.000Z"); // 14:00 fica
});

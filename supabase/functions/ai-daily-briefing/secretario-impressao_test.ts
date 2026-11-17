// A sugestão de imprimir as vias de hoje na manhã (17/11/2026): só em dia útil e com OS na agenda; sem isso, o texto
// de antes, byte a byte.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { comSugestaoDeImpressao, montarDosDados } from "./secretario.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";

Deno.test("comSugestaoDeImpressao: dia útil com OS ganha uma linha no fim; o resto fica igual", () => {
  assertEquals(comSugestaoDeImpressao("Bom dia!", "util", 2), "Bom dia!\n🖨️ Quer as 2 vias de hoje no papel? Responda: *imprime as vias de hoje*");
  assertEquals(comSugestaoDeImpressao("Bom dia!", "util", 1), "Bom dia!\n🖨️ Quer a via de hoje no papel? Responda: *imprime as vias de hoje*");
  assertEquals(comSugestaoDeImpressao("Bom dia!", "util", 0), "Bom dia!");
  assertEquals(comSugestaoDeImpressao("Bom dia! Domingo", "domingo", 3), "Bom dia! Domingo");
});

Deno.test("montarDosDados: sem viasParaImprimir o texto é o de antes; com, só ganha a linha", () => {
  const base = {
    hoje: HOJE_1510, agora: AGORA_1510, coleta: coleta1510(), historico: [],
    naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(),
    escritorio: { propostas: null, alertas: null, regras: null, debitosSemLoja: null, entradas: null },
  };
  const antes = montarDosDados(base).texto;
  const com = montarDosDados({ ...base, viasParaImprimir: 3 }).texto;
  assertEquals(com, `${antes}\n🖨️ Quer as 3 vias de hoje no papel? Responda: *imprime as vias de hoje*`);
});

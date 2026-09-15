import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dentroDaJanela, jaTocouHoje, proximoToqueApos, esperaFinalEsgotada, partesBrasilia } from "./cadencia.ts";

// 2026-09-16 é uma quarta-feira. 15:00 em Brasília = 18:00Z.
const quartaTarde = new Date("2026-09-16T18:00:00Z");
const quartaNoite = new Date("2026-09-16T22:30:00Z"); // 19:30 BRT
const quartaCedo = new Date("2026-09-16T11:30:00Z"); // 08:30 BRT
const sabado = new Date("2026-09-19T15:00:00Z"); // 12:00 BRT

Deno.test("janela: quarta 15h entra; 19h30 e 8h30 não; sábado nunca", () => {
  assertEquals(dentroDaJanela(quartaTarde), true);
  assertEquals(dentroDaJanela(quartaNoite), false);
  assertEquals(dentroDaJanela(quartaCedo), false);
  assertEquals(dentroDaJanela(sabado), false);
});

Deno.test("partesBrasilia converte o fuso de verdade (não usa o do servidor)", () => {
  const p = partesBrasilia(new Date("2026-09-17T01:30:00Z")); // ainda quarta 22:30 em Brasília
  assertEquals(p.dataISO, "2026-09-16");
  assertEquals(p.hora, 22);
});

Deno.test("dois toques no mesmo dia de Brasília é proibido — o dia é o de Brasília, não o UTC", () => {
  // 23:30 BRT de terça = 02:30Z de quarta; às 09:00 BRT de quarta já é outro dia
  assertEquals(jaTocouHoje("2026-09-16T02:30:00Z", new Date("2026-09-16T12:00:00Z")), false);
  assertEquals(jaTocouHoje("2026-09-16T13:00:00Z", quartaTarde), true);
  assertEquals(jaTocouHoje(null, quartaTarde), false);
});

Deno.test("com prazo longe, os toques caem em D-7 / D-3 / D-1 (fornecedor, 3 toques)", () => {
  const prazo = "2026-10-16T12:00:00Z";
  const dia = 86_400_000;
  const apos1 = proximoToqueApos(1, 3, prazo, quartaTarde)!;
  const apos2 = proximoToqueApos(2, 3, prazo, quartaTarde)!;
  assertEquals(Math.round((new Date(prazo).getTime() - apos1.getTime()) / dia), 3);
  assertEquals(Math.round((new Date(prazo).getTime() - apos2.getTime()) / dia), 1);
  assertEquals(proximoToqueApos(3, 3, prazo, quartaTarde), null);
});

Deno.test("cliente (2 toques) usa D-3 / D-1; prazo em cima empurra para amanhã, nunca hoje", () => {
  const dia = 86_400_000;
  const prazoLonge = "2026-10-16T12:00:00Z";
  const apos1 = proximoToqueApos(1, 2, prazoLonge, quartaTarde)!;
  assertEquals(Math.round((new Date(prazoLonge).getTime() - apos1.getTime()) / dia), 1);
  const prazoPerto = new Date(quartaTarde.getTime() + 0.5 * dia).toISOString();
  const apertado = proximoToqueApos(1, 2, prazoPerto, quartaTarde)!;
  assert(apertado.getTime() >= quartaTarde.getTime() + dia);
});

Deno.test("sem prazo: +2d, +4d, +7d", () => {
  const dia = 86_400_000;
  assertEquals((proximoToqueApos(1, 3, null, quartaTarde)!.getTime() - quartaTarde.getTime()) / dia, 2);
  assertEquals((proximoToqueApos(2, 3, null, quartaTarde)!.getTime() - quartaTarde.getTime()) / dia, 4);
  assertEquals(proximoToqueApos(3, 3, null, quartaTarde), null);
});

Deno.test("espera final: prazo vencido ou 3 dias sem resposta devolvem ao dono", () => {
  const dia = 86_400_000;
  assertEquals(esperaFinalEsgotada(new Date(quartaTarde.getTime() - 1 * dia).toISOString(), null, quartaTarde), false);
  assertEquals(esperaFinalEsgotada(new Date(quartaTarde.getTime() - 3 * dia).toISOString(), null, quartaTarde), true);
  assertEquals(esperaFinalEsgotada(null, new Date(quartaTarde.getTime() - 1).toISOString(), quartaTarde), true);
  assertEquals(esperaFinalEsgotada(null, null, quartaTarde), false);
});

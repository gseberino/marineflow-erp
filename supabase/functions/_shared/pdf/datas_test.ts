import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dataBR, dataHoraBR, horaBR, somarDiasBR } from "./datas.ts";

// Os casos-limite do fuso. Todos valem em qualquer TZ do processo — é esse o ponto.

Deno.test("dia de calendário sai como está, sem virar o dia anterior", () => {
  // A regra do JavaScript lê 'aaaa-mm-dd' como meia-noite UTC; em Brasília seria 19/09.
  assertEquals(dataBR("2026-09-20"), "20/09/2026");
  assertEquals(dataBR("2026-01-01"), "01/01/2026");
});

Deno.test("instante sai no dia de Brasília", () => {
  // 02h30 UTC do dia 25 = 23h30 de Brasília do dia 24.
  assertEquals(dataBR("2026-09-25T02:30:00.000Z"), "24/09/2026");
  assertEquals(dataBR(new Date("2026-09-25T02:30:00.000Z")), "24/09/2026");
  // Meio-dia não tem ambiguidade nenhuma.
  assertEquals(dataBR("2026-09-25T15:00:00.000Z"), "25/09/2026");
  // Carimbo com fuso explícito também.
  assertEquals(dataBR("2026-09-24T23:30:00-03:00"), "24/09/2026");
});

Deno.test("hora e carimbo completo em Brasília", () => {
  const d = new Date("2026-09-26T00:30:00.000Z");
  assertEquals(horaBR(d), "21:30");
  assertEquals(dataHoraBR(new Date("2026-09-26T02:45:00.000Z")), "25/09/2026, 23:45:00");
});

Deno.test("validade soma dias ao dia de Brasília, virando mês e ano", () => {
  // Emitido às 23h30 de 24/09 (02h30 UTC de 25/09): 7 dias depois é 01/10, não 02/10.
  assertEquals(somarDiasBR(new Date("2026-09-25T02:30:00.000Z"), 7), "01/10/2026");
  assertEquals(somarDiasBR(new Date("2026-12-28T15:00:00.000Z"), 5), "02/01/2027");
  assertEquals(somarDiasBR(new Date("2028-02-27T15:00:00.000Z"), 2), "29/02/2028");
  assertEquals(somarDiasBR(new Date("2026-09-25T15:00:00.000Z"), 0), "25/09/2026");
});

// O dia de Brasília e a carga por dia (Agenda de Produção, Fase 0 — D4, D5 e D6).
//
// A OS guarda uma janela corrida, e cada leitor a lia de um jeito: a grade punha a OS só no dia
// do início, a carga somava a janela inteira ("72h ⚠" num dia) e o assistente montava o dia em
// UTC (às 22 h de Brasília, "hoje" já era amanhã). Estes testes seguram a regra única.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cruzaODia,
  diaBR,
  diasDaJanela,
  filtroQueCruza,
  horasNoDia,
  JORNADA_PADRAO_HORAS,
  limitesDoDiaBR,
  somarDias,
} from "./agenda-dia.ts";

Deno.test("a jornada padrão é 8 h", () => {
  assertEquals(JORNADA_PADRAO_HORAS, 8);
});

Deno.test("às 22 h de Brasília ainda é hoje (não pula para o dia seguinte, como em UTC)", () => {
  const vinteEDuas = "2026-10-06T22:00:00-03:00"; // = 2026-10-07T01:00Z
  assertEquals(diaBR(vinteEDuas), "2026-10-06");
  assertEquals(limitesDoDiaBR(vinteEDuas), {
    de: "2026-10-06T03:00:00.000Z",
    ate: "2026-10-07T03:00:00.000Z",
    dia: "2026-10-06",
  });
  // O mesmo instante como Date e como epoch dá o mesmo dia.
  assertEquals(limitesDoDiaBR(new Date(vinteEDuas)).dia, "2026-10-06");
  assertEquals(limitesDoDiaBR(new Date(vinteEDuas).getTime()).dia, "2026-10-06");
  // E 00:30 de Brasília já é o dia novo (é 03:30 UTC).
  assertEquals(diaBR("2026-10-07T00:30:00-03:00"), "2026-10-07");
});

Deno.test("limitesDoDiaBR com 'AAAA-MM-DD' usa o dia como veio", () => {
  assertEquals(limitesDoDiaBR("2026-10-06"), {
    de: "2026-10-06T03:00:00.000Z",
    ate: "2026-10-07T03:00:00.000Z",
    dia: "2026-10-06",
  });
});

Deno.test("janela de 06/10 06:00 a 08/10 18:00: três dias de 8 h, nunca 18/24/18", () => {
  const ini = "2026-10-06T06:00:00-03:00";
  const fim = "2026-10-08T18:00:00-03:00";
  const dias = diasDaJanela(ini, fim, "2026-10-05", "2026-10-11");
  assertEquals(dias, ["2026-10-06", "2026-10-07", "2026-10-08"]);
  assertEquals(dias.map((d) => horasNoDia(ini, fim, d)), [8, 8, 8]);
  // Sem o teto seriam 18, 24 e 18 — a carga da grade antiga, que somava 60 h num dia só.
  assertEquals(dias.map((d) => horasNoDia(ini, fim, d, 24)), [18, 24, 18]);
  // Fora da janela não ocupa nada.
  assertEquals(horasNoDia(ini, fim, "2026-10-05"), 0);
  assertEquals(horasNoDia(ini, fim, "2026-10-09"), 0);
});

Deno.test("OS de 72 h: no máximo a jornada em cada dia", () => {
  const ini = "2026-10-06T08:00:00-03:00";
  const fim = "2026-10-09T08:00:00-03:00";
  const dias = diasDaJanela(ini, fim, "2026-10-05", "2026-10-11");
  assertEquals(dias, ["2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"]);
  for (const d of dias) {
    const h = horasNoDia(ini, fim, d);
    assertEquals(h <= JORNADA_PADRAO_HORAS, true, `${d} deu ${h} h`);
  }
});

Deno.test("OS sem fim aparece só no dia do início e não soma horas", () => {
  const ini = "2026-10-06T09:00:00-03:00";
  assertEquals(diasDaJanela(ini, null, "2026-10-05", "2026-10-11"), ["2026-10-06"]);
  assertEquals(diasDaJanela(ini, undefined, "2026-10-05", "2026-10-11"), ["2026-10-06"]);
  assertEquals(horasNoDia(ini, null, "2026-10-06"), 0);
  const hoje = limitesDoDiaBR("2026-10-06");
  const amanha = limitesDoDiaBR("2026-10-07");
  assertEquals(cruzaODia(ini, null, hoje.de, hoje.ate), true);
  assertEquals(cruzaODia(ini, null, amanha.de, amanha.ate), false);
});

Deno.test("tarefa de 2 h dá 2 h", () => {
  assertEquals(horasNoDia("2026-10-06T09:00:00-03:00", "2026-10-06T11:00:00-03:00", "2026-10-06"), 2);
  assertEquals(horasNoDia("2026-10-06T09:00:00-03:00", "2026-10-06T09:30:00-03:00", "2026-10-06"), 0.5);
});

Deno.test("virada de mês: a janela atravessa e o recorte respeita o período visível", () => {
  const ini = "2026-09-30T08:00:00-03:00";
  const fim = "2026-10-02T17:00:00-03:00";
  assertEquals(diasDaJanela(ini, fim, "2026-09-28", "2026-10-04"), ["2026-09-30", "2026-10-01", "2026-10-02"]);
  // Na grade de outubro, a OS que começou em setembro aparece nos dias de outubro que ela toca.
  assertEquals(diasDaJanela(ini, fim, "2026-10-01", "2026-10-31"), ["2026-10-01", "2026-10-02"]);
  // Na de setembro, só no último dia.
  assertEquals(diasDaJanela(ini, fim, "2026-09-01", "2026-09-30"), ["2026-09-30"]);
  assertEquals(horasNoDia(ini, fim, "2026-10-01"), 8);
  assertEquals(somarDias("2026-09-30", 1), "2026-10-01");
  assertEquals(somarDias("2026-12-31", 1), "2027-01-01");
  assertEquals(somarDias("2026-03-01", -1), "2026-02-28");
});

Deno.test("janela que termina à meia-noite exata não toca o dia que começa ali", () => {
  const ini = "2026-10-06T08:00:00-03:00";
  const fim = "2026-10-07T00:00:00-03:00";
  assertEquals(diasDaJanela(ini, fim, "2026-10-05", "2026-10-11"), ["2026-10-06"]);
  assertEquals(horasNoDia(ini, fim, "2026-10-07"), 0);
});

Deno.test("janela inteira fora do período visível não aparece", () => {
  assertEquals(diasDaJanela("2026-10-01T08:00:00-03:00", "2026-10-02T17:00:00-03:00", "2026-10-05", "2026-10-11"), []);
  assertEquals(diasDaJanela("2026-10-12T08:00:00-03:00", null, "2026-10-05", "2026-10-11"), []);
  assertEquals(diasDaJanela(null, null, "2026-10-05", "2026-10-11"), []);
});

Deno.test("cruzaODia é interseção: começar antes e terminar dentro conta; terminar no início do dia, não", () => {
  const { de, ate } = limitesDoDiaBR("2026-10-07");
  assertEquals(cruzaODia("2026-10-06T08:00:00-03:00", "2026-10-07T10:00:00-03:00", de, ate), true);
  assertEquals(cruzaODia("2026-10-06T08:00:00-03:00", "2026-10-09T10:00:00-03:00", de, ate), true);
  assertEquals(cruzaODia("2026-10-06T08:00:00-03:00", "2026-10-07T00:00:00-03:00", de, ate), false);
  assertEquals(cruzaODia("2026-10-08T00:00:00-03:00", "2026-10-08T10:00:00-03:00", de, ate), false);
  assertEquals(cruzaODia(null, null, de, ate), false);
});

Deno.test("filtroQueCruza: o .or() do PostgREST, para usar com .lt('scheduled_start_at', ate)", () => {
  const de = "2026-10-05T03:00:00.000Z";
  assertEquals(
    filtroQueCruza(de),
    "scheduled_end_at.gte.2026-10-05T03:00:00.000Z,and(scheduled_end_at.is.null,scheduled_start_at.gte.2026-10-05T03:00:00.000Z)",
  );
  // ISO não tem vírgula: o texto não precisa de aspas.
  assertEquals(de.includes(","), false);
});

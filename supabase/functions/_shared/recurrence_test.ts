import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseRRule, expandOccurrences } from "./recurrence.ts";

const d = (iso: string) => new Date(iso);

Deno.test("parseRRule: subset suportado e rejeição de lixo", () => {
  const p = parseRRule("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR;UNTIL=20261231")!;
  assertEquals(p.freq, "WEEKLY");
  assertEquals(p.interval, 2);
  assertEquals(p.byday, [1, 5]);
  assertEquals(p.until!.toISOString().slice(0, 10), "2026-12-31");
  assertEquals(parseRRule("FREQ=YEARLY"), null);
  assertEquals(parseRRule(""), null);
  assertEquals(parseRRule("RRULE:FREQ=DAILY")!.freq, "DAILY");
});

Deno.test("DAILY: intervalo e janela, sem incluir o DTSTART", () => {
  const occ = expandOccurrences(
    "FREQ=DAILY;INTERVAL=2",
    d("2026-07-20T12:00:00Z"),
    d("2026-07-20T00:00:00Z"),
    d("2026-07-27T00:00:00Z"),
  );
  assertEquals(occ.map((o) => o.toISOString()), [
    "2026-07-22T12:00:00.000Z",
    "2026-07-24T12:00:00.000Z",
    "2026-07-26T12:00:00.000Z",
  ]);
});

Deno.test("WEEKLY com BYDAY: dias certos, hora preservada", () => {
  // DTSTART qua 22/07/2026 09:00Z; BYDAY seg+sex
  const occ = expandOccurrences(
    "FREQ=WEEKLY;BYDAY=MO,FR",
    d("2026-07-22T09:00:00Z"),
    d("2026-07-22T00:00:00Z"),
    d("2026-08-01T00:00:00Z"),
  );
  assertEquals(occ.map((o) => o.toISOString()), [
    "2026-07-24T09:00:00.000Z", // sex
    "2026-07-27T09:00:00.000Z", // seg
    "2026-07-31T09:00:00.000Z", // sex
  ]);
});

Deno.test("WEEKLY sem BYDAY: repete o dia da semana do DTSTART", () => {
  const occ = expandOccurrences(
    "FREQ=WEEKLY",
    d("2026-07-22T14:30:00Z"), // quarta
    d("2026-07-22T00:00:00Z"),
    d("2026-08-06T00:00:00Z"),
  );
  assertEquals(occ.map((o) => o.toISOString()), [
    "2026-07-29T14:30:00.000Z",
    "2026-08-05T14:30:00.000Z",
  ]);
});

Deno.test("MONTHLY: mesmo dia do mês; mês sem o dia é pulado (31→fev)", () => {
  const occ = expandOccurrences(
    "FREQ=MONTHLY",
    d("2026-01-31T10:00:00Z"),
    d("2026-01-31T00:00:00Z"),
    d("2026-05-01T00:00:00Z"),
  );
  assertEquals(occ.map((o) => o.toISOString()), [
    "2026-03-31T10:00:00.000Z", // fev/abr pulados (sem dia 31 fev; abr>janela? abr30 sem dia31)
  ]);
});

Deno.test("UNTIL corta a série", () => {
  const occ = expandOccurrences(
    "FREQ=DAILY;UNTIL=20260724",
    d("2026-07-22T08:00:00Z"),
    d("2026-07-22T00:00:00Z"),
    d("2026-08-22T00:00:00Z"),
  );
  assertEquals(occ.map((o) => o.toISOString()), [
    "2026-07-23T08:00:00.000Z",
    "2026-07-24T08:00:00.000Z",
  ]);
});

Deno.test("maxOccurrences trava séries infinitas", () => {
  const occ = expandOccurrences(
    "FREQ=DAILY",
    d("2026-01-01T08:00:00Z"),
    d("2026-01-01T00:00:00Z"),
    d("2030-01-01T00:00:00Z"),
    10,
  );
  assertEquals(occ.length, 10);
});

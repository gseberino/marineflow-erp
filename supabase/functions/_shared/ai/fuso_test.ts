import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { comFusoDeBrasilia, horariosDeBrasilia } from "./fuso.ts";

Deno.test("hora sem fuso vira hora de Brasília — 09:00 continua 09:00 na agenda", () => {
  const v = comFusoDeBrasilia("2026-10-05T09:00:00") as string;
  assertEquals(v, "2026-10-05T09:00:00-03:00");
  assertEquals(new Date(v).toISOString(), "2026-10-05T12:00:00.000Z");
});

Deno.test("sem segundos e com espaço também", () => {
  assertEquals(comFusoDeBrasilia("2026-10-05T09:00"), "2026-10-05T09:00:00-03:00");
  assertEquals(comFusoDeBrasilia("2026-10-05 14:30"), "2026-10-05T14:30:00-03:00");
});

Deno.test("hora que já tem fuso não muda", () => {
  assertEquals(comFusoDeBrasilia("2026-10-05T09:00:00-03:00"), "2026-10-05T09:00:00-03:00");
  assertEquals(comFusoDeBrasilia("2026-10-05T12:00:00Z"), "2026-10-05T12:00:00Z");
  assertEquals(comFusoDeBrasilia("2026-10-05T12:00:00.000+00:00"), "2026-10-05T12:00:00.000+00:00");
});

Deno.test("só a data vira 08:00 de Brasília, como a tela de agenda", () => {
  assertEquals(comFusoDeBrasilia("2026-10-05"), "2026-10-05T08:00:00-03:00");
});

Deno.test("vazio, nulo e lixo não são inventados", () => {
  assertEquals(comFusoDeBrasilia(null), null);
  assertEquals(comFusoDeBrasilia(undefined), undefined);
  assertEquals(comFusoDeBrasilia(""), "");
  assertEquals(comFusoDeBrasilia("amanhã"), "amanhã");
});

Deno.test("só os campos de horário são tocados", () => {
  const r = horariosDeBrasilia({ title: "2026-10-05", scheduled_start_at: "2026-10-05T09:00", id: "x" });
  assertEquals(r, { title: "2026-10-05", scheduled_start_at: "2026-10-05T09:00:00-03:00", id: "x" });
  assertEquals("due_at" in r, false);
});

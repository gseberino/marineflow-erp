import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { agoraEmBrasilia, comFusoDeBrasilia, FUSO_DE_BRASILIA, horariosDeBrasilia } from "./fuso.ts";

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

// ─── C3 (24/11/2026): o relógio de Brasília para o texto que o modelo lê ────────────────────────
// A função roda em UTC: das 21:00 à meia-noite de Brasília o "Hoje é" do prompt dizia o dia seguinte.

Deno.test("agoraEmBrasilia: 00:30 UTC de 25/11 ainda é terça, 24/11, 21:30 em Brasília", () => {
  const r = agoraEmBrasilia(new Date("2026-11-25T00:30:00Z"));
  assertEquals(r.porExtenso, "terça-feira, 24 de novembro de 2026");
  assertEquals(r.hora, "21:30");
  assertEquals(r.isoComFuso, "2026-11-24T21:30:00-03:00");
  assertEquals(r.dia, "2026-11-24");
});

Deno.test("agoraEmBrasilia: sábado à noite não vira domingo", () => {
  const r = agoraEmBrasilia(new Date("2026-11-29T01:15:00Z"));
  assertEquals(r.porExtenso, "sábado, 28 de novembro de 2026");
  assertEquals(r.hora, "22:15");
  assertEquals(r.dia, "2026-11-28");
});

Deno.test("agoraEmBrasilia: virada de mês e de ano — 22h de 30/11 continua novembro, 23:59 de 31/12 continua 2026", () => {
  const fimDoMes = agoraEmBrasilia(new Date("2026-12-01T01:00:00Z"));
  assertEquals(fimDoMes.porExtenso, "segunda-feira, 30 de novembro de 2026");
  assertEquals(fimDoMes.hora, "22:00");
  assertEquals(fimDoMes.isoComFuso, "2026-11-30T22:00:00-03:00");
  assertEquals(fimDoMes.dia, "2026-11-30");
  const fimDoAno = agoraEmBrasilia(new Date("2027-01-01T02:59:59Z"));
  assertEquals(fimDoAno.porExtenso, "quinta-feira, 31 de dezembro de 2026");
  assertEquals(fimDoAno.hora, "23:59");
  assertEquals(fimDoAno.isoComFuso, "2026-12-31T23:59:59-03:00");
  assertEquals(fimDoAno.dia, "2026-12-31");
});

Deno.test("agoraEmBrasilia: meio-dia não muda nada; à meia-noite de Brasília o dia já é o novo", () => {
  const meioDia = agoraEmBrasilia(new Date("2026-11-24T15:00:00Z"));
  assertEquals(meioDia.porExtenso, "terça-feira, 24 de novembro de 2026");
  assertEquals(meioDia.hora, "12:00");
  assertEquals(meioDia.isoComFuso, "2026-11-24T12:00:00-03:00");
  assertEquals(meioDia.dia, "2026-11-24");
  const meiaNoite = agoraEmBrasilia(new Date("2026-11-25T03:00:00Z"));
  assertEquals(meiaNoite.porExtenso, "quarta-feira, 25 de novembro de 2026");
  assertEquals(meiaNoite.hora, "00:00");
  assertEquals(meiaNoite.isoComFuso, "2026-11-25T00:00:00-03:00");
  assertEquals(meiaNoite.dia, "2026-11-25");
});

Deno.test("agoraEmBrasilia: as quatro formas dizem o mesmo instante, hora a hora de um dia inteiro", () => {
  // O por extenso e a hora saem do Intl (fuso pelo nome); o ISO e o dia, de -03:00 fixo. Têm de concordar.
  const inicio = Date.UTC(2026, 10, 24, 0, 7, 9);
  for (let h = 0; h < 24; h++) {
    const instante = new Date(inicio + h * 3_600_000);
    const r = agoraEmBrasilia(instante);
    assertEquals(new Date(r.isoComFuso).getTime(), instante.getTime(), r.isoComFuso);
    assertEquals(r.isoComFuso.slice(0, 10), r.dia);
    assertEquals(r.isoComFuso.slice(11, 16), r.hora);
    const doIntl = instante.toLocaleDateString("pt-BR", { timeZone: FUSO_DE_BRASILIA });
    assertEquals(doIntl, r.dia.split("-").reverse().join("/"));
    assertEquals(r.porExtenso.includes(`, ${Number(r.dia.slice(8))} de `), true, r.porExtenso);
  }
});

Deno.test("agoraEmBrasilia: sem argumento vale o relógio; data inválida não lança", () => {
  const formato = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-03:00$/;
  const antes = Date.now();
  const agora = agoraEmBrasilia();
  const invalida = agoraEmBrasilia(new Date("isto não é data"));
  for (const r of [agora, invalida]) {
    assertEquals(formato.test(r.isoComFuso), true, r.isoComFuso);
    const diferenca = new Date(r.isoComFuso).getTime() - antes;
    assertEquals(diferenca > -2000 && diferenca < 60_000, true, `longe do relógio: ${r.isoComFuso}`);
  }
});

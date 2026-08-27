import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { apurar, minutosNoturnos, emBrasilia, duracaoDoTurno, diasDoPeriodo, type WorkProfile } from "./calculo.ts";

const porHora: WorkProfile = {
  id: "p1", modo_pagamento: "hora", valor_hora: 30,
  jornada_diaria_horas: 8, divisor_mensal: 220,
  pct_hora_extra: 50, pct_noturno: 20, pct_domingo: 100, paga_dsr: false,
};

Deno.test("hora local sai no fuso de Brasília, não no do servidor (que roda em UTC)", () => {
  // 2026-08-18T21:00:00Z = 18h em Brasília. getHours() do servidor daria 21.
  const r = emBrasilia("2026-08-18T21:00:00Z");
  assertEquals(r.hora, 18);
  assertEquals(r.dataLocal, "2026-08-18");
});

Deno.test("turno de 8h num dia útil: tudo hora normal, sem extra", () => {
  const a = apurar(porHora, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T20:00:00Z", intervalo_minutos: 60 }]);
  assertEquals(a.horas_normais, 8);
  assertEquals(a.horas_extras, 0);
  assertEquals(a.valor_normais, 240);   // 8 × 30
  assertEquals(a.valor_bruto, 240);
});

Deno.test("2h além da jornada viram extra a 50%", () => {
  const a = apurar(porHora, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T22:00:00Z", intervalo_minutos: 60 }]);
  assertEquals(a.horas_normais, 8);
  assertEquals(a.horas_extras, 2);
  assertEquals(a.valor_normais, 240);
  assertEquals(a.valor_extras, 90);     // 2 × 30 × 1,5
  assertEquals(a.valor_bruto, 330);
});

Deno.test("janela noturna é 22h-5h e o turno que cruza a meia-noite é contado certo", () => {
  // 20h às 2h em Brasília = 6h de turno, das quais 4h (22h-2h) são noturnas.
  const min = minutosNoturnos("2026-08-18T23:00:00Z", "2026-08-19T05:00:00Z");
  assertEquals(min, 240);
});

Deno.test("hora extra noturna acumula os dois adicionais: × 1,20 × 1,50 = × 1,80", () => {
  // 18h às 2h (8h de turno, sem intervalo): 4h normais diurnas + 4h que passam da jornada.
  // Das 8h, 4h caem no noturno (22h-2h) e essas são justamente as extras.
  const a = apurar(porHora, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T21:00:00Z", fim: "2026-08-19T05:00:00Z", intervalo_minutos: 0 }]);
  assertEquals(a.horas_extras, 0);          // 8h = exatamente a jornada, nada excede
  assertEquals(a.horas_noturnas, 4);
  // 4h diurnas normais (120) + 4h noturnas normais a 1,20 (144)
  assertEquals(a.valor_normais, 120);
  assertEquals(a.valor_noturnas, 144);
});

Deno.test("noturno vai primeiro para as horas EXTRAS, que são as últimas do turno", () => {
  // 18h às 4h = 10h. Jornada 8h, então 2h de extra. 6h noturnas (22h-4h).
  const a = apurar(porHora, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T21:00:00Z", fim: "2026-08-19T07:00:00Z", intervalo_minutos: 0 }]);
  assertEquals(a.horas_extras, 2);
  assertEquals(a.horas_noturnas, 6);
  // as 2h extras são noturnas: 2 × 30 × 1,2 × 1,5 = 108
  // sobram 4h noturnas normais: 4 × 30 × 1,2 = 144  -> valor_noturnas = 252
  assertEquals(a.valor_noturnas, 252);
  assertEquals(a.valor_extras, 0);          // nenhuma extra caiu no diurno
});

Deno.test("domingo paga em dobro e não acumula hora extra por cima", () => {
  // 2026-08-16 é um domingo.
  const a = apurar(porHora, [{ data: "2026-08-16", tipo: "normal",
    inicio: "2026-08-16T13:00:00Z", fim: "2026-08-16T23:00:00Z", intervalo_minutos: 0 }]);
  assertEquals(a.horas_domingo, 10);
  assertEquals(a.horas_extras, 0);
  assertEquals(a.valor_domingo, 600);   // 10 × 30 × 2
});

Deno.test("diária inteira e meia diária pelo limite de horas do perfil", () => {
  const diarista: WorkProfile = { ...porHora, modo_pagamento: "diaria", valor_diaria: 200, meia_diaria_ate_horas: 4 };
  const a = apurar(diarista, [
    { data: "2026-08-17", tipo: "diaria", inicio: "2026-08-17T11:00:00Z", fim: "2026-08-17T20:00:00Z" }, // 9h
    { data: "2026-08-18", tipo: "diaria", inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T14:00:00Z" }, // 3h
  ]);
  assertEquals(a.diarias_inteiras, 1);
  assertEquals(a.diarias_meias, 1);
  assertEquals(a.valor_diarias, 300);   // 200 + 100
});

Deno.test("diária sem horas registradas é diária inteira — é como se combina no campo", () => {
  const diarista: WorkProfile = { ...porHora, modo_pagamento: "diaria", valor_diaria: 200, meia_diaria_ate_horas: 4 };
  const a = apurar(diarista, [{ data: "2026-08-18", tipo: "diaria" }]);
  assertEquals(a.diarias_inteiras, 1);
  assertEquals(a.valor_diarias, 200);
});

// O detalhamento não é enfeite de relatório: `v_custo_real_mao_de_obra_por_os` casa o valor de cada
// dia com a OS pelo `turno_id`. Se ele sumir de qualquer ramo do cálculo, a view perde aquele dia em
// silêncio — a soma continua parecendo plausível, só que menor. Por isso o teste cobre os quatro
// ramos, e não um só.
Deno.test("cada dia do detalhamento carrega o turno_id — é o que liga o custo à OS", () => {
  const diarista: WorkProfile = { ...porHora, modo_pagamento: "diaria", valor_diaria: 200, meia_diaria_ate_horas: 4 };
  const d = apurar(diarista, [
    { id: "t-diaria", data: "2026-08-17", tipo: "diaria", inicio: "2026-08-17T11:00:00Z", fim: "2026-08-17T20:00:00Z" },
    { id: "t-folga", data: "2026-08-18", tipo: "folga" },
  ]);
  assertEquals(d.detalhamento.map((x) => x.turno_id), ["t-diaria", "t-folga"]);

  const h = apurar(porHora, [
    { id: "t-normal", data: "2026-08-17", tipo: "normal", inicio: "2026-08-17T11:00:00Z", fim: "2026-08-17T20:00:00Z" },
    { id: "t-domingo", data: "2026-08-16", tipo: "normal", inicio: "2026-08-16T13:00:00Z", fim: "2026-08-16T17:00:00Z" },
  ]);
  assertEquals(h.detalhamento.map((x) => x.turno_id).sort(), ["t-domingo", "t-normal"]);
  // E o valor tem que vir junto: turno_id sem valor não custeia nada.
  assertEquals(h.detalhamento.every((x) => typeof x.valor === "number"), true);
});

Deno.test("turno sem id não quebra a apuração — vira null, não 'undefined'", () => {
  // Apuração de prévia trabalha com turnos que ainda não existem no banco. O detalhamento tem que
  // sobreviver a isso, porque `detalhamento` vai para uma coluna jsonb.
  const a = apurar(porHora, [{ data: "2026-08-17", tipo: "normal", duracao_minutos: 480 }]);
  assertEquals(a.detalhamento[0].turno_id, null);
});

Deno.test("folga, falta e atestado não geram valor", () => {
  const a = apurar(porHora, [
    { data: "2026-08-17", tipo: "folga" },
    { data: "2026-08-18", tipo: "falta" },
    { data: "2026-08-19", tipo: "atestado" },
  ]);
  assertEquals(a.valor_bruto, 0);
  assertEquals(a.detalhamento.length, 3);
});

Deno.test("mensalista: salário entra cheio e a hora vem do divisor 220", () => {
  const clt: WorkProfile = { ...porHora, modo_pagamento: "mensal", valor_mensal: 2200, valor_hora: null, paga_dsr: true };
  // 10h num dia útil = 8 normais (dentro do salário) + 2 extras
  const a = apurar(clt, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T21:00:00Z", intervalo_minutos: 0 }],
    { diasUteis: 21, domingosEFeriados: 5 });
  assertEquals(a.valor_mensal, 2200);
  assertEquals(a.horas_extras, 2);
  assertEquals(a.valor_extras, 30);     // hora = 2200/220 = 10; 2 × 10 × 1,5 = 30
  assert(a.valor_dsr > 0, "CLT com extras precisa gerar DSR");
});

Deno.test("DSR = extras ÷ dias úteis × domingos", () => {
  const clt: WorkProfile = { ...porHora, paga_dsr: true };
  const a = apurar(clt, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T21:00:00Z", intervalo_minutos: 0 }],
    { diasUteis: 20, domingosEFeriados: 5 });
  assertEquals(a.valor_extras, 90);         // 2 × 30 × 1,5
  assertEquals(a.valor_dsr, 22.5);          // 90 / 20 × 5
});

Deno.test("perfil que paga DSR sem dias úteis avisa em vez de calcular errado", () => {
  const clt: WorkProfile = { ...porHora, paga_dsr: true };
  const a = apurar(clt, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T21:00:00Z", intervalo_minutos: 0 }]);
  assertEquals(a.valor_dsr, 0);
  assert(a.avisos.some((x) => x.includes("dias úteis")), "precisa avisar, não silenciar");
});

Deno.test("comissões somam e descontos subtraem do bruto", () => {
  const a = apurar(porHora, [{ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T20:00:00Z", intervalo_minutos: 60 }],
    { comissoes: 150, descontos: 40 });
  assertEquals(a.valor_bruto, 350);   // 240 + 150 − 40
});

Deno.test("intervalo é descontado da duração", () => {
  assertEquals(duracaoDoTurno({ data: "2026-08-18", tipo: "normal",
    inicio: "2026-08-18T11:00:00Z", fim: "2026-08-18T21:00:00Z", intervalo_minutos: 90 }), 510);
});

Deno.test("diária sem valor no perfil avisa em vez de pagar zero em silêncio", () => {
  const semValor: WorkProfile = { ...porHora, modo_pagamento: "diaria", valor_diaria: 0 };
  const a = apurar(semValor, [{ data: "2026-08-18", tipo: "diaria" }]);
  assert(a.avisos.length > 0, "precisa avisar que falta o valor da diária");
});

Deno.test("dias do período separa úteis de domingos", () => {
  // 17/08 (seg) a 23/08 (dom) de 2026: 6 úteis + 1 domingo
  const d = diasDoPeriodo("2026-08-17", "2026-08-23");
  assertEquals(d.diasUteis, 6);
  assertEquals(d.domingosEFeriados, 1);
});

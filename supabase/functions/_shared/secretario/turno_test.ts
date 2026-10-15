// A chave e o calendário da tarde (secretário, Passo 3): que turno é cada dia, o dia da revisão do mês quando o
// dia 1 cai em domingo/feriado, a revisão da semana que cede o dia à do mês, e o dia da pergunta da sexta.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  diaDaRevisaoDaSemana,
  diaDaRevisaoDoMes,
  ehDiaDaPerguntaDaSemana,
  lerFormatoDoFechamento,
  lerTurnoPedido,
  proximoDiaComManha,
  turnoDaTarde,
} from "./turno.ts";

Deno.test("lerFormatoDoFechamento: ausente, inválido ou erro = desligado", () => {
  assertEquals(lerFormatoDoFechamento("sombra"), "sombra");
  assertEquals(lerFormatoDoFechamento(" Ligado "), "ligado");
  assertEquals(lerFormatoDoFechamento('"ligado"'), "ligado");
  for (const v of ["desligado", "", "novo", "on", null, undefined, 1, "antigo"]) assertEquals(lerFormatoDoFechamento(v), "desligado", String(v));
});

Deno.test("lerTurnoPedido: tarde ou um turno; o resto é null", () => {
  assertEquals(lerTurnoPedido("tarde"), "tarde");
  assertEquals(lerTurnoPedido("FECHAMENTO"), "fechamento");
  assertEquals(lerTurnoPedido("revisao_semana"), "revisao_semana");
  assertEquals(lerTurnoPedido("revisao_mes"), "revisao_mes");
  for (const v of ["", "manha", "1", null]) assertEquals(lerTurnoPedido(v), null, String(v));
});

Deno.test("turnoDaTarde: outubro e novembro de 2026", () => {
  const casos: Array<[string, string | null]> = [
    ["2026-10-01", "revisao_mes"], // quinta, 1º dia útil do mês
    ["2026-10-02", "fechamento"],
    ["2026-10-05", "revisao_semana"], // segunda
    ["2026-10-12", null], // segunda, Nossa Senhora Aparecida
    ["2026-10-13", "revisao_semana"], // terça: a segunda foi feriado
    ["2026-10-14", "fechamento"],
    ["2026-10-15", "fechamento"],
    ["2026-10-16", "fechamento"], // sexta (com a pergunta)
    ["2026-10-17", null], // sábado
    ["2026-10-18", null], // domingo
    ["2026-10-19", "revisao_semana"],
    ["2026-11-02", null], // segunda, Finados
    ["2026-11-03", "revisao_mes"], // o dia 1 foi domingo e o 2 feriado: o 1º dia útil
    ["2026-11-04", "revisao_semana"], // a revisão da semana cede a terça à do mês
    ["2026-11-05", "fechamento"],
  ];
  for (const [dia, turno] of casos) assertEquals(turnoDaTarde(dia), turno, dia);
});

Deno.test("revisão do mês no 1º dia útil (dia 1 em sábado, domingo ou feriado) e a da semana no dia seguinte", () => {
  assertEquals(diaDaRevisaoDoMes("2026-11-20"), "2026-11-03");
  assertEquals(diaDaRevisaoDoMes("2027-01-15"), "2027-01-04"); // 01/01 feriado (sexta)
  assertEquals(diaDaRevisaoDoMes("2026-08-10"), "2026-08-03"); // 01/08 sábado
  assertEquals(turnoDaTarde("2026-08-03"), "revisao_mes");
  assertEquals(turnoDaTarde("2026-08-04"), "revisao_semana");
  assertEquals(diaDaRevisaoDaSemana("2026-10-21"), "2026-10-19");
  assertEquals(diaDaRevisaoDaSemana("2026-11-06"), "2026-11-04");
  // nunca duas revisões no mesmo dia, de 2026 a 2027
  for (let i = 0; i < 730; i++) {
    const d = new Date(Date.UTC(2026, 0, 1 + i)).toISOString().slice(0, 10);
    if (turnoDaTarde(d) === "revisao_semana") assertEquals(d === diaDaRevisaoDoMes(d), false, d);
  }
});

Deno.test("a pergunta da sexta vai no último dia útil da semana (quinta, se a sexta é feriado)", () => {
  assertEquals(ehDiaDaPerguntaDaSemana("2026-10-16"), true);
  assertEquals(ehDiaDaPerguntaDaSemana("2026-10-15"), false);
  assertEquals(ehDiaDaPerguntaDaSemana("2026-10-17"), false); // sábado
  // Sexta-feira Santa de 2027 = 26/03: a pergunta vai na quinta, 25/03
  assertEquals(ehDiaDaPerguntaDaSemana("2027-03-26"), false);
  assertEquals(ehDiaDaPerguntaDaSemana("2027-03-25"), true);
  // 20/11/2026 (sexta, Consciência Negra): quinta 19/11
  assertEquals(ehDiaDaPerguntaDaSemana("2026-11-19"), true);
});

Deno.test("proximoDiaComManha: o 'Amanhã' do fechamento (sábado tem manhã; domingo e feriado não)", () => {
  assertEquals(proximoDiaComManha("2026-10-15"), "2026-10-16");
  assertEquals(proximoDiaComManha("2026-10-16"), "2026-10-17"); // sábado
  assertEquals(proximoDiaComManha("2026-10-10"), "2026-10-13"); // domingo 11 e feriado 12
  assertEquals(proximoDiaComManha("2026-10-30"), "2026-10-31");
  assertEquals(proximoDiaComManha("2026-10-31"), "2026-11-03");
});

// Os horários do dono (secretário, Passo 4, 15/10/2026). O que se protege: a janela da manhã (07:30–09:30)
// e a do acorde (08–20) em Brasília em qualquer máquina; a próxima mensagem fixa igual à do SQL
// (_aviso_proxima_mensagem, os mesmos 12 casos do teste avisos_do_dono.sql A7); a chave semanal.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  acordeComCartao, depoisDaJanelaDaManha, emBrasilia, naJanelaDaManha, podeAcordar, proximaMensagemFixa, segundaDaSemana,
} from "./janela.ts";

const br = (s: string) => new Date(`${s}-03:00`);

Deno.test("emBrasilia: 23:30 de Brasília ainda é o mesmo dia (02:30 UTC do seguinte)", () => {
  assertEquals(emBrasilia(new Date("2026-10-22T02:30:00Z")), { dia: "2026-10-21", dow: 3, min: 23 * 60 + 30 });
});

Deno.test("janela da manhã: 07:30–09:29 sim; 07:29 e 09:30 não", () => {
  assert(!naJanelaDaManha(br("2026-10-21T07:29:00")));
  assert(naJanelaDaManha(br("2026-10-21T07:30:00")));
  assert(naJanelaDaManha(br("2026-10-21T09:29:59")));
  assert(!naJanelaDaManha(br("2026-10-21T09:30:00")));
  assert(!depoisDaJanelaDaManha(br("2026-10-21T09:29:00")));
  assert(depoisDaJanelaDaManha(br("2026-10-21T09:30:00")));
});

Deno.test("acorde: 08:00–19:59; cartão só depois das 09:30", () => {
  assert(!podeAcordar(br("2026-10-21T07:59:00")));
  assert(podeAcordar(br("2026-10-21T08:00:00")));
  assert(podeAcordar(br("2026-10-21T19:59:00")));
  assert(!podeAcordar(br("2026-10-21T20:00:00")));
  assert(!acordeComCartao(br("2026-10-21T08:10:00")), "08:10: acorda sem cartão");
  assert(!acordeComCartao(br("2026-10-21T09:29:00")));
  assert(acordeComCartao(br("2026-10-21T09:30:00")));
  assert(!acordeComCartao(br("2026-10-21T20:30:00")));
});

Deno.test("próxima mensagem fixa: os 12 casos do SQL (A7)", () => {
  const casos: Array<[string, "proxima_fixa" | "hoje" | "escritorio", "domingo" | "segunda", string, string]> = [
    ["2026-10-23T17:31:00", "proxima_fixa", "domingo", "manha", "2026-10-24T07:30:00"],
    ["2026-10-23T17:29:00", "proxima_fixa", "domingo", "fechamento", "2026-10-23T17:30:00"],
    ["2026-10-24T10:00:00", "proxima_fixa", "domingo", "manha", "2026-10-25T07:30:00"],
    ["2026-10-24T18:00:00", "proxima_fixa", "segunda", "manha", "2026-10-26T07:30:00"],
    ["2026-10-25T07:00:00", "proxima_fixa", "domingo", "manha", "2026-10-25T07:30:00"],
    ["2026-10-25T10:00:00", "proxima_fixa", "domingo", "manha", "2026-10-26T07:30:00"],
    ["2026-10-21T23:30:00", "proxima_fixa", "domingo", "manha", "2026-10-22T07:30:00"],
    ["2026-10-21T10:00:00", "escritorio", "domingo", "fechamento", "2026-10-21T17:30:00"],
    ["2026-10-23T18:00:00", "escritorio", "domingo", "fechamento", "2026-10-26T17:30:00"],
    ["2026-10-24T09:00:00", "escritorio", "domingo", "fechamento", "2026-10-26T17:30:00"],
    ["2026-10-19T06:00:00", "hoje", "domingo", "manha", "2026-10-19T07:30:00"],
    ["2026-10-19T10:00:00", "hoje", "domingo", "manha", "2026-10-20T07:30:00"],
  ];
  for (const [agora, destino, sabado, mensagem, aPartir] of casos) {
    const r = proximaMensagemFixa(br(agora), destino, sabado);
    assertEquals({ mensagem: r.mensagem, aPartirDe: r.aPartirDe.toISOString() }, { mensagem, aPartirDe: br(aPartir).toISOString() },
      `${agora} ${destino} ${sabado}`);
  }
});

Deno.test("acorde fora da janela vai para a próxima fixa: 07:59 de dia útil → fechamento; 20:00 → manhã de amanhã", () => {
  assertEquals(proximaMensagemFixa(br("2026-10-21T07:59:00"), "proxima_fixa").mensagem, "fechamento");
  assertEquals(proximaMensagemFixa(br("2026-10-21T20:00:00"), "proxima_fixa").aPartirDe.toISOString(), br("2026-10-22T07:30:00").toISOString());
});

Deno.test("segunda da semana (chave semanal)", () => {
  assertEquals(segundaDaSemana("2026-10-19"), "2026-10-19");
  assertEquals(segundaDaSemana("2026-10-21"), "2026-10-19");
  assertEquals(segundaDaSemana("2026-10-25"), "2026-10-19", "domingo fecha a semana");
  assertEquals(segundaDaSemana("2026-10-26"), "2026-10-26");
});

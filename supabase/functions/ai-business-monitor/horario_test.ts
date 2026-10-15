// Vigia do negócio (15/10/2026): o que se protege — o dia da chave é o de Brasília (o aviso de
// orçamentos parados saía às 21:10 porque o dia UTC já tinha virado); nada sai fora das 8h–20h; o
// mês começa à meia-noite de Brasília; o aviso "o resumo não chegou" só vai para quem ficou sem
// resumo e para de tentar antes das 20h.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  diaDoAviso, horaBrasilia, inicioDoDiaBR, inicioDoMesBR, podeAvisarAgora, resumoDeHojeCobre,
  tentativasAteAs20h, telefonesSemResumo, TEXTO_RESUMO_NAO_CHEGOU,
} from "./horario.ts";

Deno.test("21:05 de Brasília (00:05 UTC do dia seguinte): fora do horário, e o dia é o de Brasília", () => {
  // A rodada que reivindicou `stale_quotes:2026-10-15` em 14/10 às 21:05 (ai_operator_alerts_log).
  const rodada = new Date("2026-10-15T00:05:03Z");
  assertEquals(horaBrasilia(rodada), 21);
  assertEquals(podeAvisarAgora(rodada), false);
  assertEquals(diaDoAviso(rodada), "2026-10-14");
  // A conta antiga dava o dia seguinte — era essa a chave nova que soltava o aviso às 21:10.
  assertEquals(rodada.toISOString().slice(0, 10), "2026-10-15");
});

Deno.test("janela 8h–20h de Brasília: 08:05 e 19:59 avisam; 07:59, 20:00 e 06:05 não", () => {
  assert(podeAvisarAgora(new Date("2026-10-15T11:05:00Z")), "08:05");
  assert(podeAvisarAgora(new Date("2026-10-15T22:59:00Z")), "19:59");
  assert(!podeAvisarAgora(new Date("2026-10-15T23:00:00Z")), "20:00");
  assert(!podeAvisarAgora(new Date("2026-10-15T10:59:00Z")), "07:59");
  // O "saldo do banco não bate" de 13 e 15/10 saiu às 06:05.
  assert(!podeAvisarAgora(new Date("2026-10-15T09:05:03Z")), "06:05");
  assertEquals(diaDoAviso(new Date("2026-10-15T11:05:00Z")), "2026-10-15");
});

Deno.test("início do dia e do mês: meia-noite de Brasília, não o relógio do servidor", () => {
  // 01/11 00:30 UTC ainda é 31/10 21:30 em Brasília: o mês é outubro.
  assertEquals(inicioDoMesBR(new Date("2026-11-01T00:30:00Z")), "2026-10-01T03:00:00.000Z");
  assertEquals(inicioDoMesBR(new Date("2026-11-01T03:00:00Z")), "2026-11-01T03:00:00.000Z");
  assertEquals(inicioDoDiaBR(new Date("2026-10-15T02:00:00Z")), "2026-10-14T03:00:00.000Z");
  assertEquals(inicioDoDiaBR(new Date("2026-10-15T11:05:00Z")), "2026-10-15T03:00:00.000Z");
});

Deno.test("tentativas até as 20h: 10 em 10 min depois da 1ª; nunca menos que 1", () => {
  // 09:05: 1ª às ~09:10, a 66ª às ~20:00.
  assertEquals(tentativasAteAs20h(new Date("2026-10-15T12:05:00Z")), 66);
  // 19:05: 19:10, 19:20 … 20:00.
  assertEquals(tentativasAteAs20h(new Date("2026-10-15T22:05:00Z")), 6);
  assertEquals(tentativasAteAs20h(new Date("2026-10-15T22:58:00Z")), 1);
});

Deno.test("resumo que não chegou: só quem ficou sem resumo de hoje, uma vez cada", () => {
  // 09/10 e 13/10: o único resumo do dia desistiu (failed).
  assertEquals(telefonesSemResumo([{ phone_normalized: "5547999990000", status: "failed" }]), ["5547999990000"]);
  assertEquals(
    telefonesSemResumo([
      { phone_normalized: "A", status: "failed" },
      { phone_normalized: "B", status: "sent" },
      { phone_normalized: "A", status: "failed" },
      { phone_normalized: null, status: "failed" },
    ]),
    ["A"],
  );
  // Outro resumo do mesmo telefone chegou ou ainda está na fila: nada a avisar.
  assertEquals(telefonesSemResumo([{ phone_normalized: "A", status: "failed" }, { phone_normalized: "A", status: "sent" }]), []);
  assertEquals(telefonesSemResumo([{ phone_normalized: "A", status: "failed" }, { phone_normalized: "A", status: "pending" }]), []);
  // Dia normal (entregue): nada.
  assertEquals(telefonesSemResumo([{ phone_normalized: "A", status: "sent" }]), []);
  assertStringIncludes(TEXTO_RESUMO_NAO_CHEGOU, "não chegou");
  assertStringIncludes(TEXTO_RESUMO_NAO_CHEGOU, "*como estão as coisas?*");
});

Deno.test("orçamentos parados: o resumo de hoje cobre quando foi entregue ou ainda está a caminho", () => {
  assertEquals(resumoDeHojeCobre([]), false, "sem resumo hoje");
  assertEquals(resumoDeHojeCobre([{ phone_normalized: "A", status: "failed" }]), false, "o resumo desistiu");
  assertEquals(resumoDeHojeCobre([{ phone_normalized: "A", status: "sent" }]), true);
  assertEquals(resumoDeHojeCobre([{ phone_normalized: "A", status: "pending" }]), true);
});

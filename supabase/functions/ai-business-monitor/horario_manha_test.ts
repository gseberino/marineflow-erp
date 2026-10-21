// (20/10/2026) A manhã que quebrou ANTES de entrar na fila (spec uma voz §1.7-1): o ai-daily-briefing caiu antes do
// insert, não existe linha ai_briefing e ninguém era avisado (telefonesSemResumo só olha a linha 'failed'). O que se
// protege: depois das 08:00 de Brasília, nenhuma linha do dono = "a manhã não chegou"; antes das 08:00 (a manhã pode
// estar saindo), com qualquer linha dele (enviada, na fila ou falhada — a falhada é a outra regra) ou sem o dono lido,
// não; a hora é a de Brasília em qualquer máquina; o texto não culpa o WhatsApp. A conta das tentativas mora em
// _shared/uma-voz/janela.ts e o vigia reexporta a mesma.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { MANHA_SEM_LINHA_DESDE_MIN, manhaSemLinha, tentativasAteAs20h, TEXTO_MANHA_QUEBROU } from "./horario.ts";
import { tentativasAteAs20h as daJanela } from "../_shared/uma-voz/janela.ts";

const DONO = "5547900009654";

Deno.test("manhã sem linha: depois das 08:00 e nenhuma linha do dono = não chegou", () => {
  assertEquals(manhaSemLinha([], DONO, new Date("2026-10-21T11:05:00Z")), true, "08:05, fila vazia");
  assertEquals(manhaSemLinha([{ phone_normalized: "5547900000001", status: "sent" }], DONO, new Date("2026-10-21T11:05:00Z")), true, "só a linha de outro (financeiro)");
  assertEquals(manhaSemLinha([], DONO, new Date("2026-10-21T22:05:00Z")), true, "19:05 também");
});

Deno.test("manhã sem linha: antes das 08:00, com qualquer linha do dono ou sem o dono lido = não", () => {
  assertEquals(manhaSemLinha([], DONO, new Date("2026-10-21T10:59:00Z")), false, "07:59");
  for (const status of ["sent", "pending", "sending", "failed"]) {
    assertEquals(manhaSemLinha([{ phone_normalized: DONO, status }], DONO, new Date("2026-10-21T11:05:00Z")), false, status);
  }
  assertEquals(manhaSemLinha([], null, new Date("2026-10-21T11:05:00Z")), false);
  assertEquals(manhaSemLinha([], undefined, new Date("2026-10-21T11:05:00Z")), false);
  assertEquals(MANHA_SEM_LINHA_DESDE_MIN, 8 * 60);
});

Deno.test("o texto da manhã que quebrou não culpa o WhatsApp e oferece o panorama", () => {
  assertStringIncludes(TEXTO_MANHA_QUEBROU, "não chegou");
  assertStringIncludes(TEXTO_MANHA_QUEBROU, "erro");
  assertStringIncludes(TEXTO_MANHA_QUEBROU, "*como estão as coisas?*");
  assertEquals(TEXTO_MANHA_QUEBROU.includes("WhatsApp"), false);
});

Deno.test("as tentativas até as 20h: o vigia e a voz única usam a MESMA conta (janela.ts)", () => {
  for (const iso of ["2026-10-15T12:05:00Z", "2026-10-15T22:05:00Z", "2026-10-15T22:58:00Z", "2026-10-21T11:00:00Z"]) {
    assertEquals(tentativasAteAs20h(new Date(iso)), daJanela(new Date(iso)), iso);
  }
  assertEquals(tentativasAteAs20h(new Date("2026-10-15T12:05:00Z")), 66);
});

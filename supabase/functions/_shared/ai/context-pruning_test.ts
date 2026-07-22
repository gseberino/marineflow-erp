import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { podarHistoricoParaLLM, PODAR_APOS, TOOL_RESULT_MAX, type PrunableMessage } from "./context-pruning.ts";

const toolMsg = (n: number, len: number): PrunableMessage => ({ role: "tool", tool_call_id: `t${n}`, content: "x".repeat(len) });
const userMsg = (t: string): PrunableMessage => ({ role: "user", content: t });

Deno.test("mantém as últimas mensagens intactas", () => {
  const msgs = Array.from({ length: PODAR_APOS + 3 }, (_, i) => toolMsg(i, 5000));
  const out = podarHistoricoParaLLM(msgs);
  // As PODAR_APOS finais ficam completas
  for (let i = msgs.length - PODAR_APOS; i < msgs.length; i++) {
    assertEquals(out[i].content.length, 5000);
  }
});

Deno.test("abrevia resultados de tool ANTIGOS grandes", () => {
  const msgs = Array.from({ length: PODAR_APOS + 2 }, (_, i) => toolMsg(i, 5000));
  const out = podarHistoricoParaLLM(msgs);
  // O primeiro (antigo) foi abreviado
  assertEquals(out[0].content.length <= TOOL_RESULT_MAX + 40, true);
  assertEquals(out[0].content.includes("abreviado"), true);
});

Deno.test("não mexe em resultado antigo pequeno", () => {
  const msgs = [toolMsg(0, 100), ...Array.from({ length: PODAR_APOS }, (_, i) => userMsg(`m${i}`))];
  const out = podarHistoricoParaLLM(msgs);
  assertEquals(out[0].content.length, 100);
});

Deno.test("nunca remove mensagem (mesma quantidade e mesmos papéis)", () => {
  const msgs = [toolMsg(0, 5000), userMsg("a"), toolMsg(1, 5000), userMsg("b")];
  const out = podarHistoricoParaLLM(msgs);
  assertEquals(out.length, msgs.length);
  assertEquals(out.map((m) => m.role), msgs.map((m) => m.role));
});

Deno.test("nunca abrevia mensagem de usuário/assistant, só tool", () => {
  const msgs = [userMsg("y".repeat(5000)), ...Array.from({ length: PODAR_APOS }, () => userMsg("x"))];
  const out = podarHistoricoParaLLM(msgs);
  assertEquals(out[0].content.length, 5000); // user antigo NÃO é podado
});

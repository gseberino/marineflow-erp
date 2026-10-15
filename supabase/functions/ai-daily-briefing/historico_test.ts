import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { linhasDoHistorico } from "./historico.ts";
import { aparaJanela } from "../_shared/ai/history-window.ts";

const AGORA = new Date("2026-10-15T10:30:12.345Z"); // 07:30 de Brasília
const RESUMO = "☀️ *Bom dia! Resumo de quinta-feira, 15 de outubro*\n\n📄 Orçamentos aguardando resposta: *3*";

Deno.test("linhasDoHistorico: duas linhas, a marca do sistema antes do resumo, carimbos diferentes", () => {
  const l = linhasDoHistorico("sessao-1", RESUMO, AGORA);
  assertEquals(l.length, 2);
  assertEquals(l.map((x) => x.role), ["user", "assistant"]);
  assertEquals(l.map((x) => x.source), ["system", "system"]);
  assertEquals(l.every((x) => x.session_id === "sessao-1"), true);
  assert(l[0].created_at < l[1].created_at, "a ordem não pode empatar");
  assertEquals(l[1].content, RESUMO);
});

Deno.test("linhasDoHistorico: a marca diz que não é do dono, a hora de Brasília e o 'cobra esse'", () => {
  const [marca] = linhasDoHistorico("s", RESUMO, AGORA);
  assertStringIncludes(marca.content, "[Mensagem automática do sistema, não é do dono]");
  assertStringIncludes(marca.content, "Às 07:30");
  assertStringIncludes(marca.content, "cobra esse");
  // Gravado na hora de entrar na fila: não pode afirmar que chegou (09 e 13/10/2026 não chegou).
  assertStringIncludes(marca.content, "a entrega não é confirmada aqui");
  assert(!/enviou ao dono/.test(marca.content));
});

Deno.test("linhasDoHistorico: a janela do assistente mantém as duas linhas (começa na fala 'user')", () => {
  const linhas = linhasDoHistorico("s", RESUMO, AGORA).map((x) => ({
    role: x.role, content: x.content, tool_calls: null, tool_call_id: null, created_at: x.created_at,
  }));
  assertEquals(aparaJanela(linhas).length, 2);
});

Deno.test("linhasDoHistorico (Passo 3): sem o 4º parâmetro, a marca da manhã é a de sempre; a tarde diz o nome dela", () => {
  const [manha] = linhasDoHistorico("s", RESUMO, AGORA);
  assertEquals(manha.content,
    "[Mensagem automática do sistema, não é do dono] Às 07:30 o sistema mandou para o WhatsApp do dono o resumo da manhã abaixo (a entrega não é confirmada aqui: se ele disser que não chegou, é possível). Se ele citar um item (\"cobra esse\", \"o 2\"), é deste resumo.");
  const [tarde] = linhasDoHistorico("s", "Fechamento de quinta…", new Date("2026-10-15T20:30:00Z"), "o fechamento das 17:30");
  assertStringIncludes(tarde.content, "Às 17:30 o sistema mandou para o WhatsApp do dono o fechamento das 17:30 abaixo");
});

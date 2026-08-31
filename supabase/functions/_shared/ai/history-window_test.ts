import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aparaJanela, TAMANHO_DA_JANELA, type LinhaHistorico } from "./history-window.ts";

// O que estes testes protegem: a janela volta para a API da Anthropic, que rejeita com 400 tanto
// um `tool_result` sem o `tool_use` que o originou quanto um `tool_use` sem resultado. Cortar as
// N mais recentes de uma conversa corta exatamente nesses pontos — é o risco de inverter a ordem.

const u = (t: string): LinhaHistorico => ({ role: "user", content: t, tool_calls: null, tool_call_id: null });
const a = (t: string): LinhaHistorico => ({ role: "assistant", content: t, tool_calls: null, tool_call_id: null });
const aT = (t: string, n = 1): LinhaHistorico => ({
  role: "assistant",
  content: t,
  tool_calls: Array.from({ length: n }, (_, i) => ({
    id: `tc${i}`, type: "function" as const, function: { name: "x", arguments: "{}" },
  })),
  tool_call_id: null,
});
const tR = (t: string): LinhaHistorico => ({ role: "tool", content: t, tool_calls: null, tool_call_id: "tc0" });

Deno.test("conversa completa e bem-formada passa inteira", () => {
  const linhas = [u("oi"), aT("busco"), tR("{}"), a("achei")];
  assertEquals(aparaJanela(linhas).length, 4);
});

Deno.test("tool_result órfão no INÍCIO é descartado — é o corte que a API recusa", () => {
  // A janela pegou o meio de um turno: o tool_use ficou para trás.
  const linhas = [tR("{}"), tR("{}"), a("pronto"), u("proximo"), a("ok")];
  const r = aparaJanela(linhas);
  assertEquals(r[0].role, "user");
  assertEquals(r.length, 2);
});

Deno.test("assistant no início sem a fala do usuário também é descartado", () => {
  const linhas = [a("continuando"), u("agora sim"), a("ok")];
  const r = aparaJanela(linhas);
  assertEquals(r[0].content, "agora sim");
  assertEquals(r.length, 2);
});

Deno.test("tool_use pendente no FIM é derrubado — turno interrompido não volta pela metade", () => {
  const linhas = [u("oi"), a("ok"), u("faz"), aT("vou chamar")];
  const r = aparaJanela(linhas);
  assertEquals(r.map((l) => l.content), ["oi", "ok", "faz"]);
});

Deno.test("tool_use com resultado no fim FICA — turno fechado é contexto válido", () => {
  const linhas = [u("oi"), aT("chamo"), tR("{}")];
  assertEquals(aparaJanela(linhas).length, 3);
});

Deno.test("dois turnos pendentes seguidos são derrubados juntos", () => {
  // Cortar o último assistant expõe outro — o laço tem que reavaliar, não parar no primeiro.
  const linhas = [u("oi"), a("ok"), aT("t1"), aT("t2")];
  const r = aparaJanela(linhas);
  assertEquals(r.map((l) => l.content), ["oi", "ok"]);
});

Deno.test("janela só com tool_result vira vazia, e não um fragmento inválido", () => {
  assertEquals(aparaJanela([tR("{}"), tR("{}")]), []);
});

Deno.test("janela vazia continua vazia", () => {
  assertEquals(aparaJanela([]), []);
});

Deno.test("a janela é maior que a antiga de 30 e olha para o lado certo", () => {
  assertEquals(TAMANHO_DA_JANELA, 60);
});

Deno.test("tool_result órfão DEPOIS da fala do usuário também some — o caso do banco real", () => {
  // Todas as linhas de um turno compartilham created_at e não há coluna de sequência, então a
  // fala do usuário volta do banco ANTES dos tool_result do turno anterior. Cortar no primeiro
  // 'user' deixava esses órfãos passarem, e a API responde 400.
  const linhas = [u("oi"), tR("{}"), tR("{}"), a("resposta"), aT("chamo"), tR("{}")];
  const r = aparaJanela(linhas);
  assertEquals(r.map((l) => l.role), ["user", "assistant", "assistant", "tool"]);
});

Deno.test("janela sem nenhum tool_use não carrega tool_result nenhum", () => {
  const linhas = [u("oi"), tR("{}"), a("ok")];
  assertEquals(aparaJanela(linhas).map((l) => l.role), ["user", "assistant"]);
});

// ── Caso REAL de produção ────────────────────────────────────────────────────────────────────
Deno.test("REGRESSÃO: as 60 últimas da sessão 3ac5b84a viram janela VÁLIDA", () => {
  // Sequência lida do banco em 31/08/2026 (A=assistant, A*=com tool_calls, U=user, t=tool_result).
  // Ela começa no meio de um turno e tem a fala do usuário embaralhada com tool_results — os dois
  // cortes que a API recusa.
  const SEQ = "A*tttA*UtttttttttttttttttttttAA*UtttttttttttA*A*A*A*A*A*UtttttttttA*A*A";
  const linhas: LinhaHistorico[] = [];
  for (let i = 0; i < SEQ.length; i++) {
    const c = SEQ[i];
    if (c === "*") continue;
    if (c === "U") linhas.push(u(`u${i}`));
    else if (c === "t") linhas.push(tR("{}"));
    else if (c === "A") linhas.push(SEQ[i + 1] === "*" ? aT(`a${i}`) : a(`a${i}`));
  }

  const r = aparaJanela(linhas);
  assertEquals(r[0].role, "user", "tem que começar numa fala do usuário");

  // Nenhum tool_result antes do primeiro tool_use.
  let vistoToolUse = false;
  for (const l of r) {
    if (l.role === "assistant" && Array.isArray(l.tool_calls) && l.tool_calls.length) vistoToolUse = true;
    assertEquals(l.role === "tool" && !vistoToolUse, false, "tool_result órfão na janela");
  }

  // Não termina com tool_use pendente.
  const ultimo = r[r.length - 1];
  assertEquals(ultimo.role === "assistant" && Array.isArray(ultimo.tool_calls) && ultimo.tool_calls.length > 0, false);

  // E, o ponto de tudo: a janela alcança o FIM da conversa.
  assertEquals(r[r.length - 1], linhas[linhas.length - 1]);
});

// ── A regressão que originou tudo ────────────────────────────────────────────────────────────
Deno.test("REGRESSÃO NOVO-agente-04: a janela alcança o FIM da conversa, não o começo", () => {
  // 236 linhas como na sessão real: a criação do orçamento na 36 e os pedidos de correção no fim.
  const conversa: LinhaHistorico[] = [];
  conversa.push(u("Preciso montar um orçamento para cliente final, veículo Motorhome"));
  for (let i = 0; i < 34; i++) conversa.push(a(`levantamento ${i}`));
  conversa.push(aT("criar orçamento"));
  conversa.push(tR('{"ok":true,"orcamento":"ORÇ-00086"}'));   // linha 37
  for (let i = 0; i < 196; i++) conversa.push(a(`trabalho ${i}`));
  conversa.push(u("conserte os itens que estão na lista errada"));

  // Comportamento ANTIGO (ascending + limit 30): as 30 primeiras.
  const antiga = conversa.slice(0, 30);
  assertEquals(antiga.some((l) => (l.content || "").includes("ORÇ-00086")), false);
  assertEquals(antiga[antiga.length - 1].content, "levantamento 28");

  // Comportamento NOVO: as 60 mais recentes, em ordem cronológica, aparadas.
  const nova = aparaJanela(conversa.slice(-60));
  assertEquals(nova[nova.length - 1].content, "conserte os itens que estão na lista errada");
  // E o corte é seguro: começa numa fala do usuário.
  assertEquals(nova.length > 0 && nova[0].role, "user");
});

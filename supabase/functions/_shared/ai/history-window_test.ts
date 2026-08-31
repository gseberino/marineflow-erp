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

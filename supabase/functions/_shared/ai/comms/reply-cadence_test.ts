import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { classificarResposta } from "./reply-router.ts";
import { espacamentoMinimoDias, MAX_TOQUES, podeTocarAgora } from "./cadence.ts";

// ---- reply-router ----
Deno.test("opt-out tem precedência e manda marcar opt_out", () => {
  const r = classificarResposta("por favor pare de me mandar mensagem");
  assertEquals(r.intencao, "opt_out");
  assertEquals(r.manejo.includes("opt_out_whatsapp"), true);
});

Deno.test("disputa manda NÃO reenviar e escalar", () => {
  assertEquals(classificarResposta("eu já paguei isso semana passada").intencao, "disputa");
  assertEquals(classificarResposta("o serviço deu problema, não vou pagar").intencao, "disputa");
  assertEquals(classificarResposta("essa cobrança está errada").intencao, "disputa");
});

Deno.test("acordo é reconhecido", () => {
  assertEquals(classificarResposta("pode mandar o pix").intencao, "acordo");
  assertEquals(classificarResposta("fechado, vou pagar hoje").intencao, "acordo");
});

Deno.test("cotação parcial do fornecedor", () => {
  assertEquals(classificarResposta("só tenho o item 1 e 3").intencao, "cotacao_parcial");
  assertEquals(classificarResposta("não trabalho com esse modelo").intencao, "cotacao_parcial");
});

Deno.test("pergunta é detectada por '?' e por interrogativos", () => {
  assertEquals(classificarResposta("qual a bitola do cabo?").intencao, "pergunta");
  assertEquals(classificarResposta("vocês têm em estoque").intencao, "pergunta");
});

Deno.test("mensagem neutra vira 'outro'", () => {
  assertEquals(classificarResposta("bom dia, obrigado").intencao, "outro");
});

// ---- cadence ----
Deno.test("teto de toques bloqueia", () => {
  assertEquals(podeTocarAgora(MAX_TOQUES, new Date().toISOString()).permitido, false);
});

Deno.test("primeiro toque sempre permitido", () => {
  assertEquals(podeTocarAgora(0, null).permitido, true);
});

Deno.test("muito cedo bloqueia; passado o espaçamento libera", () => {
  const ontem = new Date(Date.now() - 1 * 86400000).toISOString();      // 1 dia < 2
  const tresDias = new Date(Date.now() - 3 * 86400000).toISOString();   // 3 dias >= 2
  assertEquals(podeTocarAgora(1, ontem).permitido, false);
  assertEquals(podeTocarAgora(1, tresDias).permitido, true);
});

Deno.test("espaçamento cresce nos toques mais tardios", () => {
  assertEquals(espacamentoMinimoDias(1), 2);
  assertEquals(espacamentoMinimoDias(4), 4);
});

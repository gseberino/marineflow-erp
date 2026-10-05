import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { respostaDoTurnoNoWhatsApp } from "./whatsapp-resposta.ts";

const antes = { pendencia_herdada: true, pending_confirm_action_id: "velha", pending_options: [{ label: "x", value: "y" }], outro: 1 };

Deno.test("texto: zera a pendência e mantém o resto do metadata", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "Pronto." }, antes);
  assertEquals(r.replyText, "Pronto.");
  assertEquals(r.metadata.pending_confirm_action_id, null);
  assertEquals(r.metadata.pendencia_herdada, false);
  assertEquals(r.metadata.outro, 1);
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "" }, {}).replyText, "Ok.");
});

Deno.test("pendência: pede confirmação e guarda o id para o SIM", () => {
  const r = respostaDoTurnoNoWhatsApp(
    { texto: "", proposal: { pending_action_id: "p1", title: "Enviar PDF ao cliente", summary_markdown: "ORÇ-00110 para Lenine", risk_level: "high" } },
    antes,
  );
  assertStringIncludes(r.replyText, "⚠️ Enviar PDF ao cliente\nORÇ-00110 para Lenine");
  assertEquals(r.metadata.pending_confirm_action_id, "p1");
  assertEquals(r.metadata.pin_attempts, 0);
  assertEquals(r.metadata.pending_options, null);
});

Deno.test("opções: lista numerada e guarda as opções", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "", options: { question: "Qual cliente?", options: [{ label: "A", value: "1" }, { label: "B", value: "2" }] } }, {});
  assertStringIncludes(r.replyText, "Qual cliente?");
  assertEquals(r.metadata.pending_options, [{ label: "A", value: "1" }, { label: "B", value: "2" }]);
});

Deno.test("erro vem na frente de tudo", () => {
  const r = respostaDoTurnoNoWhatsApp({ texto: "x", error: "Falha ao chamar a Anthropic API" }, antes);
  assertEquals(r.replyText, "⚠️ Falha ao chamar a Anthropic API");
  assertEquals(r.metadata.pending_confirm_action_id, null);
});

Deno.test("texto com pendência VIVA: guarda a referência e lembra dela (05/10/2026)", () => {
  const viva = { title: "Enviar orçamento/OS ao cliente (WhatsApp)", risk_level: "high" };
  const t = respostaDoTurnoNoWhatsApp({ texto: "Não consigo tirar o link desse formato." }, antes, viva);
  assertEquals(t.metadata.pending_confirm_action_id, "velha");
  assertEquals(t.metadata.pendencia_herdada, true, "sim sem PIN reapresenta em vez de executar");
  assertStringIncludes(t.replyText, "Não consigo tirar o link desse formato.");
  assertStringIncludes(t.replyText, "⏳ Ainda espera a sua resposta: *Enviar orçamento/OS ao cliente (WhatsApp)*");
  assertStringIncludes(t.replyText, "Para rejeitar: *não*");
  // Sem pendência viva (resolvida ou expirada), zera como sempre.
  assertEquals(respostaDoTurnoNoWhatsApp({ texto: "ok" }, antes, null).metadata.pending_confirm_action_id, null);
  // Pendência nova manda sobre a viva.
  const nova = respostaDoTurnoNoWhatsApp(
    { texto: "", proposal: { pending_action_id: "p2", title: "Enviar só o PDF", summary_markdown: "ORÇ-00113", risk_level: "high" } },
    antes,
    viva,
  );
  assertEquals(nova.metadata.pending_confirm_action_id, "p2");
});

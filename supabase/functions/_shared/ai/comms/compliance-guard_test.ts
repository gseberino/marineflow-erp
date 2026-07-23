import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { checarConformidade } from "./compliance-guard.ts";

Deno.test("horário: cliente às 22h é bloqueado; às 10h passa", () => {
  assertEquals(checarConformidade({ tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", horaBrasilia: 22, destinatarioIdentificado: true })?.codigo, "fora_de_horario");
  assertEquals(checarConformidade({ tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", horaBrasilia: 10, destinatarioIdentificado: true }), null);
});

Deno.test("horário: 7h (antes das 8) bloqueia; 8h passa; 20h bloqueia", () => {
  assertEquals(checarConformidade({ tipo: "cotacao", audiencia: "fornecedor", canal: "whatsapp", horaBrasilia: 7 })?.codigo, "fora_de_horario");
  assertEquals(checarConformidade({ tipo: "cotacao", audiencia: "fornecedor", canal: "whatsapp", horaBrasilia: 8 }), null);
  assertEquals(checarConformidade({ tipo: "cotacao", audiencia: "fornecedor", canal: "whatsapp", horaBrasilia: 20 })?.codigo, "fora_de_horario");
});

Deno.test("dono/painel não sofre trava de horário (interno)", () => {
  assertEquals(checarConformidade({ tipo: "generico", audiencia: "dono", canal: "panel", horaBrasilia: 23 }), null);
});

Deno.test("cobrança a número não identificado é bloqueada", () => {
  const v = checarConformidade({ tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", horaBrasilia: 10, destinatarioIdentificado: false });
  assertEquals(v?.codigo, "destinatario_nao_identificado");
});

Deno.test("preço para técnico é bloqueado", () => {
  const v = checarConformidade({ tipo: "generico", audiencia: "tecnico", canal: "whatsapp", horaBrasilia: 10, texto: "Beleza, o total ficou R$ 1.200" });
  assertEquals(v?.codigo, "preco_a_tecnico");
});

Deno.test("mensagem operacional ao técnico (sem preço) passa", () => {
  const v = checarConformidade({ tipo: "generico", audiencia: "tecnico", canal: "whatsapp", horaBrasilia: 10, texto: "Você consegue passar na OS-42 amanhã 9h? Endereço na agenda." });
  assertEquals(v, null);
});

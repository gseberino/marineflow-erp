import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { STATUS_INJETAVEL, colunaDaEntidade, podeInjetar } from "./memory-scope.ts";

// A regra que protege o usuário: uma anotação que ele NÃO aprovou jamais pode
// influenciar a resposta do agente.

Deno.test("mapeia cada tipo de entidade para a coluna certa", () => {
  assertEquals(colunaDaEntidade("client"), "client_id");
  assertEquals(colunaDaEntidade("vessel"), "vessel_id");
  assertEquals(colunaDaEntidade("supplier"), "supplier_id");
});

Deno.test("tipo desconhecido não vira coluna (nada é carregado)", () => {
  assertEquals(colunaDaEntidade("service_order"), null);
  assertEquals(colunaDaEntidade("qualquer_coisa"), null);
  assertEquals(colunaDaEntidade(null), null);
  assertEquals(colunaDaEntidade(undefined), null);
  assertEquals(colunaDaEntidade(""), null);
});

Deno.test("SÓ nota aprovada entra no contexto", () => {
  assertEquals(podeInjetar({ verification_status: STATUS_INJETAVEL }), true);
});

Deno.test("sugestão pendente NUNCA entra no contexto", () => {
  assertEquals(podeInjetar({ verification_status: "candidate" }), false);
});

Deno.test("nota rejeitada NUNCA entra no contexto", () => {
  assertEquals(podeInjetar({ verification_status: "rejected" }), false);
});

Deno.test("nota sem status ou inexistente não entra", () => {
  assertEquals(podeInjetar({}), false);
  assertEquals(podeInjetar({ verification_status: null }), false);
  assertEquals(podeInjetar(null), false);
  assertEquals(podeInjetar(undefined), false);
});

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { NEVER_AUTONOMOUS, autonomyKey, isAutonomyGranted } from "./autonomy-policy.ts";

// O teto rígido é a parte que NÃO pode falhar: nenhuma configuração no banco pode fazer
// uma ação de dinheiro/destrutiva rodar sem confirmação humana.

Deno.test("ação de baixo risco sempre executa direto", () => {
  assertEquals(isAutonomyGranted("search_clients", "low", {}), true);
  assertEquals(isAutonomyGranted("search_clients", "low", undefined), true);
});

Deno.test("ação sensível pede confirmação por padrão (sem chave)", () => {
  assertEquals(isAutonomyGranted("send_collection_reminder", "high", {}), false);
  assertEquals(isAutonomyGranted("send_whatsapp_message", "medium", {}), false);
});

Deno.test("ação sensível liberável com 'auto' executa direto", () => {
  // send_service_order_link NÃO é trava permanente — o dono pode liberar (Confiança Graduada).
  // Desde 26/09/2026, só no formato 'link': o padrão virou o PDF anexado, que trava por
  // argumento (NEVER_AUTONOMOUS_WHEN). Os casos do PDF estão em tools/envio-ao-cliente_test.ts.
  const s = { [autonomyKey("send_service_order_link")]: "auto" };
  assertEquals(isAutonomyGranted("send_service_order_link", "high", s, { formato: "link" }), true);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", s), false, "sem formato = PDF = pede confirmação");
  // Outra ação liberável, sem trava por argumento, continua como sempre.
  const f = { [autonomyKey("send_supplier_quote_request")]: "auto" };
  assertEquals(isAutonomyGranted("send_supplier_quote_request", "high", f), true);
});

Deno.test("valor diferente de 'auto' mantém a confirmação", () => {
  const nome = "send_collection_reminder";
  assertEquals(isAutonomyGranted(nome, "high", { [autonomyKey(nome)]: "confirm" }), false);
  assertEquals(isAutonomyGranted(nome, "high", { [autonomyKey(nome)]: "" }), false);
  assertEquals(isAutonomyGranted(nome, "high", { [autonomyKey(nome)]: "sim" }), false);
});

Deno.test("'auto' é tolerante a espaço e maiúscula", () => {
  const nome = "send_whatsapp_message";
  assertEquals(isAutonomyGranted(nome, "medium", { [autonomyKey(nome)]: "  AUTO " }), true);
});

Deno.test("TETO RÍGIDO: ações de dinheiro/destrutivas nunca ficam autônomas, mesmo com 'auto'", () => {
  for (const nome of NEVER_AUTONOMOUS) {
    const s = { [autonomyKey(nome)]: "auto" };
    assertEquals(
      isAutonomyGranted(nome, "high", s),
      false,
      `${nome} JAMAIS pode rodar sem confirmação`,
    );
    assertEquals(isAutonomyGranted(nome, "medium", s), false, `${nome} JAMAIS pode rodar sem confirmação`);
  }
});

Deno.test("aprovar propostas de lançamento NUNCA roda sozinho, com ou sem cliente confirmado (dono, 23/10/2026)", () => {
  const nome = "aprovar_propostas_de_lancamento";
  const s = { [autonomyKey(nome)]: "auto" };
  assertEquals(NEVER_AUTONOMOUS.has(nome), true);
  assertEquals(isAutonomyGranted(nome, "high", s, { ids: ["a"], cliente_confirmado: ["a"] }), false);
  assertEquals(isAutonomyGranted(nome, "high", s, { ids: ["a"] }), false);
  assertEquals(isAutonomyGranted(nome, "high", s), false);
});

Deno.test("aplicar Pix em contas NUNCA roda sozinho — dá baixa com dinheiro do extrato (dono, 23/10/2026, 'pelo recomendado')", () => {
  const nome = "aplicar_pix_em_contas";
  const s = { [autonomyKey(nome)]: "auto" };
  assertEquals(NEVER_AUTONOMOUS.has(nome), true);
  // A tool é de risco médio: sem a trava, "auto" a liberaria.
  assertEquals(isAutonomyGranted(nome, "medium", s, { bank_transaction_id: "t", aplicacoes: [{ receivable_id: "r", valor: 10 }] }), false);
  assertEquals(isAutonomyGranted(nome, "medium", s), false);
  assertEquals(isAutonomyGranted(nome, "high", s), false);
  // Ação de risco médio fora do teto, com a mesma chave, continua liberável (o teste prova a trava, não o "auto").
  assertEquals(isAutonomyGranted("send_whatsapp_message", "medium", { [autonomyKey("send_whatsapp_message")]: "auto" }), true);
});

Deno.test("a lista de bloqueio cobre dinheiro e ações destrutivas", () => {
  for (const esperado of [
    "register_payment",
    "register_deposit_and_convert",
    "receive_purchase_order",
    "cancel_service_order",
    "reopen_service_order",
    "send_collection_reminder", // cobrança individual nunca autônoma (Confiança Graduada)
    "send_bulk_collection_reminders",
    "approve_quote_full",
  ]) {
    assertEquals(NEVER_AUTONOMOUS.has(esperado), true, `${esperado} deveria estar bloqueado`);
  }
});

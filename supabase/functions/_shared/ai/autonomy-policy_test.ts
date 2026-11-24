import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { NEVER_AUTONOMOUS, autonomyKey, isAutonomyGranted } from "./autonomy-policy.ts";
import { allTools } from "./tools/index.ts";
import { buildSystemBlocks } from "./prompt.ts";

// O teto rígido é a parte que NÃO pode falhar: nenhuma configuração no banco pode fazer
// uma ação de dinheiro/destrutiva rodar sem confirmação humana.

Deno.test("ação de baixo risco sempre executa direto", () => {
  assertEquals(isAutonomyGranted("search_clients", "low", {}), true);
  assertEquals(isAutonomyGranted("search_clients", "low", undefined), true);
});

Deno.test("ação sensível pede confirmação por padrão (sem chave)", () => {
  assertEquals(isAutonomyGranted("send_collection_reminder", "high", {}), false);
  // Ação liberável (fora do teto): sem a chave, pede o "sim". Até 24/11/2026 o exemplo era send_whatsapp_message,
  // que entrou no teto (S2) e deixaria de provar o padrão.
  assertEquals(isAutonomyGranted("update_receivable", "medium", {}), false);
  assertEquals(isAutonomyGranted("update_receivable", "medium", undefined), false);
});

Deno.test("ação sensível liberável com 'auto' executa direto", () => {
  // send_service_order_link NÃO é trava permanente — o dono pode liberar (Confiança Graduada).
  // Desde 26/09/2026, só no formato 'link': o padrão virou o PDF anexado, que trava por
  // argumento (NEVER_AUTONOMOUS_WHEN). Os casos do PDF estão em tools/envio-ao-cliente_test.ts.
  const s = { [autonomyKey("send_service_order_link")]: "auto" };
  assertEquals(isAutonomyGranted("send_service_order_link", "high", s, { formato: "link" }), true);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", s), false, "sem formato = PDF = pede confirmação");
  // Outra ação liberável, sem trava por argumento, continua como sempre. (Até 24/11/2026 o exemplo era o pedido de
  // cotação, send_supplier_quote_request, que entrou no teto por decisão do dono — S2.)
  const f = { [autonomyKey("update_payable")]: "auto" };
  assertEquals(isAutonomyGranted("update_payable", "high", f), true);
});

Deno.test("valor diferente de 'auto' mantém a confirmação", () => {
  const nome = "send_collection_reminder";
  assertEquals(isAutonomyGranted(nome, "high", { [autonomyKey(nome)]: "confirm" }), false);
  assertEquals(isAutonomyGranted(nome, "high", { [autonomyKey(nome)]: "" }), false);
  assertEquals(isAutonomyGranted(nome, "high", { [autonomyKey(nome)]: "sim" }), false);
});

Deno.test("'auto' é tolerante a espaço e maiúscula", () => {
  const nome = "update_receivable"; // era send_whatsapp_message, que entrou no teto em 24/11/2026 (S2)
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
  // Era send_whatsapp_message, que entrou no teto em 24/11/2026 (S2).
  assertEquals(isAutonomyGranted("update_receivable", "medium", { [autonomyKey("update_receivable")]: "auto" }), true);
});

// ─── Pacote 1 do assistente, S2 (24/11/2026): oito ações deixam de ser liberáveis ───────────────────────────────────
// isAutonomyGranted não olha o nível do risco: com a chave 'auto', até ação de risco alto rodava sem o "sim" e sem o
// PIN. Nota fiscal, conciliação, cancelamento de lançamento, pedido de cotação, troca de Pix/conta do favorecido,
// mensagem livre e a própria liberação de autonomia entram no teto.

const OS_OITO_DE_24_11 = [
  "emit_fiscal_note",
  "emit_fiscal_service_note",
  "conciliar_transacao",
  "cancelar_lancamento",
  "send_supplier_quote_request",
  "alterar_favorecido",
  "send_whatsapp_message",
  "set_tool_autonomy",
];

Deno.test("S2: os oito nomes de 24/11 estão no teto, e cada um é uma ferramenta que existe (nome errado não protege nada)", () => {
  const catalogo = new Set(allTools.map((t) => t.name));
  for (const nome of OS_OITO_DE_24_11) {
    assertEquals(NEVER_AUTONOMOUS.has(nome), true, `${nome} deveria estar em NEVER_AUTONOMOUS`);
    assertEquals(catalogo.has(nome), true, `${nome} não existe em allTools: a trava ficaria num nome que ninguém chama`);
  }
  assertEquals(new Set(OS_OITO_DE_24_11).size, 8);
});

Deno.test("S2: com 'auto' gravado, nenhum dos oito roda sozinho — no risco declarado, no médio e no alto", () => {
  const porNome = new Map(allTools.map((t) => [t.name, t]));
  for (const nome of OS_OITO_DE_24_11) {
    const s = { [autonomyKey(nome)]: "auto" };
    const declarado = porNome.get(nome)!.risk;
    // Nenhum é de risco baixo: "low" roda direto ANTES de a lista ser consultada, e a trava não valeria.
    assertEquals(declarado === "low", false, `${nome} é de risco baixo: a lista não o alcança`);
    assertEquals(isAutonomyGranted(nome, declarado, s), false, `${nome} (${declarado}) rodaria sozinho`);
    assertEquals(isAutonomyGranted(nome, "medium", s), false, `${nome} (medium) rodaria sozinho`);
    assertEquals(isAutonomyGranted(nome, "high", s), false, `${nome} (high) rodaria sozinho`);
    assertEquals(isAutonomyGranted(nome, "high", { [autonomyKey(nome)]: "  AUTO " }), false, `${nome} com ' AUTO '`);
  }
  // Com os argumentos de um envio real: a cliente (alto) e a um número avulso (médio).
  const chave = { [autonomyKey("send_whatsapp_message")]: "auto" };
  assertEquals(isAutonomyGranted("send_whatsapp_message", "high", chave, { client_id: "c-1", message: "Oi" }), false);
  assertEquals(isAutonomyGranted("send_whatsapp_message", "medium", chave, { to_phone: "5547999990000", message: "Oi" }), false);
});

Deno.test("S2: o link da OS não entrou no teto — só o formato 'link' continua liberável (dono, 26/09/2026)", () => {
  assertEquals(NEVER_AUTONOMOUS.has("send_service_order_link"), false);
  const link = { [autonomyKey("send_service_order_link")]: "auto" };
  assertEquals(isAutonomyGranted("send_service_order_link", "high", link, { formato: "link" }), true);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", link, { formato: "pdf_e_link" }), false);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", link, { formato: "link", destino: "parceiro" }), false);
});

Deno.test("S2: o prompt não ensina o dono a liberar o que está no teto (o pedido de cotação saiu dos liberáveis)", () => {
  // Até 24/11/2026 a seção AUTONOMIA dizia "o dono PODE liberar o envio de cotação a fornecedor": o assistente
  // ofereceria, pediria o "sim" com PIN e só então a ferramenta recusaria.
  const estavel = buildSystemBlocks({}, { userName: "Teste", userRole: "admin" })[0].text;
  const linha = estavel.split("\n").find((l) => l.startsWith("- COMUNICAÇÃO (Confiança Graduada)")) ?? "";
  const ateOndeLibera = linha.indexOf("O PDF anexado");
  assertEquals(ateOndeLibera > 0, true, "a linha da Confiança Graduada mudou de forma: reveja este teste");
  const oQuePodeLiberar = linha.slice(0, ateOndeLibera);
  assertEquals(oQuePodeLiberar.includes("send_service_order_link no formato 'link'"), true);
  const citadas = oQuePodeLiberar.match(/[a-z]+(?:_[a-z]+)+/g) ?? [];
  assertEquals(citadas.filter((nome) => NEVER_AUTONOMOUS.has(nome)), [], "o prompt oferece liberar uma ação do teto");
  const oQueNunca = linha.slice(ateOndeLibera);
  for (const nome of ["send_collection_reminder", "send_supplier_quote_request", "send_whatsapp_message"]) {
    assertEquals(oQueNunca.includes(nome), true, `${nome} deveria estar entre as que NUNCA são liberáveis`);
    assertEquals(NEVER_AUTONOMOUS.has(nome), true);
  }
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

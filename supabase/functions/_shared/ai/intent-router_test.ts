import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { detectarDominios, dominiosDaTool, ehCore, filtrarTools } from "./intent-router.ts";

Deno.test("detecta domínios por palavra-chave", () => {
  assertEquals(detectarDominios("quanto faturei com Victron?").includes("financeiro"), true);
  assertEquals(detectarDominios("emitir nota fiscal da venda").includes("fiscal"), true);
  assertEquals(detectarDominios("cria um cliente novo").includes("cadastro"), true);
  assertEquals(detectarDominios("bom dia").length, 0);
});

Deno.test("ehCore: leitura e essenciais são sempre core", () => {
  assertEquals(ehCore("search_products"), true);
  assertEquals(ehCore("list_service_orders"), true);
  assertEquals(ehCore("get_revenue_by_brand"), true);
  assertEquals(ehCore("present_options"), true);
  assertEquals(ehCore("create_quote_from_items"), true);
  assertEquals(ehCore("emit_fiscal_note"), false);
});

Deno.test("dominiosDaTool tagueia escrita por padrão de nome", () => {
  assertEquals(dominiosDaTool("register_payment").includes("financeiro"), true);
  assertEquals(dominiosDaTool("emit_fiscal_note").includes("fiscal"), true);
  assertEquals(dominiosDaTool("create_vessel").includes("cadastro"), true);
});

// Lista representativa: 35 leituras (core) + 5 escritas de domínios distintos.
const NOMES = [
  ...Array.from({ length: 35 }, (_, i) => `get_x${i}`),
  "register_payment", "emit_fiscal_note", "create_vessel", "send_whatsapp_message", "create_quote_request",
];

Deno.test("mensagem vaga → null (envia tudo, seguro)", () => {
  assertEquals(filtrarTools("bom dia, tudo bem?", NOMES), null);
});

Deno.test("3+ domínios → null (envia tudo, seguro)", () => {
  // financeiro + fiscal + agenda
  assertEquals(filtrarTools("cobra o cliente, emite a nota fiscal e agenda a visita", NOMES), null);
});

Deno.test("domínio claro → mantém core + escrita do domínio, remove escrita alheia", () => {
  const set = filtrarTools("preciso registrar o pagamento vencido do cliente", NOMES);
  assertEquals(set !== null, true);
  const s = set as Set<string>;
  assertEquals(s.has("get_x1"), true); // leitura mantida
  assertEquals(s.has("register_payment"), true); // escrita do domínio financeiro mantida
  assertEquals(s.has("emit_fiscal_note"), false); // escrita fiscal removida
  assertEquals(s.has("create_vessel"), false); // escrita cadastro removida
});

Deno.test("nunca remove leitura", () => {
  const set = filtrarTools("emitir nota fiscal", NOMES);
  if (set) for (const n of NOMES) if (n.startsWith("get_")) assertEquals(set.has(n), true);
});

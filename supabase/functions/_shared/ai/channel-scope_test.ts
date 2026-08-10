import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FORA_DO_WHATSAPP, filtrarPorCanal } from "./channel-scope.ts";
import { allTools } from "./tools/index.ts";

const nomesReais = new Set(allTools.map((t) => t.name));

Deno.test("todo nome da lista existe de fato — typo cortaria nada, em silêncio", () => {
  const fantasmas = [...FORA_DO_WHATSAPP].filter((n) => !nomesReais.has(n));
  assertEquals(fantasmas, [], `nomes que não existem em allTools: ${fantasmas.join(", ")}`);
});

Deno.test("o que o WhatsApp existe para servir NÃO pode entrar na lista", () => {
  // Roteiro de execução: o técnico relata passo a passo por áudio, pelo WhatsApp.
  // Levantamento: o prompt manda usar mode='remoto' para resolver no WhatsApp.
  // Fiscal: consultar se a nota saiu é pergunta de celular.
  const intocaveis = [
    "start_service_order_step", "complete_service_order_step", "block_service_order_step",
    "skip_service_order_step", "get_service_order_route", "log_service_order_progress",
    "check_in_service_order", "check_out_service_order",
    "start_service_survey", "record_survey_answer", "assess_survey_confidence",
    "close_service_survey", "check_needs_survey",
    "list_fiscal_documents", "get_fiscal_document", "preview_fiscal_note",
  ];
  for (const nome of intocaveis) {
    assert(!FORA_DO_WHATSAPP.has(nome), `${nome} não pode ser cortado do WhatsApp`);
  }
});

Deno.test("ferramenta com uso real em 60 dias não é cortada", () => {
  // Amostra das que aparecem em ai_operator_audit — cortar qualquer uma seria regressão.
  const comUso = [
    "search_clients", "search_products", "create_quote_from_items", "get_service_order",
    "add_service_to_order", "add_material_to_order", "edit_service_order_item",
    "remove_service_order_item", "send_service_order_link", "send_whatsapp_message",
    "sugerir_conciliacao", "listar_transacoes_pendentes", "listar_categorias_financeiras",
    "criar_regra_financeira", "schedule_self_reminder", "list_unanswered_messages",
    "get_purchase_needs", "suggest_suppliers", "create_quote_request", "register_payment",
  ];
  for (const nome of comUso) {
    assert(!FORA_DO_WHATSAPP.has(nome), `${nome} tem uso real e não pode sair do WhatsApp`);
  }
});

Deno.test("filtra no WhatsApp e não mexe no painel", () => {
  const noWhats = filtrarPorCanal(allTools, "whatsapp");
  const noPainel = filtrarPorCanal(allTools, "panel");
  assertEquals(noPainel.length, allTools.length);
  assertEquals(noWhats.length, allTools.length - FORA_DO_WHATSAPP.size);
  assert(noWhats.length < allTools.length, "o filtro precisa cortar alguma coisa");
});

Deno.test("canal desconhecido recebe tudo — não corta por engano", () => {
  assertEquals(filtrarPorCanal(allTools, undefined).length, allTools.length);
  assertEquals(filtrarPorCanal(allTools, "system").length, allTools.length);
});

Deno.test("é estável: duas chamadas devolvem a mesma lista, na mesma ordem", () => {
  // Se variasse, o prefixo mudaria e o cache daria miss em toda chamada.
  const a = filtrarPorCanal(allTools, "whatsapp").map((t) => t.name);
  const b = filtrarPorCanal(allTools, "whatsapp").map((t) => t.name);
  assertEquals(a, b);
});

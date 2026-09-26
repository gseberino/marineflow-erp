// O perfil saiu do banco para o código (26/09/2026) sem mudar o que o modelo recebe — a não ser
// pelas duas ferramentas acrescentadas de propósito. Este arquivo é a prova.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/perfil-operacao_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { runAgentLoop } from "./agent.ts";
import { ehLeituraPeloNome, ESCRITAS_VERIFICADAS_DA_REDE, PERFIL_OPERACAO, rodaDiretoPelaRede, SO_PELA_REDE } from "./perfil-operacao.ts";
import { allTools } from "./tools/index.ts";

Deno.env.set("OPENROUTER_API_KEY", "test-key-not-real");

// Retrato de app_settings.ai_tool_profile_operacao em PRODUÇÃO, lido por SELECT em 26/09/2026
// (updated_at 2026-09-26 00:07 UTC, 127 nomes). Congelado aqui de propósito: é o "antes".
const BANCO_EM_26_09 = [
  "search_products", "remove_service_order_item", "get_service_order", "add_service_order_item", "create_product",
  "get_product_price_history", "add_service_to_order", "add_material_to_order", "edit_service_order_item", "search_clients",
  "search_vessels", "size_dc_cable", "search_suppliers", "list_service_orders", "create_quote_from_items",
  "search_products_batch", "search_services", "update_product", "record_survey_answer", "assess_survey_confidence",
  "survey_material_list", "create_quote_request", "create_service_order", "close_service_survey", "create_payable",
  "create_vessel", "sugerir_conciliacao", "schedule_self_reminder", "list_unanswered_messages", "listar_categorias_financeiras",
  "set_service_order_charges", "get_client_360", "present_options", "suggest_suppliers", "get_os_receivables",
  "log_service_order_progress", "list_pending_pos", "read_supplier_messages", "update_vessel", "identify_contact",
  "listar_transacoes_pendentes", "update_client", "list_reference_data", "check_needs_survey", "create_client",
  "get_os_profitability", "list_overdue_receivables", "get_service_order_route", "start_service_survey", "get_delinquency_plan",
  "apply_service_order_discount", "create_supplier", "get_route_drafting_context", "get_client_history", "list_low_stock",
  "get_purchase_needs", "update_service_order_status", "update_service_order_notes", "criar_missao_acompanhamento",
  "listar_missoes_acompanhamento", "cancelar_missao_acompanhamento", "get_situation_overview", "my_agenda", "list_tasks",
  "create_task", "update_task", "complete_task", "list_team_agenda", "schedule_service_order", "check_technician_availability",
  "get_period_summary", "resultado_do_periodo", "get_top_clients", "list_payables_due", "list_pending_collections",
  "listar_propostas_de_lancamento", "recusar_propostas_de_lancamento", "reclassificar_propostas_de_lancamento",
  "classificar_propostas_com_ia", "sugerir_regras_financeiras", "desfazer_propostas_ignoradas", "listar_regras_financeiras",
  "criar_regra_financeira", "listar_favorecidos", "cadastrar_favorecido", "analisar_extrato_e_propor_lancamentos",
  "update_quote_status", "apply_quote_price", "duplicate_service_order", "log_service_order_hours", "registrar_jornada",
  "minhas_horas", "fechar_jornada", "apurar_pagamento", "preview_fiscal_note", "preview_fiscal_service_note",
  "list_fiscal_documents", "register_stock_entry", "record_quote_response", "get_quote_comparison", "get_supplier_360",
  "get_vessel_history", "generate_service_order_route", "save_drafted_route_steps", "add_service_order_step",
  "start_service_order_step", "complete_service_order_step", "skip_service_order_step", "block_service_order_step",
  "check_in_service_order", "check_out_service_order", "attach_photo_to_service_order", "optimize_text", "list_technicians",
  "get_service_order_margin", "create_receivable", "update_payable", "update_receivable", "get_open_loops",
  "list_scheduled_whatsapp", "cancel_scheduled_whatsapp", "mute_contact", "add_kit_to_order", "add_service_order_expense",
  "link_whatsapp_lead_to_client", "unmute_contact", "send_document_pdf_to_self",
];

// O SEMPRE_NO_PERFIL que existia em agent.ts até 26/09/2026.
const SEMPRE_NO_PERFIL_ANTIGO = [
  "get_whatsapp_conversation", "buscar_lancamentos", "desfazer_aprovacao_de_lancamento", "casar_lancamento_com_extrato",
  "cadastrar_contraparte_do_extrato", "verificar_mes", "consultar_conta", "configurar_lancamento_automatico",
  "listar_lancados_sozinhos", "lancar_no_caixa", "ajustar_saldo_do_caixa", "anotar_transacao_do_banco", "gastos_por_categoria",
];

// Decisão do dono (Frente C): as que o prompt ensina e o perfil escondia sem motivo. A terceira
// (update_service) entrou na integração de 26/09/2026: pela rede, o cadastro fiscal em lote
// virava uma confirmação por serviço.
const ACRESCENTADAS = ["link_contact_to_entity", "update_supplier", "update_service"];

const ordenado = (xs: Iterable<string>) => [...new Set(xs)].sort();

Deno.test("perfil no código = banco de 26/09 ∪ SEMPRE_NO_PERFIL antigo ∪ as acrescentadas — nem mais, nem menos", () => {
  assertEquals(BANCO_EM_26_09.length, 127);
  assertEquals(ordenado(PERFIL_OPERACAO), ordenado([...BANCO_EM_26_09, ...SEMPRE_NO_PERFIL_ANTIGO, ...ACRESCENTADAS]));
});

Deno.test("todo nome do perfil e da lista SO_PELA_REDE existe em allTools, e as duas listas não se cruzam", () => {
  const existentes = new Set(allTools.map((t) => t.name));
  for (const nome of PERFIL_OPERACAO) assertEquals(existentes.has(nome), true, `perfil cita tool inexistente: ${nome}`);
  for (const nome of SO_PELA_REDE) assertEquals(existentes.has(nome), true, `SO_PELA_REDE cita tool inexistente: ${nome}`);
  for (const nome of SO_PELA_REDE) assertEquals(PERFIL_OPERACAO.has(nome), false, `${nome} está no perfil E na rede`);
});

Deno.test("SO_PELA_REDE: pela rede, roda direto só leitura e escrita de sugestão/análise; o resto pede confirmação", () => {
  // Pela rede, o executor (agent.ts) consulta rodaDiretoPelaRede: escrita que não está em
  // ESCRITAS_VERIFICADAS_DA_REDE vira pendência, mesmo de risco low. Se este teste acusar
  // diferença: nome novo em SO_PELA_REDE cai do lado "pede confirmação" sozinho — confira se é
  // isso mesmo; acrescentar a ESCRITAS_VERIFICADAS_DA_REDE só depois de ler o execute.
  for (const n of ["get_x", "list_x", "read_x", "check_x", "search_x"]) assertEquals(ehLeituraPeloNome(n), true, n);
  for (const n of ["update_x", "interpret_customer_reply", "remember_about_entity", "xget_x"]) assertEquals(ehLeituraPeloNome(n), false, n);
  // Nome herdado do protótipo de objeto não é "verificado".
  for (const n of ["constructor", "toString", "hasOwnProperty"]) assertEquals(rodaDiretoPelaRede({ name: n, risk: "low" }), false, n);

  const porNome = new Map(allTools.map((t) => [t.name, t]));
  const diretas = [...SO_PELA_REDE].filter((n) => rodaDiretoPelaRede(porNome.get(n)!));
  const escritasDiretas = diretas.filter((n) => !ehLeituraPeloNome(n)).sort();
  assertEquals(escritasDiretas, ["interpret_customer_reply", "remember_about_entity"]);
  assertEquals(escritasDiretas, Object.keys(ESCRITAS_VERIFICADAS_DA_REDE).sort(), "lista verificada com nome que não é escrita low de SO_PELA_REDE");

  // As escritas de risco low que, pela rede, pedem confirmação (conferência de 26/09/2026).
  const escritasLowConfirmadas = [...SO_PELA_REDE]
    .filter((n) => porNome.get(n)!.risk === "low" && !ehLeituraPeloNome(n) && !rodaDiretoPelaRede(porNome.get(n)!))
    .sort();
  assertEquals(escritasLowConfirmadas, [
    "convert_external_quote_to_so", "create_composed_product", "reorder_service_order_step", "review_entity_note", "update_service",
  ]);
  // E nada de risco medium/high roda direto pela rede.
  for (const n of SO_PELA_REDE) {
    if (porNome.get(n)!.risk !== "low") assertEquals(rodaDiretoPelaRede(porNome.get(n)!), false, n);
  }
  // A verificação tem de dizer o porquê, não só o nome.
  for (const [nome, porque] of Object.entries(ESCRITAS_VERIFICADAS_DA_REDE)) {
    assertEquals(porque.trim().length > 20, true, `${nome} sem o porquê da verificação`);
  }
});

Deno.test("SO_PELA_REDE: a 'leitura pelo nome' que roda direto não escreve (o nome não mente)", () => {
  // O executor confia no nome (get_/list_/read_/check_/search_) para deixar rodar direto. Aqui se
  // confere, no corpo do execute, que nenhuma delas grava. Só o corpo do execute é lido: helper
  // em outra função não aparece — quem acrescentar leitura que delega tem de ler o helper.
  const porNome = new Map(allTools.map((t) => [t.name, t]));
  const leituras = [...SO_PELA_REDE].filter((n) => ehLeituraPeloNome(n));
  assertEquals(leituras.length >= 10, true, `só ${leituras.length} leituras — o recorte quebrou?`);
  for (const n of leituras) {
    const corpo = String(porNome.get(n)!.execute);
    assertEquals(/\.(insert|update|upsert|delete|rpc)\(/.test(corpo), false, `${n} tem escrita no execute e passaria direto pela rede`);
  }
});

Deno.test("migration do perfil: versão 20260927090100, fora da faixa do financeiro (26/09 à noite), e única", () => {
  // Nasceu 20260926213000, vizinha de 20260926210000 (decisoes_do_dono, da sessão do financeiro,
  // já aplicada). Versão repetida ou fora de ordem quebra o db push de quem vier depois.
  const dir = new URL("../../../migrations/", import.meta.url);
  const arquivos = [...Deno.readDirSync(dir)].filter((e) => e.isFile && e.name.endsWith(".sql")).map((e) => e.name);
  const doPerfil = arquivos.filter((n) =>
    /delete\s+from\s+public\.app_settings\s+where\s+key\s*=\s*'ai_tool_profile_operacao'/i.test(Deno.readTextFileSync(new URL(n, dir)))
  );
  assertEquals(doPerfil, ["20260927090100_perfil_de_tools_no_codigo.sql"]);
  const versao = (n: string) => n.split("_")[0];
  assertEquals(arquivos.filter((n) => versao(n) === "20260927090100"), doPerfil, "outra migration usa a mesma versão");
});

Deno.test("comportamento: com o perfil ligado, o modelo recebe exatamente o de antes + as 2", async () => {
  // Fake do service-role: só o liga/desliga no banco, como fica em produção.
  const admin = {
    from(_t: string) {
      return {
        select: () => ({ in: async () => ({ data: [{ key: "ai_tool_profile", value: "operacao" }], error: null }) }),
        insert: () => ({ then: (r: (v: unknown) => void) => r({ data: null, error: null }) }),
      };
    },
  };
  let corpo: any = null;
  const original = globalThis.fetch;
  globalThis.fetch = (_i, init) => {
    corpo = JSON.parse(String(init?.body));
    return Promise.resolve(new Response(JSON.stringify({
      id: "g", choices: [{ message: { role: "assistant", content: "oi" }, finish_reason: "stop" }],
      usage: { prompt_tokens: 1, completion_tokens: 1 },
    }), { status: 200, headers: { "Content-Type": "application/json" } }));
  };
  try {
    await runAgentLoop({
      system: [{ type: "text", text: "teste" }],
      messages: [{ role: "user", content: [{ type: "text", text: "bom dia" }] }],
      tools: allTools,
      sessionId: "s",
      toolCtx: { sb: {}, admin, userId: "u", userRole: "admin", jwt: "", appOrigin: "", settings: {} },
    });
  } finally {
    globalThis.fetch = original;
  }
  const enviadas: string[] = corpo.tools.map((t: { function: { name: string } }) => t.function.name);

  // A regra ANTIGA do aplicarPerfilDeTools, reproduzida sobre as mesmas tools.
  const antigo = new Set([...BANCO_EM_26_09, ...SEMPRE_NO_PERFIL_ANTIGO]);
  const esperadoAntes = allTools.filter((t) => t.risk === "high" || antigo.has(t.name)).map((t) => t.name);

  assertEquals(ordenado(enviadas), ordenado([...esperadoAntes, ...ACRESCENTADAS]));
  // E a ORDEM continua a de allTools (prefixo de cache estável).
  assertEquals(enviadas, allTools.map((t) => t.name).filter((n) => enviadas.includes(n)));
});

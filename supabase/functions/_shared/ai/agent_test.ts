// Testes do núcleo do AI Operator (Claude via OpenRouter). Segue o mesmo padrão de mock
// de fetch usado em _shared/whatsapp/*_test.ts. Rodar com:
//   deno test --allow-env supabase/functions/_shared/ai/agent_test.ts
import { assertEquals, assertExists, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { callClaude } from "./anthropic.ts";
import { buildPendingSummary, interrupcaoDaTool, resumoQueRecusa, runAgentLoop, textoDoSim } from "./agent.ts";
import { quoteBuilderTools } from "./tools/quote-builder.ts";
import { retornoTools } from "./tools/retorno.ts";
import type { ToolDef } from "./tools/registry.ts";

Deno.env.set("OPENROUTER_API_KEY", "test-key-not-real");

function mockFetchSequence(
  responses: Array<{ status: number; body: unknown; headers?: Record<string, string> }>,
): { fetchStub: typeof globalThis.fetch; calls: Array<{ url: string; init?: RequestInit }> } {
  let i = 0;
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetchStub: typeof globalThis.fetch = (input, init) => {
    calls.push({ url: typeof input === "string" ? input : (input as Request).url, init });
    const r = responses[Math.min(i, responses.length - 1)];
    i++;
    return Promise.resolve(
      new Response(JSON.stringify(r.body), {
        status: r.status,
        headers: { "Content-Type": "application/json", ...(r.headers || {}) },
      }),
    );
  };
  return { fetchStub, calls };
}

function withFetch<T>(stub: typeof globalThis.fetch, fn: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  return fn().finally(() => {
    globalThis.fetch = original;
  });
}

// Descreve a resposta do modelo no nosso vocabulário nativo (content blocks + stop_reason,
// igual ao que a API da Anthropic devolveria) e monta o corpo no formato OpenAI-shape que o
// OpenRouter realmente devolve (choices[].message + finish_reason) — é isso que o fetch
// mockado retorna, exercitando a tradução feita dentro de callClaude.
function claudeMsg(opts: { content: Array<{ type: string; text?: string; id?: string; name?: string; input?: unknown }>; stop_reason: string }) {
  const textBlocks = opts.content.filter((b) => b.type === "text");
  const toolUseBlocks = opts.content.filter((b) => b.type === "tool_use");
  const finishReason =
    opts.stop_reason === "max_tokens" ? "length" : opts.stop_reason === "tool_use" ? "tool_calls" : opts.stop_reason === "end_turn" ? "stop" : opts.stop_reason;
  return {
    id: "gen_test",
    choices: [
      {
        message: {
          role: "assistant",
          content: textBlocks.map((b) => b.text).join("") || null,
          ...(toolUseBlocks.length
            ? { tool_calls: toolUseBlocks.map((b) => ({ id: b.id, type: "function", function: { name: b.name, arguments: JSON.stringify(b.input) } })) }
            : {}),
        },
        finish_reason: finishReason,
      },
    ],
    usage: { prompt_tokens: 100, completion_tokens: 20, prompt_tokens_details: { cached_tokens: 0, cache_write_tokens: 0 } },
  };
}

const testTool: ToolDef = {
  name: "test_tool",
  description: "Tool de teste, apenas ecoa o argumento recebido.",
  input_schema: { type: "object", properties: { foo: { type: "string" } }, required: ["foo"] },
  risk: "low",
  async execute(args) {
    return { echoed: args.foo };
  },
};

const presentOptionsTool: ToolDef = {
  name: "present_options",
  description: "meta-tool de teste",
  input_schema: { type: "object", properties: {} },
  risk: "low",
  async execute(args) {
    return { options_ready: true, question: args.question, options: args.options };
  },
};

// Fake mínimo do client service-role: suporta o insert+select+single usado ao gravar
// uma pendência, e o insert "solto" (thenable, sem .select()) usado na auditoria.
function makeFakeAdmin() {
  const auditRows: any[] = [];
  const pendingRows: any[] = [];
  let seq = 0;
  const admin = {
    from(table: string) {
      return {
        insert(row: any) {
          if (table === "ai_operator_audit") auditRows.push(row);
          if (table === "ai_operator_pending_actions") pendingRows.push(row);
          const id = `pending-${++seq}`;
          return {
            select: () => ({
              single: async () => ({ data: { id, title: row.title, summary: row.summary, risk_level: row.risk_level }, error: null }),
            }),
            then: (resolve: (v: unknown) => void) => resolve({ data: null, error: null }),
          };
        },
      };
    },
  };
  return { admin, auditRows, pendingRows };
}

function makeBaseParams() {
  const { admin, auditRows, pendingRows } = makeFakeAdmin();
  return {
    params: {
      system: [{ type: "text" as const, text: "Você é um assistente de teste." }],
      sessionId: "session-test-1",
      toolCtx: { sb: {}, admin, userId: "u1", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {} },
    },
    auditRows,
    pendingRows,
  };
}

const { params: baseParams } = makeBaseParams();

Deno.test("runAgentLoop: resposta só texto — encerra sem chamar tool", async () => {
  const { fetchStub, calls } = mockFetchSequence([
    { status: 200, body: claudeMsg({ content: [{ type: "text", text: "Olá! Como posso ajudar?" }], stop_reason: "end_turn" }) },
  ]);
  const result = await withFetch(fetchStub, () =>
    runAgentLoop({
      ...baseParams,
      messages: [{ role: "user", content: [{ type: "text", text: "oi" }] }],
      tools: [testTool],
    })
  );
  assertEquals(calls.length, 1);
  assertEquals(result.message.content, "Olá! Como posso ajudar?");
  assertEquals(result.toolEvents.length, 0);
  assertEquals(result.proposal, undefined);
  assertEquals(result.options, undefined);
  assertEquals(result.error, undefined);
});

Deno.test("runAgentLoop: tool_use único — executa a tool e responde no próximo giro", async () => {
  const { fetchStub, calls } = mockFetchSequence([
    { status: 200, body: claudeMsg({ content: [{ type: "tool_use", id: "toolu_01", name: "test_tool", input: { foo: "bar" } }], stop_reason: "tool_use" }) },
    { status: 200, body: claudeMsg({ content: [{ type: "text", text: "Tool executada, aqui está: bar" }], stop_reason: "end_turn" }) },
  ]);
  const result = await withFetch(fetchStub, () =>
    runAgentLoop({
      ...baseParams,
      messages: [{ role: "user", content: [{ type: "text", text: "execute o tool de teste" }] }],
      tools: [testTool],
    })
  );
  assertEquals(calls.length, 2);
  assertEquals(result.message.content, "Tool executada, aqui está: bar");
  assertEquals(result.toolEvents.length, 1);
  // 29/10/2026 (aprovação em lote): o evento diz se a tool RODOU e qual (a base do "Conferido pelo sistema")
  assertEquals(result.toolEvents[0], {
    name: "test_tool", args: { foo: "bar" }, result: { echoed: "bar" }, executou: true, ferramenta: "test_tool", rodada: 0,
  });
  // histórico: user inicial, assistant(tool_use), user(tool_result), assistant(texto final)
  assertEquals(result.messages.length, 4);
  assertEquals(result.messages[1].role, "assistant");
  assertEquals(result.messages[2].role, "user");
  assertEquals(result.messages[2].content[0].type, "tool_result");
});

Deno.test("runAgentLoop: tool_use paralelo — todos os tool_results voltam numa única mensagem user", async () => {
  const { fetchStub, calls } = mockFetchSequence([
    {
      status: 200,
      body: claudeMsg({
        content: [
          { type: "tool_use", id: "toolu_a", name: "test_tool", input: { foo: "bar" } },
          { type: "tool_use", id: "toolu_b", name: "present_options", input: { question: "Qual?", options: [{ label: "A", value: "a" }, { label: "B", value: "b" }] } },
        ],
        stop_reason: "tool_use",
      }),
    },
  ]);
  const result = await withFetch(fetchStub, () =>
    runAgentLoop({
      ...baseParams,
      messages: [{ role: "user", content: [{ type: "text", text: "faça as duas coisas" }] }],
      tools: [testTool, presentOptionsTool],
    })
  );
  assertEquals(calls.length, 1);
  // As duas tools foram executadas mesmo com short-circuit em uma delas.
  assertEquals(result.toolEvents.length, 2);
  assertExists(result.options);
  assertEquals(result.options?.question, "Qual?");
  // Uma única mensagem "user" com os dois tool_results, na ordem das chamadas.
  const toolResultMsg = result.messages[result.messages.length - 1];
  assertEquals(toolResultMsg.role, "user");
  assertEquals(toolResultMsg.content.length, 2);
  assertEquals((toolResultMsg.content[0] as any).tool_use_id, "toolu_a");
  assertEquals((toolResultMsg.content[1] as any).tool_use_id, "toolu_b");
});

Deno.test("runAgentLoop: stop_reason max_tokens — retorna erro sem quebrar", async () => {
  const { fetchStub } = mockFetchSequence([
    { status: 200, body: claudeMsg({ content: [{ type: "text", text: "resposta parcial truncada" }], stop_reason: "max_tokens" }) },
  ]);
  const result = await withFetch(fetchStub, () =>
    runAgentLoop({
      ...baseParams,
      messages: [{ role: "user", content: [{ type: "text", text: "pergunta bem longa" }] }],
      tools: [testTool],
    })
  );
  assertExists(result.error);
  assertStringIncludes(result.error!, "truncada");
  assertEquals(result.message.content, "resposta parcial truncada");
  assertEquals(result.toolEvents.length, 0);
});

// ---------------- Fase 3: interceptação por risco + defesa em profundidade de role ----------------

let mediumToolExecuted = false;
const mediumRiskTool: ToolDef = {
  name: "medium_risk_tool",
  description: "Tool de teste com risco medium — nunca deveria executar sem aprovação.",
  input_schema: { type: "object", properties: { amount: { type: "number" } } },
  risk: "medium",
  async execute(args) {
    mediumToolExecuted = true;
    return { ok: true, amount: args.amount };
  },
};

const restrictedTool: ToolDef = {
  name: "restricted_tool",
  description: "Tool de teste restrita a não-technician.",
  input_schema: { type: "object", properties: {} },
  risk: "low",
  roles: ["admin", "financial", "seller", "external_seller"],
  async execute(_args, ctx) {
    if (ctx.userRole === "technician") return { error: "Cargo não autorizado para esta ação." };
    return { ok: true };
  },
};

Deno.test("runAgentLoop: risco low executa direto, sem pendência", async () => {
  const { params, pendingRows, auditRows } = makeBaseParams();
  const { fetchStub } = mockFetchSequence([
    { status: 200, body: claudeMsg({ content: [{ type: "tool_use", id: "toolu_low", name: "test_tool", input: { foo: "bar" } }], stop_reason: "tool_use" }) },
    { status: 200, body: claudeMsg({ content: [{ type: "text", text: "feito" }], stop_reason: "end_turn" }) },
  ]);
  const result = await withFetch(fetchStub, () => runAgentLoop({ ...params, messages: [{ role: "user", content: [{ type: "text", text: "oi" }] }], tools: [testTool] }));
  assertEquals(result.toolEvents[0].result, { echoed: "bar" });
  assertEquals(pendingRows.length, 0);
  assertEquals(auditRows.length, 1);
  assertEquals(auditRows[0].event_type, "tool:test_tool");
});

Deno.test("runAgentLoop: risco medium/high intercepta — grava pending_action e NÃO executa a tool", async () => {
  mediumToolExecuted = false;
  const { params, pendingRows, auditRows } = makeBaseParams();
  const { fetchStub } = mockFetchSequence([
    { status: 200, body: claudeMsg({ content: [{ type: "tool_use", id: "toolu_med", name: "medium_risk_tool", input: { amount: 500 } }], stop_reason: "tool_use" }) },
  ]);
  const result = await withFetch(fetchStub, () =>
    runAgentLoop({ ...params, messages: [{ role: "user", content: [{ type: "text", text: "crie uma conta de R$500" }] }], tools: [mediumRiskTool] })
  );
  assertEquals(mediumToolExecuted, false, "a tool real não deveria ter sido chamada");
  assertExists(result.proposal);
  assertEquals(result.proposal?.risk_level, "medium");
  assertExists(result.proposal?.pending_action_id);
  assertEquals(pendingRows.length, 1);
  assertEquals(pendingRows[0].action_name, "medium_risk_tool");
  assertEquals(pendingRows[0].payload, { amount: 500 });
  assertEquals(pendingRows[0].status, "pending");
  assertEquals(auditRows.length, 1);
  assertEquals(auditRows[0].event_type, "pending_action:medium_risk_tool");
  // tool_result sintético devolvido ao modelo não deve conter o resultado real da tool
  const toolResultMsg = result.messages[result.messages.length - 1];
  const content = JSON.parse((toolResultMsg.content[0] as any).content);
  assertEquals(content.pending, true);
  assertExists(content.pending_action_id);
});

// ---------------- Gancho preValidar e quem pediu (gravarSolicitante) ----------------
// A pendência é executada com o ctx de quem CONFIRMA; um admin pode aprovar a de outro. O
// gancho recusa antes de a pendência nascer, e a pendência leva quem pediu para a tool
// revalidar com o cargo DELE.

function ferramentaAlta(extra: Partial<ToolDef> = {}): { def: ToolDef; executou: () => boolean } {
  let rodou = false;
  const def: ToolDef = {
    name: "ferramenta_alta",
    description: "Tool de teste de risco alto.",
    input_schema: { type: "object", properties: { alvo: { type: "string" } } },
    risk: "high",
    async execute() {
      rodou = true;
      return { ok: true };
    },
    ...extra,
  };
  return { def, executou: () => rodou };
}

async function chamarNoLoop(def: ToolDef, input: Record<string, unknown>, papel: "admin" | "external_seller" = "admin") {
  const { params, pendingRows, auditRows } = makeBaseParams();
  const { fetchStub, calls } = mockFetchSequence([
    { status: 200, body: claudeMsg({ content: [{ type: "tool_use", id: "toolu_alta", name: def.name, input }], stop_reason: "tool_use" }) },
    { status: 200, body: claudeMsg({ content: [{ type: "text", text: "entendi" }], stop_reason: "end_turn" }) },
  ]);
  const result = await withFetch(fetchStub, () =>
    runAgentLoop({
      ...params,
      toolCtx: { ...params.toolCtx, userRole: papel },
      messages: [{ role: "user", content: [{ type: "text", text: "faça" }] }],
      tools: [def],
    })
  );
  return { result, pendingRows, auditRows, calls };
}

Deno.test("preValidar recusa: NÃO grava pendência e devolve o erro ao modelo", async () => {
  const { def, executou } = ferramentaAlta({
    preValidar: (_args, ctx) => ctx.userRole === "external_seller" ? { error: "cargo não pode", alternativa: "outra" } : null,
  });
  const { result, pendingRows, auditRows, calls } = await chamarNoLoop(def, { alvo: "x" }, "external_seller");
  assertEquals(pendingRows.length, 0, "nada vai para o sino");
  assertEquals(executou(), false);
  assertEquals(result.proposal, undefined);
  assertEquals(result.toolEvents[0].result, { error: "cargo não pode", alternativa: "outra" });
  assertEquals(auditRows[0].event_type, "pre_validacao_recusada:ferramenta_alta");
  assertEquals(calls.length, 2, "o modelo recebe a recusa e responde");
});

Deno.test("preValidar devolve null: a pendência nasce normalmente", async () => {
  const { def, executou } = ferramentaAlta({ preValidar: () => null });
  const { result, pendingRows } = await chamarNoLoop(def, { alvo: "x" });
  assertEquals(pendingRows.length, 1);
  assertEquals(pendingRows[0].payload, { alvo: "x" }, "sem gravarSolicitante o payload é o input cru");
  assertEquals(executou(), false);
  assertExists(result.proposal);
});

Deno.test("preValidar que lança vira recusa, não pendência", async () => {
  const { def } = ferramentaAlta({ preValidar: () => { throw new Error("quebrou"); } });
  const { pendingRows, result } = await chamarNoLoop(def, { alvo: "x" });
  assertEquals(pendingRows.length, 0);
  assertStringIncludes(String((result.toolEvents[0].result as any).error), "quebrou");
});

Deno.test("gravarSolicitante: o payload leva quem pediu, POR CIMA do que o modelo mandou, e o resumo diz quem", async () => {
  const { def } = ferramentaAlta({ gravarSolicitante: true });
  const { pendingRows } = await chamarNoLoop(
    def,
    { alvo: "x", _solicitante: { user_id: "outro", nome: "Falso", cargo: "admin" } },
    "external_seller",
  );
  assertEquals(pendingRows.length, 1);
  // O fake de banco não lê app_users: o nome fica null e a pendência nasce mesmo assim.
  assertEquals(pendingRows[0].payload, { alvo: "x", _solicitante: { user_id: "u1", nome: null, cargo: "external_seller" } });
  assertStringIncludes(pendingRows[0].summary, "Pedido por: *—* (Vendedor Externo)");
  assertEquals(String(pendingRows[0].summary).includes("Falso"), false, "o _solicitante do modelo não entra no resumo");
});

Deno.test("registry: role bloqueia — tool restrita recusa userRole=technician mesmo sendo chamada", async () => {
  const blockedResult = await restrictedTool.execute({}, { sb: {}, admin: {}, userId: "u2", userRole: "technician", jwt: "", appOrigin: "", settings: {} });
  assertEquals(blockedResult, { error: "Cargo não autorizado para esta ação." });

  const allowedResult = await restrictedTool.execute({}, { sb: {}, admin: {}, userId: "u3", userRole: "admin", jwt: "", appOrigin: "", settings: {} });
  assertEquals(allowedResult, { ok: true });
});

Deno.test("callClaude: retry em 429 respeita retry-after e sucede na 2ª tentativa", async () => {
  const { fetchStub, calls } = mockFetchSequence([
    { status: 429, body: { error: { message: "rate limited" } }, headers: { "retry-after": "0" } },
    { status: 200, body: claudeMsg({ content: [{ type: "text", text: "ok" }], stop_reason: "end_turn" }) },
  ]);
  const result = await withFetch(fetchStub, () =>
    callClaude({
      model: "anthropic/claude-sonnet-5",
      system: [{ type: "text", text: "sistema" }],
      messages: [{ role: "user", content: [{ type: "text", text: "oi" }] }],
    })
  );
  assertEquals(calls.length, 2);
  assertEquals(result.stopReason, "end_turn");
  assertEquals((result.content[0] as any).text, "ok");
});

Deno.test("interrupcaoDaTool: o fluxo que já falou com o dono encerra o turno (11/10/2026); pendência vem antes", () => {
  const tc = { name: "completar_comprovante", input: { cmp: "1" } };
  assertEquals(interrupcaoDaTool(tc, { toolResult: { ok: true }, fluxo: { codigo: "CMP-00001" } }, false), { fluxo: { codigo: "CMP-00001" } });
  assertEquals(interrupcaoDaTool(tc, { toolResult: { ok: true }, fluxo: { codigo: "CMP-00001" } }, true), { fluxo: { codigo: "CMP-00001" } });
  const proposal = { pending_action_id: "p1", title: "t", summary_markdown: "s", risk_level: "medium" as const };
  assertEquals(interrupcaoDaTool(tc, { toolResult: {}, proposal, fluxo: { codigo: "CMP-00001" } }, false), { proposal });
  assertEquals(interrupcaoDaTool(tc, { toolResult: { ok: true } }, false), null);
});

// ─── Retorno F3 (P8.5): o orçamento com o caso amarrado vira pendência com o resumo em código ───────────────────────

function adminDoDitado(rotas: Record<string, unknown> = {}) {
  const auditRows: any[] = [];
  const pendingRows: any[] = [];
  const rpcs: string[] = [];
  const tabelas: Record<string, any[]> = {
    clients: [{ id: "c-2", name: "João Silva", generico: false }],
    vessels: [{ id: "v-2", name: "Mar Azul" }],
    ...(rotas.tabelas as Record<string, any[]> | undefined),
  };
  const admin = {
    from(t: string) {
      const q: any = {
        select: () => q, eq: () => q, gt: () => q, gte: () => q, neq: () => q, order: () => q, limit: () => q, in: () => q, ilike: () => q, range: () => q,
        maybeSingle: async () => ({ data: (tabelas[t] ?? [])[0] ?? null, error: null }),
        then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: tabelas[t] ?? [], error: null }).then(ok),
        insert: (row: any) => {
          if (t === "ai_operator_audit") auditRows.push(row);
          if (t === "ai_operator_pending_actions") pendingRows.push(row);
          return {
            select: () => ({ single: async () => ({ data: { id: "p-1", title: row.title, summary: row.summary, risk_level: row.risk_level }, error: null }) }),
            then: (r: (v: unknown) => void) => r({ data: null, error: null }),
          };
        },
      };
      return q;
    },
    rpc: (fn: string, a: unknown) => {
      rpcs.push(fn);
      const v = rotas[fn];
      return Promise.resolve(typeof v === "function" ? (v as (x: unknown) => unknown)(a) : { data: v ?? null, error: null });
    },
  };
  return { admin, auditRows, pendingRows, rpcs };
}

async function chamarComAdmin(def: ToolDef, input: unknown, admin: unknown, extra: Record<string, unknown> = {}) {
  const { fetchStub } = mockFetchSequence([
    { status: 200, body: claudeMsg({ content: [{ type: "tool_use", id: "toolu_f3", name: def.name, input }], stop_reason: "tool_use" }) },
    { status: 200, body: claudeMsg({ content: [{ type: "text", text: "feito" }], stop_reason: "end_turn" }) },
  ]);
  return await withFetch(fetchStub, () =>
    runAgentLoop({
      system: [{ type: "text" as const, text: "teste" }],
      sessionId: "s1",
      toolCtx: { sb: admin, admin, userId: "dono", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {}, ...extra },
      messages: [{ role: "user", content: [{ type: "text", text: "orça" }] }],
      tools: [def],
    } as any)
  );
}

const CRIAR_ORCAMENTO = quoteBuilderTools.find((t) => t.name === "create_quote_from_items")!;
const ORCAR_CASO = retornoTools.find((t) => t.name === "retorno_orcar_caso")!;
const UNIDADE_DO_CASO = retornoTools.find((t) => t.name === "retorno_cadastrar_unidade")!;

const ARGS_DO_ORCAMENTO = { client_id: "c-2", vessel_id: "v-2", title: "Baterias", items: [{ keyword: "Bateria", unit_price: 500 }], _retrato: { amarrada: false } };
const VER_DO_DITADO = {
  n: 1, rotulo: "Ana", titulo: "Troca", total: 1320, hash: "h", abertura_id: "a-1", phone: "5547900001234", client_id: "c-1", vessel_id: "v-1", unidade_nome: "Brisa",
  unidades: [], previa_id: "pv-1", ditado_ligado: true, cliente_generico: false, validade: "terça (15/12)",
  linhas: [{ linha: 1, tipo: "peca", product_id: "p-c", service_id: null, nome: "Controlador", quantidade: 1, preco: 1320, fonte: "catalogo", em: null, rotulo: "preço de catálogo, sem data", estado: "ok", motivo: null }],
};

Deno.test("amarrado e outro client_id: create_quote_from_items vira pendência high, com o resumo, sem 'ambíguo'; o _retrato do modelo sai", async () => {
  const { admin, pendingRows, auditRows } = adminDoDitado({ search_products_trgm: [] });
  await chamarComAdmin(CRIAR_ORCAMENTO, ARGS_DO_ORCAMENTO, admin, { sessaoAmarrada: true, casoAmarrado: { client_id: "c-1", vessel_id: "v-1" } });
  assertEquals(pendingRows.length, 1);
  assertEquals(pendingRows[0].risk_level, "high");
  assertStringIncludes(pendingRows[0].summary, "João Silva");
  assertStringIncludes(pendingRows[0].summary, "Mar Azul");
  assertStringIncludes(pendingRows[0].summary, "(não é o cliente do caso do cartão)");
  assertEquals(String(pendingRows[0].summary).toLowerCase().includes("ambíguo"), false);
  // o retrato gravado é o do agente, e não o que veio do modelo
  assertEquals(pendingRows[0].payload._retrato, { amarrada: true });
  // a auditoria diz que a sessão estava amarrada (o portão escolha_por_nome depende disso)
  assertEquals(auditRows.some((r) => r.payload?.sessao_amarrada === true), true);
});

Deno.test("sem amarra, create_quote_from_items roda direto, e a auditoria não ganha a marca", async () => {
  const { admin, pendingRows, auditRows } = adminDoDitado({ search_products_trgm: [], next_document_number: 7 });
  await chamarComAdmin(CRIAR_ORCAMENTO, { client_id: "c-2", vessel_id: "v-2", title: "x", items: [{ keyword: "Bateria", unit_price: 500 }] }, admin);
  assertEquals(pendingRows.length, 0);
  assertEquals(auditRows.some((r) => r.payload?.sessao_amarrada === true), false);
});

Deno.test("retorno_orcar_caso vira pendência high com o resumo literal; retorno_cadastrar_unidade pede só sim", async () => {
  const rotas = { retorno_destino_do_item: { ok: true }, retorno_previa_ver: VER_DO_DITADO };
  const a = adminDoDitado(rotas);
  await chamarComAdmin(ORCAR_CASO, { n: 1, trocas: [{ linha: 1, preco: 1400 }] }, a.admin);
  assertEquals(a.pendingRows[0].risk_level, "high");
  assertStringIncludes(a.pendingRows[0].summary, "Proposta de *Ana* · Brisa");
  assertStringIncludes(a.pendingRows[0].summary, "*sim <PIN>* cria o orçamento e manda o PDF a Ana");
  assertEquals(a.pendingRows[0].payload._retrato.plano.linhas[0].preco, 1400);

  const u = adminDoDitado({ retorno_previa_ver: { ...VER_DO_DITADO, vessel_id: null, unidade_nome: null } });
  await chamarComAdmin(UNIDADE_DO_CASO, { n: 1, nome: "Brisa", tipo: "lancha" }, u.admin);
  assertEquals(u.pendingRows[0].risk_level, "medium");
  assertStringIncludes(u.pendingRows[0].summary, "*sim* confirma.");
  assertEquals(String(u.pendingRows[0].summary).includes("PIN"), false);
});

Deno.test("1ª linha ⚠️ no resumo não cria pendência e volta ao modelo como recusa", async () => {
  const a = adminDoDitado({ retorno_destino_do_item: { ok: true }, retorno_previa_ver: { erro: "sem_caso" } });
  const r = await chamarComAdmin(ORCAR_CASO, { n: 3 }, a.admin);
  assertEquals(a.pendingRows.length, 0);
  assertEquals(r.toolEvents[0].result, { error: "Não há caso 3 no cartão.", nada_registrado: true });
  assertEquals(resumoQueRecusa("create_quote_from_items", "⚠️ Falta preço em X: diga o valor.")?.error, "Falta preço em X: diga o valor.");
  assertEquals(resumoQueRecusa("create_quote_from_items", "Orçamento para *A*\n1. x"), null);
});

Deno.test("textoDoSim: o ditado traz o aviso, sem dizer executado", () => {
  assertEquals(textoDoSim("Montar orçamento do caso do cartão", { ok: true, aviso: "Orçamento ORÇ-00151 criado e PDF enviado a Ana.", so_texto: true }), "Orçamento ORÇ-00151 criado e PDF enviado a Ana.");
});

Deno.test("buildPendingSummary de create_quote_from_items: sem a marca usa o genérico e não chama a RPC; com a marca, o resumo linha a linha", async () => {
  const args = { client_id: "c-2", vessel_id: "v-2", title: "x", items: [{ keyword: "Bateria", unit_price: 500 }] };
  const sem = adminDoDitado({ search_products_trgm: [] });
  const generico = await buildPendingSummary(sem.admin, "create_quote_from_items", args, { userId: "dono" });
  assertEquals(generico.includes("sim <PIN>"), false);
  assertEquals(sem.rpcs.includes("retorno_previa_precos"), false);
  const com = adminDoDitado({ search_products_trgm: [] });
  const amarrado = await buildPendingSummary(com.admin, "create_quote_from_items", args, { userId: "dono", sessaoAmarrada: true });
  assertStringIncludes(amarrado, "*sim <PIN>* cria o rascunho");
});

// Testes do núcleo do AI Operator (Claude via OpenRouter). Segue o mesmo padrão de mock
// de fetch usado em _shared/whatsapp/*_test.ts. Rodar com:
//   deno test --allow-env supabase/functions/_shared/ai/agent_test.ts
import { assertEquals, assertExists, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { callClaude } from "./anthropic.ts";
import { runAgentLoop } from "./agent.ts";
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
  assertEquals(result.toolEvents[0], { name: "test_tool", args: { foo: "bar" }, result: { echoed: "bar" } });
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

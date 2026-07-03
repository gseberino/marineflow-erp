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

const baseParams = {
  system: [{ type: "text" as const, text: "Você é um assistente de teste." }],
  toolCtx: { sb: {}, admin: {}, userId: "u1", jwt: "jwt", appOrigin: "", settings: {} },
};

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

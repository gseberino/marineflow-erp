import { describe, it, expect, vi } from "vitest";
import {
  buildLLMConfig,
  createLLMProvider,
  type FetchLike,
} from "../../supabase/functions/_shared/llm/index.ts";

function fakeFetch(captured: { url?: string; init?: any }, payload: any): FetchLike {
  return async (url, init) => {
    captured.url = url;
    captured.init = init;
    return { ok: true, status: 200, json: async () => payload };
  };
}

describe("buildLLMConfig — seleção por config + secret", () => {
  it("default openrouter quando provider não setado", () => {
    const cfg = buildLLMConfig({}, (k) => (k === "OPENROUTER_API_KEY" ? "sk-or" : undefined));
    expect(cfg).toEqual({
      provider: "openrouter",
      apiKey: "sk-or",
      defaultModel: "anthropic/claude-haiku-4-5",
    });
  });

  it("anthropic quando configurado, usa ANTHROPIC_API_KEY", () => {
    const cfg = buildLLMConfig(
      { ai_operator_llm_provider: "anthropic" },
      (k) => (k === "ANTHROPIC_API_KEY" ? "sk-ant" : undefined),
    );
    expect(cfg?.provider).toBe("anthropic");
    expect(cfg?.apiKey).toBe("sk-ant");
    expect(cfg?.defaultModel).toBe("claude-haiku-4-5");
  });

  it("modelo override via app_settings", () => {
    const cfg = buildLLMConfig(
      { ai_operator_llm_model: "anthropic/claude-sonnet-4-6" },
      () => "sk-or",
    );
    expect(cfg?.defaultModel).toBe("anthropic/claude-sonnet-4-6");
  });

  it("sem chave → null (orquestrador não escala ao LLM)", () => {
    expect(buildLLMConfig({}, () => undefined)).toBeNull();
  });
});

describe("OpenRouterProvider", () => {
  it("envia Bearer + slug e parseia choices[0].message.content", async () => {
    const cap: { url?: string; init?: any } = {};
    const provider = createLLMProvider(
      { provider: "openrouter", apiKey: "sk-or", defaultModel: "anthropic/claude-haiku-4-5" },
      fakeFetch(cap, { choices: [{ message: { content: "resposta do modelo" } }] }),
    );
    const out = await provider.complete([{ role: "user", content: "oi" }]);
    expect(out).toBe("resposta do modelo");
    expect(cap.url).toContain("openrouter.ai");
    expect(cap.init.headers["Authorization"]).toBe("Bearer sk-or");
    expect(JSON.parse(cap.init.body).model).toBe("anthropic/claude-haiku-4-5");
  });
});

describe("AnthropicProvider", () => {
  it("usa x-api-key, separa system, e parseia content text block", async () => {
    const cap: { url?: string; init?: any } = {};
    const provider = createLLMProvider(
      { provider: "anthropic", apiKey: "sk-ant", defaultModel: "claude-haiku-4-5" },
      fakeFetch(cap, { content: [{ type: "text", text: "olá" }] }),
    );
    const out = await provider.complete([
      { role: "system", content: "seja conciso" },
      { role: "user", content: "oi" },
    ]);
    expect(out).toBe("olá");
    expect(cap.url).toContain("api.anthropic.com");
    expect(cap.init.headers["x-api-key"]).toBe("sk-ant");
    const body = JSON.parse(cap.init.body);
    expect(body.system).toBe("seja conciso");
    expect(body.messages).toEqual([{ role: "user", content: "oi" }]);
  });
});

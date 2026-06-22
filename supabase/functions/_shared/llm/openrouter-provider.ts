// Adapter OpenRouter (endpoint compatível com OpenAI).
// Modelos via slug "anthropic/claude-haiku-4-5", etc.

import type {
  FetchLike,
  LLMCompleteOptions,
  LLMMessage,
  LLMProvider,
} from "./types.ts";

const ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";

export class OpenRouterProvider implements LLMProvider {
  readonly name = "openrouter";
  constructor(
    private readonly apiKey: string,
    private readonly defaultModel: string,
    private readonly fetchFn: FetchLike = globalThis.fetch as unknown as FetchLike,
  ) {}

  async complete(
    messages: LLMMessage[],
    opts?: LLMCompleteOptions,
  ): Promise<string> {
    const res = await this.fetchFn(ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
        // Boas práticas OpenRouter (opcional, ajuda atribuição):
        "X-Title": "MarineFlow AI Operator",
      },
      body: JSON.stringify({
        model: opts?.model || this.defaultModel,
        messages: messages.map((m) => ({ role: m.role, content: m.content })),
        max_tokens: opts?.maxTokens ?? 1024,
      }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(
        `OpenRouter HTTP ${res.status}: ${(err as any)?.error?.message ?? "erro"}`,
      );
    }
    const body = await res.json();
    return String(body?.choices?.[0]?.message?.content ?? "").trim();
  }
}

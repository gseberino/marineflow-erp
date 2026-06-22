// Adapter Anthropic direto (Messages API).
// Modelos: "claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8".
// Mensagens "system" vão no campo top-level `system` (a Messages API separa
// system das messages user/assistant).

import type {
  FetchLike,
  LLMCompleteOptions,
  LLMMessage,
  LLMProvider,
} from "./types.ts";

const ENDPOINT = "https://api.anthropic.com/v1/messages";

export class AnthropicProvider implements LLMProvider {
  readonly name = "anthropic";
  constructor(
    private readonly apiKey: string,
    private readonly defaultModel: string,
    private readonly fetchFn: FetchLike = globalThis.fetch as unknown as FetchLike,
  ) {}

  async complete(
    messages: LLMMessage[],
    opts?: LLMCompleteOptions,
  ): Promise<string> {
    const system = messages
      .filter((m) => m.role === "system")
      .map((m) => m.content)
      .join("\n\n");
    const convo = messages
      .filter((m) => m.role !== "system")
      .map((m) => ({ role: m.role, content: m.content }));

    const payload: Record<string, unknown> = {
      model: opts?.model || this.defaultModel,
      max_tokens: opts?.maxTokens ?? 1024,
      messages: convo,
    };
    if (system) payload.system = system;

    const res = await this.fetchFn(ENDPOINT, {
      method: "POST",
      headers: {
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(
        `Anthropic HTTP ${res.status}: ${(err as any)?.error?.message ?? "erro"}`,
      );
    }
    const body = await res.json();
    const textBlock = (body?.content ?? []).find((b: any) => b?.type === "text");
    return String(textBlock?.text ?? "").trim();
  }
}

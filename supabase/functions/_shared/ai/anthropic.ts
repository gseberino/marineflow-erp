// Cliente HTTP para a API de Mensagens da Anthropic (fetch nativo do Deno, sem SDK).
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

export type ClaudeCacheControl = { type: "ephemeral" };

export type ClaudeTextBlock = { type: "text"; text: string; cache_control?: ClaudeCacheControl };
export type ClaudeToolUseBlock = { type: "tool_use"; id: string; name: string; input: Record<string, unknown> };
export type ClaudeToolResultBlock = {
  type: "tool_result";
  tool_use_id: string;
  content: string;
  is_error?: boolean;
  cache_control?: ClaudeCacheControl;
};
export type ClaudeContentBlock = ClaudeTextBlock | ClaudeToolUseBlock | ClaudeToolResultBlock;

export type ClaudeMessage = {
  role: "user" | "assistant";
  content: ClaudeContentBlock[];
};

export type ClaudeToolSchema = {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
};

export type ClaudeUsage = {
  inputTokens: number;
  outputTokens: number;
  cacheReadInputTokens: number;
  cacheCreationInputTokens: number;
};

export type CallClaudeParams = {
  model: string;
  system: ClaudeTextBlock[];
  messages: ClaudeMessage[];
  tools?: ClaudeToolSchema[];
  maxTokens?: number;
  /** Só o modelo agente (Sonnet) aceita este campo — omitir para Haiku. */
  effort?: "medium" | "high" | "low";
};

export type CallClaudeResult = {
  content: ClaudeContentBlock[];
  stopReason: string | null;
  usage: ClaudeUsage;
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Erro com o status HTTP original da Anthropic, para o adaptador poder repassar (ex: 429). */
export class ClaudeApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "ClaudeApiError";
    this.status = status;
  }
}

/**
 * Chama a API de Mensagens da Anthropic com retry em 429 (respeitando retry-after)
 * e 529 overloaded_error (backoff, 2 tentativas). Erros 400 são bug de payload — loga
 * o corpo completo para diagnóstico e não tenta de novo.
 */
export async function callClaude(params: CallClaudeParams): Promise<CallClaudeResult> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY não configurada no Supabase");

  const body: Record<string, unknown> = {
    model: params.model,
    max_tokens: params.maxTokens ?? 4096,
    system: params.system,
    messages: params.messages,
  };
  if (params.tools && params.tools.length > 0) body.tools = params.tools;
  if (params.effort) body.output_config = { effort: params.effort };

  const MAX_ATTEMPTS = 3; // tentativa inicial + 2 retries
  let lastError: Error | null = null;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const res = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (res.ok) {
      const json = await res.json();
      const usage: ClaudeUsage = {
        inputTokens: json.usage?.input_tokens ?? 0,
        outputTokens: json.usage?.output_tokens ?? 0,
        cacheReadInputTokens: json.usage?.cache_read_input_tokens ?? 0,
        cacheCreationInputTokens: json.usage?.cache_creation_input_tokens ?? 0,
      };
      console.log(
        `[anthropic] model=${params.model} stop_reason=${json.stop_reason} usage=${JSON.stringify(usage)}`
      );
      return { content: json.content ?? [], stopReason: json.stop_reason ?? null, usage };
    }

    if (res.status === 400) {
      const text = await res.text();
      console.error(`[anthropic] 400 bad request — payload bug. Corpo completo: ${text}`);
      throw new ClaudeApiError(400, `Anthropic 400: ${text}`);
    }

    if (res.status === 429) {
      const text = await res.text();
      lastError = new ClaudeApiError(429, `Anthropic 429: ${text}`);
      if (attempt < MAX_ATTEMPTS - 1) {
        const retryAfter = Number(res.headers.get("retry-after"));
        const waitSeconds = Number.isFinite(retryAfter) && retryAfter >= 0 ? retryAfter : 2 * (attempt + 1);
        await sleep(waitSeconds * 1000);
        continue;
      }
      break;
    }

    if (res.status === 529) {
      const text = await res.text();
      lastError = new ClaudeApiError(529, `Anthropic 529 overloaded_error: ${text}`);
      if (attempt < MAX_ATTEMPTS - 1) {
        await sleep(500 * (attempt + 1));
        continue;
      }
      break;
    }

    // Outros erros (5xx genérico, etc.) — não retry, propaga com corpo pra diagnóstico.
    const text = await res.text();
    throw new ClaudeApiError(res.status, `Anthropic ${res.status}: ${text}`);
  }

  throw lastError ?? new Error("Falha desconhecida ao chamar a Anthropic API");
}

// Cliente HTTP para Claude via OpenRouter (endpoint compatível com a Chat Completions
// da OpenAI: https://openrouter.ai/api/v1/chat/completions).
//
// A interface externa deste módulo (callClaude / CallClaudeParams / CallClaudeResult)
// continua no "vocabulário" nativo da Anthropic — content blocks, tool_use/tool_result,
// cache_control. agent.ts e as tools em tools/*.ts falam só esse vocabulário e não sabem
// que existe OpenRouter por trás; a tradução para o formato OpenAI-shape que o OpenRouter
// espera (e de volta) acontece só aqui dentro. Se um dia for preciso voltar a chamar a
// Anthropic direto (endpoint /v1/messages nativo), é neste arquivo que mexe — o resto do
// núcleo do agente fica igual.
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

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
  /** Vira `reasoning: {effort}` no request do OpenRouter. Omitir para Haiku. */
  effort?: "medium" | "high" | "low";
};

export type CallClaudeResult = {
  content: ClaudeContentBlock[];
  stopReason: string | null;
  usage: ClaudeUsage;
};

/** Erro com o status HTTP original do OpenRouter, para o adaptador poder repassar (ex: 429). */
export class ClaudeApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "ClaudeApiError";
    this.status = status;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------- Tradução: vocabulário nativo Anthropic -> OpenAI-shape (OpenRouter) ----------------

type ORContentPart = { type: "text"; text: string; cache_control?: ClaudeCacheControl };
type ORToolCall = { id: string; type: "function"; function: { name: string; arguments: string } };
type ORMessage =
  | { role: "system"; content: ORContentPart[] }
  | { role: "user"; content: ORContentPart[] }
  | { role: "assistant"; content: string | null; tool_calls?: ORToolCall[] }
  | { role: "tool"; tool_call_id: string; content: string };

function buildOpenRouterMessages(system: ClaudeTextBlock[], messages: ClaudeMessage[]): ORMessage[] {
  const out: ORMessage[] = [
    {
      role: "system",
      content: system.map((b) => ({ type: "text", text: b.text, ...(b.cache_control ? { cache_control: b.cache_control } : {}) })),
    },
  ];

  for (const m of messages) {
    if (m.role === "user") {
      // Um bundle de tool_result vira N mensagens role:"tool" (formato OpenAI clássico).
      const toolResults = m.content.filter((b): b is ClaudeToolResultBlock => b.type === "tool_result");
      if (toolResults.length > 0) {
        for (const tr of toolResults) {
          out.push({ role: "tool", tool_call_id: tr.tool_use_id, content: tr.content });
        }
        continue;
      }
      const textBlocks = m.content.filter((b): b is ClaudeTextBlock => b.type === "text");
      out.push({
        role: "user",
        content: textBlocks.map((b) => ({ type: "text", text: b.text, ...(b.cache_control ? { cache_control: b.cache_control } : {}) })),
      });
    } else {
      const textBlocks = m.content.filter((b): b is ClaudeTextBlock => b.type === "text");
      const toolUseBlocks = m.content.filter((b): b is ClaudeToolUseBlock => b.type === "tool_use");
      const text = textBlocks.map((b) => b.text).join("") || null;
      const tool_calls: ORToolCall[] | undefined = toolUseBlocks.length
        ? toolUseBlocks.map((b) => ({ id: b.id, type: "function", function: { name: b.name, arguments: JSON.stringify(b.input) } }))
        : undefined;
      out.push({ role: "assistant", content: text, ...(tool_calls ? { tool_calls } : {}) });
    }
  }
  return out;
}

/** finish_reason (OpenAI-shape) -> stop_reason (nosso vocabulário nativo Anthropic). */
function finishReasonToStopReason(reason: string | null | undefined): string | null {
  switch (reason) {
    case "length":
      return "max_tokens";
    case "tool_calls":
      return "tool_use";
    case "stop":
      return "end_turn";
    default:
      return reason ?? null;
  }
}

/**
 * Chama Claude via OpenRouter. Retry com backoff em 429/502/503 (respeitando retry-after
 * quando presente — só 429 e 503 costumam mandar o header, mas checar sempre é inofensivo).
 * 400/401 são bug de payload/credencial — loga o corpo completo e não tenta de novo. 402 é
 * crédito insuficiente na conta OpenRouter — erro distinto, também sem retry.
 */
export async function callClaude(params: CallClaudeParams): Promise<CallClaudeResult> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) throw new Error("OPENROUTER_API_KEY não configurada no Supabase");

  const body: Record<string, unknown> = {
    model: params.model,
    max_tokens: params.maxTokens ?? 4096,
    messages: buildOpenRouterMessages(params.system, params.messages),
  };
  if (params.tools && params.tools.length > 0) {
    body.tools = params.tools.map((t) => ({ type: "function", function: { name: t.name, description: t.description, parameters: t.input_schema } }));
  }
  if (params.effort) body.reasoning = { effort: params.effort };

  const MAX_ATTEMPTS = 3; // tentativa inicial + 2 retries
  let lastError: Error | null = null;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
        "HTTP-Referer": "https://hbrmarine.online",
        "X-Title": "MarineFlow AI Operator",
      },
      body: JSON.stringify(body),
    });

    if (res.ok) {
      const json = await res.json();
      const choice = json.choices?.[0];
      const message = choice?.message;

      const content: ClaudeContentBlock[] = [];
      if (message?.content) content.push({ type: "text", text: message.content });
      for (const tc of message?.tool_calls || []) {
        let input: Record<string, unknown> = {};
        try {
          input = JSON.parse(tc.function?.arguments || "{}");
        } catch {
          input = {};
        }
        content.push({ type: "tool_use", id: tc.id, name: tc.function?.name, input });
      }

      const usage: ClaudeUsage = {
        inputTokens: json.usage?.prompt_tokens ?? 0,
        outputTokens: json.usage?.completion_tokens ?? 0,
        cacheReadInputTokens: json.usage?.prompt_tokens_details?.cached_tokens ?? 0,
        cacheCreationInputTokens: json.usage?.prompt_tokens_details?.cache_write_tokens ?? 0,
      };
      const stopReason = finishReasonToStopReason(choice?.finish_reason);
      console.log(`[openrouter] model=${params.model} finish_reason=${choice?.finish_reason} usage=${JSON.stringify(usage)}`);
      return { content, stopReason, usage };
    }

    if (res.status === 400 || res.status === 401) {
      const text = await res.text();
      console.error(`[openrouter] ${res.status} — payload/credencial com problema. Corpo completo: ${text}`);
      throw new ClaudeApiError(res.status, `OpenRouter ${res.status}: ${text}`);
    }

    if (res.status === 402) {
      const text = await res.text();
      throw new ClaudeApiError(402, `OpenRouter 402 (créditos insuficientes na conta): ${text}`);
    }

    if (res.status === 429 || res.status === 502 || res.status === 503) {
      const text = await res.text();
      lastError = new ClaudeApiError(res.status, `OpenRouter ${res.status}: ${text}`);
      if (attempt < MAX_ATTEMPTS - 1) {
        const retryAfter = Number(res.headers.get("retry-after"));
        const waitSeconds = Number.isFinite(retryAfter) && retryAfter >= 0 ? retryAfter : 2 * (attempt + 1);
        await sleep(waitSeconds * 1000);
        continue;
      }
      break;
    }

    // Outros erros — não retry, propaga com corpo pra diagnóstico.
    const text = await res.text();
    throw new ClaudeApiError(res.status, `OpenRouter ${res.status}: ${text}`);
  }

  throw lastError ?? new Error("Falha desconhecida ao chamar o OpenRouter");
}

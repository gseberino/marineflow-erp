// Shared AI provider error handling utilities.
// Classifies provider errors, implements safe retry with exponential backoff,
// and provides user-facing messages for overload and rate-limit scenarios.
//
// Observability notes:
// - logs only provider metadata and sanitized error previews;
// - never logs API keys, Authorization headers, prompts, messages, tool payloads,
//   or the full request body.

export type AIErrorClassification =
  | "provider_overloaded"
  | "rate_limit"
  | "billing"
  | "permission"
  | "unknown";

export type AIFetchResult =
  | { ok: true; response: Response; attempts: number }
  | {
      ok: false;
      response: Response;
      rawBody: string;
      classification: AIErrorClassification;
      attempts: number;
    };

type AIProviderLogPayload = {
  event: "ai_provider_retry" | "ai_provider_final_error" | "ai_provider_recovered";
  endpoint_host: string;
  endpoint_path: string;
  model: string;
  status?: number;
  classification?: AIErrorClassification;
  attempts: number;
  max_retries: number;
  retrying?: boolean;
  next_delay_ms?: number;
  retry_after?: number;
  body_preview?: string;
};

// Retryable classifications: only these get retried when maxRetries > 0.
// 403 (permission), 402 (billing), unknown → never retried.
const RETRYABLE: ReadonlySet<AIErrorClassification> = new Set([
  "provider_overloaded",
  "rate_limit",
]);

// Cap Retry-After at 15s so Edge Functions don't time out.
const RETRY_AFTER_CAP_MS = 15_000;

/**
 * Classifies a provider HTTP error.
 * Permission errors (403, PERMISSION_DENIED, dunning) always take precedence
 * and are never reclassified as overload.
 */
export function classifyAIProviderError(
  status: number,
  body: string
): AIErrorClassification {
  if (
    status === 403 ||
    body.includes("PERMISSION_DENIED") ||
    body.includes("dunning")
  ) {
    return "permission";
  }
  if (status === 429) return "rate_limit";
  if (status === 402) return "billing";
  if (status === 503) return "provider_overloaded";
  const lower = body.toLowerCase();
  if (
    lower.includes("unavailable") ||
    lower.includes("high demand") ||
    lower.includes("overloaded")
  ) {
    return "provider_overloaded";
  }
  return "unknown";
}

function summarizeEndpoint(url: string): { endpoint_host: string; endpoint_path: string } {
  try {
    const parsed = new URL(url);
    return { endpoint_host: parsed.host, endpoint_path: parsed.pathname };
  } catch {
    return { endpoint_host: "unknown", endpoint_path: "unknown" };
  }
}

function extractModel(init: RequestInit): string {
  try {
    if (typeof init.body !== "string") return "unknown";
    const body = JSON.parse(init.body);
    return typeof body?.model === "string" ? body.model : "unknown";
  } catch {
    return "unknown";
  }
}

function sanitizeProviderBody(rawBody: string): string {
  return String(rawBody || "")
    .replace(/AIza[0-9A-Za-z_-]{10,}/g, "[REDACTED_API_KEY]")
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, "Bearer [REDACTED]")
    .replace(/sk-[A-Za-z0-9_-]{10,}/g, "[REDACTED_API_KEY]")
    .replace(/gh[pousr]_[A-Za-z0-9_]{10,}/g, "[REDACTED_TOKEN]")
    .slice(0, 500);
}

/**
 * Extracts Retry-After delay in milliseconds from the response header.
 * Supports integer seconds only (most common for API rate limits).
 * Returns null if the header is absent or unparseable.
 */
export function extractRetryAfterMs(response: Response): number | null {
  const header = response.headers.get("Retry-After");
  if (!header) return null;
  const seconds = parseInt(header, 10);
  if (!isNaN(seconds) && seconds > 0) {
    return Math.min(seconds * 1000, RETRY_AFTER_CAP_MS);
  }
  return null;
}

function logProviderEvent(payload: AIProviderLogPayload): void {
  const logLine = JSON.stringify(payload);
  if (payload.event === "ai_provider_retry") {
    console.warn("[ai-provider]", logLine);
    return;
  }
  if (payload.event === "ai_provider_recovered") {
    console.info("[ai-provider]", logLine);
    return;
  }
  console.error("[ai-provider]", logLine);
}

/**
 * Fetches an AI endpoint with safe retry for provider_overloaded and rate_limit errors.
 * Returns a discriminated result — on failure, rawBody is pre-read so
 * callers MUST NOT call response.text() again (body already consumed).
 * On success, response body is untouched — callers use response.json() normally.
 *
 * Retry policy:
 *   - Only provider_overloaded and rate_limit are retried.
 *   - 403/402/unknown → never retried regardless of maxRetries.
 *   - Respects Retry-After header (capped at 15s) for rate_limit responses.
 *   - Pass maxRetries=0 to disable all retries (used for iter > 0 in main loops).
 */
export async function fetchAIWithRetry(
  url: string,
  init: RequestInit,
  opts: { maxRetries?: number; baseDelayMs?: number } = {}
): Promise<AIFetchResult> {
  const maxRetries = opts.maxRetries ?? 2;
  const baseDelayMs = opts.baseDelayMs ?? 1000;
  const endpoint = summarizeEndpoint(url);
  const model = extractModel(init);

  let attempts = 0;

  for (let i = 0; i <= maxRetries; i++) {
    attempts++;
    const response = await fetch(url, init);

    if (response.ok) {
      if (attempts > 1) {
        logProviderEvent({
          event: "ai_provider_recovered",
          ...endpoint,
          model,
          status: response.status,
          attempts,
          max_retries: maxRetries,
        });
      }
      return { ok: true, response, attempts };
    }

    const rawBody = await response.text();
    const classification = classifyAIProviderError(response.status, rawBody);

    const isLast = i === maxRetries;
    if (!RETRYABLE.has(classification) || isLast) {
      logProviderEvent({
        event: "ai_provider_final_error",
        ...endpoint,
        model,
        status: response.status,
        classification,
        attempts,
        max_retries: maxRetries,
        retrying: false,
        body_preview: sanitizeProviderBody(rawBody),
      });
      return { ok: false, response, rawBody, classification, attempts };
    }

    const retryAfterMs = extractRetryAfterMs(response);
    const nextDelayMs = retryAfterMs ?? baseDelayMs * Math.pow(2, i);
    logProviderEvent({
      event: "ai_provider_retry",
      ...endpoint,
      model,
      status: response.status,
      classification,
      attempts,
      max_retries: maxRetries,
      retrying: true,
      next_delay_ms: nextDelayMs,
      ...(retryAfterMs !== null ? { retry_after: retryAfterMs } : {}),
      body_preview: sanitizeProviderBody(rawBody),
    });

    await new Promise<void>((resolve) => setTimeout(resolve, nextDelayMs));
  }

  // Unreachable — TypeScript requires exhaustive return path.
  throw new Error("fetchAIWithRetry: unexpected loop exit");
}

/**
 * Returns a safe, user-facing overload message (503 / provider_overloaded).
 * iter === 0: no tool calls have been made yet, no side effects possible.
 * iter > 0: tool calls may have run; conservative message required.
 */
export function resolveOverloadUserMessage(iter: number): string {
  if (iter === 0) {
    return "A IA está temporariamente sobrecarregada no provedor. Tente novamente em instantes. Nenhum dado foi alterado.";
  }
  return "A IA está temporariamente sobrecarregada no provedor. A operação foi interrompida antes da resposta final. Verifique o histórico/registro antes de repetir a ação.";
}

/**
 * Returns a safe, user-facing rate-limit message (429 / rate_limit).
 * iter === 0: no tool calls have been made yet, no side effects possible.
 * iter > 0: tool calls may have run; conservative message required.
 */
export function resolveRateLimitUserMessage(iter: number): string {
  if (iter === 0) {
    return "O limite temporário do provedor de IA foi atingido. Aguarde cerca de 1 minuto e tente novamente. Nenhum dado foi alterado.";
  }
  return "O limite temporário do provedor de IA foi atingido. A operação foi interrompida antes da resposta final. Verifique o histórico/registro antes de repetir a ação.";
}

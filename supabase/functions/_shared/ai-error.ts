// Shared AI provider error handling utilities.
// Classifies provider errors, implements safe retry with exponential backoff,
// and provides user-facing messages for overload scenarios.

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

/**
 * Fetches an AI endpoint with safe retry for provider_overloaded errors.
 * Returns a discriminated result — on failure, rawBody is pre-read so
 * callers MUST NOT call response.text() again (body already consumed).
 * On success, response body is untouched — callers use response.json() normally.
 */
export async function fetchAIWithRetry(
  url: string,
  init: RequestInit,
  opts: { maxRetries?: number; baseDelayMs?: number } = {}
): Promise<AIFetchResult> {
  const maxRetries = opts.maxRetries ?? 2;
  const baseDelayMs = opts.baseDelayMs ?? 1000;

  let attempts = 0;

  for (let i = 0; i <= maxRetries; i++) {
    attempts++;
    const response = await fetch(url, init);

    if (response.ok) {
      return { ok: true, response, attempts };
    }

    const rawBody = await response.text();
    const classification = classifyAIProviderError(response.status, rawBody);

    const isLast = i === maxRetries;
    if (classification !== "provider_overloaded" || isLast) {
      return { ok: false, response, rawBody, classification, attempts };
    }

    await new Promise<void>((resolve) =>
      setTimeout(resolve, baseDelayMs * Math.pow(2, i))
    );
  }

  // Unreachable — TypeScript requires exhaustive return path.
  throw new Error("fetchAIWithRetry: unexpected loop exit");
}

/**
 * Returns a safe, user-facing overload message.
 * iter === 0: no tool calls have been made yet, no side effects possible.
 * iter > 0: tool calls may have run; conservative message required.
 */
export function resolveOverloadUserMessage(iter: number): string {
  if (iter === 0) {
    return "A IA está temporariamente sobrecarregada no provedor. Tente novamente em instantes. Nenhum dado foi alterado.";
  }
  return "A IA está temporariamente sobrecarregada no provedor. A operação foi interrompida antes da resposta final. Verifique o histórico/registro antes de repetir a ação.";
}

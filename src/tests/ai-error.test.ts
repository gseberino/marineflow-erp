import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  classifyAIProviderError,
  fetchAIWithRetry,
  extractRetryAfterMs,
  resolveOverloadUserMessage,
  resolveRateLimitUserMessage,
} from "../../supabase/functions/_shared/ai-error.ts";

// ---------------------------------------------------------------------------
// classifyAIProviderError
// ---------------------------------------------------------------------------
describe("classifyAIProviderError", () => {
  it("classifies 503 with UNAVAILABLE body as provider_overloaded", () => {
    expect(
      classifyAIProviderError(503, '{"error":{"status":"UNAVAILABLE","message":"..."}}'
    )).toBe("provider_overloaded");
  });

  it("classifies 503 with 'high demand' body as provider_overloaded", () => {
    expect(
      classifyAIProviderError(
        503,
        "This model is currently experiencing high demand."
      )
    ).toBe("provider_overloaded");
  });

  it("classifies 503 with 'overloaded' body as provider_overloaded", () => {
    expect(classifyAIProviderError(503, "server overloaded")).toBe(
      "provider_overloaded"
    );
  });

  it("classifies bare 503 (empty body) as provider_overloaded", () => {
    expect(classifyAIProviderError(503, "")).toBe("provider_overloaded");
  });

  it("classifies 429 as rate_limit", () => {
    expect(classifyAIProviderError(429, "")).toBe("rate_limit");
  });

  it("classifies 402 as billing", () => {
    expect(classifyAIProviderError(402, "")).toBe("billing");
  });

  it("classifies 403 as permission", () => {
    expect(classifyAIProviderError(403, "")).toBe("permission");
  });

  it("classifies PERMISSION_DENIED body as permission regardless of status code", () => {
    expect(classifyAIProviderError(400, "PERMISSION_DENIED")).toBe("permission");
  });

  it("classifies dunning body as permission", () => {
    expect(classifyAIProviderError(403, "dunning")).toBe("permission");
  });

  it("does NOT reclassify 403 PERMISSION_DENIED as provider_overloaded", () => {
    const result = classifyAIProviderError(403, "PERMISSION_DENIED overloaded");
    expect(result).toBe("permission");
    expect(result).not.toBe("provider_overloaded");
  });

  it("classifies unknown status with generic body as unknown", () => {
    expect(classifyAIProviderError(500, "internal server error")).toBe(
      "unknown"
    );
  });

  it("classifies 504 with unrecognized body as unknown", () => {
    expect(classifyAIProviderError(504, "gateway timeout")).toBe("unknown");
  });

  it("classifies 403 with RESOURCE_EXHAUSTED body as rate_limit (Google quota exhaustion)", () => {
    expect(
      classifyAIProviderError(
        403,
        '{"error":{"code":403,"status":"RESOURCE_EXHAUSTED","message":"Quota exceeded"}}'
      )
    ).toBe("rate_limit");
  });

  it("classifies 429 with RESOURCE_EXHAUSTED body as rate_limit", () => {
    expect(
      classifyAIProviderError(429, '{"error":{"status":"RESOURCE_EXHAUSTED"}}')
    ).toBe("rate_limit");
  });

  it("classifies rateLimitExceeded body as rate_limit regardless of status", () => {
    expect(classifyAIProviderError(400, "rateLimitExceeded")).toBe("rate_limit");
  });

  it("403 with RESOURCE_EXHAUSTED is NOT classified as permission", () => {
    const result = classifyAIProviderError(
      403,
      '{"error":{"status":"RESOURCE_EXHAUSTED"}}'
    );
    expect(result).not.toBe("permission");
    expect(result).toBe("rate_limit");
  });
});

// ---------------------------------------------------------------------------
// resolveOverloadUserMessage
// ---------------------------------------------------------------------------
describe("resolveOverloadUserMessage", () => {
  it("returns no-side-effects message for iter === 0", () => {
    const msg = resolveOverloadUserMessage(0);
    expect(msg).toContain("Nenhum dado foi alterado");
  });

  it("returns conservative message for iter === 1", () => {
    const msg = resolveOverloadUserMessage(1);
    expect(msg).toContain("Verifique o histórico");
  });

  it("returns conservative message for any iter > 0", () => {
    expect(resolveOverloadUserMessage(5)).toContain("Verifique o histórico");
  });

  it("messages for iter === 0 and iter > 0 are different", () => {
    expect(resolveOverloadUserMessage(0)).not.toBe(
      resolveOverloadUserMessage(1)
    );
  });
});

// ---------------------------------------------------------------------------
// resolveRateLimitUserMessage
// ---------------------------------------------------------------------------
describe("resolveRateLimitUserMessage", () => {
  it("returns no-side-effects message for iter === 0", () => {
    const msg = resolveRateLimitUserMessage(0);
    expect(msg).toContain("Nenhum dado foi alterado");
  });

  it("returns conservative message for iter === 1", () => {
    const msg = resolveRateLimitUserMessage(1);
    expect(msg).toContain("Verifique o histórico");
  });

  it("returns conservative message for any iter > 0", () => {
    expect(resolveRateLimitUserMessage(5)).toContain("Verifique o histórico");
  });

  it("messages for iter === 0 and iter > 0 are different", () => {
    expect(resolveRateLimitUserMessage(0)).not.toBe(
      resolveRateLimitUserMessage(1)
    );
  });

  it("iter=0 message is different from overload iter=0 message", () => {
    expect(resolveRateLimitUserMessage(0)).not.toBe(resolveOverloadUserMessage(0));
  });
});

// ---------------------------------------------------------------------------
// extractRetryAfterMs
// ---------------------------------------------------------------------------
describe("extractRetryAfterMs", () => {
  it("returns null when header is absent", () => {
    const res = new Response("", { status: 429 });
    expect(extractRetryAfterMs(res)).toBeNull();
  });

  it("parses integer seconds and converts to ms", () => {
    const res = new Response("", {
      status: 429,
      headers: { "Retry-After": "5" },
    });
    expect(extractRetryAfterMs(res)).toBe(5000);
  });

  it("caps at 15 000 ms", () => {
    const res = new Response("", {
      status: 429,
      headers: { "Retry-After": "120" },
    });
    expect(extractRetryAfterMs(res)).toBe(15_000);
  });

  it("returns null for non-integer value", () => {
    const res = new Response("", {
      status: 429,
      headers: { "Retry-After": "not-a-number" },
    });
    expect(extractRetryAfterMs(res)).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// fetchAIWithRetry
// ---------------------------------------------------------------------------
describe("fetchAIWithRetry", () => {
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns ok:true on success and does NOT consume the response body", async () => {
    const bodyText = JSON.stringify({ choices: [{ message: { content: "ok" } }] });
    fetchMock.mockResolvedValueOnce(new Response(bodyText, { status: 200 }));

    const result = await fetchAIWithRetry("https://example.com", {});

    expect(result.ok).toBe(true);
    if (result.ok) {
      // Body must still be consumable by the caller
      const json = await result.response.json();
      expect(json.choices).toBeDefined();
    }
  });

  it("returns ok:false with rawBody on error, body already read", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response('{"error":"UNAVAILABLE"}', { status: 503 })
    );

    const result = await fetchAIWithRetry("https://example.com", {}, { maxRetries: 0 });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.rawBody).toBe('{"error":"UNAVAILABLE"}');
      expect(result.classification).toBe("provider_overloaded");
    }
  });

  it("attempts reflects real attempts: 403 with maxRetries=2 → attempts=1", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response("PERMISSION_DENIED", { status: 403 })
    );

    const result = await fetchAIWithRetry("https://example.com", {}, {
      maxRetries: 2,
    });

    expect(result.ok).toBe(false);
    expect(result.attempts).toBe(1);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("attempts reflects real attempts: 503 with 2 retries and final failure → attempts=3", async () => {
    fetchMock
      .mockResolvedValueOnce(new Response("overloaded", { status: 503 }))
      .mockResolvedValueOnce(new Response("overloaded", { status: 503 }))
      .mockResolvedValueOnce(new Response("overloaded", { status: 503 }));

    const result = await fetchAIWithRetry("https://example.com", {}, {
      maxRetries: 2,
      baseDelayMs: 0,
    });

    expect(result.ok).toBe(false);
    expect(result.attempts).toBe(3);
    if (!result.ok) {
      expect(result.classification).toBe("provider_overloaded");
    }
  });

  it("retries provider_overloaded and succeeds on second attempt", async () => {
    fetchMock
      .mockResolvedValueOnce(new Response("overloaded", { status: 503 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ choices: [] }), { status: 200 })
      );

    const result = await fetchAIWithRetry("https://example.com", {}, {
      maxRetries: 2,
      baseDelayMs: 0,
    });

    expect(result.ok).toBe(true);
    expect(result.attempts).toBe(2);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("does NOT retry 403 (permission)", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response("PERMISSION_DENIED", { status: 403 })
    );

    await fetchAIWithRetry("https://example.com", {}, { maxRetries: 2 });

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("does NOT retry 402 (billing)", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response("billing required", { status: 402 })
    );

    await fetchAIWithRetry("https://example.com", {}, { maxRetries: 2 });

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("retries 429 (rate_limit) when maxRetries > 0", async () => {
    fetchMock
      .mockResolvedValueOnce(new Response("rate limit", { status: 429 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ choices: [] }), { status: 200 })
      );

    const result = await fetchAIWithRetry("https://example.com", {}, {
      maxRetries: 2,
      baseDelayMs: 0,
    });

    expect(result.ok).toBe(true);
    expect(result.attempts).toBe(2);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("does NOT retry 429 when maxRetries === 0 (safe for iter > 0)", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response("rate limit", { status: 429 })
    );

    const result = await fetchAIWithRetry("https://example.com", {}, { maxRetries: 0 });

    expect(result.ok).toBe(false);
    expect(result.attempts).toBe(1);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    if (!result.ok) {
      expect(result.classification).toBe("rate_limit");
    }
  });

  it("attempts reflects real attempts: 429 with 2 retries and final failure → attempts=3", async () => {
    fetchMock
      .mockResolvedValueOnce(new Response("rate limit", { status: 429 }))
      .mockResolvedValueOnce(new Response("rate limit", { status: 429 }))
      .mockResolvedValueOnce(new Response("rate limit", { status: 429 }));

    const result = await fetchAIWithRetry("https://example.com", {}, {
      maxRetries: 2,
      baseDelayMs: 0,
    });

    expect(result.ok).toBe(false);
    expect(result.attempts).toBe(3);
    if (!result.ok) {
      expect(result.classification).toBe("rate_limit");
    }
  });

  it("respects Retry-After header for 429 responses", async () => {
    const delaysSeen: number[] = [];
    const origSetTimeout = globalThis.setTimeout;
    vi.spyOn(globalThis, "setTimeout").mockImplementation((fn: any, ms?: number) => {
      delaysSeen.push(ms ?? 0);
      fn();
      return 0 as any;
    });

    fetchMock
      .mockResolvedValueOnce(
        new Response("rate limit", {
          status: 429,
          headers: { "Retry-After": "3" },
        })
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true }), { status: 200 })
      );

    await fetchAIWithRetry("https://example.com", {}, {
      maxRetries: 1,
      baseDelayMs: 1000,
    });

    expect(delaysSeen[0]).toBe(3000);
    vi.restoreAllMocks();
  });

  it("503 allows retry (provider_overloaded is retryable)", async () => {
    fetchMock
      .mockResolvedValueOnce(new Response("overloaded", { status: 503 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true }), { status: 200 })
      );

    const result = await fetchAIWithRetry("https://example.com", {}, {
      maxRetries: 1,
      baseDelayMs: 0,
    });

    expect(result.ok).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("success on first attempt → attempts=1", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ ok: true }), { status: 200 })
    );

    const result = await fetchAIWithRetry("https://example.com", {});
    expect(result.attempts).toBe(1);
  });

  it("falls back to fallbackModel after rate_limit exhaustion and returns ok:true", async () => {
    const body = JSON.stringify({ model: "gemini-2.5-pro", messages: [] });
    fetchMock
      .mockResolvedValueOnce(new Response("rate limit", { status: 429 }))
      .mockResolvedValueOnce(new Response("rate limit", { status: 429 }))
      .mockResolvedValueOnce(new Response("rate limit", { status: 429 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ choices: [] }), { status: 200 })
      );

    const result = await fetchAIWithRetry(
      "https://example.com",
      { method: "POST", body },
      { maxRetries: 2, baseDelayMs: 0, fallbackModel: "gemini-2.5-flash" }
    );

    expect(result.ok).toBe(true);
    expect(result.attempts).toBe(4);
    expect(fetchMock).toHaveBeenCalledTimes(4);
    // The 4th call must use the fallback model
    const lastCallBody = JSON.parse(fetchMock.mock.calls[3][1].body);
    expect(lastCallBody.model).toBe("gemini-2.5-flash");
  });

  it("does NOT attempt fallback when fallbackModel equals the current model", async () => {
    const body = JSON.stringify({ model: "gemini-2.5-flash", messages: [] });
    fetchMock.mockResolvedValueOnce(new Response("rate limit", { status: 429 }));

    const result = await fetchAIWithRetry(
      "https://example.com",
      { method: "POST", body },
      { maxRetries: 0, baseDelayMs: 0, fallbackModel: "gemini-2.5-flash" }
    );

    expect(result.ok).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("does NOT attempt fallback for non-rate-limit errors (permission stays permission)", async () => {
    const body = JSON.stringify({ model: "gemini-2.5-pro", messages: [] });
    fetchMock.mockResolvedValueOnce(
      new Response("PERMISSION_DENIED", { status: 403 })
    );

    const result = await fetchAIWithRetry(
      "https://example.com",
      { method: "POST", body },
      { maxRetries: 2, fallbackModel: "gemini-2.5-flash" }
    );

    expect(result.ok).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    if (!result.ok) expect(result.classification).toBe("permission");
  });
});

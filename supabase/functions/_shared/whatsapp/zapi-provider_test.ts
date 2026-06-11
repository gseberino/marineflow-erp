// Tests for ZapiProvider
// Run: deno test supabase/functions/_shared/whatsapp/zapi-provider_test.ts
import {
  assertEquals,
  assertFalse,
  assertMatch,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ZapiProvider } from "./zapi-provider.ts";

// ─── helpers ─────────────────────────────────────────────────────────────────

function mockFetch(
  body: unknown,
  status = 200,
): { fetchStub: typeof globalThis.fetch; calls: Array<{ url: string; init?: RequestInit }> } {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetchStub: typeof globalThis.fetch = (input, init) => {
    calls.push({ url: typeof input === "string" ? input : (input as Request).url, init });
    return Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };
  return { fetchStub, calls };
}

function withFetch<T>(
  stub: typeof globalThis.fetch,
  fn: () => Promise<T>,
): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  return fn().finally(() => {
    globalThis.fetch = original;
  });
}

const provider = new ZapiProvider({
  instanceId: "inst123",
  token: "tok456",
  clientToken: "ct789",
});

const BASE = "https://api.z-api.io/instances/inst123/token/tok456";

// ─── sendText ────────────────────────────────────────────────────────────────

Deno.test("sendText: success response maps messageId to providerMessageId", async () => {
  const { fetchStub } = mockFetch({ messageId: "zapi-msg-001" });
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Olá"),
  );
  assertEquals(result, { ok: true, providerMessageId: "zapi-msg-001" });
});

Deno.test("sendText: success response uses id field when messageId absent", async () => {
  const { fetchStub } = mockFetch({ id: "zapi-id-002" });
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Olá"),
  );
  assertEquals(result, { ok: true, providerMessageId: "zapi-id-002" });
});

Deno.test("sendText: provider returns {error} field → ok:false, retryable:false", async () => {
  const { fetchStub } = mockFetch({ error: "BLOCKED_NUMBER" }, 200);
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Olá"),
  );
  assertEquals(result, { ok: false, error: "BLOCKED_NUMBER", retryable: false });
});

Deno.test("sendText: HTTP 500 → ok:false, retryable:true", async () => {
  const { fetchStub } = mockFetch({}, 500);
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Olá"),
  );
  assertEquals(result, { ok: false, error: "HTTP 500", retryable: true });
});

Deno.test("sendText: HTTP 400 → ok:false, retryable:false", async () => {
  const { fetchStub } = mockFetch({}, 400);
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Olá"),
  );
  assertEquals(result, { ok: false, error: "HTTP 400", retryable: false });
});

Deno.test("sendText: network error (fetch throws) → ok:false, retryable:true", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => Promise.reject(new Error("connection refused"));
  try {
    const result = await provider.sendText("5547999999999", "Olá");
    assertFalse(result.ok);
    assertEquals((result as { ok: false; error: string; retryable: boolean }).retryable, true);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("sendText: phone is normalized before sending (strips formatting)", async () => {
  const { fetchStub, calls } = mockFetch({ messageId: "m1" });
  await withFetch(fetchStub, () =>
    provider.sendText("+55 (47) 9-9999-9999", "Hi"),
  );
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.phone, "5547999999999");
});

Deno.test("sendText: hits the correct endpoint URL", async () => {
  const { fetchStub, calls } = mockFetch({ messageId: "m2" });
  await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Hi"),
  );
  assertEquals(calls[0].url, `${BASE}/send-text`);
});

// ─── sendLink ────────────────────────────────────────────────────────────────

Deno.test("sendLink: hits send-link endpoint with correct payload", async () => {
  const { fetchStub, calls } = mockFetch({ messageId: "m3" });
  await withFetch(fetchStub, () =>
    provider.sendLink(
      "5547999999999",
      "Confira",
      "https://example.com",
      "Título",
      "Desc",
      "https://img.example.com/img.png",
    ),
  );
  assertEquals(calls[0].url, `${BASE}/send-link`);
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.linkUrl, "https://example.com");
  assertEquals(body.image, "https://img.example.com/img.png");
});

Deno.test("sendLink: imageUrl is omitted when not provided", async () => {
  const { fetchStub, calls } = mockFetch({ messageId: "m4" });
  await withFetch(fetchStub, () =>
    provider.sendLink("5547999999999", "Confira", "https://example.com"),
  );
  const body = JSON.parse(calls[0].init?.body as string);
  assertFalse("image" in body);
});

// ─── sendDocument ────────────────────────────────────────────────────────────

Deno.test("sendDocument: hits send-document/pdf endpoint", async () => {
  const { fetchStub, calls } = mockFetch({ messageId: "m5" });
  await withFetch(fetchStub, () =>
    provider.sendDocument(
      "5547999999999",
      "https://cdn.example.com/doc.pdf",
      "boleto.pdf",
      "Seu boleto",
    ),
  );
  assertEquals(calls[0].url, `${BASE}/send-document/pdf`);
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.document, "https://cdn.example.com/doc.pdf");
  assertEquals(body.fileName, "boleto.pdf");
  assertEquals(body.caption, "Seu boleto");
});

// ─── checkNumberExists ───────────────────────────────────────────────────────

Deno.test("checkNumberExists: returns true when body.exists === true", async () => {
  const { fetchStub } = mockFetch({ exists: true });
  const exists = await withFetch(fetchStub, () =>
    provider.checkNumberExists("5547999999999"),
  );
  assertEquals(exists, true);
});

Deno.test("checkNumberExists: returns false when body.exists !== true", async () => {
  const { fetchStub } = mockFetch({ exists: false });
  const exists = await withFetch(fetchStub, () =>
    provider.checkNumberExists("5547999999999"),
  );
  assertFalse(exists);
});

Deno.test("checkNumberExists: returns false on network error", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => Promise.reject(new Error("timeout"));
  try {
    const exists = await provider.checkNumberExists("5547999999999");
    assertFalse(exists);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("checkNumberExists: hits phone-exists/{phone} endpoint with normalized phone", async () => {
  const { fetchStub, calls } = mockFetch({ exists: true });
  await withFetch(fetchStub, () =>
    provider.checkNumberExists("+55 (47) 9-9999-9999"),
  );
  assertStringIncludes(calls[0].url, "/phone-exists/5547999999999");
});

// ─── parseIncomingWebhook ────────────────────────────────────────────────────

Deno.test("parseIncomingWebhook: inbound text message returns correct event", () => {
  const payload = {
    type: "ReceivedCallback",
    phone: "5547999999999",
    messageId: "ABCDEF12345",
    fromMe: false,
    senderName: "João",
    text: { message: "Olá, quero informações" },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.from, "5547999999999");
  assertEquals(event?.messageId, "ABCDEF12345");
  assertEquals(event?.fromMe, false);
  assertEquals(event?.text, "Olá, quero informações");
  assertEquals(event?.messageType, "text");
  assertEquals(event?.senderName, "João");
});

Deno.test("parseIncomingWebhook: PresenceChatCallback returns null", () => {
  const payload = { type: "PresenceChatCallback", phone: "5547999999999" };
  assertEquals(provider.parseIncomingWebhook(payload), null);
});

Deno.test("parseIncomingWebhook: MessageStatusCallback returns null", () => {
  const payload = { type: "MessageStatusCallback", messageId: "x", status: "read" };
  assertEquals(provider.parseIncomingWebhook(payload), null);
});

Deno.test("parseIncomingWebhook: isGroup:true returns null", () => {
  const payload = {
    type: "ReceivedCallback",
    phone: "5547999999999",
    isGroup: true,
    text: { message: "msg de grupo" },
  };
  assertEquals(provider.parseIncomingWebhook(payload), null);
});

Deno.test("parseIncomingWebhook: fromMe:true uses 'to' field for phone", () => {
  const payload = {
    type: "SentCallback",
    to: "5547888888888",
    messageId: "OUT001",
    fromMe: true,
    text: { message: "Resposta enviada" },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.fromMe, true);
  assertEquals(event?.from, "5547888888888");
});

Deno.test("parseIncomingWebhook: image message sets messageType and mediaUrl", () => {
  const payload = {
    type: "ReceivedCallback",
    phone: "5547999999999",
    messageId: "IMG001",
    fromMe: false,
    image: {
      imageUrl: "https://cdn.z-api.io/img/test.jpg",
      caption: "Veja essa foto",
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.messageType, "image");
  assertEquals(event?.mediaUrl, "https://cdn.z-api.io/img/test.jpg");
  assertEquals(event?.text, "Veja essa foto");
});

Deno.test("parseIncomingWebhook: audio message sets messageType and mediaUrl, text null", () => {
  const payload = {
    type: "ReceivedCallback",
    phone: "5547999999999",
    messageId: "AUD001",
    fromMe: false,
    audio: { audioUrl: "https://cdn.z-api.io/audio/test.ogg" },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.messageType, "audio");
  assertEquals(event?.mediaUrl, "https://cdn.z-api.io/audio/test.ogg");
  assertEquals(event?.text, null);
});

Deno.test("parseIncomingWebhook: document message sets messageType and mediaUrl", () => {
  const payload = {
    type: "ReceivedCallback",
    phone: "5547999999999",
    messageId: "DOC001",
    fromMe: false,
    document: {
      documentUrl: "https://cdn.z-api.io/doc/boleto.pdf",
      caption: "Boleto em anexo",
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.messageType, "document");
  assertEquals(event?.mediaUrl, "https://cdn.z-api.io/doc/boleto.pdf");
  assertEquals(event?.text, "Boleto em anexo");
});

Deno.test("parseIncomingWebhook: phone without DDI is normalized (DDI prepended)", () => {
  const payload = {
    type: "ReceivedCallback",
    phone: "47999999999",
    messageId: "NORM001",
    fromMe: false,
    text: { message: "Oi" },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.from, "5547999999999");
});

Deno.test("parseIncomingWebhook: payload without phone returns null", () => {
  const payload = { type: "ReceivedCallback", fromMe: false };
  assertEquals(provider.parseIncomingWebhook(payload), null);
});

Deno.test("parseIncomingWebhook: Client-Token header is sent when configured", async () => {
  const { fetchStub, calls } = mockFetch({ messageId: "m6" });
  await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "test"),
  );
  const headers = calls[0].init?.headers as Record<string, string>;
  assertEquals(headers["Client-Token"], "ct789");
});

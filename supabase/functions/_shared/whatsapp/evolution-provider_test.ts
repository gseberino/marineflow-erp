// Tests for EvolutionProvider
// Run: deno test supabase/functions/_shared/whatsapp/evolution-provider_test.ts
import {
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { EvolutionProvider } from "./evolution-provider.ts";

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
  return fn().finally(() => { globalThis.fetch = original; });
}

const provider = new EvolutionProvider({
  apiUrl: "https://evo.example.com",
  apiKey: "test-api-key-32chars",
  instance: "marineflow",
});

const BASE = "https://evo.example.com";

// ─── sendText ────────────────────────────────────────────────────────────────

Deno.test("sendText: success — extracts providerMessageId from key.id", async () => {
  const { fetchStub } = mockFetch({ key: { id: "BAE123ABC" } });
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Olá"),
  );
  assertEquals(result, { ok: true, providerMessageId: "BAE123ABC" });
});

Deno.test("sendText: hits correct endpoint URL", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  await withFetch(fetchStub, () => provider.sendText("5547999999999", "Hi"));
  assertEquals(calls[0].url, `${BASE}/message/sendText/marineflow`);
});

Deno.test("sendText: sends phone and text in correct payload shape", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  await withFetch(fetchStub, () => provider.sendText("5547999999999", "Mensagem"));
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.number, "5547999999999");
  assertEquals(body.text, "Mensagem");
});

Deno.test("sendText: normalizes phone number before sending", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  await withFetch(fetchStub, () => provider.sendText("+55 (47) 9-9999-9999", "Hi"));
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.number, "5547999999999");
});

Deno.test("sendText: sets apikey header", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  await withFetch(fetchStub, () => provider.sendText("5547999999999", "Hi"));
  const headers = calls[0].init?.headers as Record<string, string>;
  assertEquals(headers["apikey"], "test-api-key-32chars");
});

Deno.test("sendText: HTTP 500 → ok:false, retryable:true", async () => {
  const { fetchStub } = mockFetch({}, 500);
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Hi"),
  );
  assertEquals(result, { ok: false, error: "HTTP 500", retryable: true });
});

Deno.test("sendText: HTTP 401 → ok:false, retryable:false", async () => {
  const { fetchStub } = mockFetch({ message: "Unauthorized" }, 401);
  const result = await withFetch(fetchStub, () =>
    provider.sendText("5547999999999", "Hi"),
  );
  assertEquals(result.ok, false);
  assertEquals((result as { retryable: boolean }).retryable, false);
});

Deno.test("sendText: network error → ok:false, retryable:true", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => Promise.reject(new Error("ECONNREFUSED"));
  try {
    const result = await provider.sendText("5547999999999", "Hi");
    assertFalse(result.ok);
    assertEquals((result as { ok: false; error: string; retryable: boolean }).retryable, true);
  } finally {
    globalThis.fetch = original;
  }
});

// ─── sendLink ────────────────────────────────────────────────────────────────

Deno.test("sendLink: uses sendText endpoint with linkPreview:true", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  await withFetch(fetchStub, () =>
    provider.sendLink("5547999999999", "Veja", "https://example.com"),
  );
  assertEquals(calls[0].url, `${BASE}/message/sendText/marineflow`);
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.linkPreview, true);
});

Deno.test("sendLink: appends URL to message when not already included", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  await withFetch(fetchStub, () =>
    provider.sendLink("5547999999999", "Confira nosso site", "https://example.com"),
  );
  const body = JSON.parse(calls[0].init?.body as string);
  assertStringIncludes(body.text, "https://example.com");
});

Deno.test("sendLink: does not duplicate URL when message already contains it", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  const msg = "Acesse https://example.com agora";
  await withFetch(fetchStub, () =>
    provider.sendLink("5547999999999", msg, "https://example.com"),
  );
  const body = JSON.parse(calls[0].init?.body as string);
  const occurrences = (body.text.match(/https:\/\/example\.com/g) || []).length;
  assertEquals(occurrences, 1);
});

// ─── sendDocument ────────────────────────────────────────────────────────────

Deno.test("sendDocument: hits sendMedia endpoint with document mediatype", async () => {
  const { fetchStub, calls } = mockFetch({ key: { id: "x" } });
  await withFetch(fetchStub, () =>
    provider.sendDocument("5547999999999", "https://cdn.example.com/doc.pdf", "boleto.pdf", "Seu boleto"),
  );
  assertEquals(calls[0].url, `${BASE}/message/sendMedia/marineflow`);
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.mediatype, "document");
  assertEquals(body.mimetype, "application/pdf");
  assertEquals(body.media, "https://cdn.example.com/doc.pdf");
  assertEquals(body.fileName, "boleto.pdf");
  assertEquals(body.caption, "Seu boleto");
});

// ─── checkNumberExists ───────────────────────────────────────────────────────

Deno.test("checkNumberExists: returns true when first element has exists:true", async () => {
  const { fetchStub } = mockFetch([{ exists: true, jid: "5547999999999@s.whatsapp.net" }]);
  const exists = await withFetch(fetchStub, () =>
    provider.checkNumberExists("5547999999999"),
  );
  assertEquals(exists, true);
});

Deno.test("checkNumberExists: returns false when exists:false", async () => {
  const { fetchStub } = mockFetch([{ exists: false }]);
  const exists = await withFetch(fetchStub, () =>
    provider.checkNumberExists("5547999999999"),
  );
  assertFalse(exists);
});

Deno.test("checkNumberExists: returns false on HTTP error", async () => {
  const { fetchStub } = mockFetch({}, 500);
  const exists = await withFetch(fetchStub, () =>
    provider.checkNumberExists("5547999999999"),
  );
  assertFalse(exists);
});

Deno.test("checkNumberExists: returns false on network error", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => Promise.reject(new Error("timeout"));
  try {
    assertFalse(await provider.checkNumberExists("5547999999999"));
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("checkNumberExists: hits correct endpoint with numbers array", async () => {
  const { fetchStub, calls } = mockFetch([{ exists: true }]);
  await withFetch(fetchStub, () => provider.checkNumberExists("5547999999999"));
  assertEquals(calls[0].url, `${BASE}/chat/whatsappNumbers/marineflow`);
  const body = JSON.parse(calls[0].init?.body as string);
  assertEquals(body.numbers, ["5547999999999"]);
});

// ─── parseIncomingWebhook ────────────────────────────────────────────────────

Deno.test("parseIncomingWebhook: LID remoteJid uses senderPn for the real phone", () => {
  // WhatsApp multi-device: remoteJid is a @lid, real phone comes in key.senderPn.
  // senderPn 554799159654 (12-digit) → 9th digit inserted → 5547999159654.
  const payload = {
    event: "messages.upsert",
    instance: "hbr-local",
    data: {
      key: {
        id: "LID001",
        fromMe: false,
        senderPn: "554799159654@s.whatsapp.net",
        remoteJid: "113408678621372@lid",
      },
      pushName: "Gustavo",
      messageTimestamp: 1781145909,
      message: { conversation: "teste lid" },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.from, "5547999159654");
  assertEquals(event?.text, "teste lid");
  assertEquals(event?.senderName, "Gustavo");
});

Deno.test("parseIncomingWebhook: LID falls back to remoteJidAlt when senderPn absent", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: {
        id: "LID002",
        fromMe: false,
        remoteJidAlt: "5547988887777@s.whatsapp.net",
        remoteJid: "999999999999999@lid",
      },
      message: { conversation: "alt" },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.from, "5547988887777");
});

Deno.test("parseIncomingWebhook: MESSAGES_UPSERT text message returns correct event", () => {
  const payload = {
    event: "messages.upsert",
    instance: "marineflow",
    data: {
      key: { remoteJid: "5547999999999@s.whatsapp.net", fromMe: false, id: "BAE001" },
      pushName: "João",
      messageTimestamp: 1700000000,
      message: { conversation: "Olá, quero informações" },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.from, "5547999999999");
  assertEquals(event?.messageId, "BAE001");
  assertEquals(event?.fromMe, false);
  assertEquals(event?.text, "Olá, quero informações");
  assertEquals(event?.messageType, "text");
  assertEquals(event?.senderName, "João");
  assertEquals(event?.timestamp, 1700000000 * 1000);
});

Deno.test("parseIncomingWebhook: non messages.upsert event returns null", () => {
  assertEquals(provider.parseIncomingWebhook({ event: "connection.update" }), null);
  assertEquals(provider.parseIncomingWebhook({ event: "messages.update" }), null);
  assertEquals(provider.parseIncomingWebhook({ event: "qrcode.updated" }), null);
});

Deno.test("parseIncomingWebhook: MESSAGES_UPSERT in type field returns correct event", () => {
  const payload = {
    type: "MESSAGES_UPSERT",
    instance: "marineflow",
    data: {
      key: { remoteJid: "5547999999999@s.whatsapp.net", fromMe: false, id: "BAE999" },
      pushName: "Maria",
      messageTimestamp: 1700000000,
      message: { conversation: "Olá, esta é uma mensagem inbound" },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.from, "5547999999999");
  assertEquals(event?.messageId, "BAE999");
  assertEquals(event?.text, "Olá, esta é uma mensagem inbound");
  assertEquals(event?.senderName, "Maria");
});

Deno.test("parseIncomingWebhook: group JID (@g.us) returns null", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: { remoteJid: "120363000000000000@g.us", fromMe: false, id: "GRP001" },
      message: { conversation: "grupo" },
    },
  };
  assertEquals(provider.parseIncomingWebhook(payload), null);
});

Deno.test("parseIncomingWebhook: fromMe:true uses remoteJid as 'from'", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: { remoteJid: "5547888888888@s.whatsapp.net", fromMe: true, id: "OUT001" },
      message: { conversation: "Resposta" },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.fromMe, true);
  assertEquals(event?.from, "5547888888888");
});

Deno.test("parseIncomingWebhook: image message sets correct type and mediaUrl", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: { remoteJid: "5547999999999@s.whatsapp.net", fromMe: false, id: "IMG001" },
      message: {
        imageMessage: {
          url: "https://mmg.whatsapp.net/img/test.jpg",
          caption: "Foto do barco",
        },
      },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.messageType, "image");
  assertEquals(event?.mediaUrl, "https://mmg.whatsapp.net/img/test.jpg");
  assertEquals(event?.text, "Foto do barco");
});

Deno.test("parseIncomingWebhook: audio message sets correct type, text null", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: { remoteJid: "5547999999999@s.whatsapp.net", fromMe: false, id: "AUD001" },
      message: { audioMessage: { url: "https://mmg.whatsapp.net/audio/test.ogg" } },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.messageType, "audio");
  assertEquals(event?.mediaUrl, "https://mmg.whatsapp.net/audio/test.ogg");
  assertEquals(event?.text, null);
});

Deno.test("parseIncomingWebhook: document message extracts caption as text", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: { remoteJid: "5547999999999@s.whatsapp.net", fromMe: false, id: "DOC001" },
      message: {
        documentMessage: {
          url: "https://mmg.whatsapp.net/doc/boleto.pdf",
          fileName: "boleto.pdf",
          caption: "Boleto de cobrança",
        },
      },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.messageType, "document");
  assertEquals(event?.text, "Boleto de cobrança");
  assertEquals(event?.mediaUrl, "https://mmg.whatsapp.net/doc/boleto.pdf");
});

Deno.test("parseIncomingWebhook: extendedTextMessage falls back to text.text", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: { remoteJid: "5547999999999@s.whatsapp.net", fromMe: false, id: "EXT001" },
      message: {
        extendedTextMessage: { text: "Link com preview" },
      },
    },
  };
  const event = provider.parseIncomingWebhook(payload);
  assertEquals(event?.text, "Link com preview");
  assertEquals(event?.messageType, "text");
});

Deno.test("parseIncomingWebhook: missing data field returns null", () => {
  assertEquals(provider.parseIncomingWebhook({ event: "messages.upsert" }), null);
});

Deno.test("parseIncomingWebhook: missing message object returns null", () => {
  const payload = {
    event: "messages.upsert",
    data: {
      key: { remoteJid: "5547999999999@s.whatsapp.net", fromMe: false, id: "X" },
    },
  };
  assertEquals(provider.parseIncomingWebhook(payload), null);
});

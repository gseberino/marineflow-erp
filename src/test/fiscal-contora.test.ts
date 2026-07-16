import { describe, it, expect, vi, afterEach } from "vitest";
import { webcrypto } from "node:crypto";
import { createHmac } from "node:crypto";
import {
  ContoraProvider,
  hmacSha256Hex,
  mapContoraEvent,
  mapContoraStatus,
  verifyContoraSignature,
} from "../../supabase/functions/_shared/fiscal/contora-provider";

// jsdom não expõe WebCrypto subtle; usa o do Node para os testes de HMAC.
if (!(globalThis.crypto && globalThis.crypto.subtle)) {
  // @ts-expect-error — atribui o WebCrypto do Node no ambiente de teste
  globalThis.crypto = webcrypto;
}

function makeProvider(overrides: Partial<ConstructorParameters<typeof ContoraProvider>[0]> = {}) {
  return new ContoraProvider({
    baseUrl: "https://fiscal.contora.com.br/api/v1",
    token: "token-teste",
    webhookSecret: "whsec-teste",
    environment: "homologacao",
    ...overrides,
  });
}

function jsonResponse(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

afterEach(() => vi.restoreAllMocks());

describe("mapContoraStatus", () => {
  it("mapeia o ciclo de vida da Contora para status normalizado", () => {
    expect(mapContoraStatus("authorized", "completed")).toBe("authorized");
    expect(mapContoraStatus("error", "completed")).toBe("rejected");
    expect(mapContoraStatus("authorize_pending", "queued")).toBe("queued");
    expect(mapContoraStatus("built_signed", "processing")).toBe("processing");
    expect(mapContoraStatus("built_signed", "failed")).toBe("failed");
    expect(mapContoraStatus("draft", "draft")).toBe("draft");
    expect(mapContoraStatus("cancelled", "completed")).toBe("cancelled");
  });
});

describe("mapContoraEvent", () => {
  it("mapeia eventos de webhook para status (ou null quando inconclusivo)", () => {
    expect(mapContoraEvent("document.authorized")).toBe("authorized");
    expect(mapContoraEvent("document.rejected")).toBe("rejected");
    expect(mapContoraEvent("document.failed")).toBe("failed");
    expect(mapContoraEvent("document.processing_started")).toBe("processing");
    expect(mapContoraEvent("document.queued")).toBe("queued");
    expect(mapContoraEvent("document.created")).toBeNull();
    expect(mapContoraEvent(undefined)).toBeNull();
  });
});

describe("HMAC do webhook", () => {
  it("hmacSha256Hex bate com o crypto do Node (implementação correta)", async () => {
    const secret = "whsec-teste";
    const message = "2026-07-14T10:00:00-03:00.{\"event\":\"x\"}";
    const ours = await hmacSha256Hex(secret, message);
    const nodeHex = createHmac("sha256", secret).update(message).digest("hex");
    expect(ours).toBe(nodeHex);
  });

  it("verifyContoraSignature aceita assinatura válida e rejeita adulteração", async () => {
    const secret = "whsec-teste";
    const ts = "2026-07-14T10:00:00-03:00";
    const body = JSON.stringify({ event: "document.authorized", data: { id: "doc1" } });
    const sig = await hmacSha256Hex(secret, `${ts}.${body}`);

    expect(await verifyContoraSignature(secret, ts, body, sig)).toBe(true);
    // corpo adulterado
    expect(await verifyContoraSignature(secret, ts, body + "x", sig)).toBe(false);
    // assinatura errada
    expect(await verifyContoraSignature(secret, ts, body, "deadbeef")).toBe(false);
    // segredo ausente
    expect(await verifyContoraSignature("", ts, body, sig)).toBe(false);
  });
});

describe("ContoraProvider — chamadas HTTP (fetch mockado)", () => {
  it("createDraft envia document_type para NF-e e normaliza a resposta", async () => {
    const spy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(jsonResponse({ ok: true, data: { id: "doc-123", status: "draft", processing_status: "draft" } }));

    const provider = makeProvider();
    const r = await provider.createDraft({
      documentType: "nfe",
      series: 1,
      number: 214,
      payload: { nature_operation: "Venda" },
    });

    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.providerDocumentId).toBe("doc-123");
      expect(r.data.status).toBe("draft");
    }
    const [url, init] = spy.mock.calls[0];
    expect(url).toBe("https://fiscal.contora.com.br/api/v1/nfe/drafts");
    const sentBody = JSON.parse((init as RequestInit).body as string);
    expect(sentBody.document_type).toBe("nfe");
    expect(sentBody.series).toBe(1);
  });

  it("getStatus normaliza autorização com chave/protocolo", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({
        ok: true,
        data: {
          id: "doc-123",
          lifecycle: { status: "authorized", processing_status: "completed" },
          sefaz: { status_code: "100", status_message: "Autorizado o uso da NF-e", access_key: "K123", protocol: "P999", authorized_at: "2026-07-14T10:22:11-03:00" },
        },
      }),
    );

    const r = await makeProvider().getStatus("nfe", "doc-123");
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.status).toBe("authorized");
      expect(r.data.accessKey).toBe("K123");
      expect(r.data.statusCode).toBe("100");
      expect(r.data.protocol).toBe("P999");
    }
  });

  it("propaga rejeição SEFAZ como erro não-retryável", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse(
        { ok: false, message: "Rejeição SEFAZ 204", error: { type: "sefaz_rejection", details: { status: "204" } } },
        422,
      ),
    );
    const r = await makeProvider().dispatch("nfe", "doc-123");
    expect(r.ok).toBe(false);
    const err = r as Extract<typeof r, { ok: false }>;
    expect(err.error).toContain("204");
    expect(err.errorType).toBe("sefaz_rejection");
    expect(err.retryable).toBe(false);
  });

  it("trata 5xx como retryável", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(jsonResponse({ ok: false, message: "erro interno" }, 503));
    const r = await makeProvider().getStatus("nfe", "doc-123");
    expect(r.ok).toBe(false);
    const err = r as Extract<typeof r, { ok: false }>;
    expect(err.retryable).toBe(true);
  });

  it("listCompanies normaliza a empresa (city_code/certificado/UF) do envelope { data: [...] }", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({
        ok: true,
        data: [{
          id: "cmp-1", legal_name: "HBR LTDA", document: "50057049000159",
          state_code: "SC", city_code: "4204202", has_certificate: true, default_environment: "homologacao",
        }],
      }),
    );
    const r = await makeProvider().listCompanies();
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data).toHaveLength(1);
      expect(r.data[0]).toMatchObject({
        legalName: "HBR LTDA", stateCode: "SC", cityCode: "4204202", hasCertificate: true,
      });
    }
  });

  it("listCompanies detecta empresa SEM city_code (causa do erro de build)", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({ ok: true, data: [{ id: "cmp-1", legal_name: "HBR", state_code: "SC", has_certificate: true }] }),
    );
    const r = await makeProvider().listCompanies();
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.data[0].cityCode ?? null).toBeNull();
  });

  it("sefazStatus reporta ok=true e certificateLoaded no sucesso", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({ ok: true, data: { environment: "homologacao", state_code: "SC", certificate_loaded: true } }),
    );
    const r = await makeProvider().sefazStatus();
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.data.ok).toBe(true);
      expect(r.data.certificateLoaded).toBe(true);
    }
  });

  it("sefazStatus reporta ok=false quando a consulta falha (SEFAZ indisponível)", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(jsonResponse({ ok: false, message: "sefaz offline" }, 503));
    const r = await makeProvider().sefazStatus();
    expect(r.ok).toBe(true); // o método nunca "falha"; embute o status
    if (r.ok) expect(r.data.ok).toBe(false);
  });
});

describe("ContoraProvider.parseWebhook", () => {
  it("valida assinatura e extrai documento + status; rejeita assinatura inválida", async () => {
    const secret = "whsec-teste";
    const ts = "2026-07-14T10:00:00-03:00";
    const body = JSON.stringify({ event: "document.authorized", data: { id: "doc-123" } });
    const sig = await hmacSha256Hex(secret, `${ts}.${body}`);
    const provider = makeProvider({ webhookSecret: secret });

    const evt = await provider.parseWebhook(
      {
        "X-Fiscal-Timestamp": ts,
        "X-Fiscal-Signature": sig,
        "X-Fiscal-Event": "document.authorized",
        "X-Fiscal-Idempotency-Key": "idem-1",
        "X-Fiscal-Delivery-Id": "42",
      },
      body,
    );
    expect(evt).not.toBeNull();
    expect(evt?.providerDocumentId).toBe("doc-123");
    expect(evt?.status).toBe("authorized");
    expect(evt?.idempotencyKey).toBe("idem-1");

    const invalid = await provider.parseWebhook(
      { "X-Fiscal-Timestamp": ts, "X-Fiscal-Signature": "deadbeef", "X-Fiscal-Event": "document.authorized" },
      body,
    );
    expect(invalid).toBeNull();
  });
});

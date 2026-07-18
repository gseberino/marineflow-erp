// ContoraProvider — implements FiscalProvider against the Fiscal Contora API v1.
// https://fiscal.contora.com.br/documentacao — async pipeline:
//   draft -> build (NF-e only) -> dispatch{authorize} -> status/webhook -> artifacts
// Uses only Web-standard APIs (fetch, crypto.subtle) so it runs in Deno (edge
// functions) and under Vitest (Node) for unit tests.
import type {
  CompanyInfo,
  CreateDraftInput,
  DocumentStatusInfo,
  DocumentType,
  DraftCreated,
  FiscalArtifact,
  FiscalEnvironment,
  FiscalProvider,
  FiscalResult,
  FiscalStatus,
  FiscalWebhookEvent,
  SefazStatusInfo,
} from "./types.ts";

export interface ContoraConfig {
  baseUrl: string; // e.g. "https://fiscal.contora.com.br/api/v1" — no trailing slash
  token: string; // Bearer API token (per environment)
  webhookSecret: string; // HMAC secret configured on the webhook endpoint
  environment: FiscalEnvironment;
  // Note: this provider always uses Contora's "flat/global" routes (/nfe/drafts,
  // not /companies/{id}/nfe/drafts) — recommended by Contora's own docs and
  // sufficient for a single-CNPJ account. No company id is needed on requests.
}

// Route family: nfe/nfce share the /nfe surface; nfse has its own.
function family(documentType: DocumentType): "nfe" | "nfse" {
  return documentType === "nfse" ? "nfse" : "nfe";
}

// Contora's own status vocabulary -> normalized FiscalStatus.
// status: draft|built_unsigned|built_signed|authorize_pending|authorized|error
// processing_status: draft|queued|processing|completed|failed
export function mapContoraStatus(
  status?: string | null,
  processingStatus?: string | null,
): FiscalStatus {
  const s = (status ?? "").toLowerCase();
  const p = (processingStatus ?? "").toLowerCase();
  if (s === "authorized") return "authorized";
  if (s === "cancelled" || s === "canceled") return "cancelled";
  if (s === "error" || s === "rejected") return "rejected";
  if (p === "failed") return "failed";
  if (p === "processing") return "processing";
  if (s === "authorize_pending" || p === "queued") return "queued";
  return "draft"; // draft, built_unsigned, built_signed
}

// Webhook event name -> best-effort normalized status. null means "inconclusive,
// fetch /status to confirm" (the webhook handler always reconciles).
export function mapContoraEvent(event?: string | null): FiscalStatus | null {
  switch ((event ?? "").toLowerCase()) {
    case "document.authorized":
      return "authorized";
    case "document.rejected":
      return "rejected";
    case "document.failed":
    case "document.build_sync_failed":
    case "document.receipt_poll_exhausted":
    case "document.receipt_poll_failed":
      return "failed";
    case "document.cancelled":
    case "document.canceled":
      return "cancelled";
    case "document.queued":
    case "document.authorization_pending":
    case "document.receipt_still_pending":
      return "queued";
    case "document.processing_started":
      return "processing";
    default:
      return null;
  }
}

// hex(HMAC-SHA256(message, secret)) using Web Crypto.
export async function hmacSha256Hex(
  secret: string,
  message: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Constant-time comparison to avoid timing attacks.
export function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Verifies the Contora webhook signature: HMAC over `${timestamp}.${rawBody}`.
export async function verifyContoraSignature(
  secret: string,
  timestamp: string,
  rawBody: string,
  signature: string,
): Promise<boolean> {
  if (!secret || !timestamp || !signature) return false;
  const expected = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  return timingSafeEqualHex(expected, signature);
}

type Envelope = {
  ok?: boolean;
  data?: unknown;
  message?: string;
  error?: { type?: string; details?: unknown };
};

export class ContoraProvider implements FiscalProvider {
  readonly name = "contora";
  private readonly baseUrl: string;
  private readonly headers: Record<string, string>;
  private readonly webhookSecret: string;
  private readonly environment: FiscalEnvironment;

  constructor(config: ContoraConfig) {
    this.baseUrl = config.baseUrl.replace(/\/$/, "");
    this.webhookSecret = config.webhookSecret;
    this.environment = config.environment;
    this.headers = {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Authorization": `Bearer ${config.token}`,
    };
  }

  // Core request against the { ok, data } / { ok:false, message, error } envelope.
  private async request<T = unknown>(
    method: string,
    path: string,
    body?: unknown,
  ): Promise<FiscalResult<T>> {
    try {
      const res = await fetch(`${this.baseUrl}${path}`, {
        method,
        headers: this.headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const env = (await res.json().catch(() => ({}))) as Envelope;

      if (res.ok && env.ok !== false) {
        return { ok: true, data: (env.data ?? env) as T };
      }
      const retryable = res.status >= 500 || res.status === 429 ||
        res.status === 408;
      return {
        ok: false,
        error: env.message ?? `HTTP ${res.status}`,
        errorType: env.error?.type,
        details: env.error?.details,
        retryable,
      };
    } catch (err) {
      // Network/transport failure — safe to retry.
      return {
        ok: false,
        error: err instanceof Error ? err.message : String(err),
        retryable: true,
      };
    }
  }

  async validateToken(): Promise<
    FiscalResult<{ tokenId?: string; name?: string }>
  > {
    const r = await this.request<Record<string, unknown>>("GET", "/me");
    if (!r.ok) return r;
    const token = (r.data?.["token"] ?? r.data) as Record<string, unknown>;
    return {
      ok: true,
      data: {
        tokenId: token?.["id"] ? String(token["id"]) : undefined,
        name: token?.["name"] ? String(token["name"]) : undefined,
      },
    };
  }

  async listCompanies(): Promise<FiscalResult<CompanyInfo[]>> {
    const r = await this.request<unknown>("GET", "/companies");
    if (!r.ok) return r as FiscalResult<CompanyInfo[]>;
    const raw = r.data as Record<string, unknown> | unknown[];
    const arr: unknown[] = Array.isArray(raw)
      ? raw
      : ((raw as Record<string, unknown>)?.["data"] as unknown[]) ??
        ((raw as Record<string, unknown>)?.["companies"] as unknown[]) ??
        [];
    const companies: CompanyInfo[] = arr.map((c) => {
      const o = c as Record<string, unknown>;
      // A Contora aninha um resumo do certificado (CompanyCertificateSummary)
      // no objeto da empresa, com valid_until (validade do A1).
      const cert = o["certificate"] as Record<string, unknown> | null | undefined;
      return {
        id: o["id"] ? String(o["id"]) : undefined,
        legalName: (o["legal_name"] as string) ?? null,
        tradeName: (o["trade_name"] as string) ?? null,
        document: (o["document"] as string) ?? null,
        stateCode: (o["state_code"] as string) ?? null,
        cityCode: (o["city_code"] as string) ?? null,
        hasCertificate: o["has_certificate"] === true,
        certificateValidUntil: (cert?.["valid_until"] as string) ?? null,
        defaultEnvironment: (o["default_environment"] as string) ?? null,
        raw: o,
      };
    });
    return { ok: true, data: companies };
  }

  async sefazStatus(): Promise<FiscalResult<SefazStatusInfo>> {
    const r = await this.request<Record<string, unknown>>("GET", "/sefaz/status");
    // ok:false aqui já significa SEFAZ indisponível / não pronta.
    if (!r.ok) return { ok: true, data: { ok: false, raw: r } };
    const d = r.data ?? {};
    return {
      ok: true,
      data: {
        ok: true,
        certificateLoaded: d["certificate_loaded"] === true,
        stateCode: (d["state_code"] as string) ?? null,
        environment: (d["environment"] as string) ?? null,
        raw: d,
      },
    };
  }

  async createDraft(
    input: CreateDraftInput,
  ): Promise<FiscalResult<DraftCreated>> {
    const fam = family(input.documentType);
    // A Contora lê série/número DE DENTRO do `payload` no build ("Informe number
    // no payload com valor maior que zero"); a doc também os mostra no topo do
    // request. Enviamos nos dois lugares para satisfazer as duas variações.
    const payload: Record<string, unknown> = { ...input.payload };
    if (input.series !== undefined) payload.series = input.series;
    if (input.number !== undefined) payload.number = input.number;

    const body: Record<string, unknown> = {
      environment: input.environment ?? this.environment,
      payload,
    };
    if (input.series !== undefined) body.series = input.series;
    if (input.number !== undefined) body.number = input.number;
    if (fam === "nfe") body.document_type = input.documentType; // nfe | nfce

    const r = await this.request<Record<string, unknown>>(
      "POST",
      `/${fam}/drafts`,
      body,
    );
    // Cast explícito (em vez de deixar o narrowing estrutural resolver): TS
    // não estreita bem uniões discriminadas genéricas quando o tipo de retorno
    // da função usa uma instanciação diferente do genérico (aqui:
    // Record<string,unknown> vs DraftCreated) — a ramificação ok:false não
    // depende de T, então o cast é seguro.
    if (!r.ok) return r as FiscalResult<DraftCreated>;
    const d = r.data ?? {};
    return {
      ok: true,
      data: {
        providerDocumentId: String(d["id"] ?? ""),
        status: mapContoraStatus(
          d["status"] as string,
          d["processing_status"] as string,
        ),
        raw: d,
      },
    };
  }

  build(
    documentType: DocumentType,
    id: string,
    sign = true,
  ): Promise<FiscalResult<unknown>> {
    return this.request(
      "POST",
      `/${family(documentType)}/drafts/${id}/build`,
      { sign },
    );
  }

  dispatch(
    documentType: DocumentType,
    id: string,
    action = "authorize",
  ): Promise<FiscalResult<unknown>> {
    const fam = family(documentType);
    // NF-e expects { action: "authorize" }; NFS-e dispatch is the emission trigger.
    const body = fam === "nfe" ? { action } : {};
    return this.request("POST", `/${fam}/drafts/${id}/dispatch`, body);
  }

  async getStatus(
    documentType: DocumentType,
    id: string,
  ): Promise<FiscalResult<DocumentStatusInfo>> {
    const r = await this.request<Record<string, unknown>>(
      "GET",
      `/${family(documentType)}/drafts/${id}/status`,
    );
    if (!r.ok) return r as FiscalResult<DocumentStatusInfo>;
    const d = r.data ?? {};
    const lifecycle = (d["lifecycle"] ?? {}) as Record<string, unknown>;
    const sefaz = (d["sefaz"] ?? {}) as Record<string, unknown>;
    const provider = (d["provider"] ?? {}) as Record<string, unknown>; // nfse
    const statusStr = (lifecycle["status"] ?? d["status"]) as string;
    const procStr = (lifecycle["processing_status"] ??
      d["processing_status"]) as string;
    return {
      ok: true,
      data: {
        providerDocumentId: String(d["id"] ?? id),
        status: mapContoraStatus(statusStr, procStr),
        statusCode: (sefaz["status_code"] as string) ?? null,
        statusMessage: (sefaz["status_message"] ??
          d["last_error_message"] ?? null) as string | null,
        accessKey: (sefaz["access_key"] as string) ?? null,
        protocol: (sefaz["protocol"] ?? provider["protocol"] ?? null) as
          | string
          | null,
        authorizedAt: (sefaz["authorized_at"] as string) ?? null,
        raw: d,
      },
    };
  }

  async listArtifacts(
    documentType: DocumentType,
    id: string,
  ): Promise<FiscalResult<FiscalArtifact[]>> {
    const r = await this.request<unknown>(
      "GET",
      `/${family(documentType)}/drafts/${id}/artifacts`,
    );
    if (!r.ok) return r as FiscalResult<FiscalArtifact[]>;
    // The list may come as an array or wrapped in { artifacts: [...] } / { data: [...] }.
    const raw = r.data as Record<string, unknown> | unknown[];
    const arr: unknown[] = Array.isArray(raw)
      ? raw
      : ((raw as Record<string, unknown>)?.["artifacts"] as unknown[]) ??
        ((raw as Record<string, unknown>)?.["data"] as unknown[]) ??
        [];
    const artifacts: FiscalArtifact[] = arr.map((a) => {
      const o = a as Record<string, unknown>;
      return {
        type: String(o["type"] ?? ""),
        label: o["label"] ? String(o["label"]) : undefined,
        filename: o["filename"] ? String(o["filename"]) : undefined,
        available: o["available"] !== false,
        downloadUrl: (o["download_url"] as string) ?? null,
      };
    });
    return { ok: true, data: artifacts };
  }

  async fetchArtifact(
    url: string,
  ): Promise<FiscalResult<{ contentType: string; bytes: ArrayBuffer }>> {
    try {
      // Autentica com o mesmo Bearer das demais rotas. A URL pode redirecionar
      // para um link pré-assinado (o fetch segue o 3xx automaticamente).
      const res = await fetch(url, {
        headers: { "Authorization": this.headers["Authorization"], "Accept": "*/*" },
      });
      if (!res.ok) {
        return {
          ok: false,
          error: `HTTP ${res.status} ao baixar o artefato`,
          retryable: res.status >= 500 || res.status === 429 || res.status === 408,
        };
      }
      const contentType = res.headers.get("content-type") ?? "application/octet-stream";
      const bytes = await res.arrayBuffer();
      return { ok: true, data: { contentType, bytes } };
    } catch (err) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : String(err),
        retryable: true,
      };
    }
  }

  cancel(
    documentType: DocumentType,
    id: string,
    reason: string,
  ): Promise<FiscalResult<unknown>> {
    return this.request(
      "POST",
      `/${family(documentType)}/drafts/${id}/cancel`,
      { reason },
    );
  }

  correct(
    documentType: DocumentType,
    id: string,
    text: string,
  ): Promise<FiscalResult<unknown>> {
    // Carta de Correção — NF-e/CT-e only.
    return this.request(
      "POST",
      `/${family(documentType)}/drafts/${id}/corrections`,
      { text },
    );
  }

  async parseWebhook(
    headers: Record<string, string>,
    rawBody: string,
  ): Promise<FiscalWebhookEvent | null> {
    // Header lookup is case-insensitive.
    const h = (name: string): string => {
      const key = Object.keys(headers).find(
        (k) => k.toLowerCase() === name,
      );
      return key ? headers[key] : "";
    };
    const timestamp = h("x-fiscal-timestamp");
    const signature = h("x-fiscal-signature");

    const valid = await verifyContoraSignature(
      this.webhookSecret,
      timestamp,
      rawBody,
      signature,
    );
    if (!valid) return null;

    const event = h("x-fiscal-event");
    let parsed: Record<string, unknown> = {};
    try {
      parsed = JSON.parse(rawBody) as Record<string, unknown>;
    } catch {
      parsed = {};
    }
    const data = (parsed["data"] ?? parsed) as Record<string, unknown>;
    const providerDocumentId =
      (data["id"] ?? data["document_id"] ?? parsed["document_id"] ?? null) as
        | string
        | null;

    return {
      event: event || String(parsed["event"] ?? ""),
      providerDocumentId: providerDocumentId ? String(providerDocumentId) : null,
      status: mapContoraEvent(event || (parsed["event"] as string)),
      idempotencyKey: h("x-fiscal-idempotency-key") || null,
      deliveryId: h("x-fiscal-delivery-id") || null,
      raw: parsed,
    };
  }
}

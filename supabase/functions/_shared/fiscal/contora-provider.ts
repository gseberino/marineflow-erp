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
  NfseHealthInfo,
  SefazStatusInfo,
} from "./types.ts";

export interface ContoraConfig {
  baseUrl: string; // e.g. "https://fiscal.contora.com.br/api/v1" — no trailing slash
  token: string; // Bearer API token (per environment)
  webhookSecret: string; // HMAC secret configured on the webhook endpoint
  environment: FiscalEnvironment;
  // CNPJ sem máscara. Vira X-Company-Document nas rotas globais — a Contora exige quando o
  // token administra mais de uma empresa. Opcional: com um CNPJ só, o token já resolve.
  companyDocument?: string;
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
    // Nas rotas globais a Contora exige X-Company-Document quando o token administra mais
    // de uma empresa. Com um CNPJ só ele é inofensivo; com dois, sem ele a nota sai pela
    // empresa errada — e nota emitida no CNPJ errado não se corrige, se cancela.
    const doc = (config.companyDocument ?? "").replace(/\D/g, "");
    if (doc) this.headers["X-Company-Document"] = doc;
  }

  // Core request against the { ok, data } / { ok:false, message, error } envelope.
  private async request<T = unknown>(
    method: string,
    path: string,
    body?: unknown,
    opts?: { idempotencyKey?: string },
  ): Promise<FiscalResult<T>> {
    try {
      // Idempotency-Key em todo POST, como a doc pede. Sem ela, um timeout de rede seguido
      // de retry emite a MESMA nota duas vezes — e a segunda consome numeração fiscal que
      // não volta.
      const headers = opts?.idempotencyKey
        ? { ...this.headers, "Idempotency-Key": opts.idempotencyKey }
        : this.headers;
      const res = await fetch(`${this.baseUrl}${path}`, {
        method,
        headers,
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

  // Liga/desliga allows_homologation na empresa (recurso novo da Contora: uma
  // empresa de produção pode gerar espelhos de homologação com a MESMA chave se
  // este flag estiver ligado). O endpoint aceita SOMENTE este campo (por
  // segurança da Contora). Setar pela API garante que o flag vá para a empresa
  // exata que o token resolve — sem depender do toggle do painel.
  async setAllowsHomologation(
    companyId: string,
    allow: boolean,
  ): Promise<FiscalResult<{ allows_homologation: boolean; raw: unknown }>> {
    const r = await this.request<Record<string, unknown>>(
      "PATCH",
      `/companies/${companyId}`,
      { allows_homologation: allow },
    );
    if (!r.ok) return r as FiscalResult<{ allows_homologation: boolean; raw: unknown }>;
    const d = r.data ?? {};
    return { ok: true, data: { allows_homologation: d["allows_homologation"] === true, raw: d } };
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

  /**
   * Pré-voo da NFS-e: GET /companies/{id}/nfse/health.
   *
   * A resposta da Contora não tem contrato fixo publicado campo a campo, então lemos os
   * nomes prováveis e, o mais importante, PRESERVAMOS o `raw`. A tela mostra o que
   * entendemos e, quando não entendemos, mostra o bruto — melhor do que afirmar "tudo
   * certo" a partir de um campo que talvez nem exista.
   */
  async nfseHealth(companyId: string): Promise<FiscalResult<NfseHealthInfo>> {
    const r = await this.request<Record<string, unknown>>(
      "GET",
      `/companies/${companyId}/nfse/health`,
    );
    if (!r.ok) return r as FiscalResult<NfseHealthInfo>;
    const d = r.data ?? {};
    // FORMATO REAL confirmado ao vivo (13-18/08/2026): o corpo vem ANINHADO —
    // { company_id, health: { ready, public_emission_enabled, checks[], blocks[],
    //   warnings[], provider{...} } }. O mapeamento antigo lia d["ready"]/d["city_code"]
    // no nível de cima e devolvia tudo nulo/falso — o painel mostrava a empresa "vazia"
    // mesmo com o cadastro 100% ok.
    const h = ((d["health"] ?? d) as Record<string, unknown>) ?? {};
    const cert = (h["certificate"] ?? d["certificate"] ?? {}) as Record<string, unknown>;

    // checks[]: o retrato POR ITEM do cadastro da empresa (CNPJ, city_code, IM, CNAE,
    // certificado…). É a fonte da verdade do que É da empresa.
    const checks = Array.isArray(h["checks"]) ? (h["checks"] as Record<string, unknown>[]) : [];
    const checkPor = (key: string) => checks.find((c) => c?.["key"] === key);
    const checksOk = checks.length > 0 ? checks.every((c) => c?.["ok"] === true) : null;
    const certCheck = checkPor("certificate");
    const cityCheck = checkPor("city_code");

    // blocks[]: mistura pendência de empresa com ORIENTAÇÃO DE PAYLOAD (ex.: "informe
    // service.national_tax_code…"). A guidance derruba o ready da Contora mesmo com a
    // empresa perfeita — quem decide o que bloqueia é o handleNfseHealth, com contexto.
    const blocks = Array.isArray(h["blocks"])
      ? (h["blocks"] as unknown[]).map((b) =>
        typeof b === "string" ? b : String((b as Record<string, unknown>)?.["message"] ?? JSON.stringify(b)))
      : [];
    const brutoPendencias = (h["pending"] ?? d["pending"] ?? d["pendencies"] ?? d["missing"] ?? []) as unknown;
    const pending = Array.isArray(brutoPendencias)
      ? brutoPendencias.map((p) =>
        typeof p === "string"
          ? p
          : String((p as Record<string, unknown>)?.["message"] ?? JSON.stringify(p)))
      : [];

    const ready = h["ready"] === true || d["ready"] === true || d["status"] === "ready";
    // Certificado válido até: o check traz "… ate 12/05/2027" no detail.
    const certDetail = String(certCheck?.["detail"] ?? "");
    const certValidUntil = (cert["valid_until"] ?? cert["expires_at"]
      ?? (certDetail.match(/ate\s+(\d{2}\/\d{2}\/\d{4})/)?.[1] ?? null)) as string | null;

    return {
      ok: true,
      data: {
        ready,
        publicEmissionEnabled: h["public_emission_enabled"] === true,
        checksOk,
        blocks,
        standard: (h["standard"] ?? d["standard"] ?? d["nfse_standard"] ?? null) as string | null,
        cityCode: ((cityCheck?.["detail"] ?? d["city_code"]) ?? null) as string | null,
        cityName: (d["city_name"] ?? null) as string | null,
        certificateOk: certCheck ? certCheck["ok"] === true : (cert["valid"] === true || d["certificate_loaded"] === true),
        certificateValidUntil: certValidUntil,
        pending,
        raw: d,
      },
    };
  }

  /**
   * POST /nfse/drafts/{id}/refresh — sincroniza a situação fiscal com o autorizador.
   *
   * Usado depois de um dispatch com timeout ou resultado técnico desconhecido, ANTES de
   * qualquer nova emissão: a Contora reconcilia a DPS pelo RPS e é isso que impede a mesma
   * nota de sair duas vezes.
   */
  refresh(
    documentType: DocumentType,
    id: string,
    companyId?: string,
  ): Promise<FiscalResult<unknown>> {
    const fam = family(documentType);
    const base = companyId ? `/companies/${companyId}/${fam}` : `/${fam}`;
    return this.request("POST", `${base}/drafts/${id}/refresh`, undefined, {
      idempotencyKey: `refresh-${documentType}-${id}`,
    });
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

    // Rota por-empresa (/companies/{id}/nfe/drafts) quando companyId presente —
    // exigida para homologação numa empresa de produção (o flag allows_homologation
    // é por-empresa; a rota global valida o ambiente do token e recusa).
    const base = input.companyId ? `/companies/${input.companyId}/${fam}` : `/${fam}`;
    const r = await this.request<Record<string, unknown>>(
      "POST",
      `${base}/drafts`,
      body,
      { idempotencyKey: input.idempotencyKey },
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
    companyId?: string,
  ): Promise<FiscalResult<unknown>> {
    const fam = family(documentType);
    const base = companyId ? `/companies/${companyId}/${fam}` : `/${fam}`;
    return this.request(
      "POST",
      `${base}/drafts/${id}/build`,
      { sign },
    );
  }

  dispatch(
    documentType: DocumentType,
    id: string,
    action = "authorize",
    companyId?: string,
  ): Promise<FiscalResult<unknown>> {
    const fam = family(documentType);
    const base = companyId ? `/companies/${companyId}/${fam}` : `/${fam}`;
    // NF-e expects { action: "authorize" }; NFS-e dispatch is the emission trigger.
    const body = fam === "nfe" ? { action } : {};
    // Chave derivada do documento e da ação: um retry de dispatch não pode virar uma
    // segunda emissão da mesma nota.
    return this.request("POST", `${base}/drafts/${id}/dispatch`, body, {
      idempotencyKey: `dispatch-${documentType}-${id}-${action}`,
    });
  }

  async getStatus(
    documentType: DocumentType,
    id: string,
    companyId?: string,
  ): Promise<FiscalResult<DocumentStatusInfo>> {
    const fam = family(documentType);
    const base = companyId ? `/companies/${companyId}/${fam}` : `/${fam}`;
    const r = await this.request<Record<string, unknown>>(
      "GET",
      `${base}/drafts/${id}/status`,
    );
    if (!r.ok) return r as FiscalResult<DocumentStatusInfo>;
    const d = r.data ?? {};
    const lifecycle = (d["lifecycle"] ?? {}) as Record<string, unknown>;
    const sefaz = (d["sefaz"] ?? {}) as Record<string, unknown>;
    const provider = (d["provider"] ?? {}) as Record<string, unknown>; // nfse
    const statusStr = (lifecycle["status"] ?? d["status"]) as string;
    const procStr = (lifecycle["processing_status"] ??
      d["processing_status"]) as string;

    // CANCELAMENTO: a Contora rastreia num grupo SEPARADO (`cancellation`) — o
    // lifecycle.status continua "authorized" mesmo após cancelar. Se o
    // cancelamento foi homologado (SEFAZ 135 "evento registrado" / 155 "fora do
    // prazo") ou já tem cancelled_at, o status EFETIVO do documento é
    // "cancelled". Sem isto, o reconcile/webhook sobrescrevia de volta para
    // "authorized" e a nota cancelada aparecia como autorizada.
    const cancellation = (d["cancellation"] ?? {}) as Record<string, unknown>;
    const cancelCode = cancellation["status_code"] != null ? String(cancellation["status_code"]) : "";
    const cancelledAt = (cancellation["cancelled_at"] as string) ?? null;
    const isCancelled = !!cancelledAt || cancelCode === "135" || cancelCode === "155";
    // [VERIFICAÇÃO 18/08] Os códigos 135/155 são vocabulário de NF-e; o cancelamento de
    // NFS-e nacional pode chegar com outro formato que ainda não vimos ao vivo. Se o
    // grupo cancellation vier POPULADO sem casar com o que reconhecemos, deixa rastro —
    // o primeiro cancelamento real de NFS-e mostra o formato e a gente amplia.
    if (!isCancelled && (cancellation["status"] != null || cancelCode)) {
      console.warn(
        `[fiscal] cancellation não reconhecido em ${id}: status=${cancellation["status"]} code=${cancelCode} — verifique o formato (NFS-e?)`,
      );
    }

    return {
      ok: true,
      data: {
        providerDocumentId: String(d["id"] ?? id),
        status: isCancelled ? "cancelled" : mapContoraStatus(statusStr, procStr),
        statusCode: isCancelled ? cancelCode : ((sefaz["status_code"] as string) ?? null),
        statusMessage: isCancelled
          ? ((cancellation["status_message"] as string) ?? "Cancelamento homologado pela SEFAZ.")
          : ((sefaz["status_message"] ?? d["last_error_message"] ?? null) as string | null),
        // NFS-e não tem grupo `sefaz` — a chave nacional (50 dígitos) vem no nível do
        // documento (access_key). O fallback cobre as duas famílias.
        accessKey: ((sefaz["access_key"] ?? d["access_key"]) as string) ?? null,
        protocol: isCancelled
          ? ((cancellation["protocol"] as string) ?? (sefaz["protocol"] as string) ?? null)
          : ((sefaz["protocol"] ?? provider["protocol"] ?? null) as string | null),
        authorizedAt: (sefaz["authorized_at"] as string) ?? null,
        raw: d,
      },
    };
  }

  async listArtifacts(
    documentType: DocumentType,
    id: string,
    companyId?: string,
  ): Promise<FiscalResult<FiscalArtifact[]>> {
    const fam = family(documentType);
    const base = companyId ? `/companies/${companyId}/${fam}` : `/${fam}`;
    const r = await this.request<unknown>(
      "GET",
      `${base}/drafts/${id}/artifacts`,
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
      // Sem chave, um retry de cancelamento após timeout viraria um segundo pedido de
      // cancelamento do mesmo documento.
      { idempotencyKey: `cancel-${documentType}-${id}` },
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

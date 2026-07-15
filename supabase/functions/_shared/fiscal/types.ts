// Canonical types for the fiscal (NF-e/NFS-e) provider abstraction layer.
// Mirrors the shape of _shared/whatsapp so a provider can be swapped by env var
// without touching the callers (fiscal-emit, fiscal-webhook, fiscal-reconcile).
// ContoraProvider is the first implementation; a fallback (Focus NFe / Emissor
// Nacional) can implement the same interface later for NFS-e in production.

export type DocumentType = "nfe" | "nfce" | "nfse";
export type FiscalEnvironment = "homologacao" | "producao";

// Normalized lifecycle status stored in issued_fiscal_documents, independent of
// the provider's own status vocabulary.
export type FiscalStatus =
  | "draft"
  | "queued"
  | "processing"
  | "authorized"
  | "rejected" // business / SEFAZ / prefeitura rejection
  | "failed" // technical failure (job, queue, network, certificate)
  | "cancelled";

// Discriminated result, same convention as WhatsApp's SendResult.
export type FiscalResult<T> =
  | { ok: true; data: T }
  | {
      ok: false;
      error: string;
      errorType?: string; // provider error.type (e.g. sefaz_rejection, validation_error)
      details?: unknown;
      retryable: boolean;
    };

export interface CreateDraftInput {
  documentType: DocumentType;
  environment?: FiscalEnvironment;
  series?: number;
  number?: number;
  // Provider document body. For NF-e this is the SEFAZ layout (or a template.apply
  // result); for NFS-e it is { service, taker, amounts, ... }.
  payload: Record<string, unknown>;
}

export interface DraftCreated {
  providerDocumentId: string;
  status: FiscalStatus;
  raw: unknown;
}

export interface DocumentStatusInfo {
  providerDocumentId: string;
  status: FiscalStatus;
  statusCode?: string | null; // e.g. SEFAZ "100"
  statusMessage?: string | null;
  accessKey?: string | null;
  protocol?: string | null;
  authorizedAt?: string | null;
  raw: unknown;
}

export interface FiscalArtifact {
  type: string; // xml_authorized, pdf_danfe, xml_signed, xml_cancelled, ...
  label?: string;
  filename?: string;
  available: boolean;
  downloadUrl?: string | null;
}

// Canonical webhook event parsed (and signature-verified) from a provider callback.
export interface FiscalWebhookEvent {
  event: string; // e.g. document.authorized
  providerDocumentId: string | null;
  status: FiscalStatus | null; // best-effort from the event name; null = fetch status to confirm
  idempotencyKey: string | null; // for dedup on the consumer side
  deliveryId: string | null;
  raw: unknown;
}

export interface FiscalProvider {
  readonly name: string;

  // Auth smoke test (Contora: GET /me).
  validateToken(): Promise<FiscalResult<{ tokenId?: string; name?: string }>>;

  createDraft(input: CreateDraftInput): Promise<FiscalResult<DraftCreated>>;

  // NF-e/NFC-e only. NFS-e has no build step.
  build(
    documentType: DocumentType,
    providerDocumentId: string,
    sign?: boolean,
  ): Promise<FiscalResult<unknown>>;

  // Enqueue authorization (async). action defaults to "authorize".
  dispatch(
    documentType: DocumentType,
    providerDocumentId: string,
    action?: string,
  ): Promise<FiscalResult<unknown>>;

  // Free of charge on Contora (does not consume fiscal-event quota).
  getStatus(
    documentType: DocumentType,
    providerDocumentId: string,
  ): Promise<FiscalResult<DocumentStatusInfo>>;

  listArtifacts(
    documentType: DocumentType,
    providerDocumentId: string,
  ): Promise<FiscalResult<FiscalArtifact[]>>;

  cancel(
    documentType: DocumentType,
    providerDocumentId: string,
    reason: string,
  ): Promise<FiscalResult<unknown>>;

  // Carta de Correção Eletrônica (NF-e/CT-e only).
  correct(
    documentType: DocumentType,
    providerDocumentId: string,
    text: string,
  ): Promise<FiscalResult<unknown>>;

  // Verifies the HMAC signature and parses a webhook payload.
  // Returns null when the signature is invalid (caller must respond 401).
  parseWebhook(
    headers: Record<string, string>,
    rawBody: string,
  ): Promise<FiscalWebhookEvent | null>;
}

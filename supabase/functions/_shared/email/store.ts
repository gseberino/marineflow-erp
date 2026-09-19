// Persistência do espelho (Fase E1) — mapeamento puro + gravação com deduplicação.
//
// Independente do canal: qualquer adaptador (provedor de inbound, Worker, IMAP) produz
// um InboundEmail, e daqui para baixo o caminho é o mesmo.
//
// O que este módulo NÃO faz, de propósito: não chama LLM, não decide classe, não envia
// nada. Ele só guarda o que chegou, do jeito que chegou.

import {
  classifyAttachment, dedupKey, domainOf, normalizeAddress, normalizeMessageId,
  readableBody, safeStorageName, threadKey,
} from "./normalize.ts";
import type { InboundEmail } from "./types.ts";
import type { SenderMatch } from "./sender-match.ts";

export interface MessageRow {
  account_id: string;
  dedup_key: string;
  message_id: string | null;
  in_reply_to: string | null;
  references_ids: string[] | null;
  thread_key: string | null;
  from_name: string | null;
  from_address: string;
  to_addresses: string[];
  cc_addresses: string[];
  subject: string | null;
  body_text: string | null;
  received_at: string;
  raw_size: number | null;
  has_attachments: boolean;
  auth_results: string | null;
  client_id: string | null;
  supplier_id: string | null;
  match_confidence: number | null;
  match_reason: string | null;
}

export interface AttachmentRow {
  message_id: string;
  filename: string | null;
  mime_type: string | null;
  size_bytes: number | null;
  storage_path: string | null;
  kind: string;
}

/** Corpo guardado tem teto: e-mail com 2 MB de HTML não vira linha de 2 MB no banco. */
export const MAX_BODY_STORED = 20000;

/**
 * Caminho no bucket privado. Prefixado pelo id da mensagem para não haver colisão entre
 * dois fornecedores que mandam "nota.pdf" no mesmo dia.
 */
export function storagePathFor(messageId: string, filename: string | null, index: number): string {
  return `${messageId}/${index}-${safeStorageName(filename)}`;
}

/** Cabeçalho de autenticação da entrega ORIGINAL — lido, nunca recalculado. */
function authResultsOf(headers: Record<string, string>): string | null {
  for (const [k, v] of Object.entries(headers ?? {})) {
    if (k.toLowerCase() === "authentication-results") return String(v).slice(0, 500);
  }
  return null;
}

/** InboundEmail → linha de email_messages. Função pura. */
export function toMessageRow(
  email: InboundEmail,
  accountId: string,
  match: SenderMatch | null,
): MessageRow {
  const corpo = readableBody(email).slice(0, MAX_BODY_STORED);
  return {
    account_id: accountId,
    dedup_key: dedupKey(email),
    message_id: normalizeMessageId(email.messageId),
    in_reply_to: normalizeMessageId(email.inReplyTo),
    references_ids: (email.references ?? []).length > 0
      ? (email.references ?? []).map(normalizeMessageId).filter((r): r is string => !!r)
      : null,
    thread_key: threadKey(email),
    from_name: email.from?.name?.trim() || null,
    from_address: normalizeAddress(email.from?.address),
    to_addresses: (email.to ?? []).map((a) => normalizeAddress(a.address)).filter(Boolean),
    cc_addresses: (email.cc ?? []).map((a) => normalizeAddress(a.address)).filter(Boolean),
    subject: email.subject?.trim().slice(0, 500) || null,
    body_text: corpo || null,
    received_at: email.receivedAt,
    raw_size: email.rawSize ?? null,
    has_attachments: (email.attachments ?? []).length > 0,
    auth_results: authResultsOf(email.headers ?? {}),
    client_id: match?.kind === "client" ? match.id : null,
    supplier_id: match?.kind === "supplier" ? match.id : null,
    match_confidence: match?.confidence ?? null,
    match_reason: match?.reason ?? null,
  };
}

/** Anexos → linhas, já com tipo e caminho de storage. Função pura. */
export function toAttachmentRows(email: InboundEmail, messageId: string): AttachmentRow[] {
  return (email.attachments ?? []).map((a, i) => ({
    message_id: messageId,
    filename: a.filename ?? null,
    mime_type: a.mimeType ?? null,
    size_bytes: a.size ?? null,
    storage_path: storagePathFor(messageId, a.filename, i),
    kind: classifyAttachment(a),
  }));
}

/**
 * Decide se o remetente cai numa regra manual antes de qualquer triagem.
 * Regra por domínio usa o prefixo '@'.
 */
export function applySenderRules(
  fromAddress: string,
  rules: { pattern: string; action: string }[],
): string | null {
  const addr = normalizeAddress(fromAddress);
  const dom = domainOf(addr);
  for (const r of rules ?? []) {
    const p = normalizeAddress(r.pattern);
    if (!p) continue;
    if (p.startsWith("@")) {
      if (dom && `@${dom}` === p) return r.action;
    } else if (p === addr) {
      return r.action;
    }
  }
  return null;
}

// ───────────────────────── gravação ─────────────────────────

// Contrato mínimo do client, para o teste poder passar um dublê sem rede.
export interface DbLike {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
}

export interface PersistResult {
  status: "inserted" | "duplicate" | "error";
  messageId?: string;
  attachments?: number;
  error?: string;
}

/**
 * Grava a mensagem e os anexos.
 *
 * A deduplicação é do BANCO, não do código: a unique (account_id, dedup_key) é a
 * autoridade, e o 23505 é tratado como caminho normal — reentrega do provedor é
 * esperada, não é erro. Checar antes com um SELECT abriria janela de corrida entre
 * duas entregas simultâneas do mesmo e-mail.
 */
export async function persistInboundEmail(
  db: DbLike,
  email: InboundEmail,
  accountId: string,
  match: SenderMatch | null,
): Promise<PersistResult> {
  const row = toMessageRow(email, accountId, match);

  const { data, error } = await db
    .from("email_messages")
    .insert(row)
    .select("id")
    .single();

  if (error) {
    if ((error as { code?: string }).code === "23505") return { status: "duplicate" };
    return { status: "error", error: String((error as { message?: string }).message ?? error) };
  }

  const messageId = (data as { id: string }).id;
  const anexos = toAttachmentRows(email, messageId);

  if (anexos.length > 0) {
    const { error: attErr } = await db.from("email_attachments").insert(anexos);
    // Anexo que falha não invalida a mensagem: melhor ter o e-mail sem o anexo do que
    // perder os dois. O erro fica visível na contagem devolvida.
    if (attErr) return { status: "inserted", messageId, attachments: 0 };
  }

  return { status: "inserted", messageId, attachments: anexos.length };
}

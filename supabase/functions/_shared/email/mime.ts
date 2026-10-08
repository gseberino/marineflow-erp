// Fonte RFC 822 (o que o IMAP entrega) → InboundEmail, o contrato de todo o resto (08/10/2026).
// O parse é do npm:postal-mime (sem dependências, roda em Deno/Workers); aqui só se adapta a forma.

import PostalMime from "npm:postal-mime@2.4.3";
import type { EmailAddress, InboundEmail } from "./types.ts";

/** Cabeçalhos que a triagem determinística e a auditoria usam — o resto não é guardado. */
const CABECALHOS_UTEIS = new Set([
  "list-unsubscribe", "list-id", "precedence", "auto-submitted", "x-auto-response-suppress",
  "authentication-results", "return-path", "reply-to", "x-mailer", "content-type",
]);

// deno-lint-ignore no-explicit-any
function endereco(a: any): EmailAddress | null {
  if (!a) return null;
  if (a.address) return { name: a.name || null, address: String(a.address) };
  return null;
}

// deno-lint-ignore no-explicit-any
function lista(xs: any): EmailAddress[] {
  const out: EmailAddress[] = [];
  for (const x of Array.isArray(xs) ? xs : []) {
    // Grupo ("Equipe: a@b, c@d;") vem com .group.
    if (Array.isArray(x?.group)) for (const g of x.group) { const e = endereco(g); if (e) out.push(e); }
    else { const e = endereco(x); if (e) out.push(e); }
  }
  return out;
}

/** "<a@b> <c@d>" → ["a@b", "c@d"]. */
export function idsDeReferencia(v: string | null | undefined): string[] {
  return (String(v ?? "").match(/<[^>]+>/g) ?? []).map((s) => s.slice(1, -1));
}

/**
 * Tira o enchimento invisível dos e-mails de propaganda (o "preheader": centenas de &zwnj; e
 * caracteres de largura zero) — sem isso o texto que o assistente lê vira ruído (GoDaddy, 28/07).
 */
export function limparTexto(t: string | null | undefined): string | null {
  if (t == null) return null;
  return String(t)
    .replace(/&(zwnj|zwj|nbsp|shy);/gi, " ")
    .replace(/[\u200b-\u200d\u2060\ufeff\u00ad\u034f]/g, "")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n");
}

export async function mimeParaInbound(
  bruto: Uint8Array,
  opts: { recebidoEmFallback: string | null; tamanho: number | null },
): Promise<InboundEmail> {
  // deno-lint-ignore no-explicit-any
  const p: any = await PostalMime.parse(bruto);
  const headers: Record<string, string> = {};
  for (const h of p.headers ?? []) {
    const k = String(h.key ?? "").toLowerCase();
    if (CABECALHOS_UTEIS.has(k) && !(k in headers)) headers[k] = String(h.value ?? "").slice(0, 1000);
  }
  const data = p.date ? new Date(p.date) : null;
  const recebido = data && !Number.isNaN(data.getTime()) ? data.toISOString() : (opts.recebidoEmFallback ?? new Date().toISOString());
  return {
    messageId: p.messageId ? String(p.messageId).replace(/^<|>$/g, "") : null,
    inReplyTo: p.inReplyTo ? String(p.inReplyTo).replace(/^<|>$/g, "") : null,
    references: idsDeReferencia(p.references),
    from: endereco(p.from) ?? { name: null, address: "" },
    to: lista(p.to),
    cc: lista(p.cc),
    subject: p.subject ?? null,
    text: limparTexto(p.text),
    html: p.html ?? null,
    receivedAt: recebido,
    headers,
    // deno-lint-ignore no-explicit-any
    attachments: (p.attachments ?? []).map((a: any) => {
      const content = a.content instanceof ArrayBuffer ? new Uint8Array(a.content)
        : a.content instanceof Uint8Array ? a.content
        : typeof a.content === "string" ? new TextEncoder().encode(a.content) : null;
      return { filename: a.filename ?? null, mimeType: a.mimeType ?? null, size: content?.length ?? null, content };
    }),
    rawSize: opts.tamanho ?? bruto.length,
  };
}

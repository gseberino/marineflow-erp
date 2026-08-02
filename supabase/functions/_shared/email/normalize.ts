// Normalização de e-mail recebido — lógica pura, sem rede, sem banco, sem LLM.
//
// Tudo aqui é determinístico de propósito: é a camada que decide identidade (dedup),
// conversa (thread), o que é ruído óbvio e o que é anexo processável — coisas que não
// precisam de modelo e que ficariam mais caras e menos confiáveis se precisassem.

import type {
  AttachmentKind,
  EmailAddress,
  EmailAttachmentInput,
  InboundEmail,
  PreClassification,
} from "./types.ts";

// ─────────────────────────── identidade ───────────────────────────

/** Message-ID sem <>, minúsculo. O RFC 5322 trata a parte do domínio como case-insensitive. */
export function normalizeMessageId(raw: string | null | undefined): string | null {
  const s = String(raw ?? "").trim().replace(/^<|>$/g, "").trim();
  return s.length > 0 ? s.toLowerCase() : null;
}

/**
 * Chave de deduplicação. O Message-ID é a fonte da verdade; quando falta (remetente
 * malcomportado, ou canal que não repassa o cabeçalho), cai para uma chave sintética
 * estável a partir de remetente + assunto + minuto de recebimento.
 *
 * O minuto (e não o segundo) é proposital: o mesmo e-mail reentregue pelo provedor pode
 * chegar com timestamps de segundo diferentes, e reentrega não pode virar linha duplicada.
 */
export function dedupKey(email: Pick<InboundEmail, "messageId" | "from" | "subject" | "receivedAt">): string {
  const mid = normalizeMessageId(email.messageId);
  if (mid) return `mid:${mid}`;
  const from = normalizeAddress(email.from?.address ?? "");
  const subj = (email.subject ?? "").trim().toLowerCase().slice(0, 120);
  const minute = String(email.receivedAt ?? "").slice(0, 16); // YYYY-MM-DDTHH:mm
  return `syn:${from}|${subj}|${minute}`;
}

/**
 * Raiz da conversa. Pelo RFC 5322 o References é ordenado do mais antigo para o mais
 * recente, então o primeiro elemento é a raiz da árvore. Sem References, usa In-Reply-To;
 * sem nada, o próprio e-mail é a raiz.
 */
export function threadKey(email: Pick<InboundEmail, "messageId" | "inReplyTo" | "references">): string | null {
  const refs = (email.references ?? []).map(normalizeMessageId).filter((r): r is string => !!r);
  if (refs.length > 0) return refs[0];
  return normalizeMessageId(email.inReplyTo) ?? normalizeMessageId(email.messageId);
}

export function normalizeAddress(raw: string | null | undefined): string {
  return String(raw ?? "").trim().toLowerCase();
}

/** Domínio do endereço, sem o @. */
export function domainOf(address: string | null | undefined): string | null {
  const at = normalizeAddress(address).lastIndexOf("@");
  if (at < 0) return null;
  const d = normalizeAddress(address).slice(at + 1).trim();
  return d.length > 0 ? d : null;
}

// ──────────────────── pré-filtro determinístico ────────────────────

/**
 * Cabeçalhos que provam automação/lista. Vêm de RFC 3834 (Auto-Submitted), da convenção
 * antiga Precedence, e do RFC 2369 (List-*). Um e-mail marcado assim NUNCA merece resposta
 * nossa e quase nunca merece atenção — então é barrado antes de gastar token com ele.
 */
const BULK_PRECEDENCE = new Set(["bulk", "list", "junk"]);

export function preClassify(headers: Record<string, string>): PreClassification {
  const h: Record<string, string> = {};
  for (const [k, v] of Object.entries(headers ?? {})) h[k.toLowerCase()] = String(v ?? "").trim();

  const autoSubmitted = (h["auto-submitted"] || "").toLowerCase();
  // RFC 3834: qualquer valor diferente de "no" indica mensagem gerada automaticamente.
  if (autoSubmitted && autoSubmitted !== "no") {
    return { isBulk: false, isAutoReply: true, reason: `Auto-Submitted: ${autoSubmitted}` };
  }
  if ((h["x-autoreply"] || h["x-autorespond"] || "").length > 0) {
    return { isBulk: false, isAutoReply: true, reason: "cabeçalho de auto-resposta" };
  }

  const precedence = (h["precedence"] || "").toLowerCase();
  if (BULK_PRECEDENCE.has(precedence)) {
    return { isBulk: true, isAutoReply: false, reason: `Precedence: ${precedence}` };
  }
  if (h["list-unsubscribe"] || h["list-id"]) {
    return { isBulk: true, isAutoReply: false, reason: "mensagem de lista (List-Unsubscribe/List-Id)" };
  }
  if ((h["x-campaign-id"] || h["x-mailer-campaign"] || "").length > 0) {
    return { isBulk: true, isAutoReply: false, reason: "disparo de campanha de marketing" };
  }

  return { isBulk: false, isAutoReply: false, reason: null };
}

/** Remetente que não aceita resposta. Sinal forte de que responder é inútil. */
export function isNoReplySender(address: string | null | undefined): boolean {
  const local = normalizeAddress(address).split("@")[0] ?? "";
  return /^(no-?reply|nao-?responda|nao-?responder|donotreply|notifica(coes|cao)?|mailer-daemon|postmaster)/.test(local);
}

// ───────────────────────── limpeza de corpo ─────────────────────────

/**
 * Remove citação de mensagem anterior e assinatura. Sem isso, um fio com 8 respostas
 * manda 8 cópias do mesmo texto para o modelo — caro e ruim para a classificação, porque
 * a evidência mais forte costuma estar no texto ANTIGO, não no que acabou de chegar.
 *
 * Conservador de propósito: na dúvida mantém o texto. Perder assunto é pior que gastar token.
 */
const QUOTE_MARKERS = [
  /^-{2,}\s*mensagem original\s*-{2,}/i,
  /^-{2,}\s*original message\s*-{2,}/i,
  /^-{2,}\s*forwarded message\s*-{2,}/i,
  /^_{5,}$/,
  /^em\s.+escreveu:\s*$/i,
  /^on\s.+wrote:\s*$/i,
  /^de:\s.+$/i,
  /^from:\s.+$/i,
];

export function stripQuotedReply(body: string | null | undefined): string {
  const text = String(body ?? "").replace(/\r\n/g, "\n");
  if (!text.trim()) return "";
  const lines = text.split("\n");

  let cut = lines.length;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (QUOTE_MARKERS.some((re) => re.test(line))) { cut = i; break; }
    // Bloco de citação: 3+ linhas seguidas começando com ">" encerra o texto novo.
    if (line.startsWith(">")) {
      let run = 0;
      for (let j = i; j < lines.length && lines[j].trim().startsWith(">"); j++) run++;
      if (run >= 3) { cut = i; break; }
    }
  }

  let kept = lines.slice(0, cut);

  // Assinatura: separador "-- " do RFC 3676 corta o resto.
  const sigAt = kept.findIndex((l) => l.trimEnd() === "--" || l.trimEnd() === "-- ");
  if (sigAt >= 0) kept = kept.slice(0, sigAt);

  return kept.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

/** HTML → texto pobre mas suficiente para triagem, quando não veio parte text/plain. */
export function htmlToText(html: string | null | undefined): string {
  return String(html ?? "")
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|tr|li|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** Texto que a triagem enxerga: prefere text/plain, cai para HTML, corta citação. */
export function readableBody(email: Pick<InboundEmail, "text" | "html">): string {
  const plain = stripQuotedReply(email.text);
  if (plain.length >= 20) return plain;
  const fromHtml = stripQuotedReply(htmlToText(email.html));
  return fromHtml.length > plain.length ? fromHtml : plain;
}

// ─────────────────────────── anexos ───────────────────────────

const XML_EXT = /\.xml$/i;
const PDF_EXT = /\.pdf$/i;

/**
 * Tipagem de anexo por nome + mime. Determinístico e conservador: só marca `nfe_xml`
 * quando o indício é forte, porque essa classe destrava um fluxo de escrita no estoque.
 */
export function classifyAttachment(att: Pick<EmailAttachmentInput, "filename" | "mimeType">): AttachmentKind {
  const name = String(att.filename ?? "").trim();
  const mime = String(att.mimeType ?? "").toLowerCase();

  if (XML_EXT.test(name) || mime.includes("xml")) {
    // Chave de acesso da NF-e tem 44 dígitos e costuma ser o próprio nome do arquivo.
    if (/\d{44}/.test(name) || /(nfe|nf-e|proc|procnfe)/i.test(name)) return "nfe_xml";
    return "nfe_xml"; // XML anexado por fornecedor é NF-e em praticamente 100% dos casos
  }
  if (PDF_EXT.test(name) || mime === "application/pdf") {
    if (/(boleto|cobran|fatura|titulo|título)/i.test(name)) return "boleto_pdf";
    if (/(danfe|nfe|nf-e|nota)/i.test(name)) return "danfe";
    return "outro";
  }
  if (mime.startsWith("image/") || /\.(png|jpe?g|gif|webp|heic)$/i.test(name)) return "imagem";
  if (/\.(xlsx?|csv|ods)$/i.test(name) || mime.includes("spreadsheet") || mime.includes("excel")) return "planilha";
  return "outro";
}

/** Nome de arquivo seguro para virar path de storage. */
export function safeStorageName(filename: string | null | undefined, fallback = "anexo"): string {
  const base = String(filename ?? "").split(/[\\/]/).pop() ?? "";
  const cleaned = base
    // ̀-ͯ = marcas diacríticas combinantes soltas pelo NFD ("ç" → "c" + cedilha)
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-zA-Z0-9._-]/g, "_")
    .replace(/_{2,}/g, "_")
    .replace(/^[._-]+/, "")
    .slice(0, 120);
  return cleaned.length > 0 ? cleaned : fallback;
}

/** Formata o remetente para exibição, sem inventar nome. */
export function displaySender(from: EmailAddress | null | undefined): string {
  const name = String(from?.name ?? "").trim();
  const addr = normalizeAddress(from?.address);
  if (name && name.toLowerCase() !== addr) return `${name} <${addr}>`;
  return addr || "(remetente desconhecido)";
}

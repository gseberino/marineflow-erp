import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  toMessageRow, toAttachmentRows, storagePathFor, applySenderRules, persistInboundEmail,
  MAX_BODY_STORED, type DbLike,
} from "./store.ts";
import type { InboundEmail } from "./types.ts";
import type { SenderMatch } from "./sender-match.ts";

function email(over: Partial<InboundEmail> = {}): InboundEmail {
  return {
    messageId: "<abc@fornecedor.com.br>", inReplyTo: null, references: [],
    from: { name: "Náutica Sul", address: "Vendas@NauticaSul.com.br" },
    to: [{ name: null, address: "Gustavo@hbrmarine.com.br" }], cc: [],
    subject: "  Nota fiscal do pedido 4471  ",
    text: "Segue a nota fiscal do pedido 4471 em anexo.",
    html: null, receivedAt: "2026-08-03T13:00:00Z",
    headers: { "Authentication-Results": "mx.secureserver.net; spf=pass smtp.mailfrom=nauticasul.com.br" },
    attachments: [], rawSize: 4096,
    ...over,
  };
}

const MATCH_FORN: SenderMatch = {
  id: "f-1", kind: "supplier", name: "Náutica Sul", confidence: 1, reason: "exact_email",
};

Deno.test("toMessageRow: normaliza endereços e apara o assunto", () => {
  const r = toMessageRow(email(), "acc-1", null);
  assertEquals(r.from_address, "vendas@nauticasul.com.br");
  assertEquals(r.to_addresses, ["gustavo@hbrmarine.com.br"]);
  assertEquals(r.subject, "Nota fiscal do pedido 4471");
  assertEquals(r.account_id, "acc-1");
});

Deno.test("toMessageRow: dedup_key usa o Message-ID quando existe", () => {
  assertEquals(toMessageRow(email(), "acc-1", null).dedup_key, "mid:abc@fornecedor.com.br");
});

Deno.test("toMessageRow: preserva o Authentication-Results da entrega original", () => {
  const r = toMessageRow(email(), "acc-1", null);
  assert(r.auth_results?.includes("spf=pass"));
});

Deno.test("toMessageRow: sem cabeçalho de autenticação, guarda null (não inventa)", () => {
  assertEquals(toMessageRow(email({ headers: {} }), "acc-1", null).auth_results, null);
});

Deno.test("toMessageRow: fornecedor vai em supplier_id e NÃO em client_id", () => {
  const r = toMessageRow(email(), "acc-1", MATCH_FORN);
  assertEquals(r.supplier_id, "f-1");
  assertEquals(r.client_id, null);
  assertEquals(r.match_confidence, 1);
  assertEquals(r.match_reason, "exact_email");
});

Deno.test("toMessageRow: cliente vai em client_id e NÃO em supplier_id", () => {
  const m: SenderMatch = { id: "c-9", kind: "client", name: "Marina", confidence: 0.8, reason: "domain" };
  const r = toMessageRow(email(), "acc-1", m);
  assertEquals(r.client_id, "c-9");
  assertEquals(r.supplier_id, null);
});

Deno.test("toMessageRow: sem casamento, os dois ficam null", () => {
  const r = toMessageRow(email(), "acc-1", null);
  assertEquals(r.client_id, null);
  assertEquals(r.supplier_id, null);
  assertEquals(r.match_confidence, null);
});

Deno.test("toMessageRow: corpo gigante é truncado antes de virar linha", () => {
  const r = toMessageRow(email({ text: "a".repeat(80000) }), "acc-1", null);
  assert((r.body_text?.length ?? 0) <= MAX_BODY_STORED);
});

Deno.test("toMessageRow: fio da conversa sai do primeiro References", () => {
  const r = toMessageRow(email({ references: ["<raiz@x>", "<meio@x>"] }), "acc-1", null);
  assertEquals(r.thread_key, "raiz@x");
  assertEquals(r.references_ids, ["raiz@x", "meio@x"]);
});

Deno.test("toMessageRow: sem References, references_ids é null e não array vazio", () => {
  assertEquals(toMessageRow(email(), "acc-1", null).references_ids, null);
});

Deno.test("toMessageRow: has_attachments reflete a realidade", () => {
  assertEquals(toMessageRow(email(), "acc-1", null).has_attachments, false);
  const comAnexo = email({ attachments: [{ filename: "n.xml", mimeType: "text/xml", size: 10 }] });
  assertEquals(toMessageRow(comAnexo, "acc-1", null).has_attachments, true);
});

Deno.test("toAttachmentRows: tipa e gera caminho sem colisão", () => {
  const e = email({
    attachments: [
      { filename: "35260712345678000199.xml", mimeType: "text/xml", size: 900 },
      { filename: "boleto 4471.pdf", mimeType: "application/pdf", size: 50000 },
    ],
  });
  const rows = toAttachmentRows(e, "msg-1");
  assertEquals(rows.length, 2);
  assertEquals(rows[0].kind, "nfe_xml");
  assertEquals(rows[1].kind, "boleto_pdf");
  assertEquals(rows[0].storage_path, "msg-1/0-35260712345678000199.xml");
  assertEquals(rows[1].storage_path, "msg-1/1-boleto_4471.pdf");
});

Deno.test("storagePathFor: nome perigoso não escapa do prefixo da mensagem", () => {
  const p = storagePathFor("msg-1", "../../etc/senha.pdf", 0);
  assert(p.startsWith("msg-1/0-"));
  assertEquals(p.includes(".."), false);
});

Deno.test("applySenderRules: casa endereço exato e domínio", () => {
  const regras = [
    { pattern: "newsletter@loja.com", action: "ignore_always" },
    { pattern: "@spammer.com.br", action: "ignore_always" },
  ];
  assertEquals(applySenderRules("Newsletter@Loja.com", regras), "ignore_always");
  assertEquals(applySenderRules("qualquer@spammer.com.br", regras), "ignore_always");
  assertEquals(applySenderRules("vendas@nauticasul.com.br", regras), null);
});

Deno.test("applySenderRules: regra de domínio não vaza para domínio parecido", () => {
  const regras = [{ pattern: "@spammer.com.br", action: "ignore_always" }];
  assertEquals(applySenderRules("x@nao-spammer.com.br", regras), null);
});

// ── gravação, com dublê de banco ──────────────────────────────────────

function fakeDb(behavior: { insertError?: { code?: string; message?: string }; attError?: unknown }): {
  db: DbLike; inserts: Record<string, unknown[]>;
} {
  const inserts: Record<string, unknown[]> = { email_messages: [], email_attachments: [] };
  const db: DbLike = {
    from(table: string) {
      return {
        // deno-lint-ignore no-explicit-any
        insert(payload: any) {
          if (table === "email_attachments") {
            if (behavior.attError) return Promise.resolve({ error: behavior.attError });
            inserts.email_attachments.push(...(Array.isArray(payload) ? payload : [payload]));
            return Promise.resolve({ error: null });
          }
          inserts.email_messages.push(payload);
          return {
            select() {
              return {
                single() {
                  if (behavior.insertError) return Promise.resolve({ data: null, error: behavior.insertError });
                  return Promise.resolve({ data: { id: "msg-novo" }, error: null });
                },
              };
            },
          };
        },
      };
    },
  };
  return { db, inserts };
}

Deno.test("persistInboundEmail: grava mensagem e anexos", async () => {
  const { db, inserts } = fakeDb({});
  const e = email({ attachments: [{ filename: "n.xml", mimeType: "text/xml", size: 10 }] });
  const r = await persistInboundEmail(db, e, "acc-1", MATCH_FORN);
  assertEquals(r.status, "inserted");
  assertEquals(r.messageId, "msg-novo");
  assertEquals(r.attachments, 1);
  assertEquals(inserts.email_messages.length, 1);
  assertEquals(inserts.email_attachments.length, 1);
});

Deno.test("persistInboundEmail: 23505 é reentrega, não erro", async () => {
  const { db } = fakeDb({ insertError: { code: "23505", message: "duplicate key" } });
  const r = await persistInboundEmail(db, email(), "acc-1", null);
  assertEquals(r.status, "duplicate");
  assertEquals(r.error, undefined);
});

Deno.test("persistInboundEmail: outro erro do banco é reportado", async () => {
  const { db } = fakeDb({ insertError: { code: "42703", message: "column does not exist" } });
  const r = await persistInboundEmail(db, email(), "acc-1", null);
  assertEquals(r.status, "error");
  assert(r.error?.includes("column does not exist"));
});

Deno.test("persistInboundEmail: anexo que falha não derruba a mensagem", async () => {
  const { db } = fakeDb({ attError: { message: "storage indisponível" } });
  const e = email({ attachments: [{ filename: "n.xml", mimeType: "text/xml", size: 10 }] });
  const r = await persistInboundEmail(db, e, "acc-1", null);
  assertEquals(r.status, "inserted", "melhor ter o e-mail sem o anexo do que perder os dois");
  assertEquals(r.attachments, 0);
});

Deno.test("persistInboundEmail: e-mail sem anexo não chama a tabela de anexos", async () => {
  const { db, inserts } = fakeDb({});
  const r = await persistInboundEmail(db, email(), "acc-1", null);
  assertEquals(r.attachments, 0);
  assertEquals(inserts.email_attachments.length, 0);
});

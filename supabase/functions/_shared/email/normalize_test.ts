import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeMessageId, dedupKey, threadKey, domainOf, preClassify, isNoReplySender,
  stripQuotedReply, htmlToText, readableBody, classifyAttachment, safeStorageName, displaySender,
} from "./normalize.ts";

Deno.test("normalizeMessageId: tira <> e normaliza caixa", () => {
  assertEquals(normalizeMessageId("<ABC@Example.COM>"), "abc@example.com");
  assertEquals(normalizeMessageId("  "), null);
  assertEquals(normalizeMessageId(null), null);
});

Deno.test("dedupKey: usa Message-ID quando existe", () => {
  const k = dedupKey({
    messageId: "<x1@fornecedor.com.br>", from: { name: null, address: "a@b.com" },
    subject: "Nota", receivedAt: "2026-07-27T10:00:00Z",
  });
  assertEquals(k, "mid:x1@fornecedor.com.br");
});

Deno.test("dedupKey: sem Message-ID, reentrega no mesmo minuto gera a MESMA chave", () => {
  const base = {
    messageId: null, from: { name: "F", address: "Fornecedor@Empresa.com" },
    subject: " Nota Fiscal ", receivedAt: "2026-07-27T10:00:31Z",
  };
  const k1 = dedupKey(base);
  const k2 = dedupKey({ ...base, receivedAt: "2026-07-27T10:00:58Z" });
  assertEquals(k1, k2, "segundos diferentes no mesmo minuto não podem virar duas linhas");
  const k3 = dedupKey({ ...base, receivedAt: "2026-07-27T10:01:02Z" });
  assert(k1 !== k3);
});

Deno.test("threadKey: a raiz é o primeiro References (RFC 5322)", () => {
  assertEquals(
    threadKey({ messageId: "<c@x>", inReplyTo: "<b@x>", references: ["<a@x>", "<b@x>"] }),
    "a@x",
  );
});

Deno.test("threadKey: sem References cai para In-Reply-To, e depois para si mesmo", () => {
  assertEquals(threadKey({ messageId: "<c@x>", inReplyTo: "<b@x>", references: [] }), "b@x");
  assertEquals(threadKey({ messageId: "<c@x>", inReplyTo: null, references: [] }), "c@x");
});

Deno.test("domainOf: extrai domínio e tolera lixo", () => {
  assertEquals(domainOf("Fulano@Empresa.COM.BR"), "empresa.com.br");
  assertEquals(domainOf("sem-arroba"), null);
});

Deno.test("preClassify: Auto-Submitted diferente de 'no' é auto-resposta (RFC 3834)", () => {
  assertEquals(preClassify({ "Auto-Submitted": "auto-replied" }).isAutoReply, true);
  assertEquals(preClassify({ "auto-submitted": "no" }).isAutoReply, false);
});

Deno.test("preClassify: lista e campanha viram bulk", () => {
  assert(preClassify({ "Precedence": "bulk" }).isBulk);
  assert(preClassify({ "List-Unsubscribe": "<https://x/u>" }).isBulk);
  assert(preClassify({ "X-Campaign-Id": "42" }).isBulk);
});

Deno.test("preClassify: e-mail normal não é marcado", () => {
  const p = preClassify({ "From": "cliente@marina.com.br", "Subject": "orçamento" });
  assertEquals(p.isBulk, false);
  assertEquals(p.isAutoReply, false);
  assertEquals(p.reason, null);
});

Deno.test("isNoReplySender: pega as variações usadas no Brasil", () => {
  assert(isNoReplySender("no-reply@banco.com.br"));
  assert(isNoReplySender("naoresponda@loja.com"));
  assert(isNoReplySender("nao-responder@x.com"));
  assertEquals(isNoReplySender("gustavo@hbrmarine.com.br"), false);
});

Deno.test("stripQuotedReply: corta 'Em ... escreveu:' e mantém o texto novo", () => {
  const corpo = `Bom dia, consegue passar o prazo?

Em 26 de julho de 2026, Gustavo escreveu:
> Segue o orçamento em anexo
> Qualquer dúvida me chame`;
  assertEquals(stripQuotedReply(corpo), "Bom dia, consegue passar o prazo?");
});

Deno.test("stripQuotedReply: corta bloco de citação com 3+ linhas '>'", () => {
  const corpo = "Ok, obrigado!\n\n> linha 1\n> linha 2\n> linha 3";
  assertEquals(stripQuotedReply(corpo), "Ok, obrigado!");
});

Deno.test("stripQuotedReply: uma linha '>' isolada NÃO corta (conservador)", () => {
  const corpo = "Segue conforme falamos:\n> item unico citado\ne o restante do texto importante";
  assert(stripQuotedReply(corpo).includes("restante do texto importante"));
});

Deno.test("stripQuotedReply: corta assinatura após '--'", () => {
  const corpo = "Confirmado para terça.\n--\nJoão\nGerente";
  assertEquals(stripQuotedReply(corpo), "Confirmado para terça.");
});

Deno.test("htmlToText: vira texto legível sem tags nem entidades", () => {
  const t = htmlToText("<p>Ol&aacute;</p><div>Prazo &amp; valor</div><script>x()</script>");
  assert(!t.includes("<"));
  assert(t.includes("Prazo & valor"));
  assert(!t.includes("x()"));
});

Deno.test("readableBody: usa o HTML quando o texto plano é vazio", () => {
  const b = readableBody({ text: "", html: "<p>Segue a nota fiscal do pedido 1234 em anexo.</p>" });
  assert(b.includes("nota fiscal do pedido 1234"));
});

Deno.test("classifyAttachment: XML de fornecedor é NF-e; PDF depende do nome", () => {
  assertEquals(classifyAttachment({ filename: "35260712345678000199.xml", mimeType: "text/xml" }), "nfe_xml");
  assertEquals(classifyAttachment({ filename: "boleto_4471.pdf", mimeType: "application/pdf" }), "boleto_pdf");
  assertEquals(classifyAttachment({ filename: "danfe.pdf", mimeType: "application/pdf" }), "danfe");
  assertEquals(classifyAttachment({ filename: "contrato.pdf", mimeType: "application/pdf" }), "outro");
  assertEquals(classifyAttachment({ filename: "motor.jpg", mimeType: "image/jpeg" }), "imagem");
  assertEquals(classifyAttachment({ filename: "tabela.xlsx", mimeType: null }), "planilha");
});

Deno.test("safeStorageName: remove acento, caminho e caractere perigoso", () => {
  assertEquals(safeStorageName("../../etc/Nota Fiscal ção.pdf"), "Nota_Fiscal_cao.pdf");
  assertEquals(safeStorageName(null), "anexo");
  assertEquals(safeStorageName("   "), "anexo");
});

Deno.test("displaySender: não repete o endereço quando o nome é igual", () => {
  assertEquals(displaySender({ name: "Marina Itajaí", address: "contato@marina.com.br" }), "Marina Itajaí <contato@marina.com.br>");
  assertEquals(displaySender({ name: "a@b.com", address: "a@b.com" }), "a@b.com");
  assertEquals(displaySender(null), "(remetente desconhecido)");
});

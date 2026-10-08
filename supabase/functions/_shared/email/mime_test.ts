import { assertEquals } from "jsr:@std/assert@1";
import { idsDeReferencia, mimeParaInbound } from "./mime.ts";

const fonte = [
  "From: \"Coremma Peças\" <vendas@coremma.com.br>",
  "To: financeiro@hbrmarine.com.br, \"Gustavo\" <gustavo@hbrmarine.com.br>",
  "Subject: =?UTF-8?Q?Boleto_e_nota_da_compra_n=C2=BA_812?=",
  "Message-ID: <abc123@coremma.com.br>",
  "In-Reply-To: <antes@hbrmarine.com.br>",
  "References: <x1@a> <antes@hbrmarine.com.br>",
  "Date: Tue, 07 Oct 2026 10:15:00 -0300",
  "List-Unsubscribe: <mailto:sair@coremma.com.br>",
  "MIME-Version: 1.0",
  "Content-Type: multipart/mixed; boundary=\"XYZ\"",
  "",
  "--XYZ",
  "Content-Type: text/plain; charset=utf-8",
  "Content-Transfer-Encoding: 8bit",
  "",
  "Segue a nota e o boleto da compra nº 812.",
  "--XYZ",
  "Content-Type: application/xml; name=\"nfe.xml\"",
  "Content-Disposition: attachment; filename=\"nfe.xml\"",
  "Content-Transfer-Encoding: base64",
  "",
  btoa("<nfeProc>ok</nfeProc>"),
  "--XYZ--",
  "",
].join("\r\n");

Deno.test("MIME com anexo vira InboundEmail: remetente, destinatários, assunto codificado, anexo com conteúdo", async () => {
  const e = await mimeParaInbound(new TextEncoder().encode(fonte), { recebidoEmFallback: null, tamanho: null });
  assertEquals(e.messageId, "abc123@coremma.com.br");
  assertEquals(e.inReplyTo, "antes@hbrmarine.com.br");
  assertEquals(e.references, ["x1@a", "antes@hbrmarine.com.br"]);
  assertEquals(e.from, { name: "Coremma Peças", address: "vendas@coremma.com.br" });
  assertEquals(e.to.map((t) => t.address), ["financeiro@hbrmarine.com.br", "gustavo@hbrmarine.com.br"]);
  assertEquals(e.subject, "Boleto e nota da compra nº 812");
  assertEquals(e.receivedAt, "2026-10-07T13:15:00.000Z");
  assertEquals(e.text?.trim(), "Segue a nota e o boleto da compra nº 812.");
  assertEquals(e.headers["list-unsubscribe"], "<mailto:sair@coremma.com.br>");
  assertEquals(e.attachments.length, 1);
  assertEquals(e.attachments[0].filename, "nfe.xml");
  assertEquals(new TextDecoder().decode(e.attachments[0].content!), "<nfeProc>ok</nfeProc>");
});

Deno.test("sem Date usa a data de chegada do servidor", async () => {
  const e = await mimeParaInbound(new TextEncoder().encode("From: a@b.com\r\nSubject: x\r\n\r\ncorpo\r\n"), { recebidoEmFallback: "2026-10-07T17:30:00.000Z", tamanho: 50 });
  assertEquals(e.receivedAt, "2026-10-07T17:30:00.000Z");
  assertEquals(e.rawSize, 50);
});

Deno.test("idsDeReferencia", () => assertEquals(idsDeReferencia("<a@b>  <c@d>"), ["a@b", "c@d"]));

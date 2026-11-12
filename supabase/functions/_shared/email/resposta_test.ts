import { assertEquals } from "jsr:@std/assert@1";
import { assuntoDaResposta, cabecalhosDeResposta, ehEnderecoDaHbr, envioDaCaixa, pastaDeEnviados, podeResponder } from "./resposta.ts";

const base = { from_address: "vendas@coremma.com.br", triage_class: null as string | null, muted: false, client_id: null, supplier_id: null };

Deno.test("podeResponder: só e-mail importante — nunca propaganda, automático ou silenciado", () => {
  assertEquals(podeResponder({ ...base, triage_class: "urgent" }).ok, true);
  assertEquals(podeResponder({ ...base, triage_class: "respond" }).ok, true);
  assertEquals(podeResponder({ ...base, triage_class: "notify" }).ok, false);
  assertEquals(podeResponder({ ...base, triage_class: "notify", supplier_id: "s1" }).ok, true);
  assertEquals(podeResponder({ ...base, supplier_id: "s1" }).ok, true); // histórico de fornecedor
  assertEquals(podeResponder({ ...base, triage_class: "ignore", supplier_id: "s1" }).ok, false);
  assertEquals(podeResponder({ ...base, triage_class: "urgent", muted: true }).ok, false);
  assertEquals(podeResponder({ ...base, triage_class: "urgent", from_address: "no-reply@banco.com.br" }).ok, false);
  assertEquals(podeResponder({ ...base, triage_class: "urgent", from_address: "donotreply@godaddy.com" }).ok, false);
  assertEquals(podeResponder({ ...base, triage_class: "respond", from_address: "gustavo@hbrmarine.com.br" }).ok, false);
});

Deno.test("assunto e cabeçalhos da resposta", () => {
  assertEquals(assuntoDaResposta("RE: Res: Fwd: Pedido 812"), "Re: Pedido 812");
  assertEquals(assuntoDaResposta(null), "Re: (sem assunto)");
  assertEquals(cabecalhosDeResposta("m3@x", ["m1@x", "m2@x"]), { "In-Reply-To": "<m3@x>", References: "<m1@x> <m2@x> <m3@x>" });
  assertEquals(cabecalhosDeResposta(null, []), {});
});

Deno.test("pasta de Enviados: a marcada \\Sent vence o nome", () => {
  assertEquals(pastaDeEnviados([{ nome: "INBOX", atributos: [] }, { nome: "Itens Enviados", atributos: ["\\HasNoChildren", "\\Sent"] }]), "Itens Enviados");
  assertEquals(pastaDeEnviados([{ nome: "INBOX.Sent", atributos: [] }]), "INBOX.Sent");
  assertEquals(pastaDeEnviados([{ nome: "INBOX", atributos: [] }]), null);
});

Deno.test("Gmail hbr.boats@ (12/11/2026): é da própria HBR e responde pelo smtp.gmail.com, sem cópia por APPEND", () => {
  assertEquals(ehEnderecoDaHbr("HBR.Boats@Gmail.com"), true);
  assertEquals(ehEnderecoDaHbr("gustavo@hbrmarine.com.br"), true);
  assertEquals(ehEnderecoDaHbr("@hbrmarine.com.br"), true);
  assertEquals(ehEnderecoDaHbr("outro.boats@gmail.com"), false);
  assertEquals(ehEnderecoDaHbr("vendas@coremma.com.br"), false);
  assertEquals(podeResponder({ ...base, triage_class: "urgent", from_address: "hbr.boats@gmail.com" }).ok, false);

  assertEquals(envioDaCaixa("imap.gmail.com", { host: "smtpout.secureserver.net", porta: "465" }), { host: "smtp.gmail.com", porta: 465, copiarEmEnviados: false });
  assertEquals(envioDaCaixa("imap.secureserver.net", { host: "smtpout.secureserver.net", porta: "465" }), { host: "smtpout.secureserver.net", porta: 465, copiarEmEnviados: true });
  assertEquals(envioDaCaixa(null, {}), { host: "smtpout.secureserver.net", porta: 465, copiarEmEnviados: true });
});

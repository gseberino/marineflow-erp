// O envio do whatsapp-send entra na conversa (15/10/2026). Os casos são os de produção: em 07/10 o
// assistente mandou 3 mensagens ao Miguel (08:54, 13:45 e 14:58) e nenhuma ficou em
// whatsapp_messages — daí o "nada foi enviado" e o "esperando resposta" errado.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { deveRegistrarEnvio, linhaDaMensagemEnviada, origemDoEnvio, quemEnviou, textoDoEnvio } from "./registro-do-envio.ts";

const DONO = "6f1c1f0e-1111-4c4c-9a9a-0a0a0a0a0a0a";
const MIGUEL = "351966776422";
const CLIENTE = "c0c0c0c0-2222-4d4d-8b8b-1b1b1b1b1b1b";

Deno.test("texto do assistente ao Miguel: linha de saída, com quem mandou, a origem e o cliente da conversa", () => {
  const msg = "Bom dia, Miguel! Dá sim pra colocar uma câmera na casa de máquinas e ver na tela";
  const linha = linhaDaMensagemEnviada({ kind: "text", message: msg }, MIGUEL, "3EB0B3F4597EA0C291B1BC", DONO, "assistente", null, {
    client_id: CLIENTE, lead_id: null, supplier_id: null,
  });
  assertEquals(linha, {
    direction: "outbound",
    phone_normalized: MIGUEL,
    message_type: "text",
    body: msg,
    wa_message_id: "3EB0B3F4597EA0C291B1BC",
    delivery_status: "sent",
    sent_by: DONO,
    client_id: CLIENTE,
    lead_id: null,
    supplier_id: null,
    service_order_id: null,
    raw_payload: { origem: "assistente", contexto: null, via: "whatsapp-send" },
  });
});

Deno.test("link: o texto e a URL (sem repetir quando a URL já está no texto); PDF: a legenda ou o nome do arquivo", () => {
  assertEquals(textoDoEnvio({ kind: "link", message: "Segue o orçamento", link_url: "https://x/view/abc" }), "Segue o orçamento\nhttps://x/view/abc");
  assertEquals(textoDoEnvio({ kind: "link", message: "Segue o link: https://x/view/abc", link_url: "https://x/view/abc" }), "Segue o link: https://x/view/abc");
  assertEquals(textoDoEnvio({ kind: "document", document_caption: "ORÇ-00112", document_filename: "orc.pdf" }), "ORÇ-00112");
  assertEquals(textoDoEnvio({ kind: "document", document_filename: "ORC-00112.pdf" }), "[pdf] ORC-00112.pdf");
  const pdf = linhaDaMensagemEnviada({ kind: "document", document_filename: "ORC-00112.pdf", service_order_id: CLIENTE }, MIGUEL, null, null, "sistema", "quote");
  assertEquals([pdf.message_type, pdf.body, pdf.service_order_id, pdf.client_id], ["document", "[pdf] ORC-00112.pdf", CLIENTE, null]);
  assertEquals(pdf.raw_payload, { origem: "sistema", contexto: "quote", via: "whatsapp-send" });
});

Deno.test("não entra: desviado pelo modo de teste ou para quem conversa com o assistente (nono dígito tanto faz)", () => {
  const assistente = ["5547999159654"];
  assertEquals(deveRegistrarEnvio({ desviadoPorTeste: false, telefone: MIGUEL, telefonesDoAssistente: assistente }), true);
  assertEquals(deveRegistrarEnvio({ desviadoPorTeste: true, telefone: MIGUEL, telefonesDoAssistente: assistente }), false);
  assertEquals(deveRegistrarEnvio({ desviadoPorTeste: false, telefone: "554799159654", telefonesDoAssistente: assistente }), false);
  assertEquals(deveRegistrarEnvio({ desviadoPorTeste: false, telefone: MIGUEL, telefonesDoAssistente: [null, undefined] }), true);
});

Deno.test("quem mandou: o usuário do JWT manda sobre o corpo; chamada de sistema usa o corpo; não-uuid vira null", () => {
  const outro = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
  assertEquals(quemEnviou(outro, false, DONO), DONO);
  assertEquals(quemEnviou(outro, true, null), outro);
  assertEquals(quemEnviou("u1", true, null), null);
  assertEquals(quemEnviou(undefined, true, null), null);
  assertEquals(origemDoEnvio("assistente", false), "assistente");
  assertEquals(origemDoEnvio(undefined, false), "tela");
  assertEquals(origemDoEnvio("qualquer", true), "sistema");
});

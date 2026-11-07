// O envio do whatsapp-send entra na conversa (15/10/2026). Os casos são os de produção: em 07/10 o
// assistente mandou 3 mensagens ao Miguel (08:54, 13:45 e 14:58) e nenhuma ficou em
// whatsapp_messages — daí o "nada foi enviado" e o "esperando resposta" errado.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  deveRegistrarEnvio,
  ehOrigemDoRetorno,
  idDaSaidaDoRetorno,
  linhaDaMensagemEnviada,
  ORIGENS_DO_RETORNO,
  origemDoEnvio,
  quemEnviou,
  textoDoEnvio,
} from "./registro-do-envio.ts";

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

// ═══ Retorno F1 (16/11/2026): o recibo, a coleta e o adiamento do retorno saem pelo whatsapp-send
// com origem retorno_* e contexto "retorno:<id da saída>".

const SAIDA = "3f2b9c1e-7a4d-4e8b-9c0f-12ab34cd56ef";

Deno.test("origem do retorno: aceita só em chamada de sistema; com JWT de usuário vira tela", () => {
  assertEquals([...ORIGENS_DO_RETORNO], ["retorno_recibo", "retorno_coleta", "retorno_adiamento", "retorno_modelo"]);
  for (const o of ORIGENS_DO_RETORNO) {
    assertEquals(origemDoEnvio(o, true), o, o);
    assertEquals(origemDoEnvio(o, false), "tela", `${o} com JWT`);
    assertEquals(ehOrigemDoRetorno(o), true, o);
    // Cabe no esquema do whatsapp-send (origem ≤ 20 caracteres).
    assert(o.length <= 20, o);
  }
  // As de hoje não mudam, e nenhuma delas é do retorno.
  assertEquals(origemDoEnvio("sistema", true), "sistema");
  assertEquals(origemDoEnvio("assistente", true), "assistente");
  assertEquals(origemDoEnvio(undefined, true), "sistema");
  for (const o of ["assistente", "tela", "sistema", "retorno", "RETORNO_RECIBO", "retorno_outro", "", null, undefined, 1]) {
    assertEquals(ehOrigemDoRetorno(o), false, String(o));
  }
  // Origem do retorno com outra grafia não é do retorno: cai na regra de sempre.
  assertEquals(origemDoEnvio("Retorno_Recibo", true), "sistema");
});

Deno.test("via retorno só para as origens do retorno, com sent_by nulo; as outras seguem com via whatsapp-send", () => {
  const recibo = linhaDaMensagemEnviada(
    { kind: "text", message: "Oi, Lenine! Recebi sua mensagem." },
    MIGUEL,
    "3EB0RETORNO",
    DONO,
    "retorno_recibo",
    `retorno:${SAIDA}`,
    { client_id: CLIENTE, lead_id: null, supplier_id: null },
  );
  assertEquals(recibo.raw_payload, { origem: "retorno_recibo", contexto: `retorno:${SAIDA}`, via: "retorno" });
  assertEquals(recibo.sent_by, null, "o retorno não é ninguém da equipe, mesmo com sent_by no corpo");
  assertEquals([recibo.direction, recibo.client_id, recibo.wa_message_id], ["outbound", CLIENTE, "3EB0RETORNO"]);
  for (const o of ORIGENS_DO_RETORNO) {
    const l = linhaDaMensagemEnviada({ kind: "text", message: "x" }, MIGUEL, null, null, o, `retorno:${SAIDA}`);
    assertEquals(l.raw_payload.via, "retorno", o);
  }
  for (const o of ["assistente", "tela", "sistema"] as const) {
    const l = linhaDaMensagemEnviada({ kind: "text", message: "x" }, MIGUEL, null, DONO, o, null);
    assertEquals(l.raw_payload.via, "whatsapp-send", o);
    assertEquals(l.sent_by, DONO, o);
  }
});

Deno.test("idDaSaidaDoRetorno: contexto bom dá o id; sem prefixo, uuid curto ou outro formato dá null", () => {
  const contexto = `retorno:${SAIDA}`;
  assertEquals(idDaSaidaDoRetorno(contexto), SAIDA);
  // Cabe no esquema do whatsapp-send (context ≤ 64 caracteres).
  assert(contexto.length <= 64);
  assertEquals(idDaSaidaDoRetorno(SAIDA), null, "sem prefixo");
  assertEquals(idDaSaidaDoRetorno("retorno:3f2b9c1e-7a4d-4e8b-9c0f-12ab34cd56e"), null, "uuid curto");
  assertEquals(idDaSaidaDoRetorno(`retorno:${SAIDA}0`), null, "uuid comprido");
  assertEquals(idDaSaidaDoRetorno(`retorno:${SAIDA}:recibo`), null, "a dedupe_key não é contexto");
  assertEquals(idDaSaidaDoRetorno(` retorno:${SAIDA}`), null, "espaço antes");
  assertEquals(idDaSaidaDoRetorno(`Retorno:${SAIDA}`), null, "prefixo com maiúscula");
  assertEquals(idDaSaidaDoRetorno(`retorno:${SAIDA.toUpperCase()}`), null, "uuid em maiúsculas");
  assertEquals(idDaSaidaDoRetorno("retorno:------------------------------------"), null, "36 traços");
  assertEquals(idDaSaidaDoRetorno("retorno:3f2b9c1e7a4d4e8b9c0f12ab34cd56ef----"), null, "traços fora do lugar");
  assertEquals(idDaSaidaDoRetorno("retorno:"), null);
  assertEquals(idDaSaidaDoRetorno("comprovante"), null);
  assertEquals(idDaSaidaDoRetorno(undefined), null);
  assertEquals(idDaSaidaDoRetorno(null), null);
  assertEquals(idDaSaidaDoRetorno(42), null);
});

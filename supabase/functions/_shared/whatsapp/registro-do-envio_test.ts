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
  registrarEnvioDoOrcamento,
  textoDoEnvio,
  viaDoOrcamento,
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
  // F4 (P5.2): as duas origens do parceiro (o texto à MP e o aviso ao cliente final) entram no fim da lista.
  // F5 (P5.2): a do orçamento (cadência, "Fechado" e dados da nota) entra depois delas.
  assertEquals([...ORIGENS_DO_RETORNO], [
    "retorno_recibo",
    "retorno_coleta",
    "retorno_adiamento",
    "retorno_modelo",
    "retorno_parceiro",
    "retorno_aviso",
    "retorno_orcamento",
  ]);
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

Deno.test("F4: as origens do parceiro valem só em chamada de sistema e gravam via retorno, sem sent_by", () => {
  for (const o of ["retorno_parceiro", "retorno_aviso"] as const) {
    assertEquals(ehOrigemDoRetorno(o), true, o);
    assertEquals(origemDoEnvio(o, true), o, o);
    assertEquals(origemDoEnvio(o, false), "tela", `${o} com JWT`);
    const l = linhaDaMensagemEnviada({ kind: "text", message: "x" }, MIGUEL, null, DONO, o, `retorno:${SAIDA}`);
    assertEquals(l.raw_payload, { origem: o, contexto: `retorno:${SAIDA}`, via: "retorno" }, o);
    assertEquals(l.sent_by, null, o);
  }
  // Grafia diferente não é do retorno.
  for (const o of ["retorno_parceiros", "Retorno_Aviso", "parceiro"]) assertEquals(ehOrigemDoRetorno(o), false, o);
});

Deno.test("F5: retorno_orcamento é origem do retorno só em chamada de sistema; com JWT vira tela; grava via retorno, sem sent_by", () => {
  const o = "retorno_orcamento";
  assertEquals(ehOrigemDoRetorno(o), true);
  assertEquals(origemDoEnvio(o, true), o);
  assertEquals(origemDoEnvio(o, false), "tela");
  // Cabe no esquema do whatsapp-send (origem ≤ 20 caracteres).
  assertEquals(o.length, 17);
  const l = linhaDaMensagemEnviada({ kind: "text", message: "x" }, MIGUEL, null, DONO, o, `retorno:${SAIDA}`);
  assertEquals(l.raw_payload, { origem: o, contexto: `retorno:${SAIDA}`, via: "retorno" });
  assertEquals(l.sent_by, null);
  // Grafia diferente não é do retorno.
  for (const x of ["retorno_orcamentos", "Retorno_Orcamento", "orcamento", "retorno_orçamento"]) {
    assertEquals(ehOrigemDoRetorno(x), false, x);
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

// ─── Retorno F5 (P11.6): a via do envio de orçamento e o registro de todo envio (orcamento_registrar_envio) ──────────

Deno.test("F5 viaDoOrcamento: assistente, assistente pelo cartão, tela e o agendamento da tela (sistema)", () => {
  assertEquals(viaDoOrcamento("assistente", undefined), "assistente");
  assertEquals(viaDoOrcamento("assistente", "cartao"), "cartao");
  assertEquals(viaDoOrcamento("tela", undefined), "tela");
  // a marca do cartão só vale para o assistente: a tela que mandasse "cartao" continua tela
  assertEquals(viaDoOrcamento("tela", "cartao"), "tela");
  assertEquals(viaDoOrcamento("sistema", undefined), "tela");
  assertEquals(viaDoOrcamento("assistente", "outra"), "assistente");
});

function adminDoRegistro(resposta: { data?: unknown; error?: unknown; lanca?: boolean } = {}) {
  const rpcs: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const logs: Array<Record<string, unknown>> = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      if (fn === "log_app_error") {
        logs.push(args);
        return Promise.resolve({ data: null, error: null });
      }
      rpcs.push({ fn, args });
      if (resposta.lanca) return Promise.reject(new Error("rede"));
      return Promise.resolve({ data: resposta.data ?? { ok: true, ao_cliente: true, id: "e-1" }, error: resposta.error ?? null });
    },
  };
  return { admin, rpcs, logs };
}
const OS = "a1a1a1a1-3333-4e4e-8c8c-2c2c2c2c2c2c";

Deno.test("F5 registrarEnvioDoOrcamento: chama a função com a ordem, a via, os 8 últimos dígitos e se marcou", async () => {
  const a = adminDoRegistro();
  assertEquals(await registrarEnvioDoOrcamento(a.admin, { serviceOrderId: OS, via: "tela", telefone: "5547900009901", marcou: true, desviadoPorTeste: false }), "registrado");
  assertEquals(a.rpcs, [{ fn: "orcamento_registrar_envio", args: { p_os: OS, p_via: "tela", p_chave: "00009901", p_marcou: true } }]);
  // a outro número e no reenvio também (o banco decide se é ao cliente)
  const b = adminDoRegistro({ data: { ok: true, ao_cliente: false, id: "e-2" } });
  assertEquals(await registrarEnvioDoOrcamento(b.admin, { serviceOrderId: OS, via: "cartao", telefone: "5547900009955", marcou: false, desviadoPorTeste: false }), "registrado");
  assertEquals(b.rpcs[0].args.p_marcou, false);
});

Deno.test("F5 registrarEnvioDoOrcamento: no desvio do modo de teste nada é registrado", async () => {
  const a = adminDoRegistro();
  assertEquals(await registrarEnvioDoOrcamento(a.admin, { serviceOrderId: OS, via: "tela", telefone: "5547900009901", marcou: false, desviadoPorTeste: true }), "desviado");
  assertEquals(a.rpcs.length, 0);
});

Deno.test("F5 registrarEnvioDoOrcamento: erro ou exceção vão a log_app_error sem telefone, e nunca lança", async () => {
  for (const r of [{ error: { code: "57014", message: "tempo esgotado" } }, { lanca: true }, { data: { ok: false } }]) {
    const a = adminDoRegistro(r);
    assertEquals(await registrarEnvioDoOrcamento(a.admin, { serviceOrderId: OS, via: "assistente", telefone: "5547900009901", marcou: false, desviadoPorTeste: false }), "erro", JSON.stringify(r));
    assertEquals(a.logs.length, 1, JSON.stringify(r));
    assertEquals(a.logs[0].p_source, "edge");
    assertEquals(a.logs[0].p_context, "whatsapp-send");
    assertEquals(a.logs[0].p_action, "orcamento_registrar_envio");
    assert(!JSON.stringify(a.logs[0]).includes("9901"), "sem telefone no log");
    assertEquals((a.logs[0].p_details as Record<string, unknown>).service_order_id, OS);
  }
});

// A edge: o registro fica no bloco do orçamento, depois da marcação, e o deduplicado e o que falhou voltam antes dele.
const fonteDaEdge = () => Deno.readTextFile(new URL("../../whatsapp-send/index.ts", import.meta.url));

Deno.test("F5 whatsapp-send: a via e a chave junto do 'sent'; o registro em todo kind, depois da marcação e fora do desvio", async () => {
  const edge = await fonteDaEdge();
  assert(/orcamento_via:\s*z\.enum\(\["cartao"\]\)\.optional\(\)/.test(edge), "o campo orcamento_via no corpo");
  const bloco = edge.indexOf('if (body.context === "quote" && body.service_order_id)');
  assert(bloco > 0, "o bloco do orçamento");
  const marca = edge.indexOf('quote_status: "sent", orcamento_enviado_via: via, orcamento_enviado_chave: phoneClean.slice(-8)', bloco);
  assert(marca > bloco, "o update do 'sent' leva a via e a chave");
  const registro = edge.indexOf("registrarEnvioDoOrcamento(supabaseAdmin", bloco);
  assert(registro > marca, "o registro vem depois da marcação, no mesmo bloco");
  assert(edge.slice(registro - 200, registro).includes("desviadoPorTeste: foiDesviado") || edge.slice(registro, registro + 300).includes("desviadoPorTeste: foiDesviado"), "o desvio vai ao registro");
  assert(edge.slice(registro, registro + 300).includes("marcou"), "se marcou vai ao registro");
  // o deduplicado e o que falhou voltam antes do bloco: nada se registra, porque nada saiu nesta chamada
  const dedup = edge.indexOf("deduplicated: true");
  const falhou = edge.indexOf("502,");
  assert(dedup > 0 && dedup < bloco, "o deduplicado volta antes");
  assert(falhou > 0 && falhou < bloco, "o que falhou volta antes");
  // o bloco vale para os três kind: nenhuma condição de kind antes do registro
  assert(!/body\.kind\s*===?\s*["']document["']/.test(edge.slice(bloco, registro)), "o registro não depende do kind");
});

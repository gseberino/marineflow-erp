import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  campoObrigatorioFaltando,
  decidirMarcarEnviado,
  desviadoPorTeste,
  numeroDeTesteAtivo,
  urlDeDocumentoPermitida,
} from "./marcar-enviado.ts";

// Os casos reais que motivaram a regra (26/09/2026): o dono mandando o PDF para si, o modo de
// teste desviando tudo, OS cancelada e OS concluída recebendo "enviado".

const orcamento = { status: "draft", quote_status: "draft", converted_to_os_at: null };
const base = {
  context: "quote",
  serviceOrderId: "so-1",
  desviadoPorTeste: false,
  telefoneDestino: "5547999159654",
  telefonesDoCliente: ["47 99915-9654", null],
  ordem: orcamento,
};

Deno.test("marca quando o orçamento vai ao WhatsApp do cliente", () => {
  assertEquals(decidirMarcarEnviado(base).marcar, true);
  // Nono dígito diferente e número no 'phone' em vez do 'whatsapp': mesmo contato.
  assertEquals(decidirMarcarEnviado({ ...base, telefoneDestino: "554799159654", telefonesDoCliente: [null, "(47) 9915-9654"] }).marcar, true);
  assertEquals(decidirMarcarEnviado({ ...base, ordem: { ...orcamento, quote_status: "awaiting_approval" } }).marcar, true);
});

Deno.test("não marca quando o destino não é o cliente (o dono mandando para si)", () => {
  const r = decidirMarcarEnviado({ ...base, telefoneDestino: "5548988887777" });
  assertEquals(r.marcar, false);
  assertEquals(r.motivo, "o número de destino não é o do cliente da ordem");
});

Deno.test("cliente sem telefone cadastrado nunca marca", () => {
  assertEquals(decidirMarcarEnviado({ ...base, telefonesDoCliente: [null, undefined, ""] }).marcar, false);
});

Deno.test("modo de teste nunca marca, mesmo com o número do cliente", () => {
  assertEquals(decidirMarcarEnviado({ ...base, desviadoPorTeste: true }).marcar, false);
});

Deno.test("OS cancelada, concluída, convertida ou funil adiante não marcam", () => {
  for (const status of ["cancelled", "completed", "approved", "invoiced", "open"]) {
    assertEquals(decidirMarcarEnviado({ ...base, ordem: { ...orcamento, status } }).marcar, false, status);
  }
  assertEquals(decidirMarcarEnviado({ ...base, ordem: { ...orcamento, converted_to_os_at: "2026-09-01T00:00:00Z" } }).marcar, false);
  for (const qs of ["sent", "rejected", "awaiting_deposit", "approved", null]) {
    assertEquals(decidirMarcarEnviado({ ...base, ordem: { ...orcamento, quote_status: qs } }).marcar, false, String(qs));
  }
  assertEquals(decidirMarcarEnviado({ ...base, ordem: null }).marcar, false);
});

Deno.test("só envio de orçamento com ordem vinculada entra na regra", () => {
  assertEquals(decidirMarcarEnviado({ ...base, context: "service_order" }).marcar, false);
  assertEquals(decidirMarcarEnviado({ ...base, context: "agente_pdf_proprio" }).marcar, false);
  assertEquals(decidirMarcarEnviado({ ...base, serviceOrderId: null }).marcar, false);
});

const SB = "https://okurngvcodmljjicopdp.supabase.co";

Deno.test("documento: só URL do Storage deste projeto", () => {
  assertEquals(urlDeDocumentoPermitida(`${SB}/storage/v1/object/sign/pdf-agente/agente/2026/x.pdf?token=a`, SB), true);
  assertEquals(urlDeDocumentoPermitida(`${SB}/storage/v1/object/sign/fiscal-xml/nfe/1.pdf?token=a`, SB), true);
  assertEquals(urlDeDocumentoPermitida(`${SB}/storage/v1/object/public/documents/2026/x.pdf`, SB), true);
  // Rede interna, outro projeto, http, outro caminho do próprio projeto, lixo.
  assertEquals(urlDeDocumentoPermitida("http://localhost:8081/instance/fetchInstances", SB), false);
  assertEquals(urlDeDocumentoPermitida("http://192.168.0.10/relatorio.pdf", SB), false);
  assertEquals(urlDeDocumentoPermitida("https://zssewfqhmrlagqbfqsmb.supabase.co/storage/v1/object/public/documents/x.pdf", SB), false);
  assertEquals(urlDeDocumentoPermitida(`http://okurngvcodmljjicopdp.supabase.co/storage/v1/object/public/documents/x.pdf`, SB), false);
  assertEquals(urlDeDocumentoPermitida(`${SB}/rest/v1/clients?select=*`, SB), false);
  assertEquals(urlDeDocumentoPermitida(`${SB}.evil.com/storage/v1/object/public/documents/x.pdf`, SB), false);
  assertEquals(urlDeDocumentoPermitida("não é url", SB), false);
});

// ─── Modo de teste: a MESMA regra na edge e nas tools (conferência de 26/09/2026) ──────────
// A edge desvia só com o modo ligado E um número de teste. As tools olhavam só o interruptor:
// com o número vazio o PDF ia ao cliente, a tool dizia "foi para o TESTE" e a chave levava
// ":teste" — desligado o modo no mesmo dia, o cliente recebia o mesmo documento de novo.

Deno.test("modo de teste: desvia só com o modo ligado E um número", () => {
  assertEquals(numeroDeTesteAtivo({ wa_test_mode: "true", wa_test_number: "5547988887777" }), "5547988887777");
  assertEquals(desviadoPorTeste({ wa_test_mode: "true", wa_test_number: "5547988887777" }), true);
  // Desligado, com ou sem número: não desvia.
  assertEquals(desviadoPorTeste({ wa_test_mode: "false", wa_test_number: "5547988887777" }), false);
  assertEquals(desviadoPorTeste({ wa_test_number: "5547988887777" }), false);
  assertEquals(desviadoPorTeste({}), false);
});

Deno.test("modo ligado sem número: NÃO desvia (a mensagem vai ao destino de verdade)", () => {
  // Chave ausente (a edge), texto vazio (o ai-agent grava null como "") e null cru.
  for (const numero of [undefined, "", null]) {
    const settings = { wa_test_mode: "true", wa_test_number: numero };
    assertEquals(numeroDeTesteAtivo(settings), null, String(numero));
    assertEquals(desviadoPorTeste(settings), false, String(numero));
  }
  assertEquals(desviadoPorTeste({ zapi_test_mode: "true" }), false);
});

Deno.test("modo de teste: os nomes antigos zapi_* valem como reserva, e o número zapi só com dígitos", () => {
  assertEquals(numeroDeTesteAtivo({ zapi_test_mode: "true", zapi_test_number: "+55 (47) 98888-7777" }), "5547988887777");
  // O wa_* vence o zapi_* (é o que a tela grava hoje).
  assertEquals(numeroDeTesteAtivo({ wa_test_mode: "true", wa_test_number: "5511900000000", zapi_test_number: "5547988887777" }), "5511900000000");
  assertEquals(desviadoPorTeste({ wa_test_mode: "false", zapi_test_mode: "true", zapi_test_number: "5547988887777" }), false);
});

// ─── Campo obrigatório por tipo, conferido ANTES da reserva ───────────────────────────────
Deno.test("campo obrigatório: message no text, link_url+message no link, document_url no document", () => {
  assertEquals(campoObrigatorioFaltando({ kind: "text", message: "oi" }), null);
  assertEquals(campoObrigatorioFaltando({ kind: "text" }), "message é obrigatório para kind=text");
  assertEquals(campoObrigatorioFaltando({ kind: "text", message: "" }), "message é obrigatório para kind=text");

  assertEquals(campoObrigatorioFaltando({ kind: "link", message: "veja", link_url: "https://x.example/v/1" }), null);
  assertEquals(campoObrigatorioFaltando({ kind: "link", message: "veja" }), "link_url e message são obrigatórios para kind=link");
  assertEquals(campoObrigatorioFaltando({ kind: "link", link_url: "https://x.example/v/1" }), "link_url e message são obrigatórios para kind=link");

  assertEquals(campoObrigatorioFaltando({ kind: "document", document_url: "https://sb.example/a.pdf" }), null);
  // A legenda é opcional no documento; o arquivo não.
  assertEquals(campoObrigatorioFaltando({ kind: "document", message: "segue" }), "document_url é obrigatório para kind=document");
});

// ─── A edge e as tools usam estas funções, e na ordem certa ───────────────────────────────
const lerFonte = (relativo: string) => Deno.readTextFile(new URL(relativo, import.meta.url));

Deno.test("whatsapp-send: nenhum 400 depois de reservar a chave; campo obrigatório vem antes", async () => {
  const edge = await lerFonte("../../whatsapp-send/index.ts");
  const reserva = edge.indexOf("reservarEnvio(");
  const validacao = edge.indexOf("campoObrigatorioFaltando(body)");
  assert(reserva > 0, "a edge não reserva mais a chave? a guarda ficou cega");
  assert(validacao > 0, "a edge não chama campoObrigatorioFaltando");
  assert(validacao < reserva, "a checagem de campo obrigatório tem de vir ANTES da reserva da chave");
  // Um 400 depois da reserva prende a chave: o pedido corrigido ouviria "já enviado".
  const depoisDaReserva = edge.slice(reserva);
  assert(!/,\s*400\s*\)/.test(depoisDaReserva), "há um 400 depois de reservarEnvio: a chave ficaria presa");
});

Deno.test("modo de teste: a edge e as tools usam a mesma função, nenhuma lê o interruptor à mão", async () => {
  const edge = await lerFonte("../../whatsapp-send/index.ts");
  assertStringIncludes(edge, "numeroDeTesteAtivo(settingsMap)");
  assert(!/(wa|zapi)_test_(mode|number)/.test(edge), "a edge voltou a calcular o modo de teste à mão");
  for (const tool of ["../ai/tools/whatsapp.ts", "../ai/tools/documentos-pdf.ts"]) {
    const fonte = await lerFonte(tool);
    assertStringIncludes(fonte, "desviadoPorTeste(", tool);
    assert(!/settings(\.|\[["'])(wa|zapi)_test_mode/.test(fonte), `${tool} lê o interruptor do modo de teste à mão`);
  }
});

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decidirMarcarEnviado, urlDeDocumentoPermitida } from "./marcar-enviado.ts";

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

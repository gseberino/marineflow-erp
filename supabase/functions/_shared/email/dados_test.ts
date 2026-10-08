import { assertEquals } from "jsr:@std/assert@1";
import { extrairDados, resumoDosDados } from "./dados.ts";
import { dvChaveAcesso } from "./nfe-identify.ts";
import { mod10, mod11Barcode } from "./boleto.ts";
import type { InboundEmail } from "./types.ts";

/** Linha digitável de título (47 dígitos) com todos os DVs certos. */
function linhaValida(banco: string, fator: number, centavos: number): string {
  const livre = "1234567890123456789012345";
  const fv = String(fator).padStart(4, "0") + String(centavos).padStart(10, "0");
  const dvGeral = mod11Barcode(banco + "9" + fv + livre);
  const c1 = banco + "9" + livre.slice(0, 5);
  const c2 = livre.slice(5, 15);
  const c3 = livre.slice(15, 25);
  return c1 + mod10(c1) + c2 + mod10(c2) + c3 + mod10(c3) + dvGeral + fv;
}

const base43 = "42261011222333000181550010000081210000000001";
const CHAVE = base43.slice(0, 43) + dvChaveAcesso(base43.slice(0, 43));
const xml = (dest: string) => `<?xml version="1.0" encoding="UTF-8"?><nfeProc><NFe><infNFe versao="4.00" Id="NFe${CHAVE}">
<ide><serie>1</serie><nNF>812</nNF><dhEmi>2026-10-07T10:00:00-03:00</dhEmi><tpNF>1</tpNF></ide>
<emit><CNPJ>11222333000181</CNPJ><xNome>Coremma Pecas</xNome></emit><dest><CNPJ>${dest}</CNPJ></dest>
<total><ICMSTot><vNF>1234.56</vNF></ICMSTot></total></infNFe></NFe></nfeProc>`;

const email = (texto: string, anexos: InboundEmail["attachments"]): InboundEmail => ({
  messageId: "x@y", inReplyTo: null, references: [], from: { name: "Coremma", address: "vendas@coremma.com.br" },
  to: [], cc: [], subject: "Nota e boleto", text: texto, html: null, receivedAt: "2026-10-07T13:00:00.000Z",
  headers: {}, attachments: anexos, rawSize: null,
});

const reais = (n: number) => `R$ ${n.toFixed(2)}`;

Deno.test("NF-e anexa destinada à HBR + boleto no texto, conferidos por DV", async () => {
  const linha = linhaValida("341", 9999, 35000);
  const d = await extrairDados(
    email(`Segue o boleto: ${linha}`, [{ filename: "nfe.xml", mimeType: "application/xml", size: null, content: new TextEncoder().encode(xml("50057049000159")) }]),
    "50.057.049/0001-59", null,
  );
  assertEquals(d!.nfes.length, 1);
  assertEquals(d!.nfes[0].chave, CHAVE);
  assertEquals(d!.nfes[0].para_empresa, true);
  assertEquals(d!.nfes[0].valor, 1234.56);
  assertEquals(d!.boletos.length, 1);
  assertEquals(d!.boletos[0].valor, 350);
  assertEquals(resumoDosDados(d, reais)!.startsWith("NF-e 812 · R$ 1234.56 · boleto R$ 350.00"), true);
});

Deno.test("NF-e de outro destinatário fica marcada (não aparece para importar)", async () => {
  const d = await extrairDados(
    email("", [{ filename: "nfe.xml", mimeType: "text/xml", size: null, content: new TextEncoder().encode(xml("99888777000166")) }]),
    "50057049000159", null,
  );
  assertEquals(d!.nfes[0].para_empresa, false);
  assertEquals(resumoDosDados(d, reais), null);
});

Deno.test("boleto no PDF (leitor injetado); linha com DV errado é ignorada", async () => {
  const boa = linhaValida("001", 9999, 120000);
  const ruim = boa.slice(0, 10) + (boa[10] === "1" ? "2" : "1") + boa.slice(11);
  const d = await extrairDados(
    email(`linha errada ${ruim}`, [{ filename: "boleto.pdf", mimeType: "application/pdf", size: null, content: new Uint8Array([1, 2, 3]) }]),
    null, async () => `Pague até o vencimento ${boa}`,
  );
  assertEquals(d!.boletos.map((b) => [b.valor, b.origem]), [[1200, "pdf"]]);
});

Deno.test("sem nada a extrair: null", async () => {
  assertEquals(await extrairDados(email("só um oi", []), null, null), null);
});

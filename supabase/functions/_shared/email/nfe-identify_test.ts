import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  dvChaveAcesso, validarChaveAcesso, pareceNFe, ehEventoNFe,
  identificarNFe, ehParaEmpresa, resumoNFe,
} from "./nfe-identify.ts";

/** Monta uma chave de 44 dígitos com DV correto a partir dos 43 primeiros. */
function chaveValida(base43: string): string {
  const b = base43.padEnd(43, "0").slice(0, 43);
  return b + String(dvChaveAcesso(b));
}

const CHAVE = chaveValida("42260750057049000159550010000044710000000001");

const XML_NFE = `<?xml version="1.0" encoding="UTF-8"?>
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <NFe><infNFe versao="4.00" Id="NFe${CHAVE}">
    <ide><cUF>42</cUF><natOp>VENDA DE MERCADORIA</natOp><serie>1</serie>
      <nNF>4471</nNF><dhEmi>2026-07-20T14:32:10-03:00</dhEmi><tpNF>1</tpNF></ide>
    <emit><CNPJ>11222333000181</CNPJ><xNome>N&#225;utica Sul Distribuidora LTDA</xNome></emit>
    <dest><CNPJ>50057049000159</CNPJ><xNome>HBR MARINE SOLUTIONS</xNome></dest>
    <total><ICMSTot><vProd>1300.00</vProd><vDesc>65.44</vDesc><vNF>1234.56</vNF></ICMSTot></total>
  </infNFe></NFe>
</nfeProc>`;

const XML_EVENTO = `<procEventoNFe versao="1.00"><evento><infEvento>
  <chNFe>${CHAVE}</chNFe><tpEvento>110111</tpEvento></infEvento></evento></procEventoNFe>`;

Deno.test("dvChaveAcesso: resto 0 ou 1 vira DV 0 (regra SEFAZ)", () => {
  assertEquals(dvChaveAcesso("0".repeat(43)), 0);
});

Deno.test("validarChaveAcesso: aceita chave íntegra e rejeita adulterada", () => {
  assert(validarChaveAcesso(CHAVE));
  const adulterada = CHAVE.slice(0, 43) + String((Number(CHAVE[43]) + 1) % 10);
  assertEquals(validarChaveAcesso(adulterada), false);
});

Deno.test("validarChaveAcesso: tamanho errado não passa", () => {
  assertEquals(validarChaveAcesso("123"), false);
  assertEquals(validarChaveAcesso(CHAVE + "0"), false);
  assertEquals(validarChaveAcesso(""), false);
});

Deno.test("validarChaveAcesso: tolera máscara com separadores", () => {
  const mascarada = CHAVE.replace(/(\d{4})/g, "$1 ").trim();
  assert(validarChaveAcesso(mascarada));
});

Deno.test("pareceNFe / ehEventoNFe: distinguem nota de evento", () => {
  assert(pareceNFe(XML_NFE));
  assertEquals(ehEventoNFe(XML_NFE), false);
  assert(ehEventoNFe(XML_EVENTO));
  assertEquals(pareceNFe("<html><body>oi</body></html>"), false);
});

Deno.test("identificarNFe: extrai os campos da nota", () => {
  const n = identificarNFe(XML_NFE);
  assert(n !== null);
  assertEquals(n!.chave, CHAVE);
  assertEquals(n!.chaveValida, true);
  assertEquals(n!.emitenteCnpj, "11222333000181");
  assertEquals(n!.numero, "4471");
  assertEquals(n!.serie, "1");
  assertEquals(n!.dataEmissao, "2026-07-20");
  assertEquals(n!.valorTotal, 1234.56);
  assertEquals(n!.tipoOperacao, "1");
  assertEquals(n!.ehEvento, false);
});

Deno.test("identificarNFe: decodifica entidade XML no nome do emitente", () => {
  const n = identificarNFe(XML_NFE);
  assertEquals(n!.emitenteNome, "Náutica Sul Distribuidora LTDA");
});

Deno.test("identificarNFe: não confunde CNPJ do emitente com o do destinatário", () => {
  const n = identificarNFe(XML_NFE)!;
  assertEquals(n.emitenteCnpj, "11222333000181");
  assertEquals(n.destinatarioCnpj, "50057049000159");
});

Deno.test("identificarNFe: evento é reconhecido e marcado", () => {
  const n = identificarNFe(XML_EVENTO);
  assert(n !== null);
  assertEquals(n!.ehEvento, true);
  assertEquals(n!.chave, CHAVE);
});

Deno.test("identificarNFe: XML que não é NF-e devolve null", () => {
  assertEquals(identificarNFe("<pedido><item>1</item></pedido>"), null);
  assertEquals(identificarNFe(""), null);
});

Deno.test("ehParaEmpresa: só aceita quando o destinatário é a HBR", () => {
  const n = identificarNFe(XML_NFE)!;
  assert(ehParaEmpresa(n, "50.057.049/0001-59"), "deve tolerar máscara no CNPJ configurado");
  assertEquals(ehParaEmpresa(n, "11222333000181"), false, "nota de outro destinatário não entra");
  assertEquals(ehParaEmpresa(n, null), false);
});

Deno.test("resumoNFe: linha do digest, sem inventar dado ausente", () => {
  const n = identificarNFe(XML_NFE)!;
  const s = resumoNFe(n);
  assert(s.includes("Náutica Sul"));
  assert(s.includes("NF 4471"));
  assert(s.includes("1.234,56"));
  assert(!s.includes("⚠️"));
});

Deno.test("resumoNFe: chave inválida é sinalizada em vez de silenciada", () => {
  const n = identificarNFe(XML_NFE.replace(`Id="NFe${CHAVE}"`, `Id="NFe${"1".repeat(44)}"`))!;
  assertEquals(n.chaveValida, false);
  assert(resumoNFe(n).includes("⚠️"));
});

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

// ── Agenda de Produção, Fase 4 (P3): a saída, o frete, o lugar do emitente e os itens ─────────────────────
const CHAVE_KAMELL = chaveValida("32261011222333000144550010000510381000000001");
const det = (n: number, xProd: string, q = "1.0000", u = "UN", c = `C${n}`) =>
  `<det nItem="${n}"><prod><cProd>${c}</cProd><xProd>${xProd}</xProd><uCom>${u}</uCom><qCom>${q}</qCom><vProd>10.00</vProd></prod>` +
  `<imposto><ICMS><ICMS00><orig>0</orig></ICMS00></ICMS></imposto></det>`;
const XML_KAMELL = (dets: string, ide = "<dhEmi>2026-10-26T09:10:00-03:00</dhEmi><dhSaiEnt>2026-10-26T15:40:00-03:00</dhSaiEnt>") =>
  `<?xml version="1.0" encoding="UTF-8"?><nfeProc versao="4.00"><NFe><infNFe versao="4.00" Id="NFe${CHAVE_KAMELL}">
  <ide><serie>1</serie><nNF>51038</nNF>${ide}<tpNF>1</tpNF></ide>
  <emit><CNPJ>11222333000144</CNPJ><xNome>KAMELL COMERCIO GLOBAL LTDA</xNome>
    <enderEmit><xLgr>Rua A</xLgr><xMun>Vila Velha</xMun><UF>es</UF><CEP>29100000</CEP></enderEmit></emit>
  <dest><CNPJ>50057049000159</CNPJ><enderDest><xMun>Itajai</xMun><UF>SC</UF></enderDest></dest>
  ${dets}
  <total><ICMSTot><vNF>3054.44</vNF></ICMSTot></total>
  <transp><modFrete>0</modFrete><transporta><xNome>Transp X</xNome><UF>SC</UF></transporta></transp>
  </infNFe></NFe></nfeProc>`;

Deno.test("Fase 4: saída (dhSaiEnt), frete, UF e município do EMITENTE (não do destinatário nem da transportadora)", () => {
  const n = identificarNFe(XML_KAMELL(det(1, "CENTRAL DE CONTROLE CERBO GX VICTRON ENERGY")))!;
  assertEquals(n.dataEmissao, "2026-10-26");
  assertEquals(n.dataSaida, "2026-10-26");
  assertEquals(n.modFrete, "0");
  assertEquals(n.emitenteUf, "ES");
  assertEquals(n.emitenteMunicipio, "Vila Velha");
  assertEquals(n.itens, [{ n: 1, codigo: "C1", descricao: "CENTRAL DE CONTROLE CERBO GX VICTRON ENERGY", quantidade: 1, unidade: "UN" }]);
});

Deno.test("Fase 4: a saída noutro dia vence a emissão; dSaiEnt (layout antigo) também vale; sem saída = null", () => {
  const outra = identificarNFe(XML_KAMELL(det(1, "PECA"), "<dhEmi>2026-10-23T18:00:00-03:00</dhEmi><dhSaiEnt>2026-10-26T08:00:00-03:00</dhSaiEnt>"))!;
  assertEquals([outra.dataEmissao, outra.dataSaida], ["2026-10-23", "2026-10-26"]);
  const antiga = identificarNFe(XML_KAMELL(det(1, "PECA"), "<dEmi>2026-10-23</dEmi><dSaiEnt>2026-10-24</dSaiEnt>"))!;
  assertEquals([antiga.dataEmissao, antiga.dataSaida], ["2026-10-23", "2026-10-24"]);
  const sem = identificarNFe(XML_KAMELL(det(1, "PECA"), "<dhEmi>2026-10-29T10:00:00-03:00</dhEmi>"))!;
  assertEquals(sem.dataSaida, null);
});

Deno.test("Fase 4: modFrete 9 (sem transporte) e frete ausente; UF que não é sigla vira null", () => {
  const sem = identificarNFe(XML_KAMELL(det(1, "PECA")).replace("<modFrete>0</modFrete>", "<modFrete>9</modFrete>"))!;
  assertEquals(sem.modFrete, "9");
  const nada = identificarNFe(XML_KAMELL(det(1, "PECA")).replace(/<transp>[\s\S]*<\/transp>/, ""))!;
  assertEquals(nada.modFrete, null);
  const uf = identificarNFe(XML_KAMELL(det(1, "PECA")).replace("<UF>es</UF>", "<UF>Espirito Santo</UF>"))!;
  assertEquals(uf.emitenteUf, null);
});

Deno.test("Fase 4: até 40 itens, na ordem; descrição até 120; item sem descrição fica de fora", () => {
  const longa = "X".repeat(150);
  const dets = [det(1, longa), det(2, "  "), ...Array.from({ length: 43 }, (_, i) => det(i + 3, `ITEM ${i + 3}`, "2.5000", "PC"))].join("");
  const n = identificarNFe(XML_KAMELL(dets))!;
  assertEquals(n.itens.length, 40);
  assertEquals(n.itens[0].descricao.length, 120);
  assertEquals(n.itens[1], { n: 3, codigo: "C3", descricao: "ITEM 3", quantidade: 2.5, unidade: "PC" });
  assertEquals(n.itens[39].n, 41);
});

Deno.test("Fase 4: a nota de antes (sem itens nem endereço) e o evento: campos novos nulos, itens vazios", () => {
  const n = identificarNFe(XML_NFE)!;
  assertEquals([n.dataSaida, n.modFrete, n.emitenteUf, n.emitenteMunicipio], [null, null, null, null]);
  assertEquals(n.itens, []);
  assertEquals(identificarNFe(XML_EVENTO)!.itens, []);
});

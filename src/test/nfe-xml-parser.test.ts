import { describe, it, expect } from "vitest";
import { parseNfeReferenceXml } from "../lib/nfe-xml-parser";

// Estrutura mínima porém real do layout nacional da NF-e (modelo 55),
// inspirada na nota de referência real usada nesta sessão (HBR → Apolo).
const SAMPLE_XML = `<?xml version="1.0" encoding="UTF-8"?>
<nfeProc>
  <NFe>
    <infNFe Id="NFe42260550057049000159550010000001111138202600" versao="4.00">
      <ide>
        <cUF>42</cUF>
        <natOp>Venda de mercadoria adquirida ou recebida de terceiros</natOp>
        <nNF>111</nNF>
      </ide>
      <emit>
        <CNPJ>50057049000159</CNPJ>
        <xNome>HBR Marine Solutions LTDA</xNome>
      </emit>
      <dest>
        <CNPJ>17589800000192</CNPJ>
        <xNome>APOLO INDUSTRIA E COMERCIO DE VEICULOS DE RECREACAO LTDA</xNome>
        <enderDest>
          <xLgr>Rodovia 418</xLgr>
          <nro>12000</nro>
          <xBairro>Campestre</xBairro>
          <cMun>4204202</cMun>
          <xMun>Campo Alegre</xMun>
          <UF>SC</UF>
          <CEP>89294000</CEP>
        </enderDest>
        <email>compras@apolotrailer.com.br</email>
      </dest>
      <det nItem="1">
        <prod>
          <cProd>LP-28-C02PE-3</cProd>
          <xProd>TOMADA ENGATE RAPIDO MACHO E FEMEA 50A 500V 2 PINOS IP68</xProd>
          <NCM>85369090</NCM>
          <CFOP>5102</CFOP>
          <uCom>Un</uCom>
          <qCom>10.0000</qCom>
          <vUnCom>270.00</vUnCom>
          <vProd>2700.00</vProd>
        </prod>
      </det>
    </infNFe>
  </NFe>
</nfeProc>`;

describe("parseNfeReferenceXml", () => {
  it("retorna null para um arquivo que não é NF-e", () => {
    expect(parseNfeReferenceXml("<html><body>não é isso</body></html>")).toBeNull();
  });

  it("extrai o destinatário corretamente (não o emitente)", () => {
    const parsed = parseNfeReferenceXml(SAMPLE_XML);
    expect(parsed).not.toBeNull();
    expect(parsed!.recipient.name).toBe("APOLO INDUSTRIA E COMERCIO DE VEICULOS DE RECREACAO LTDA");
    expect(parsed!.recipient.document).toBe("17589800000192");
    expect(parsed!.recipient.email).toBe("compras@apolotrailer.com.br");
  });

  it("extrai o endereço do destinatário", () => {
    const { address } = parseNfeReferenceXml(SAMPLE_XML)!.recipient;
    expect(address.street).toBe("Rodovia 418");
    expect(address.number).toBe("12000");
    expect(address.district).toBe("Campestre");
    expect(address.cityName).toBe("Campo Alegre");
    expect(address.stateCode).toBe("SC");
    expect(address.postalCode).toBe("89294000");
  });

  it("extrai os itens com quantidade e valor unitário numéricos", () => {
    const { items } = parseNfeReferenceXml(SAMPLE_XML)!;
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      code: "LP-28-C02PE-3",
      name: "TOMADA ENGATE RAPIDO MACHO E FEMEA 50A 500V 2 PINOS IP68",
      ncm: "85369090",
      cfop: "5102",
      unit: "Un",
      quantity: 10,
      unitPrice: 270,
    });
  });

  it("não confunde CNPJ do emitente com o do destinatário", () => {
    const parsed = parseNfeReferenceXml(SAMPLE_XML)!;
    expect(parsed.recipient.document).not.toBe("50057049000159"); // CNPJ do emitente (HBR)
  });
});

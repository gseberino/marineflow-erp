import { describe, it, expect } from "vitest";
import { parseNfeReferenceXml, parseNfeSupplierNote } from "../lib/nfe-xml-parser";

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

// Nota de COMPRA (entrada) de um fornecedor, para a devolução ao fornecedor:
// aqui o <emit> é o fornecedor (vira destinatário da devolução) e o <dest>
// somos nós (HBR). Precisamos da chave, do emitente e da origem por item.
const SUPPLIER_XML = `<?xml version="1.0" encoding="UTF-8"?>
<nfeProc>
  <NFe>
    <infNFe Id="NFe35240612345678000199550010000000451123456789" versao="4.00">
      <ide><nNF>45</nNF></ide>
      <emit>
        <CNPJ>12345678000199</CNPJ>
        <xNome>FORNECEDOR NAUTICO LTDA</xNome>
        <IE>110042490114</IE>
        <enderEmit>
          <xLgr>Av. Industrial</xLgr>
          <nro>500</nro>
          <xBairro>Distrito</xBairro>
          <xMun>Sao Paulo</xMun>
          <UF>SP</UF>
          <CEP>04001000</CEP>
        </enderEmit>
      </emit>
      <dest>
        <CNPJ>50057049000159</CNPJ>
        <xNome>HBR Marine Solutions LTDA</xNome>
      </dest>
      <det nItem="1">
        <prod>
          <cProd>MOTOR-01</cProd>
          <xProd>MOTOR DE POPA 15HP</xProd>
          <NCM>84079010</NCM>
          <CFOP>6102</CFOP>
          <uCom>UN</uCom>
          <qCom>2.0000</qCom>
          <vUnCom>5000.00</vUnCom>
          <vProd>10000.00</vProd>
        </prod>
        <imposto><ICMS><ICMS00>
          <orig>0</orig><CST>00</CST><vICMS>1200.00</vICMS>
        </ICMS00></ICMS></imposto>
      </det>
      <det nItem="2">
        <prod>
          <cProd>HELICE-09</cProd>
          <xProd>HELICE INOX</xProd>
          <NCM>84879000</NCM>
          <CFOP>6102</CFOP>
          <uCom>UN</uCom>
          <qCom>4.0000</qCom>
          <vUnCom>250.00</vUnCom>
          <vProd>1000.00</vProd>
        </prod>
        <imposto><ICMS><ICMS00>
          <orig>2</orig><CST>00</CST>
        </ICMS00></ICMS></imposto>
      </det>
    </infNFe>
  </NFe>
</nfeProc>`;

describe("parseNfeSupplierNote", () => {
  it("retorna null quando não é uma NF-e", () => {
    expect(parseNfeSupplierNote("<html>nada</html>")).toBeNull();
  });

  it("retorna null quando não há chave de acesso de 44 dígitos", () => {
    const semChave = SUPPLIER_XML.replace(
      /Id="NFe35240612345678000199550010000000451123456789"/,
      'versao="4.00"',
    );
    expect(parseNfeSupplierNote(semChave)).toBeNull();
  });

  it("extrai a chave de acesso do atributo Id do infNFe", () => {
    const note = parseNfeSupplierNote(SUPPLIER_XML)!;
    expect(note.accessKey).toBe("35240612345678000199550010000000451123456789");
    expect(note.accessKey).toHaveLength(44);
  });

  it("usa o EMITENTE (fornecedor) como destinatário da devolução, não o dest", () => {
    const { issuer } = parseNfeSupplierNote(SUPPLIER_XML)!;
    expect(issuer.name).toBe("FORNECEDOR NAUTICO LTDA");
    expect(issuer.document).toBe("12345678000199");
    expect(issuer.document).not.toBe("50057049000159"); // não é o CNPJ da HBR (dest)
    expect(issuer.stateRegistration).toBe("110042490114");
  });

  it("extrai o endereço do emitente (enderEmit)", () => {
    const { address } = parseNfeSupplierNote(SUPPLIER_XML)!.issuer;
    expect(address.street).toBe("Av. Industrial");
    expect(address.number).toBe("500");
    expect(address.cityName).toBe("Sao Paulo");
    expect(address.stateCode).toBe("SP");
    expect(address.postalCode).toBe("04001000");
  });

  it("preserva quantidade, valor e origem EXATOS de cada item", () => {
    const { items } = parseNfeSupplierNote(SUPPLIER_XML)!;
    expect(items).toHaveLength(2);
    expect(items[0]).toMatchObject({
      code: "MOTOR-01", ncm: "84079010", quantity: 2, unitPrice: 5000, origin: 0,
    });
    expect(items[1]).toMatchObject({
      code: "HELICE-09", ncm: "84879000", quantity: 4, unitPrice: 250, origin: 2,
    });
  });
});

// Nota de compra REAL de fornecedor do regime normal: ICMS e IPI destacados,
// desconto por item e <ide> completo. Espelha o caso da devolução por garantia.
// As bases de ICMS e IPI são PROPOSITALMENTE diferentes: é o que prova que cada
// grupo é lido isoladamente (a tag <vBC> existe nos dois).
const SUPPLIER_XML_COM_IMPOSTOS = `<?xml version="1.0" encoding="UTF-8"?>
<nfeProc>
  <NFe>
    <infNFe Id="NFe35250912345678000199550010000404801123456789" versao="4.00">
      <ide>
        <natOp>VENDA DE MERCADORIA</natOp>
        <serie>1</serie>
        <nNF>40480</nNF>
        <dhEmi>2025-09-11T10:32:00-03:00</dhEmi>
      </ide>
      <emit>
        <CNPJ>12345678000199</CNPJ>
        <xNome>KAMELL DISTRIBUIDORA LTDA</xNome>
        <IE>110042490114</IE>
        <enderEmit>
          <xLgr>Rod. Industrial</xLgr><nro>1500</nro><xBairro>Centro</xBairro>
          <xMun>Curitiba</xMun><UF>PR</UF><CEP>80000000</CEP>
        </enderEmit>
      </emit>
      <det nItem="1">
        <prod>
          <cProd>7891234</cProd>
          <xProd>BOMBA DE COMBUSTIVEL</xProd>
          <NCM>84133090</NCM>
          <CFOP>6102</CFOP>
          <uCom>PC</uCom>
          <qCom>1.0000</qCom>
          <vUnCom>1699.2500</vUnCom>
          <vProd>1699.25</vProd>
          <vDesc>50.98</vDesc>
        </prod>
        <imposto>
          <ICMS><ICMS00>
            <orig>0</orig><CST>00</CST><modBC>3</modBC>
            <vBC>1648.27</vBC><pICMS>12.00</pICMS><vICMS>197.79</vICMS>
          </ICMS00></ICMS>
          <IPI>
            <cEnq>999</cEnq>
            <IPITrib><CST>50</CST><vBC>1699.25</vBC><pIPI>5.00</pIPI><vIPI>84.96</vIPI></IPITrib>
          </IPI>
        </imposto>
      </det>
      <det nItem="2">
        <prod>
          <cProd>FILTRO-22</cProd>
          <xProd>FILTRO DE OLEO</xProd>
          <NCM>84212300</NCM>
          <CFOP>6102</CFOP>
          <uCom>PC</uCom>
          <qCom>3.0000</qCom>
          <vUnCom>40.00</vUnCom>
          <vProd>120.00</vProd>
        </prod>
        <imposto>
          <ICMS><ICMS00>
            <orig>0</orig><CST>00</CST><vBC>120.00</vBC><pICMS>12.00</pICMS><vICMS>14.40</vICMS>
          </ICMS00></ICMS>
          <IPI><cEnq>999</cEnq><IPINT><CST>53</CST></IPINT></IPI>
        </imposto>
      </det>
    </infNFe>
  </NFe>
</nfeProc>`;

describe("parseNfeSupplierNote — impostos exatos p/ a devolução ao fornecedor", () => {
  it("lê número, série e data da nota de compra (sem deslocar o dia por fuso)", () => {
    const note = parseNfeSupplierNote(SUPPLIER_XML_COM_IMPOSTOS)!;
    expect(note.number).toBe("40480");
    expect(note.series).toBe("1");
    expect(note.issueDate).toBe("2025-09-11"); // dhEmi tem offset -03:00
  });

  it("extrai ICMS e IPI de grupos SEPARADOS (a tag vBC existe nos dois)", () => {
    const [item] = parseNfeSupplierNote(SUPPLIER_XML_COM_IMPOSTOS)!.items;
    expect(item.icmsBase).toBe(1648.27);
    expect(item.icmsRate).toBe(12);
    expect(item.icmsValue).toBe(197.79);
    expect(item.ipiBase).toBe(1699.25); // diferente da base de ICMS
    expect(item.ipiRate).toBe(5);
    expect(item.ipiValue).toBe(84.96);
  });

  it("extrai total e desconto do item", () => {
    const [item] = parseNfeSupplierNote(SUPPLIER_XML_COM_IMPOSTOS)!.items;
    expect(item.itemTotal).toBe(1699.25);
    expect(item.discount).toBe(50.98);
    expect(item.quantity).toBe(1);
    expect(item.unitPrice).toBe(1699.25);
  });

  it("item sem IPI tributado (IPINT) não inventa valor de IPI", () => {
    const [, item2] = parseNfeSupplierNote(SUPPLIER_XML_COM_IMPOSTOS)!.items;
    expect(item2.ipiValue).toBeUndefined();
    expect(item2.ipiRate).toBeUndefined();
    expect(item2.icmsValue).toBe(14.4); // mas o ICMS continua lido
    expect(item2.discount).toBeUndefined(); // sem desconto nesse item
  });

  it("não quebra em nota antiga sem os grupos de imposto", () => {
    const note = parseNfeSupplierNote(SUPPLIER_XML)!;
    expect(note.items[1].icmsValue).toBeUndefined();
    expect(note.items[0].icmsValue).toBe(1200);
    expect(note.number).toBe("45");
  });
});

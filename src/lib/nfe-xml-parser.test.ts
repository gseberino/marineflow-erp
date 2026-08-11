// Cobertura do parser de XML de NF-e — módulo sem teste até agora.
//
// Ele alimenta duas telas em que errar custa dinheiro de verdade:
//   · duplicar uma nota de venda para um novo rascunho de emissão;
//   · montar a DEVOLUÇÃO ao fornecedor, que precisa espelhar EXATAMENTE o que o fornecedor
//     destacou (base, alíquota e valor de ICMS e IPI, item a item) — se a devolução não bate
//     com a original, o crédito do fornecedor não fecha e a nota é rejeitada ou contestada.
//
// O parse é por expressão regular, não por parser de XML. Isso torna dois erros fáceis e
// invisíveis: ler a tag homônima do grupo errado (`vBC` existe no ICMS e no IPI) e devolver o
// dia anterior por conversão de fuso na data de emissão. Os dois têm caso próprio aqui.
import { describe, it, expect } from 'vitest';
import { parseNfeReferenceXml, parseNfeSupplierNote } from './nfe-xml-parser';

/** Item com ICMS e IPI destacados — os dois têm <vBC>, com valores diferentes de propósito. */
const DET_COM_IMPOSTOS = `
<det nItem="1">
  <prod>
    <cProd>DJ-63</cProd>
    <xProd>Disjuntor 63A Tripolar</xProd>
    <NCM>85362000</NCM>
    <CFOP>5102</CFOP>
    <uCom>UN</uCom>
    <qCom>2.0000</qCom>
    <vUnCom>400.0000</vUnCom>
    <vProd>800.00</vProd>
    <vDesc>50.00</vDesc>
  </prod>
  <imposto>
    <ICMS>
      <ICMS00>
        <orig>0</orig>
        <CST>00</CST>
        <vBC>750.00</vBC>
        <pICMS>12.00</pICMS>
        <vICMS>90.00</vICMS>
      </ICMS00>
    </ICMS>
    <IPI>
      <IPITrib>
        <vBC>800.00</vBC>
        <pIPI>5.00</pIPI>
        <vIPI>40.00</vIPI>
      </IPITrib>
    </IPI>
  </imposto>
</det>`;

const CHAVE = '42250912345678000199550010000012341234567890';

const NOTA_FORNECEDOR = `<?xml version="1.0" encoding="UTF-8"?>
<nfeProc versao="4.00">
  <NFe>
    <infNFe Id="NFe${CHAVE}" versao="4.00">
      <ide>
        <nNF>1234</nNF>
        <serie>1</serie>
        <dhEmi>2026-09-11T23:30:00-03:00</dhEmi>
      </ide>
      <emit>
        <CNPJ>12345678000199</CNPJ>
        <xNome>Fornecedor N&#225;utico &amp; Cia</xNome>
        <IE>255123456</IE>
        <enderEmit>
          <xLgr>Rua das Marinas</xLgr>
          <nro>1500</nro>
          <xCpl>Galp&#227;o 3</xCpl>
          <xBairro>Centro</xBairro>
          <xMun>Itaja&#237;</xMun>
          <UF>SC</UF>
          <CEP>88301000</CEP>
        </enderEmit>
      </emit>
      <dest>
        <CNPJ>99887766000155</CNPJ>
        <xNome>HBR Marine</xNome>
      </dest>
      ${DET_COM_IMPOSTOS}
    </infNFe>
  </NFe>
</nfeProc>`;

const NOTA_VENDA = `<?xml version="1.0" encoding="UTF-8"?>
<NFe>
  <infNFe Id="NFe${CHAVE}" versao="4.00">
    <dest>
      <CNPJ>11222333000144</CNPJ>
      <xNome>Charline Souza &amp; Filhos</xNome>
      <email>charline@exemplo.com</email>
      <enderDest>
        <xLgr>Av. Beira Mar</xLgr>
        <nro>200</nro>
        <xCpl>Apto 51</xCpl>
        <xBairro>Praia Brava</xBairro>
        <xMun>Itaja&#237;</xMun>
        <UF>SC</UF>
        <CEP>88306000</CEP>
      </enderDest>
    </dest>
    ${DET_COM_IMPOSTOS}
  </infNFe>
</NFe>`;

describe('parseNfeReferenceXml — duplicar uma nota de venda', () => {
  it('recusa arquivo que não é NF-e em vez de devolver estrutura vazia', () => {
    expect(parseNfeReferenceXml('')).toBeNull();
    expect(parseNfeReferenceXml('<html><body>oi</body></html>')).toBeNull();
    expect(parseNfeReferenceXml('{"json":true}')).toBeNull();
  });

  it('lê o destinatário e o endereço', () => {
    const r = parseNfeReferenceXml(NOTA_VENDA)!;
    expect(r.recipient.document).toBe('11222333000144');
    expect(r.recipient.email).toBe('charline@exemplo.com');
    expect(r.recipient.address).toEqual({
      street: 'Av. Beira Mar',
      number: '200',
      complement: 'Apto 51',
      district: 'Praia Brava',
      cityName: 'Itajaí',
      stateCode: 'SC',
      postalCode: '88306000',
    });
  });

  it('decodifica entidades — o cliente não se chama "Souza &amp; Filhos"', () => {
    expect(parseNfeReferenceXml(NOTA_VENDA)!.recipient.name).toBe('Charline Souza & Filhos');
  });

  it('aceita CPF quando o destinatário é pessoa física', () => {
    const pf = NOTA_VENDA.replace('<CNPJ>11222333000144</CNPJ>', '<CPF>12345678909</CPF>');
    expect(parseNfeReferenceXml(pf)!.recipient.document).toBe('12345678909');
  });

  it('lê os itens com quantidade e preço unitário', () => {
    const item = parseNfeReferenceXml(NOTA_VENDA)!.items[0];
    expect(item.code).toBe('DJ-63');
    expect(item.name).toBe('Disjuntor 63A Tripolar');
    expect(item.ncm).toBe('85362000');
    expect(item.cfop).toBe('5102');
    expect(item.unit).toBe('UN');
    expect(item.quantity).toBe(2);
    expect(item.unitPrice).toBe(400);
  });

  it('lê todos os itens quando há mais de um', () => {
    const doisItens = NOTA_VENDA.replace(
      DET_COM_IMPOSTOS,
      DET_COM_IMPOSTOS + DET_COM_IMPOSTOS.replace('DJ-63', 'CB-6').replace('Disjuntor 63A Tripolar', 'Cabo 6mm'),
    );
    const itens = parseNfeReferenceXml(doisItens)!.items;
    expect(itens).toHaveLength(2);
    expect(itens.map(i => i.code)).toEqual(['DJ-63', 'CB-6']);
  });

  it('nota sem itens devolve lista vazia, não null — o usuário completa na mão', () => {
    const semItens = NOTA_VENDA.replace(DET_COM_IMPOSTOS, '');
    const r = parseNfeReferenceXml(semItens);
    expect(r).not.toBeNull();
    expect(r!.items).toEqual([]);
  });

  it('campo ausente vira string vazia em vez de derrubar o import inteiro', () => {
    const semEmail = NOTA_VENDA.replace('<email>charline@exemplo.com</email>', '');
    expect(parseNfeReferenceXml(semEmail)!.recipient.email).toBe('');
  });
});

describe('parseNfeSupplierNote — devolução ao fornecedor', () => {
  it('recusa nota sem chave de acesso — devolução exige referência à original', () => {
    const semChave = NOTA_FORNECEDOR.replace(`Id="NFe${CHAVE}"`, 'Id="NFe123"');
    expect(parseNfeSupplierNote(semChave)).toBeNull();
    expect(parseNfeSupplierNote('<html>não é nota</html>')).toBeNull();
  });

  it('lê a chave do atributo Id do infNFe', () => {
    expect(parseNfeSupplierNote(NOTA_FORNECEDOR)!.accessKey).toBe(CHAVE);
  });

  it('cai para o <chNFe> do protocolo quando o Id não serve', () => {
    const comProt = NOTA_FORNECEDOR
      .replace(`Id="NFe${CHAVE}"`, 'Id="NFe"')
      .replace('</nfeProc>', `<protNFe><infProt><chNFe>${CHAVE}</chNFe></infProt></protNFe></nfeProc>`);
    expect(parseNfeSupplierNote(comProt)!.accessKey).toBe(CHAVE);
  });

  it('lê o EMITENTE (que vira destinatário da devolução), com IE', () => {
    const emit = parseNfeSupplierNote(NOTA_FORNECEDOR)!.issuer;
    expect(emit.name).toBe('Fornecedor Náutico & Cia');
    expect(emit.document).toBe('12345678000199');
    expect(emit.stateRegistration).toBe('255123456');
    expect(emit.address.cityName).toBe('Itajaí');
    expect(emit.address.complement).toBe('Galpão 3');
  });

  it('não confunde emitente com destinatário — são blocos distintos', () => {
    const nota = parseNfeSupplierNote(NOTA_FORNECEDOR)!;
    expect(nota.issuer.document).toBe('12345678000199');
    expect(nota.issuer.document).not.toBe('99887766000155'); // esse é o nosso CNPJ, o <dest>
  });

  it('lê número e série da nota', () => {
    const nota = parseNfeSupplierNote(NOTA_FORNECEDOR)!;
    expect(nota.number).toBe('1234');
    expect(nota.series).toBe('1');
  });

  it('a data de emissão é o dia do XML, sem deslocamento de fuso', () => {
    // dhEmi 23:30 com fuso -03:00 vira 11/09 02:30 UTC — um `new Date().toISOString()`
    // devolveria o dia SEGUINTE. O parser corta os 10 primeiros caracteres justamente por
    // isso, e este caso existe para que ninguém "melhore" o código convertendo para Date.
    expect(parseNfeSupplierNote(NOTA_FORNECEDOR)!.issueDate).toBe('2026-09-11');
  });

  it('aceita o dEmi do leiaute antigo', () => {
    const antigo = NOTA_FORNECEDOR.replace(
      '<dhEmi>2026-09-11T23:30:00-03:00</dhEmi>',
      '<dEmi>2026-09-11</dEmi>',
    );
    expect(parseNfeSupplierNote(antigo)!.issueDate).toBe('2026-09-11');
  });
});

describe('impostos por item — o que a devolução precisa espelhar', () => {
  const item = () => parseNfeSupplierNote(NOTA_FORNECEDOR)!.items[0];

  it('separa o vBC do ICMS do vBC do IPI — a tag tem o mesmo nome nos dois grupos', () => {
    // É o erro mais provável neste arquivo: ler `vBC` do <det> inteiro pega o primeiro que
    // aparecer (o do ICMS) e a base do IPI sai errada na devolução. Os valores do XML de
    // teste são diferentes de propósito para que a troca apareça.
    expect(item().icmsBase).toBe(750);
    expect(item().ipiBase).toBe(800);
    expect(item().icmsBase).not.toBe(item().ipiBase);
  });

  it('lê alíquota e valor de cada imposto', () => {
    expect(item().icmsRate).toBe(12);
    expect(item().icmsValue).toBe(90);
    expect(item().ipiRate).toBe(5);
    expect(item().ipiValue).toBe(40);
  });

  it('lê total e desconto do item', () => {
    expect(item().itemTotal).toBe(800);
    expect(item().discount).toBe(50);
  });

  it('lê a origem da mercadoria, que mora dentro do grupo ICMS e não do prod', () => {
    expect(item().origin).toBe(0);
    const importado = NOTA_FORNECEDOR.replace('<orig>0</orig>', '<orig>1</orig>');
    expect(parseNfeSupplierNote(importado)!.items[0].origin).toBe(1);
  });

  it('imposto ausente vira undefined, não zero — zero é uma afirmação, undefined é silêncio', () => {
    // Numa nota sem IPI destacado, gravar 0 diria "o fornecedor destacou IPI zero". Não é a
    // mesma coisa que "não havia IPI", e a devolução precisa da diferença.
    const semIpi = NOTA_FORNECEDOR.replace(/<IPI>[\s\S]*?<\/IPI>/, '');
    const i = parseNfeSupplierNote(semIpi)!.items[0];
    expect(i.ipiBase).toBeUndefined();
    expect(i.ipiRate).toBeUndefined();
    expect(i.ipiValue).toBeUndefined();
    expect(i.icmsValue).toBe(90); // e o ICMS continua lido
  });

  it('ICMS do Simples (CSOSN) também é lido — o grupo filho muda de nome, os valores não', () => {
    const simples = NOTA_FORNECEDOR
      .replace('<ICMS00>', '<ICMSSN101>')
      .replace('</ICMS00>', '</ICMSSN101>')
      .replace('<CST>00</CST>', '<CSOSN>101</CSOSN>');
    const i = parseNfeSupplierNote(simples)!.items[0];
    expect(i.icmsBase).toBe(750);
    expect(i.icmsValue).toBe(90);
    expect(i.origin).toBe(0);
  });
});

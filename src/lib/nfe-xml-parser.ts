// Parses a reference NF-e XML (modelo 55, layout nacional) to pre-fill the
// "Emitir NF-e" dialog — reuses the same regex tag-extraction approach as
// supabase/functions/process-nfe-xml (which parses <emit> for inbound stock
// entry); here we read <dest> + <det>/<prod> instead, to duplicate a
// previous outbound note into a new draft. Pure, client-side, no network —
// runs entirely in the browser via FileReader, nothing is persisted.

export interface ParsedNfeAddress {
  street: string;
  number: string;
  complement: string;
  district: string;
  cityName: string;
  stateCode: string;
  postalCode: string;
}

export interface ParsedNfeRecipient {
  name: string;
  document: string;
  email: string;
  address: ParsedNfeAddress;
}

export interface ParsedNfeItem {
  code: string;
  name: string;
  ncm: string;
  cfop: string;
  unit: string;
  quantity: number;
  unitPrice: number;
  // Origem da mercadoria (0=nacional, 1=estrangeira importação direta, 2=estrangeira
  // adquirida no mercado interno, …). Intrínseca ao produto — reaproveitada na
  // devolução ao fornecedor. Ausente no parse de venda (fica undefined).
  origin?: number;
}

export interface ParsedNfeReference {
  recipient: ParsedNfeRecipient;
  items: ParsedNfeItem[];
}

// O emitente (fornecedor) de uma NF-e de entrada — vira o DESTINATÁRIO na
// devolução ao fornecedor. Inclui a IE (o fornecedor é contribuinte do ICMS).
export interface ParsedNfeIssuer {
  name: string;
  document: string;
  stateRegistration: string;
  address: ParsedNfeAddress;
}

export interface ParsedNfeSupplierNote {
  accessKey: string;
  issuer: ParsedNfeIssuer;
  items: ParsedNfeItem[];
}

function tag(xml: string, name: string): string {
  const re = new RegExp(`<${name}[^>]*>([^<]*)<\\/${name}>`, "i");
  return xml.match(re)?.[1]?.trim() ?? "";
}

function tagAll(xml: string, name: string): string[] {
  const re = new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`, "gi");
  return [...xml.matchAll(re)].map((m) => m[1]);
}

/**
 * Parses a reference NF-e XML into recipient + item data ready to drop into
 * the emission form's state. Returns null when the file doesn't look like an
 * NF-e at all; otherwise returns best-effort data — missing fields come back
 * as empty strings/zeros so the user can complete them manually rather than
 * the whole import failing on one malformed tag.
 */
export function parseNfeReferenceXml(xmlText: string): ParsedNfeReference | null {
  if (!xmlText.includes("<infNFe") && !xmlText.includes("<NFe")) {
    return null;
  }

  const destBlock = xmlText.match(/<dest>([\s\S]*?)<\/dest>/i)?.[1] ?? "";
  const enderDest = destBlock.match(/<enderDest>([\s\S]*?)<\/enderDest>/i)?.[1] ?? "";

  const recipient: ParsedNfeRecipient = {
    name: tag(destBlock, "xNome"),
    document: tag(destBlock, "CNPJ") || tag(destBlock, "CPF"),
    email: tag(destBlock, "email"),
    address: {
      street: tag(enderDest, "xLgr"),
      number: tag(enderDest, "nro"),
      complement: tag(enderDest, "xCpl"),
      district: tag(enderDest, "xBairro"),
      cityName: tag(enderDest, "xMun"),
      stateCode: tag(enderDest, "UF"),
      postalCode: tag(enderDest, "CEP"),
    },
  };

  const items: ParsedNfeItem[] = tagAll(xmlText, "det").map(parseDetItem);

  return { recipient, items };
}

// Extrai um item de um bloco <det>. O <orig> mora no grupo <ICMS> (fora de
// <prod>), então é lido do det inteiro — o primeiro <orig> é o da origem ICMS.
function parseDetItem(det: string): ParsedNfeItem {
  const prod = det.match(/<prod>([\s\S]*?)<\/prod>/i)?.[1] ?? det;
  const origRaw = tag(det, "orig");
  return {
    code: tag(prod, "cProd"),
    name: tag(prod, "xProd"),
    ncm: tag(prod, "NCM"),
    cfop: tag(prod, "CFOP"),
    unit: tag(prod, "uCom"),
    quantity: parseFloat(tag(prod, "qCom") || "0") || 0,
    unitPrice: parseFloat(tag(prod, "vUnCom") || "0") || 0,
    origin: origRaw !== "" ? (parseInt(origRaw, 10) || 0) : undefined,
  };
}

/**
 * Parses an inbound supplier NF-e (a nota de compra importada) for a
 * devolução ao fornecedor: reads the ISSUER (<emit>) — who becomes the
 * recipient of our return note — the access key, and the item lines with
 * exact quantities/values/origin. Returns null when it doesn't look like an
 * NF-e or has no readable access key (a devolução exige referência à original).
 */
export function parseNfeSupplierNote(xmlText: string): ParsedNfeSupplierNote | null {
  if (!xmlText.includes("<infNFe") && !xmlText.includes("<NFe")) {
    return null;
  }

  // Chave de acesso: do atributo Id do <infNFe> (Id="NFe" + 44 dígitos); como
  // fallback, de um <chNFe> avulso (protNFe). Sem chave não há como referenciar.
  const accessKey =
    xmlText.match(/<infNFe[^>]*\bId="NFe(\d{44})"/i)?.[1] ??
    tag(xmlText, "chNFe").replace(/\D/g, "");
  if (accessKey.length !== 44) {
    return null;
  }

  const emitBlock = xmlText.match(/<emit>([\s\S]*?)<\/emit>/i)?.[1] ?? "";
  const enderEmit = emitBlock.match(/<enderEmit>([\s\S]*?)<\/enderEmit>/i)?.[1] ?? "";

  const issuer: ParsedNfeIssuer = {
    name: tag(emitBlock, "xNome"),
    document: tag(emitBlock, "CNPJ") || tag(emitBlock, "CPF"),
    stateRegistration: tag(emitBlock, "IE"),
    address: {
      street: tag(enderEmit, "xLgr"),
      number: tag(enderEmit, "nro"),
      complement: tag(enderEmit, "xCpl"),
      district: tag(enderEmit, "xBairro"),
      cityName: tag(enderEmit, "xMun"),
      stateCode: tag(enderEmit, "UF"),
      postalCode: tag(enderEmit, "CEP"),
    },
  };

  const items: ParsedNfeItem[] = tagAll(xmlText, "det").map(parseDetItem);

  return { accessKey, issuer, items };
}

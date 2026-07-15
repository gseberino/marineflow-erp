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
}

export interface ParsedNfeReference {
  recipient: ParsedNfeRecipient;
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

  const items: ParsedNfeItem[] = tagAll(xmlText, "det").map((det) => {
    const prod = det.match(/<prod>([\s\S]*?)<\/prod>/i)?.[1] ?? det;
    return {
      code: tag(prod, "cProd"),
      name: tag(prod, "xProd"),
      ncm: tag(prod, "NCM"),
      cfop: tag(prod, "CFOP"),
      unit: tag(prod, "uCom"),
      quantity: parseFloat(tag(prod, "qCom") || "0") || 0,
      unitPrice: parseFloat(tag(prod, "vUnCom") || "0") || 0,
    };
  });

  return { recipient, items };
}

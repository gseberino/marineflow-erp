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
  // Valores EXATOS da nota de compra. A devolução tem que espelhar o que o
  // fornecedor destacou, senão o crédito dele não fecha. Todos por item e
  // opcionais (o parse de uma nota de venda nossa não os usa).
  itemTotal?: number; // prod/vProd
  discount?: number; // prod/vDesc
  icmsBase?: number; // imposto/ICMS/*/vBC
  icmsRate?: number; // imposto/ICMS/*/pICMS
  icmsValue?: number; // imposto/ICMS/*/vICMS
  ipiBase?: number; // imposto/IPI/IPITrib/vBC
  ipiRate?: number; // imposto/IPI/IPITrib/pIPI
  ipiValue?: number; // imposto/IPI/IPITrib/vIPI
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
  // Identificação da nota de compra (grupo <ide>) — usada nos dados adicionais
  // da devolução ("Devolução Parcial Ref. Nº 40.480 de 11/09/2025").
  number: string; // ide/nNF
  series: string; // ide/serie
  issueDate: string; // ide/dhEmi (ou dEmi), normalizado em YYYY-MM-DD
}

/**
 * Decodifica entidades XML no texto lido.
 *
 * A leitura é por regex (sem parser), então as entidades chegam cruas: uma NF-e
 * real de fornecedor traz `ECRA TOUCH GX TOUCH 50 (5&amp;quot;)` — sem decodificar,
 * esse nome iria para a NF-e de DEVOLUÇÃO que emitimos à SEFAZ. Duas passadas no
 * máximo (há emissores que codificam em dobro) e `&amp;` sempre por ÚLTIMO em
 * cada passada, senão `&amp;lt;` viraria `<` indevidamente.
 */
function decodeEntities(s: string): string {
  const once = (t: string) =>
    t.replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">")
      .replace(/&quot;/gi, '"')
      .replace(/&apos;/gi, "'")
      .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
      .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
      .replace(/&amp;/gi, "&");
  const first = once(s);
  return /&(amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/i.test(first) ? once(first) : first;
}

function tag(xml: string, name: string): string {
  const re = new RegExp(`<${name}[^>]*>([^<]*)<\\/${name}>`, "i");
  const raw = xml.match(re)?.[1];
  return raw == null ? "" : decodeEntities(raw).trim();
}

// Recorta um grupo do XML (<ICMS>…</ICMS>, <IPI>…</IPI>) para ler as tags de
// dentro dele. Necessário porque nomes se repetem entre grupos: <vBC> existe
// tanto no ICMS quanto no IPI, e ler do <det> inteiro pegaria o primeiro.
function block(xml: string, name: string): string {
  const re = new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`, "i");
  return xml.match(re)?.[1] ?? "";
}

function num(xml: string, name: string): number | undefined {
  const raw = tag(xml, name);
  if (raw === "") return undefined;
  const v = parseFloat(raw);
  return Number.isFinite(v) ? v : undefined;
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
  // Os grupos são recortados antes de ler: ICMS e IPI têm tags homônimas (vBC).
  // O <ICMS> abriga um filho por CST/CSOSN (ICMS00, ICMS10, ICMSSN101…) — como
  // só nos interessam os valores, lemos direto do grupo inteiro.
  const icms = block(det, "ICMS");
  const ipi = block(det, "IPI");
  return {
    code: tag(prod, "cProd"),
    name: tag(prod, "xProd"),
    ncm: tag(prod, "NCM"),
    cfop: tag(prod, "CFOP"),
    unit: tag(prod, "uCom"),
    quantity: parseFloat(tag(prod, "qCom") || "0") || 0,
    unitPrice: parseFloat(tag(prod, "vUnCom") || "0") || 0,
    origin: origRaw !== "" ? (parseInt(origRaw, 10) || 0) : undefined,
    itemTotal: num(prod, "vProd"),
    discount: num(prod, "vDesc"),
    icmsBase: num(icms, "vBC"),
    icmsRate: num(icms, "pICMS"),
    icmsValue: num(icms, "vICMS"),
    ipiBase: num(ipi, "vBC"),
    ipiRate: num(ipi, "pIPI"),
    ipiValue: num(ipi, "vIPI"),
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

  // Identificação da nota de compra. dhEmi (leiaute 4.00) vem como
  // "2025-09-11T10:00:00-03:00"; dEmi (antigo) já é a data pura. Cortar os 10
  // primeiros caracteres evita converter para Date e cair no clássico
  // deslocamento de fuso que mostraria o dia anterior.
  const ide = block(xmlText, "ide");
  const issueDate = (tag(ide, "dhEmi") || tag(ide, "dEmi")).slice(0, 10);

  return {
    accessKey,
    issuer,
    items,
    number: tag(ide, "nNF"),
    series: tag(ide, "serie"),
    issueDate,
  };
}

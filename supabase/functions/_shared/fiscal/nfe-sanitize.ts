// Sanitização e validação de campos conforme o leiaute NF-e 4.00 (MOC 7.0).
// A SEFAZ rejeita por schema (facet maxLength / pattern) e por caracteres
// inválidos (espaços duplos, nas pontas, chars de controle). Este módulo é
// puro (sem fetch/Deno) — roda no Vitest e no edge fiscal-emit.

// Tamanhos máximos (em caracteres) dos campos que enviamos. Fonte: leiaute 4.00.
export const NFE_LIMITS = {
  recipientName: 60, // dest/xNome
  street: 60, // xLgr
  number: 60, // nro
  complement: 60, // xCpl
  district: 60, // xBairro
  cityName: 60, // xMun
  email: 60, // email
  itemCode: 60, // cProd
  itemName: 120, // xProd
  unit: 6, // uCom / uTrib
  additionalInfo: 5000, // infCpl
  purchaseOrder: 60, // compra/xPed (o xPed POR ITEM, det/prod, tem 15)
} as const;

// Limpa um texto para caber no XML da NF-e:
//  - remove caracteres de controle (C0 < 32 e C1 127–159) trocando por espaço
//    (feito por código do caractere para não usar literais de controle no fonte,
//     que o tooling de escrita corrompe)
//  - colapsa espaços consecutivos e apara as pontas (a SEFAZ rejeita espaço
//    duplo/nas pontas)
//  - trunca no tamanho máximo do campo
export function cleanText(value: string | null | undefined, max: number): string {
  const raw = (value ?? "").normalize("NFC");
  let s = "";
  for (const ch of raw) {
    const c = ch.codePointAt(0) ?? 32;
    s += (c < 32 || (c >= 127 && c <= 159)) ? " " : ch;
  }
  s = s.replace(/\s+/g, " ").trim();
  if (max > 0 && s.length > max) s = s.slice(0, max).trim();
  return s;
}

const GTIN_LENGTHS = new Set([8, 12, 13, 14]);

// cEAN/cEANTrib: obrigatório. GTIN válido (8/12/13/14 dígitos) ou o literal
// "SEM GTIN" (maiúsculas) quando o produto não tem código de barras.
// Sem isso a SEFAZ rejeita (883/889).
export function resolveGtin(barcode: string | null | undefined): string {
  const digits = (barcode ?? "").replace(/\D/g, "");
  return GTIN_LENGTHS.has(digits.length) ? digits : "SEM GTIN";
}

export function isValidNcm(ncm: string | null | undefined): boolean {
  const d = (ncm ?? "").replace(/\D/g, "");
  return d.length === 8; // NF-e de produto exige NCM completo (8 dígitos)
}

export function isValidCfop(cfop: string | null | undefined): boolean {
  return /^\d{4}$/.test((cfop ?? "").trim());
}

export function isValidCep(cep: string | null | undefined): boolean {
  return (cep ?? "").replace(/\D/g, "").length === 8;
}

// Arredonda para N casas decimais (qCom: 4; vUnCom: até 10). Evita ruído de
// ponto flutuante que gera divergência de totais (rejeições da família 5xx).
export function roundTo(n: number, decimals: number): number {
  if (!Number.isFinite(n)) return 0;
  const f = Math.pow(10, decimals);
  return Math.round(n * f) / f;
}

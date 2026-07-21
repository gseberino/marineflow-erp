// Informações complementares (infCpl) da NF-e para emitente do Simples Nacional.
//
// Regra fiscal por trás deste arquivo:
// - A declaração "DOCUMENTO EMITIDO POR ME OU EPP OPTANTE PELO SIMPLES NACIONAL"
//   é OBRIGATÓRIA (Resolução CGSN 140/2018, art. 60).
// - A frase que afirma o aproveitamento do crédito de ICMS só é válida com
//   **CSOSN 101** (tributada COM permissão de crédito) E os campos `pCredSN`
//   (alíquota) e `vCredICMSSN` (valor) preenchidos, e o texto precisa trazer o
//   VALOR em R$ e a ALÍQUOTA em % (art. 23 da LC 123/2006). Uma frase genérica
//   ("conforme a legislação") não transfere crédito nenhum.
// - Com **CSOSN 102** (tributada SEM permissão de crédito) essa frase é
//   CONTRADITÓRIA: o XML declara que não há crédito e o texto afirma o contrário.
//
// Versões antigas do sistema gravaram a frase inválida no infCpl. Como duplicar/
// reemitir uma nota reaproveita o texto da nota anterior, o erro se propagaria
// para notas novas — por isso a normalização abaixo.

export const SIMPLES_INFO_NOTE =
  'Documento emitido por ME ou EPP optante pelo Simples Nacional. ' +
  'Não gera direito a crédito fiscal de IPI.';

// Frase legada (e variações): termina na referência à LC 123/2006, que pode vir
// entre parênteses. O ponto de "art. 23" impede um corte ingênuo por sentença.
const LEGACY_ICMS_CREDIT_CLAIMS: RegExp[] = [
  /\s*Permite\s+o\s+aproveitamento\s+do\s+cr[ée]dito\s+de\s+ICMS[\s\S]*?123\s*\/\s*2006\s*\)?\s*\.?/gi,
  /\s*Permite\s+o\s+aproveitamento\s+do\s+cr[ée]dito\s+de\s+ICMS[^)]*\)\s*\.?/gi,
];

/** Remove a afirmação de crédito de ICMS inválida para CSOSN 102. */
export function stripInvalidIcmsCreditClaim(text: string): string {
  let out = String(text ?? '');
  for (const re of LEGACY_ICMS_CREDIT_CLAIMS) out = out.replace(re, '');
  return out.replace(/[ \t]{2,}/g, ' ').trim();
}

/**
 * Normaliza o infCpl ao reaproveitar/gerar uma nota: tira a frase de crédito de
 * ICMS inválida e garante a declaração obrigatória do Simples Nacional.
 * Preserva o texto livre do usuário (ordem de compra, comprador etc.).
 */
export function normalizeAdditionalInfo(text: string | null | undefined): string {
  const cleaned = stripInvalidIcmsCreditClaim(String(text ?? ''));
  if (!cleaned) return SIMPLES_INFO_NOTE;
  // Já traz a declaração obrigatória (em qualquer redação) → não duplicar.
  if (/optante\s+(pelo\s+)?Simples\s+Nacional/i.test(cleaned)) return cleaned;
  return `${cleaned} ${SIMPLES_INFO_NOTE}`;
}

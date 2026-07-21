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

// Declaração do Simples em QUALQUER redação já usada pelo sistema — a antiga
// ("optante DO Simples Nacional") e a atual ("ME ou EPP optante PELO Simples
// Nacional") —, com ou sem a frase do IPI logo em seguida.
//
// Removemos todas e reinserimos UMA vez na redação canônica. Só *detectar* a
// declaração não bastava: a variante antiga escapava do teste de presença e a
// declaração acabava ANEXADA, saindo duplicada na nota.
const SIMPLES_DECLARATIONS =
  /Documento\s+emitido\s+por\s+(?:ME\s+ou\s+EPP\s+)?optante\s+(?:pelo|pela|do|da|de)\s+Simples\s+Nacional\s*\.?\s*(?:N[ãa]o\s+gera\s+direito\s+a\s+cr[ée]dito\s+fiscal\s+de\s+IPI\s*\.?)?/gi;

/**
 * Normaliza o infCpl ao reaproveitar/gerar uma nota: tira a frase de crédito de
 * ICMS inválida, remove qualquer redação da declaração do Simples e devolve o
 * texto com a declaração obrigatória UMA única vez, ao final.
 * Preserva o texto livre do usuário (ordem de compra, comprador etc.).
 */
export function normalizeAdditionalInfo(text: string | null | undefined): string {
  const base = stripInvalidIcmsCreditClaim(String(text ?? ''))
    .replace(SIMPLES_DECLARATIONS, '')
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
  if (!base) return SIMPLES_INFO_NOTE;
  // Sem pontuação no fim do texto do usuário, a declaração colaria na frase dele.
  const separator = /[.;:!?]$/.test(base) ? ' ' : '. ';
  return `${base}${separator}${SIMPLES_INFO_NOTE}`;
}

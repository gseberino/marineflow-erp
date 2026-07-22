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
 * Separador entre os blocos do infCpl.
 *
 * ⚠️ NÃO usar "\n": o infCpl não aceita caracteres de formatação (CR/LF/TAB) —
 * quebra de linha literal é causa conhecida de Rejeição 215 (falha no schema) e
 * 588 (caractere de controle), e uma emissão rejeitada já consumiu o número
 * reservado (lacuna que exige inutilização de numeração). O "|" é o marcador
 * usual de fim de linha no infCpl. Este é o ÚNICO ponto a trocar caso a Contora
 * confirme que converte algum marcador em quebra real na DANFE.
 */
export const BLOCK_SEPARATOR = ' | ';

// Segmentos "Pedido de Compra: …" / "Comprador: …" que NÓS compomos — sempre no
// início do texto ou logo após um separador de blocos. A âncora (^|\|) evita
// engolir um "Comprador:" que o usuário tenha escrito no meio do texto dele.
const PURCHASE_SEGMENTS = /(?:^|\|)\s*(?:Pedido\s+de\s+Compra|Comprador)\s*:[^|]*/gi;

function tidy(text: string): string {
  return text
    // Chars de formatação viram espaço: o infCpl não os aceita (Rejeição
    // 215/588) e o servidor já os removeria no cleanText — se deixássemos passar
    // aqui, o espelho mostraria uma quebra que o XML não teria.
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/\s*\|\s*\|\s*/g, BLOCK_SEPARATOR) // separadores órfãos no meio
    .replace(/^\s*\|\s*/, '')
    .replace(/\s*\|\s*$/, '')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

/** Remove o bloco de pedido/comprador já composto (evita duplicá-lo ao recompor). */
export function stripPurchaseBlock(text: string | null | undefined): string {
  return tidy(String(text ?? '').replace(PURCHASE_SEGMENTS, ''));
}

/**
 * Devolve só o texto do USUÁRIO: sem a declaração do Simples e sem a frase
 * inválida de crédito de ICMS — os blocos que o sistema gerencia e reinsere.
 * É o que deve aparecer no campo editável da tela.
 */
export function stripManagedBlocks(text: string | null | undefined): string {
  return tidy(
    stripInvalidIcmsCreditClaim(String(text ?? '')).replace(SIMPLES_DECLARATIONS, ''),
  );
}

/**
 * Monta o infCpl na ordem fixa, por contrato:
 *   1) Pedido de Compra / Comprador   2) texto livre   3) declaração do Simples.
 * A declaração obrigatória fica SEMPRE por último, e os dados do cliente
 * sempre primeiro — sem depender de como o usuário digitou.
 */
export function composeAdditionalInfo(input: {
  purchaseOrder?: string | null;
  buyer?: string | null;
  freeText?: string | null;
}): string {
  const purchase = [
    input.purchaseOrder?.trim() ? `Pedido de Compra: ${input.purchaseOrder.trim()}` : '',
    input.buyer?.trim() ? `Comprador: ${input.buyer.trim()}` : '',
  ].filter(Boolean).join(' - ');

  const managed = stripManagedBlocks(input.freeText);
  // Só limpamos o bloco de pedido quando vamos reinseri-lo — assim um texto
  // livre legado que contenha "Comprador: ..." não é apagado à toa.
  const free = purchase ? stripPurchaseBlock(managed) : managed;

  return [purchase, free, SIMPLES_INFO_NOTE].filter(Boolean).join(BLOCK_SEPARATOR);
}

/**
 * Normaliza um infCpl existente (duplicar/reemitir, devoluções): tira a frase de
 * crédito de ICMS inválida, remove qualquer redação da declaração do Simples e
 * devolve o texto com a declaração obrigatória UMA única vez, ao final.
 * Preserva o texto livre do usuário.
 */
export function normalizeAdditionalInfo(text: string | null | undefined): string {
  return composeAdditionalInfo({ freeText: text });
}

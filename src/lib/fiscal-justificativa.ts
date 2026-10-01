/**
 * Cancelamento e Carta de Correção: o mínimo de texto que a SEFAZ exige e o prazo desde a
 * autorização. Extraído de FiscalEmission.tsx no D33 (01/10/2026).
 */

/** Mínimo de caracteres da justificativa (cancelamento e CC-e), o mesmo da SEFAZ. O backend confere de novo. */
export const MIN_JUSTIFICATION_LENGTH = 15;

/**
 * Há quanto tempo a nota foi autorizada, para o aviso do cancelamento (24 h sem ônus).
 * `null` sem hora de autorização. Os minutos saem da conta em minutos inteiros: o
 * arredondamento à parte mostrava "23h60min".
 */
export function tempoDesdeAAutorizacao(
  autorizadaEm: string | null | undefined,
  agora: number = Date.now(),
): { horas: number; dentroDoPrazo: boolean; texto: string } | null {
  if (!autorizadaEm) return null;
  const inicio = new Date(autorizadaEm).getTime();
  if (Number.isNaN(inicio)) return null;
  const horas = (agora - inicio) / 3_600_000;
  const minutos = Math.max(0, Math.floor(horas * 60));
  return {
    horas,
    dentroDoPrazo: horas <= 24,
    texto: `${Math.floor(minutos / 60)}h${minutos % 60}min`,
  };
}

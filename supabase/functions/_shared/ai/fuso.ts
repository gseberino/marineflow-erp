/**
 * Horário que o assistente manda sem fuso vira horário de Brasília.
 *
 * O prompt pede ISO com -03:00, mas é pedido, não trava: "2026-10-05T09:00:00" sem fuso o
 * Postgres lê como UTC, e o compromisso das 9h aparece às 6h na agenda, na via do técnico e nas
 * listas. Foi o mesmo defeito que o formulário da OS tinha (corrigido em 01/10/2026 com
 * src/lib/datetime-local.ts); aqui a trava fica no lado do assistente.
 *
 *  · com fuso (Z, +hh:mm, -hh:mm)   → não muda;
 *  · data e hora sem fuso            → acrescenta -03:00 (Brasília não tem horário de verão);
 *  · só a data ("2026-10-05")        → 08:00 de Brasília, o mesmo padrão da tela de agenda;
 *  · qualquer outra coisa            → não mexe (o banco recusa ou o tool reclama).
 */

const COM_FUSO = /(Z|[+-]\d{2}:?\d{2})$/i;
const DATA_E_HORA = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/;
const SO_DATA = /^\d{4}-\d{2}-\d{2}$/;

export function comFusoDeBrasilia(valor: unknown): unknown {
  if (typeof valor !== "string") return valor;
  const s = valor.trim();
  if (!s || COM_FUSO.test(s)) return valor;
  if (SO_DATA.test(s)) return `${s}T08:00:00-03:00`;
  if (DATA_E_HORA.test(s)) {
    const base = s.replace(" ", "T");
    return `${/T\d{2}:\d{2}$/.test(base) ? `${base}:00` : base}-03:00`;
  }
  return valor;
}

/** Os campos de horário que as ferramentas do assistente gravam. */
export const CAMPOS_DE_HORARIO = [
  "scheduled_start_at", "scheduled_end_at", "due_at", "snoozed_until",
  // 05/10/2026: mensagem agendada — "08:00" sem fuso saía às 05:00 em Brasília.
  "scheduled_at",
] as const;

/** Devolve os argumentos com cada campo de horário presente convertido. */
export function horariosDeBrasilia<T extends Record<string, unknown>>(args: T): T {
  const saida: Record<string, unknown> = { ...args };
  for (const campo of CAMPOS_DE_HORARIO) {
    if (campo in saida) saida[campo] = comFusoDeBrasilia(saida[campo]);
  }
  return saida as T;
}

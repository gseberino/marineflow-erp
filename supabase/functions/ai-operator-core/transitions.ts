// MarineFlow AI Operator — interpretação determinística do resultado de
// UPDATE filtrado por estado. Garante que respostas só sejam consideradas
// sucesso quando a transição realmente ocorreu.

export type PendingUpdateOutcome =
  | { ok: true }
  | { ok: false; status: 409; reason: "conflict" };

/**
 * UPDATE de approve/reject em ai_operator_pending_actions:
 * a leitura inicial garante existência (404 não é possível aqui).
 * Se nada foi alterado, é corrida ou estado já alterado → 409.
 */
export function interpretPendingUpdate(updatedRow: unknown): PendingUpdateOutcome {
  if (updatedRow) return { ok: true };
  return { ok: false, status: 409, reason: "conflict" };
}

export type MemoryUpdateOutcome =
  | { ok: true }
  | { ok: false; status: 404; reason: "not_found" }
  | { ok: false; status: 409; reason: "conflict"; existingStatus: string };

/**
 * UPDATE de verify/reject em ai_operator_memory_notes:
 *  - se atualizou linha → sucesso.
 *  - se não atualizou e a nota não existe → 404.
 *  - se não atualizou mas a nota existe em outro status → 409.
 */
export function interpretMemoryUpdate(
  updatedRow: unknown,
  existing: { verification_status: string } | null | undefined
): MemoryUpdateOutcome {
  if (updatedRow) return { ok: true };
  if (!existing) return { ok: false, status: 404, reason: "not_found" };
  return { ok: false, status: 409, reason: "conflict", existingStatus: existing.verification_status };
}

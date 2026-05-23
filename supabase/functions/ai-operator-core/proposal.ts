// MarineFlow AI Operator — resolução segura do draft_id em propose_action.
// Isolado para teste unitário pelo Vitest sem runtime Deno.

export type DraftLookup = (id: string) => Promise<{ id: string; session_id: string } | null>;

export type ProposalDraftResolution =
  | { ok: true; draftId: string | null }
  | { ok: false; reason: "foreign_draft"; requestedDraftId: string };

/**
 * Regras:
 *  - Se o modelo não passou draft_id mas existe um createdDraftId desta
 *    execução, usa o createdDraftId (já foi criado ligado à sessão atual).
 *  - Se o modelo passou draft_id igual ao createdDraftId, idem.
 *  - Se passou outro draft_id, exige que pertença a `currentSessionId`.
 *    Caso contrário, bloqueia (proposta recusada).
 *  - Se não passou nada e não há createdDraftId, devolve null (pending sem draft).
 */
export async function resolveProposalDraftId(opts: {
  requestedDraftId: string | null | undefined;
  createdDraftIdThisRun: string | null;
  currentSessionId: string;
  lookup: DraftLookup;
}): Promise<ProposalDraftResolution> {
  const { requestedDraftId, createdDraftIdThisRun, currentSessionId, lookup } = opts;
  const requested =
    typeof requestedDraftId === "string" && requestedDraftId.length > 0 ? requestedDraftId : null;

  if (!requested) {
    return { ok: true, draftId: createdDraftIdThisRun ?? null };
  }
  if (requested === createdDraftIdThisRun) {
    return { ok: true, draftId: createdDraftIdThisRun };
  }
  const row = await lookup(requested);
  if (!row || row.session_id !== currentSessionId) {
    return { ok: false, reason: "foreign_draft", requestedDraftId: requested };
  }
  return { ok: true, draftId: requested };
}

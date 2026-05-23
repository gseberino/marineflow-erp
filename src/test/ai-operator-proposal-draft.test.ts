import { describe, it, expect } from "vitest";
// @ts-ignore — Vitest resolve .ts.
import { resolveProposalDraftId } from "../../supabase/functions/ai-operator-core/proposal.ts";

const SESSION_A = "session-a";
const SESSION_B = "session-b";

function makeLookup(drafts: Record<string, { session_id: string }>) {
  return async (id: string) => (drafts[id] ? { id, session_id: drafts[id].session_id } : null);
}

describe("AI Operator — propose_action draft ownership", () => {
  it("sem draft requisitado e sem createdDraftId → pending sem draft (ok=true, null)", async () => {
    const r = await resolveProposalDraftId({
      requestedDraftId: null,
      createdDraftIdThisRun: null,
      currentSessionId: SESSION_A,
      lookup: makeLookup({}),
    });
    expect(r).toEqual({ ok: true, draftId: null });
  });

  it("sem draft requisitado mas existe createdDraftId → usa o criado", async () => {
    const r = await resolveProposalDraftId({
      requestedDraftId: undefined,
      createdDraftIdThisRun: "draft-just-created",
      currentSessionId: SESSION_A,
      lookup: makeLookup({}),
    });
    expect(r).toEqual({ ok: true, draftId: "draft-just-created" });
  });

  it("draft requisitado bate com createdDraftId desta execução → ok", async () => {
    const r = await resolveProposalDraftId({
      requestedDraftId: "draft-x",
      createdDraftIdThisRun: "draft-x",
      currentSessionId: SESSION_A,
      lookup: makeLookup({}),
    });
    expect(r).toEqual({ ok: true, draftId: "draft-x" });
  });

  it("draft requisitado pertence à mesma sessão → ok", async () => {
    const lookup = makeLookup({ "draft-same": { session_id: SESSION_A } });
    const r = await resolveProposalDraftId({
      requestedDraftId: "draft-same",
      createdDraftIdThisRun: null,
      currentSessionId: SESSION_A,
      lookup,
    });
    expect(r).toEqual({ ok: true, draftId: "draft-same" });
  });

  it("draft requisitado pertence a OUTRA sessão → BLOQUEIA", async () => {
    const lookup = makeLookup({ "draft-foreign": { session_id: SESSION_B } });
    const r = await resolveProposalDraftId({
      requestedDraftId: "draft-foreign",
      createdDraftIdThisRun: null,
      currentSessionId: SESSION_A,
      lookup,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.reason).toBe("foreign_draft");
      expect(r.requestedDraftId).toBe("draft-foreign");
    }
  });

  it("draft requisitado inexistente → BLOQUEIA (mesma reason de cross-session, fail-closed)", async () => {
    const r = await resolveProposalDraftId({
      requestedDraftId: "draft-ghost",
      createdDraftIdThisRun: null,
      currentSessionId: SESSION_A,
      lookup: makeLookup({}),
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe("foreign_draft");
  });

  it("draft requisitado diferente do createdDraftId mas mesma sessão → ok via lookup", async () => {
    const lookup = makeLookup({
      "draft-other-in-session": { session_id: SESSION_A },
    });
    const r = await resolveProposalDraftId({
      requestedDraftId: "draft-other-in-session",
      createdDraftIdThisRun: "draft-created-now",
      currentSessionId: SESSION_A,
      lookup,
    });
    expect(r).toEqual({ ok: true, draftId: "draft-other-in-session" });
  });

  it("string vazia em requestedDraftId é tratada como ausente", async () => {
    const r = await resolveProposalDraftId({
      requestedDraftId: "",
      createdDraftIdThisRun: "x",
      currentSessionId: SESSION_A,
      lookup: makeLookup({}),
    });
    expect(r).toEqual({ ok: true, draftId: "x" });
  });
});

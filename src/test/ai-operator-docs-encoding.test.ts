import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("AI Operator - documentation encoding", () => {
  it("does not contain known mojibake in macro cycle 1 consolidation docs", () => {
    const doc = readFileSync("docs/ai-operator/macro-cycle-1-functional-consolidation.md", "utf8");

    expect(doc).not.toContain("CÃ©lio");
    expect(doc).not.toContain("evoluÃ");
    expect(doc).not.toContain("confirmaÃ");
    expect(doc).not.toContain("NÃƒO");
  });

  it("documents the protected-state audit event used by update_draft", () => {
    const doc = readFileSync("docs/ai-operator/macro-cycle-1-functional-consolidation.md", "utf8");
    const core = readFileSync("supabase/functions/ai-operator-core/index.ts", "utf8");
    const policy = readFileSync("supabase/functions/ai-operator-core/entity-linking.ts", "utf8");

    expect(doc).toContain("model_draft_update_blocked_protected_state");
    expect(core).toContain('draftProtectedAuditEventForOperation("model_update_draft")');
    expect(policy).toContain("model_draft_update_blocked_protected_state");
  });

  it("documents the global protected-draft mutation gate", () => {
    const doc = readFileSync("docs/ai-operator/macro-cycle-1-functional-consolidation.md", "utf8");

    expect(doc).toContain("model_draft_item_blocked_protected_state");
    expect(doc).toContain("model_draft_question_blocked_protected_state");
    expect(doc).toContain("draft_entity_link_blocked_protected_state");
    expect(doc).toMatch(/add_draft_item.*ask_pending_question.*link_draft_entities/s);
  });
});

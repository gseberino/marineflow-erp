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

    expect(doc).toContain("model_draft_update_blocked_protected_state");
    expect(core).toContain("model_draft_update_blocked_protected_state");
  });
});

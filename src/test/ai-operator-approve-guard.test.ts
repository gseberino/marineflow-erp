import { describe, it, expect } from "vitest";
// @ts-ignore — Vitest resolve .ts.
import { preAuthorizeApprove } from "../../supabase/functions/ai-operator-core/approve-guard.ts";

describe("AI Operator — pre-authorize approve (early gate)", () => {
  it("admin pode ler a ação (pré-auth liberado)", () => {
    expect(preAuthorizeApprove("admin")).toEqual({ allowedToRead: true });
  });

  it("technician pode ler a ação (escopo restrito a memória, revalidado depois)", () => {
    expect(preAuthorizeApprove("technician")).toEqual({ allowedToRead: true });
  });

  it("seller, financial, other, external_seller, unknown → bloqueia sem ler", () => {
    for (const role of ["seller", "financial", "other", "external_seller", "unknown", ""]) {
      const r = preAuthorizeApprove(role);
      expect(r).toMatchObject({ allowedToRead: false, reason: "role" });
    }
  });

  it("null/undefined também são bloqueados (fail-closed)", () => {
    expect(preAuthorizeApprove(null)).toMatchObject({ allowedToRead: false });
    expect(preAuthorizeApprove(undefined)).toMatchObject({ allowedToRead: false });
  });
});

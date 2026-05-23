import { describe, it, expect } from "vitest";
// @ts-ignore — Vitest resolve .ts.
import { preAuthorizeApprove } from "../../supabase/functions/ai-operator-core/approve-guard.ts";

describe("AI Operator — pre-authorize approve (admin-only)", () => {
  it("admin pode ler a ação (pré-auth liberado)", () => {
    expect(preAuthorizeApprove("admin")).toEqual({ allowedToRead: true });
  });

  it("technician NÃO pode aprovar via approve_action — endpoints de memória são dedicados", () => {
    const r = preAuthorizeApprove("technician");
    expect(r).toMatchObject({ allowedToRead: false, reason: "role" });
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

  it("a mensagem de bloqueio uniforme protege existência da ação", () => {
    // Mesmo tipo de retorno (reason='role') tanto para technician quanto para
    // demais — o caller deve responder 403 genérico em todos os casos.
    const r1 = preAuthorizeApprove("technician");
    const r2 = preAuthorizeApprove("seller");
    expect(r1).toEqual(r2);
  });
});

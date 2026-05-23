import { describe, it, expect } from "vitest";
// @ts-ignore — Vitest resolve .ts.
import {
  interpretPendingUpdate,
  interpretMemoryUpdate,
} from "../../supabase/functions/ai-operator-core/transitions.ts";

describe("AI Operator — pending action transition (approve/reject)", () => {
  it("ok quando UPDATE retornou linha", () => {
    expect(interpretPendingUpdate({ id: "x", status: "approved" })).toEqual({ ok: true });
  });
  it("409 quando UPDATE não retornou linha (corrida ou já resolvido)", () => {
    expect(interpretPendingUpdate(null)).toEqual({ ok: false, status: 409, reason: "conflict" });
    expect(interpretPendingUpdate(undefined)).toEqual({
      ok: false,
      status: 409,
      reason: "conflict",
    });
  });
});

describe("AI Operator — memory verify/reject transition", () => {
  it("ok quando UPDATE retornou linha", () => {
    expect(
      interpretMemoryUpdate({ id: "m", verification_status: "verified" }, null)
    ).toEqual({ ok: true });
  });
  it("404 quando UPDATE não retornou linha e nota não existe", () => {
    const r = interpretMemoryUpdate(null, null);
    expect(r).toEqual({ ok: false, status: 404, reason: "not_found" });
  });
  it("409 quando UPDATE não retornou linha mas a nota existe em outro estado", () => {
    const r = interpretMemoryUpdate(null, { verification_status: "verified" });
    expect(r).toEqual({
      ok: false,
      status: 409,
      reason: "conflict",
      existingStatus: "verified",
    });
  });
  it("409 cobre também 'rejected' como estado existente", () => {
    const r = interpretMemoryUpdate(null, { verification_status: "rejected" });
    expect(r).toMatchObject({ ok: false, status: 409, reason: "conflict" });
    if (!r.ok && r.reason === "conflict") expect(r.existingStatus).toBe("rejected");
  });
  it("nunca retorna ok=true quando updatedRow é nulo", () => {
    const r1 = interpretMemoryUpdate(null, null);
    const r2 = interpretMemoryUpdate(null, { verification_status: "candidate" });
    expect(r1.ok).toBe(false);
    expect(r2.ok).toBe(false);
  });
});

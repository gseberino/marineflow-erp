import { describe, it, expect } from "vitest";
// @ts-ignore — Vitest resolve .ts.
import { resolveCoreChannel } from "../../supabase/functions/ai-operator-core/channel-source.ts";

describe("AI Operator — channel source (web core)", () => {
  it("sem channel no body → enforced=web, sem spoof", () => {
    const r = resolveCoreChannel(undefined);
    expect(r.enforced).toBe("web");
    expect(r.declared).toBeNull();
    expect(r.spoofAttempt).toBe(false);
  });

  it("body.channel = 'web' → enforced=web, sem spoof", () => {
    const r = resolveCoreChannel("web");
    expect(r.enforced).toBe("web");
    expect(r.declared).toBe("web");
    expect(r.spoofAttempt).toBe(false);
  });

  it("body.channel = 'whatsapp' → enforced=web e MARCA spoof", () => {
    const r = resolveCoreChannel("whatsapp");
    expect(r.enforced).toBe("web");
    expect(r.declared).toBe("whatsapp");
    expect(r.spoofAttempt).toBe(true);
  });

  it("body.channel = 'system' → enforced=web e MARCA spoof", () => {
    const r = resolveCoreChannel("system");
    expect(r.enforced).toBe("web");
    expect(r.declared).toBe("system");
    expect(r.spoofAttempt).toBe(true);
  });

  it("body.channel valor inesperado → enforced=web e MARCA spoof", () => {
    const r = resolveCoreChannel("evolution");
    expect(r.enforced).toBe("web");
    expect(r.declared).toBe("evolution");
    expect(r.spoofAttempt).toBe(true);
  });

  it("tipo não-string é tratado como ausente (sem spoof, sem declared)", () => {
    for (const bad of [null, 0, 42, true, false, {}, []]) {
      const r = resolveCoreChannel(bad);
      expect(r.enforced).toBe("web");
      expect(r.declared).toBeNull();
      expect(r.spoofAttempt).toBe(false);
    }
  });

  it("nunca retorna enforced != 'web'", () => {
    for (const v of ["web", "whatsapp", "system", "xyz", "", undefined, null]) {
      expect(resolveCoreChannel(v).enforced).toBe("web");
    }
  });
});

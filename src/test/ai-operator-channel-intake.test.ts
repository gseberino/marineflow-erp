import { describe, it, expect } from "vitest";
// @ts-ignore — Vitest resolve .ts.
import {
  safeEqual,
  validateIntakeAuth,
} from "../../supabase/functions/ai-operator-channel-intake/auth.ts";

describe("AI Operator — channel intake fail-closed", () => {
  describe("safeEqual", () => {
    it("compara strings iguais como true", () => {
      expect(safeEqual("abc123", "abc123")).toBe(true);
    });
    it("strings diferentes retornam false", () => {
      expect(safeEqual("abc", "def")).toBe(false);
      expect(safeEqual("abc", "abcd")).toBe(false);
    });
    it("strings vazias comparam como iguais (mas validateIntakeAuth bloqueia)", () => {
      expect(safeEqual("", "")).toBe(true);
    });
  });

  describe("validateIntakeAuth", () => {
    it("503 quando secret não configurada", () => {
      expect(validateIntakeAuth(undefined, "any-token")).toMatchObject({
        ok: false,
        status: 503,
      });
      expect(validateIntakeAuth("", "any-token")).toMatchObject({ ok: false, status: 503 });
      expect(validateIntakeAuth(null, "any-token")).toMatchObject({ ok: false, status: 503 });
      expect(validateIntakeAuth("   ", "any-token")).toMatchObject({ ok: false, status: 503 });
    });

    it("403 quando header ausente mesmo com secret configurada", () => {
      expect(validateIntakeAuth("the-secret", undefined)).toMatchObject({
        ok: false,
        status: 403,
      });
      expect(validateIntakeAuth("the-secret", "")).toMatchObject({ ok: false, status: 403 });
      expect(validateIntakeAuth("the-secret", "   ")).toMatchObject({
        ok: false,
        status: 403,
      });
    });

    it("403 quando token inválido", () => {
      expect(validateIntakeAuth("the-secret", "wrong")).toMatchObject({
        ok: false,
        status: 403,
      });
    });

    it("ok=true quando token bate exatamente", () => {
      expect(validateIntakeAuth("the-secret", "the-secret")).toMatchObject({ ok: true });
    });

    it("trim defensivo no header recebido", () => {
      expect(validateIntakeAuth("the-secret", "  the-secret  ")).toMatchObject({ ok: true });
    });

    it("NUNCA fail-open: undefined/undefined recusa", () => {
      expect(validateIntakeAuth(undefined, undefined)).toMatchObject({ ok: false });
      expect(validateIntakeAuth(undefined, undefined)).not.toMatchObject({ ok: true });
    });
  });
});

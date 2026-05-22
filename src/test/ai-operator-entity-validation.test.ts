import { describe, it, expect } from "vitest";
// @ts-ignore — Vite/Vitest resolve .ts.
import {
  validateEntityVisible,
  validateAllReferences,
  type SupabaseLike,
} from "../../supabase/functions/ai-operator-core/entity-validation.ts";

// Mock mínimo de supabase-js que satisfaz SupabaseLike.
function mockSb(responder: (table: string, id: string) => { data: any; error: any }): SupabaseLike {
  return {
    from(table: string) {
      return {
        select() {
          return {
            eq(_col: string, id: string) {
              return {
                async maybeSingle() {
                  return responder(table, id);
                },
              };
            },
          };
        },
      };
    },
  };
}

describe("AI Operator — entity reference validation", () => {
  it("ok quando a linha é visível pelo JWT do usuário", async () => {
    const sb = mockSb(() => ({ data: { id: "abc" }, error: null }));
    const r = await validateEntityVisible(sb, "client", "abc");
    expect(r.ok).toBe(true);
  });

  it("not_visible quando RLS oculta a linha (data null sem erro)", async () => {
    const sb = mockSb(() => ({ data: null, error: null }));
    const r = await validateEntityVisible(sb, "vessel", "hidden");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe("not_visible");
  });

  it("db_error é tratado como bloqueio (fail-closed)", async () => {
    const sb = mockSb(() => ({ data: null, error: { message: "boom" } }));
    const r = await validateEntityVisible(sb, "product", "xyz");
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe("db_error");
  });

  it("id ausente é bloqueado sem chamar o banco", async () => {
    let called = 0;
    const sb = mockSb(() => {
      called++;
      return { data: { id: "x" }, error: null };
    });
    const r1 = await validateEntityVisible(sb, "service", "");
    expect(r1.ok).toBe(false);
    expect(called).toBe(0);
  });

  it("kind desconhecido bloqueia", async () => {
    const sb = mockSb(() => ({ data: { id: "x" }, error: null }));
    // @ts-expect-error testando entrada inválida intencionalmente
    const r = await validateEntityVisible(sb, "spaceship", "abc");
    expect(r.ok).toBe(false);
  });

  it("validateAllReferences ignora chaves vazias/null", async () => {
    const sb = mockSb((table) => ({
      data: table === "clients" ? { id: "c1" } : null,
      error: null,
    }));
    const r = await validateAllReferences(sb, {
      client: "c1",
      vessel: undefined,
      product: "",
      service: null,
    } as any);
    expect(r.client?.ok).toBe(true);
    expect(r.vessel).toBeUndefined();
    expect(r.product).toBeUndefined();
    expect(r.service).toBeUndefined();
  });

  it("validateAllReferences distingue ref legítima de bloqueada", async () => {
    const sb = mockSb((table, id) => {
      // Apenas vessel "v1" visível; demais ocultas.
      if (table === "vessels" && id === "v1") return { data: { id: "v1" }, error: null };
      return { data: null, error: null };
    });
    const r = await validateAllReferences(sb, {
      client: "blocked-client",
      vessel: "v1",
      product: "blocked-product",
    });
    expect(r.client?.ok).toBe(false);
    expect(r.vessel?.ok).toBe(true);
    expect(r.product?.ok).toBe(false);
  });

  it("não vaza diferença entre inexistente e invisível (mesma reason)", async () => {
    const sb = mockSb(() => ({ data: null, error: null }));
    const r1 = await validateEntityVisible(sb, "client", "inexistente");
    const r2 = await validateEntityVisible(sb, "client", "invisivel-por-rls");
    expect(r1.ok).toBe(false);
    expect(r2.ok).toBe(false);
    if (!r1.ok && !r2.ok) expect(r1.reason).toBe(r2.reason);
  });
});

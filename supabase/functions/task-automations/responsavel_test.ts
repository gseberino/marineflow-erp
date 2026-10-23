// Quem recebe a tarefa (23/10/2026): 'financial' sem financeiro ativo cai no admin; erro de leitura
// lança (o motor registra a falha da regra em vez de criar tarefa sem dono).
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolveAssignee } from "./responsavel.ts";

const ADMIN = "ece63ee6-0000-4000-8000-000000000001";
const FINANCEIRO = "f1a00000-0000-4000-8000-000000000002";

/** app_users de mentira: devolve o 1º ativo do cargo pedido, e anota cada leitura. */
function bancoDeUsuarios(ativos: Record<string, string | undefined>, erro?: unknown) {
  const leituras: string[] = [];
  return {
    leituras,
    from(tabela: string) {
      if (tabela !== "app_users") throw new Error(`não devia ler ${tabela}`);
      const filtros: Record<string, unknown> = {};
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { filtros[c] = v; return q; },
        order: () => q,
        limit: () => q,
        maybeSingle: async () => {
          leituras.push(String(filtros.role));
          if (erro) return { data: null, error: erro };
          const id = filtros.active === true ? ativos[String(filtros.role)] : undefined;
          return { data: id ? { id } : null, error: null };
        },
      };
      return q;
    },
  };
}

Deno.test("resolveAssignee: com financeiro ativo, a cobrança vai para ele", async () => {
  const db = bancoDeUsuarios({ admin: ADMIN, financial: FINANCEIRO });
  assertEquals(await resolveAssignee(db, "financial", new Map()), FINANCEIRO);
  assertEquals(db.leituras, ["financial"]);
});

Deno.test("resolveAssignee: sem financeiro ativo, cai no admin", async () => {
  const db = bancoDeUsuarios({ admin: ADMIN });
  const cache = new Map<string, string | null>();
  assertEquals(await resolveAssignee(db, "financial", cache), ADMIN);
  // Uma leitura por cargo na rodada: a 2ª cobrança e a tarefa do admin vêm do cache.
  assertEquals(await resolveAssignee(db, "financial", cache), ADMIN);
  assertEquals(await resolveAssignee(db, "admin", cache), ADMIN);
  assertEquals(db.leituras, ["financial", "admin"]);
});

Deno.test("resolveAssignee: ninguém ativo em nenhum dos dois → sem responsável", async () => {
  assertEquals(await resolveAssignee(bancoDeUsuarios({}), "financial", new Map()), null);
  assertEquals(await resolveAssignee(bancoDeUsuarios({}), "admin", new Map()), null);
});

Deno.test("resolveAssignee: erro de leitura lança (não vira tarefa sem dono) e não fica no cache", async () => {
  const cache = new Map<string, string | null>();
  await assertRejects(() => resolveAssignee(bancoDeUsuarios({}, { code: "57014", message: "timeout" }), "financial", cache));
  assertEquals(cache.has("financial"), false);
  // Sem financeiro e com o admin falhando: também lança.
  const db = {
    from: () => {
      let role = "";
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, order: () => q, limit: () => q,
        eq: (c: string, v: unknown) => { if (c === "role") role = String(v); return q; },
        maybeSingle: async () => role === "admin" ? { data: null, error: { message: "timeout" } } : { data: null, error: null },
      };
      return q;
    },
  };
  await assertRejects(() => resolveAssignee(db, "financial", new Map()));
});

Deno.test("resolveAssignee: uuid passa direto e null fica null, sem ler o banco", async () => {
  const db = bancoDeUsuarios({ admin: ADMIN });
  assertEquals(await resolveAssignee(db, "1b2c3d4e-0000-4000-8000-000000000003", new Map()), "1b2c3d4e-0000-4000-8000-000000000003");
  assertEquals(await resolveAssignee(db, null, new Map()), null);
  assertEquals(db.leituras, []);
});

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fechamentoTools, mesAnterior, mesDosArgs } from "./fechamento.ts";

Deno.test("mês pedido: sem ano, o mais recente que já aconteceu", () => {
  const jan = new Date(2027, 0, 15);
  assertEquals(mesAnterior(jan), { ano: 2026, mes: 12 });
  assertEquals(mesDosArgs({ mes: 12 }, jan), { ano: 2026, mes: 12 });   // "fecha dezembro" em janeiro
  assertEquals(mesDosArgs({ mes: 1 }, jan), { ano: 2027, mes: 1 });
  assertEquals(mesDosArgs({}, new Date(2026, 8, 25)), { ano: 2026, mes: 8 }); // sem mês = mês passado
  assertEquals(mesDosArgs({ mes: 8, ano: 2025 }, jan), { ano: 2025, mes: 8 });
});

Deno.test("fechar o mês: só admin, sempre com confirmação, motivo vai junto", async () => {
  const t = fechamentoTools.find((x) => x.name === "fechar_mes")!;
  assertEquals(t.risk, "high");
  assertEquals(t.roles, ["admin"]);
  let chamada: any = null;
  const ctx = {
    sb: { rpc: (nome: string, a: unknown) => { chamada = { nome, a }; return Promise.resolve({ data: { ok: true }, error: null }); } },
    admin: {}, userId: "u", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {},
  };
  await t.execute({ mes: 8, ano: 2026, motivo: "conferido com o contador" }, ctx as never);
  assertEquals(chamada, { nome: "fechar_mes", a: { p_ano: 2026, p_mes: 8, p_motivo: "conferido com o contador", p_autor: "u" } });
});

Deno.test("financeiro não fecha mês pelo assistente", async () => {
  const t = fechamentoTools.find((x) => x.name === "fechar_mes")!;
  const ctx = { sb: {}, admin: {}, userId: "u", userRole: "technician" as const, jwt: "", appOrigin: "", settings: {} };
  const r = await t.execute({ mes: 8 }, ctx as never) as { error?: string };
  assertEquals(typeof r.error, "string");
});

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { financeRulesTools } from "./finance-rules.ts";

/* Aprovar pelo assistente com a escolha "casar com o já lançado" — a linha que pode já estar
   lançada é recusada pelo servidor sem essa escolha, então ela tem de chegar inteira. */

const tool = (nome: string) => financeRulesTools.find((t) => t.name === nome)!;

Deno.test("aprovar leva a escolha de vínculo por proposta ao servidor", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  let corpo: any = null;
  globalThis.fetch = ((_url: string, init?: RequestInit) => {
    corpo = JSON.parse(String(init?.body ?? "{}"));
    return Promise.resolve(new Response(JSON.stringify({ ok: true, aprovadas: 2 }), { status: 200 }));
  }) as typeof fetch;
  try {
    const ctx = { sb: {}, admin: {}, userId: "u", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {} };
    await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p84", "p75"], vinculos: { p84: "pg84", p75: "nenhum" } }, ctx as never);
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(corpo, {
    action: "approve", ids: ["p84", "p75"],
    overrides: { p84: { vinculo: { id: "pg84" } }, p75: { vinculo: "nenhum" } },
  });
});

Deno.test("cadastrar a partir do extrato pede confirmação e só para o financeiro", () => {
  const t = tool("cadastrar_contraparte_do_extrato");
  assertEquals(t.risk, "medium");
  assertEquals(t.roles, ["admin", "financial"]);
});

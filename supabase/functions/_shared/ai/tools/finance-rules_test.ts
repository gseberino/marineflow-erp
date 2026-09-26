import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { financeRulesTools, resolverFornecedorDito } from "./finance-rules.ts";

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

/* Fornecedor dito pelo usuário (decisão do dono de 26/09/2026: nome diferente só por escolha
   dele). Um banco falso com a tabela de fornecedores, lida em páginas. */
function sbComFornecedores(lista: Array<{ id: string; name: string; trade_name?: string | null; cnpj_cpf?: string | null }>) {
  const linhas = lista.map((f) => ({ trade_name: null, cnpj_cpf: null, ...f }));
  const b: any = {
    select: () => b, order: () => b, eq: () => b,
    range: (de: number, ate: number) => Promise.resolve({ data: linhas.slice(de, ate + 1), error: null }),
    maybeSingle: () => Promise.resolve({ data: null, error: null }),
  };
  return { from: () => b };
}

Deno.test("fornecedor dito com acento acha o cadastro sem acento", async () => {
  const ctx = { sb: sbComFornecedores([{ id: "k1", name: "KAMELL COMERCIO GLOBAL LTDA", cnpj_cpf: "11.111.111/0001-11" }]) };
  assertEquals(await resolverFornecedorDito(ctx as never, "Kamell Comércio Global"), { id: "k1", nome: "KAMELL COMERCIO GLOBAL LTDA" });
});

Deno.test("matriz e filial com o mesmo nome são um cadastro só (a matriz)", async () => {
  const ctx = { sb: sbComFornecedores([
    { id: "filial", name: "Coremma Ltda", cnpj_cpf: "83.109.504/0006-86" },
    { id: "matriz", name: "COREMMA LTDA", cnpj_cpf: "83.109.504/0001-71" },
  ]) };
  assertEquals(await resolverFornecedorDito(ctx as never, "Coremma"), { id: "matriz", nome: "COREMMA LTDA" });
});

Deno.test("duas empresas com o mesmo nome viram pergunta, com id e CNPJ", async () => {
  const ctx = { sb: sbComFornecedores([
    { id: "a", name: "TIM S.A.", cnpj_cpf: "02.421.421/0001-11" },
    { id: "b", name: "TIM SA", cnpj_cpf: "99.999.999/0001-99" },
  ]) };
  const r = await resolverFornecedorDito(ctx as never, "Tim") as any;
  assertEquals(typeof r.error, "string");
  assertEquals(r.opcoes.map((o: any) => o.id).sort(), ["a", "b"]);
});

Deno.test("nome parcial nunca é escolhido calado: vira pergunta", async () => {
  const ctx = { sb: sbComFornecedores([{ id: "f", name: "FERNANDO NUNES FACHINI EPP" }]) };
  const r = await resolverFornecedorDito(ctx as never, "Fernando") as any;
  assertEquals(typeof r.error, "string");
  assertEquals(r.opcoes[0].id, "f");
});

Deno.test("aprovar leva as respostas de OS e OC, e recusa número no lugar do id", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  let corpo: any = null;
  globalThis.fetch = ((_url: string, init?: RequestInit) => {
    corpo = JSON.parse(String(init?.body ?? "{}"));
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }));
  }) as typeof fetch;
  const os = "11111111-1111-1111-1111-111111111111";
  const oc = "22222222-2222-2222-2222-222222222222";
  try {
    const ctx = { sb: {}, admin: {}, userId: "u", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {} };
    await tool("aprovar_propostas_de_lancamento").execute({ ids: ["p1", "p2"], os: { p1: os, p2: "nenhuma" }, oc: { p1: oc } }, ctx as never);
    const errado = await tool("aprovar_propostas_de_lancamento").execute({ ids: ["p1"], oc: { p1: "OC-0003" } }, ctx as never) as any;
    assertEquals(typeof errado.error, "string");
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(corpo.overrides, { p1: { serviceOrderId: os, purchaseOrderId: oc }, p2: { serviceOrderId: null } });
});

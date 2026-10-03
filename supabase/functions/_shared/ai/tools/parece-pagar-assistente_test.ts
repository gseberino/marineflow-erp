// "Parece pagar" pelo assistente (forma A, F4 — 03/10/2026): a lista de propostas diz o que a
// entrada parece pagar, com as aplicações prontas para aplicar_pix_em_contas, e a aprovação recusa
// "receita nova" sem a pergunta respondida — a mesma trava da tela do Extrato.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { financeRulesTools } from "./finance-rules.ts";

const ENTRADA = {
  id: "pMP", kind: "create_receivable", title: "Receita: MP MOTORHOMES", bank_transaction_id: "tMP",
  suggested_client_id: "cMP", suggested_amount: 1670, suggested_date: "2026-10-10",
  suggested_category: "Serviços prestados", confidence: 80, evidencia: null, vinculo_sugerido: null,
  suggested_service_order_id: null, suggested_purchase_order_id: null,
};

/** Banco de mentira: devolve as linhas da tabela, sem olhar os filtros; guarda o que foi pedido. */
function bancoFalso(tabelas: Record<string, unknown[]>, falham: string[] = []) {
  const pedidos: string[] = [];
  return {
    pedidos,
    from(tabela: string) {
      pedidos.push(tabela);
      // deno-lint-ignore no-explicit-any
      const q: any = {};
      for (const m of ["select", "eq", "neq", "in", "is", "not", "gte", "lte", "order", "limit", "range"]) q[m] = () => q;
      // deno-lint-ignore no-explicit-any
      q.then = (ok: any, erro: any) => Promise.resolve(
        falham.includes(tabela) ? { data: null, error: { message: `falha em ${tabela}` } } : { data: tabelas[tabela] ?? [], error: null },
      ).then(ok, erro);
      return q;
    },
  };
}

const contasDaMP = [
  { id: "r45", client_id: "cMP", description: "OS OS-00045", due_date: "2026-07-22", amount: 1650, paid_amount: 0, service_orders: { service_order_number: "OS-00045" } },
  { id: "r46", client_id: "cMP", description: "OS OS-00046", due_date: "2026-07-22", amount: 520, paid_amount: 500, service_orders: { service_order_number: "OS-00046" } },
];

const ctx = (sb: unknown) => ({ sb, admin: sb, userId: "u", userRole: "admin", jwt: "jwt", appOrigin: "", settings: {} }) as never;
const ferramenta = (nome: string) =>
  // deno-lint-ignore no-explicit-any
  financeRulesTools.find((t) => t.name === nome) as any;

Deno.test("listar_propostas: a entrada traz o que parece pagar, pronto para aplicar_pix_em_contas", async () => {
  const sb = bancoFalso({ finance_review_queue: [ENTRADA], receivables: contasDaMP, payments: [] });
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctx(sb));
  const p = r.propostas[0];
  assertEquals(p.bank_transaction_id, "tMP");
  assertEquals(p.parece_pagar.perguntar_antes_de_aprovar, true);
  assertEquals(p.parece_pagar.aplicacoes, [
    { receivable_id: "r45", valor: 1650 },
    { receivable_id: "r46", valor: 20 },
  ]);
  assert(/OS-00045/.test(p.parece_pagar.frase) && /OS-00046/.test(p.parece_pagar.frase));
});

Deno.test("listar_propostas: sem conseguir ler as contas, falha — não diz que não paga nada", async () => {
  const sb = bancoFalso({ finance_review_queue: [ENTRADA], payments: [] }, ["receivables"]);
  let erro = "";
  try { await ferramenta("listar_propostas_de_lancamento").execute({}, ctx(sb)); } catch (e) { erro = (e as Error).message; }
  assert(/contas em aberto/.test(erro), erro);
});

Deno.test("aprovar: entrada que parece pagar contas existentes é recusada sem resposta", async () => {
  const sb = bancoFalso({ finance_review_queue: [ENTRADA], receivables: contasDaMP, payments: [] });
  const original = globalThis.fetch;
  let chamou = false;
  globalThis.fetch = (() => { chamou = true; return Promise.resolve(new Response("{}")); }) as typeof fetch;
  try {
    const r = await ferramenta("aprovar_propostas_de_lancamento").execute({ ids: ["pMP"] }, ctx(sb));
    assert(/parecem pagar contas que já existem/.test(r.error), JSON.stringify(r));
    assertEquals(r.entradas[0].bank_transaction_id, "tMP");
    assertEquals(chamou, false);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("aprovar: com 'nenhum' (é receita nova), segue para a aprovação sem reler as contas", async () => {
  const sb = bancoFalso({ finance_review_queue: [ENTRADA], receivables: contasDaMP, payments: [] });
  const original = globalThis.fetch;
  let corpo: Record<string, unknown> | null = null;
  globalThis.fetch = ((_u: unknown, init?: RequestInit) => {
    corpo = JSON.parse(String(init?.body ?? "{}"));
    return Promise.resolve(new Response(JSON.stringify({ ok: true })));
  }) as typeof fetch;
  try {
    const r = await ferramenta("aprovar_propostas_de_lancamento").execute({ ids: ["pMP"], vinculos: { pMP: "nenhum" } }, ctx(sb));
    assertEquals(r, { ok: true });
    assertEquals((corpo as unknown as { overrides: Record<string, unknown> }).overrides, { pMP: { vinculo: "nenhum" } });
    assertEquals(sb.pedidos.includes("receivables"), false);
  } finally {
    globalThis.fetch = original;
  }
});

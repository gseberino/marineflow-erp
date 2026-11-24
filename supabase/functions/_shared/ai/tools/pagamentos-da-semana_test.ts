// Pagamentos da semana pelo assistente (24/11/2026): list_payables_due devolve a MESMA ordem da mensagem da manhã
// (pagamentos_da_semana), com saldo, soma e falta; e definir_prioridade_de_pagamento grava o grupo do fornecedor.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { financialTools } from "./financial.ts";
import type { ToolCtx } from "./registry.ts";

type Qualquer = Record<string, any>;

const CONTAS = [
  { id: "kamell", description: "NF 123 parcela 2", amount: 1433.6, balance_amount: 1433.6, due_date: "2026-11-05", status: "pending", supplier_name: "KAMELL", expense_category: "Compras de mercadorias", notes: null },
  { id: "socio", description: "Pago por Gustavo: diárias — João", amount: 250, balance_amount: 250, due_date: "2026-10-09", status: "pending", supplier_name: null, expense_category: "Diárias de freelancers", notes: "Reembolso ao sócio — pago do bolso para João." },
  { id: "unifique", description: "Boleto Unifique 12345678901", amount: 117.18, balance_amount: 117.18, due_date: "2026-11-20", status: "pending", supplier_name: "Unifique", expense_category: null, notes: null },
];

const FILA = {
  hoje: "2026-11-24", ate: "2026-12-01", saldo_no_banco: 1476.13, saldo_em: "2026-11-23T21:34:00+00:00",
  contas: [
    { id: "unifique", nome: "Unifique", valor: 117.18, vencimento: "2026-11-20", vencida: true, grupo: 2, a_definir: false, categoria: null, boleto_linha: "00190000090123456789012345678901234567890123456" },
    { id: "kamell", nome: "KAMELL", valor: 1433.6, vencimento: "2026-11-05", vencida: true, grupo: 3, a_definir: true, categoria: "Compras de mercadorias", boleto_linha: null },
  ],
  soma: 1550.78, vencido: { n: 2, total: 1550.78 }, reembolsos: { n: 1, total: 250 },
};

function ctxDe(rpc: (fn: string, args: Qualquer) => { data: unknown; error: unknown }, cargo = "admin") {
  const chamadas: Array<{ fn: string; args: Qualquer }> = [];
  const consulta: Qualquer = {
    select: () => consulta, not: () => consulta, lte: () => consulta, order: () => consulta,
    limit: () => Promise.resolve({ data: CONTAS.map((c) => ({ ...c })), error: null }),
  };
  const admin = {
    from: () => consulta,
    rpc: (fn: string, args: Qualquer) => { chamadas.push({ fn, args }); return Promise.resolve(rpc(fn, args)); },
  };
  return { ctx: { admin, sb: admin, userId: "dono-1", userRole: cargo } as unknown as ToolCtx, chamadas };
}

const tool = (nome: string) => financialTools.find((t) => t.name === nome)!;

Deno.test("list_payables_due: vem na ordem da fila, com prioridade, boleto, saldo, soma e falta; o reembolso ao sócio fica fora da fila", async () => {
  const { ctx, chamadas } = ctxDe(() => ({ data: FILA, error: null }));
  const r = await tool("list_payables_due").execute({}, ctx) as Qualquer;
  assertEquals(r.results.map((x: Qualquer) => x.id), ["unifique", "kamell", "socio"]);
  assertEquals(r.results[0].prioridade, "2 — serviço que corta");
  assertEquals(r.results[0].boleto, "00190000090123456789012345678901234567890123456");
  assertEquals(r.results[0].description, "Boleto Unifique ***.456.789-**"); // CPF continua mascarado
  assertEquals(r.results[1].prioridade, "3 — fornecedor com boleto (palpite: o dono ainda não disse o grupo deste fornecedor)");
  assertEquals("boleto" in r.results[1], false);
  assertEquals(r.results[2].prioridade, "fora da fila: a empresa deve ao sócio (pago do bolso)");
  assertEquals("notes" in r.results[2] || "_reembolso" in r.results[2], false);
  assertEquals([r.saldo_no_banco, r.soma_da_fila, r.falta_no_banco, r.reembolsos_a_socio], [1476.13, 1550.78, 74.65, { n: 1, total: 250 }]);
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].fn, "pagamentos_da_semana");
  assertEquals(/^\d{4}-\d{2}-\d{2}$/.test(chamadas[0].args.p_ate), true);
});

Deno.test("list_payables_due: saldo que cobre dá falta zero; função ainda não publicada devolve a lista de antes", async () => {
  const cobre = await tool("list_payables_due").execute({}, ctxDe(() => ({ data: { ...FILA, saldo_no_banco: 9000 }, error: null })).ctx) as Qualquer;
  assertEquals(cobre.falta_no_banco, 0);

  const antes = await tool("list_payables_due").execute({}, ctxDe(() => ({ data: null, error: { code: "PGRST202", message: "sem função" } })).ctx) as Qualquer;
  assertEquals(antes.results.map((x: Qualquer) => x.id), ["kamell", "socio", "unifique"]);
  assertEquals(Object.keys(antes), ["results"]);
  assertEquals("notes" in antes.results[1] || "_reembolso" in antes.results[1], false);
});

Deno.test("list_payables_due: erro de leitura da fila aparece (não vira lista sem ordem calada); técnico não lê", async () => {
  await assertRejects(
    () => tool("list_payables_due").execute({}, ctxDe(() => ({ data: null, error: { code: "57014", message: "timeout" } })).ctx) as Promise<unknown>,
    Error, "Não consegui ler a ordem de pagamento",
  );
  const tecnico = await tool("list_payables_due").execute({}, ctxDe(() => ({ data: FILA, error: null }), "technician").ctx) as Qualquer;
  assertEquals(typeof tecnico.error, "string");
});

Deno.test("definir_prioridade_de_pagamento: chama a função do banco com a conta, o grupo e quem pediu; erro do banco volta em português", async () => {
  const t = tool("definir_prioridade_de_pagamento");
  assertEquals(t.risk, "medium"); // pede o "sim" do dono
  const { ctx, chamadas } = ctxDe(() => ({ data: { ok: true, fornecedor: "Unifique", grupo: 2, contas_em_aberto: 1 }, error: null }));
  assertEquals(await t.execute({ payable_id: "unifique", grupo: 2 }, ctx), { ok: true, fornecedor: "Unifique", grupo: 2, contas_em_aberto: 1 });
  assertEquals(chamadas, [{ fn: "definir_prioridade_de_pagamento", args: { p_conta: "unifique", p_grupo: 2, p_autor: "dono-1" } }]);

  const erro = await t.execute({ payable_id: "x", grupo: 2 }, ctxDe(() => ({ data: null, error: { message: "P0001: Conta a pagar não encontrada." } })).ctx) as Qualquer;
  assertEquals(erro, { error: "Conta a pagar não encontrada." });
});

// Reabrir OS pelo assistente — Fase 0b do Fechar juntas (28/10/2026, spec-fechar-juntas 3.7 e 3.10.3), paridade com a tela
// (src/lib/cascade-updates.ts, reopenServiceOrder):
//   - conta CANCELADA fica cancelada (antes voltava para 'pending' e ressuscitava dívida);
//   - pagamento que veio do extrato do banco recusa a reabertura (um Pix pode ter pago outras contas; soltar a linha pelo
//     reconciled_payment_id fazia o dinheiro voltar para a fila e entrar em dobro);
//   - leitura que falha não vira "sem contas".
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/reabrir-os_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { toolsByName } from "./index.ts";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;
const OS = "22222222-2222-4222-8222-222222222077";

function bancoFalso(tabelas: Record<string, Linha[]>, falhas: string[] = []) {
  const escritas: Array<[string, Linha, Linha]> = [];
  // deno-lint-ignore no-explicit-any
  const db: any = {
    escritas,
    tabelas,
    from(tabela: string) {
      const filtros: Array<(l: Linha) => boolean> = [];
      const erro = falhas.includes(tabela) ? { message: `${tabela} fora do ar` } : null;
      const linhas = () => (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
      let patch: Linha | null = null;
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, limit: () => q,
        eq: (c: string, v: unknown) => (filtros.push((l) => l[c] === v), q),
        in: (c: string, vs: unknown[]) => (filtros.push((l) => vs.includes(l[c])), q),
        single: () => {
          if (patch) aplicar();
          return Promise.resolve({ data: erro ? null : linhas()[0] ?? null, error: erro });
        },
        // deno-lint-ignore no-explicit-any
        then: (ok: any, ko: any) => {
          if (patch) aplicar();
          return Promise.resolve({ data: erro || patch ? null : linhas(), error: erro }).then(ok, ko);
        },
        update: (v: Linha) => (patch = v, q),
      };
      const aplicar = () => {
        const alvo = linhas();
        escritas.push([tabela, patch!, { ids: alvo.map((l) => l.id) }]);
        for (const l of alvo) Object.assign(l, patch);
        patch = null;
      };
      return q;
    },
  };
  return db;
}

function ambiente(extra: { pagamentos?: Linha[]; linhasDoBanco?: Linha[]; falhas?: string[] } = {}) {
  const db = bancoFalso({
    service_orders: [{ id: OS, status: "completed" }],
    receivables: [
      { id: "rPaga", service_order_id: OS, amount: 1000, paid_amount: 1000, balance_amount: 0, status: "paid" },
      { id: "rCancelada", service_order_id: OS, amount: 300, paid_amount: 0, balance_amount: 300, status: "cancelled" },
    ],
    payments: extra.pagamentos ?? [
      { id: "p1", receivable_id: "rPaga", status: "confirmed", bank_transaction_id: null },
      { id: "p9", receivable_id: "rCancelada", status: "confirmed", bank_transaction_id: null },
    ],
    bank_transactions: extra.linhasDoBanco ?? [],
  }, extra.falhas);
  const ctx = { sb: db, admin: db, userId: "dono-1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} };
  return { db, ctx };
}

const reabrir = toolsByName["reopen_service_order"];

Deno.test("reabrir: a conta cancelada fica cancelada e o pagamento dela não é mexido; a paga volta a pendente", async () => {
  const { db, ctx } = ambiente();
  // deno-lint-ignore no-explicit-any
  const r = await reabrir.execute({ service_order_id: OS, reason: "ajuste de valor" }, ctx) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  const conta = (id: string) => db.tabelas.receivables.find((l: Linha) => l.id === id);
  assertEquals(conta("rCancelada").status, "cancelled");
  assertEquals(conta("rPaga").status, "pending");
  assertEquals(conta("rPaga").paid_amount, 0);
  assertEquals(conta("rPaga").balance_amount, 1000);
  const pag = (id: string) => db.tabelas.payments.find((l: Linha) => l.id === id);
  assertEquals(pag("p1").status, "cancelled");
  assertStringIncludes(pag("p1").cancellation_reason, "ajuste de valor (reabertura de OS)");
  assertEquals(pag("p9").status, "confirmed", "pagamento de conta cancelada não é estornado pela reabertura");
  assertEquals(db.escritas.filter(([t]: [string]) => t === "bank_transactions"), [], "o extrato não é tocado");
  assertEquals(db.tabelas.service_orders[0].status, "completed");
  assert(db.tabelas.service_orders[0].reopened_at);
});

Deno.test("reabrir: pagamento que veio do extrato (bank_transaction_id) recusa e nada é gravado", async () => {
  const { db, ctx } = ambiente({ pagamentos: [{ id: "p1", receivable_id: "rPaga", status: "confirmed", bank_transaction_id: "bt1" }] });
  // deno-lint-ignore no-explicit-any
  const r = await reabrir.execute({ service_order_id: OS, reason: "x" }, ctx) as any;
  assertStringIncludes(r.error, "pagamento que veio do extrato do banco");
  assertStringIncludes(r.error, "Nada foi reaberto");
  assertEquals(db.escritas, []);
});

Deno.test("reabrir: linha do extrato ligada ao pagamento (reconciled_payment_id) também recusa — não solta a linha", async () => {
  const { db, ctx } = ambiente({ linhasDoBanco: [{ id: "bt7", reconciled_payment_id: "p1", reconciled: true }] });
  // deno-lint-ignore no-explicit-any
  const r = await reabrir.execute({ service_order_id: OS, reason: "x" }, ctx) as any;
  assertStringIncludes(r.error, "pagamento que veio do extrato do banco");
  assertEquals(db.escritas, []);
  assertEquals(db.tabelas.bank_transactions[0].reconciled_payment_id, "p1");
});

Deno.test("reabrir: leitura das contas, dos pagamentos ou do extrato que falha recusa sem gravar nada", async () => {
  for (const tabela of ["receivables", "payments", "bank_transactions"]) {
    const { db, ctx } = ambiente({ falhas: [tabela] });
    // deno-lint-ignore no-explicit-any
    const r = await reabrir.execute({ service_order_id: OS, reason: "x" }, ctx) as any;
    assertStringIncludes(r.error, "Nada foi reaberto", tabela);
    assertEquals(db.escritas, [], tabela);
  }
});

Deno.test("reabrir: só Concluída ou Faturada (sem mudança) e técnico não reabre", async () => {
  const { db, ctx } = ambiente();
  db.tabelas.service_orders[0].status = "in_progress";
  // deno-lint-ignore no-explicit-any
  assertStringIncludes((await reabrir.execute({ service_order_id: OS, reason: "x" }, ctx) as any).error, "Faturada ou Concluída");
  // deno-lint-ignore no-explicit-any
  assertStringIncludes((await reabrir.execute({ service_order_id: OS, reason: "x" }, { ...ctx, userRole: "technician" }) as any).error, "não autorizado");
  assertEquals(db.escritas, []);
});

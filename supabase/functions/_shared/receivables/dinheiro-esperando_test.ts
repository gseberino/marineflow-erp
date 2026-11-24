// Dinheiro esperando no Extrato: quais entradas contam para qual cliente (24/11/2026).
// Os casos saem do dado real de 24/11 (nomes trocados por letras).
import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  contaApontada, contasApontadas, dinheiroEsperando, esperandoDaConta, lerDinheiroEsperando,
  type ContaAberta, type EntradaDaFila,
} from "./dinheiro-esperando.ts";

const vinculo = (tipo: string, lancamentoId: string | null) => ({ principal: { tipo, lancamentoId, nivel: "weak" }, alternativas: [] });
const entrada = (p: Partial<EntradaDaFila>): EntradaDaFila => ({
  suggested_client_id: null, suggested_amount: 0, suggested_date: null, title: "Receita", vinculo_sugerido: null, ...p,
});

Deno.test("contaApontada: só o vínculo principal do tipo conta a receber, com código", () => {
  assertEquals(contaApontada(vinculo("receivable", "r1")), "r1");
  assertEquals(contaApontada(vinculo("existing_payment", "r1")), null);
  assertEquals(contaApontada(vinculo("service_order_balance", "os1")), null);
  assertEquals(contaApontada(vinculo("receivable", null)), null);
  assertEquals(contaApontada({ principal: null }), null);
  assertEquals(contaApontada(null), null);
  assertEquals(contaApontada("texto"), null);
  assertEquals(contaApontada({ alternativas: [{ tipo: "receivable", lancamentoId: "r9" }] }), null);
});

Deno.test("boleto na fila SEM cliente, com o vínculo apontando a conta aberta: conta para o cliente da conta (o caso da Apolo)", () => {
  const abertas: ContaAberta[] = [{ id: "r-apolo-2", client_id: "apolo" }, { id: "r-apolo-3", client_id: "apolo" }];
  const r = dinheiroEsperando([
    entrada({ suggested_amount: 5237.99, suggested_date: "2026-10-16", vinculo_sugerido: vinculo("receivable", "r-apolo-2") }),
    entrada({ suggested_amount: "5238.02", suggested_date: "2026-11-13T00:00:00", vinculo_sugerido: vinculo("receivable", "r-apolo-3") }),
  ], abertas);
  assertEquals(r.map((e) => [e.clienteId, e.valor, e.data, e.contaId, e.pelaConta]), [
    ["apolo", 5237.99, "2026-10-16", "r-apolo-2", true],
    ["apolo", 5238.02, "2026-11-13", "r-apolo-3", true],
  ]);
  assertEquals(esperandoDaConta(r, { id: "r-apolo-3", client_id: "apolo" }).map((e) => e.valor), [5238.02]);
});

Deno.test("entrada com o cliente identificado pela fila continua contando, com ou sem vínculo (o que já valia)", () => {
  const r = dinheiroEsperando([
    entrada({ suggested_client_id: "mp", suggested_amount: 20000, suggested_date: "2026-10-27" }),
    entrada({ suggested_client_id: "mp", suggested_amount: -1500, suggested_date: "2026-10-24", vinculo_sugerido: vinculo("receivable", "r-mp-1") }),
  ], [{ id: "r-mp-1", client_id: "mp" }]);
  assertEquals(r.map((e) => [e.clienteId, e.valor, e.contaId, e.pelaConta]), [["mp", 20000, null, false], ["mp", 1500, "r-mp-1", false]]);
});

Deno.test("sem cliente e sem conta aberta apontada: não conta para ninguém", () => {
  const r = dinheiroEsperando([
    entrada({ suggested_amount: 6500 }),
    // aponta conta que já está paga (não veio na lista das abertas)
    entrada({ suggested_amount: 7600, vinculo_sugerido: vinculo("receivable", "r-paga") }),
    // vínculo de outro tipo
    entrada({ suggested_amount: 2869.5, vinculo_sugerido: vinculo("existing_payment", "r1") }),
    // conta aberta sem cliente
    entrada({ suggested_amount: 10, vinculo_sugerido: vinculo("receivable", "r-sem-cliente") }),
  ], [{ id: "r1", client_id: "c1" }, { id: "r-sem-cliente", client_id: null }]);
  assertEquals(r, []);
});

Deno.test("cliente da fila diferente do cliente da conta apontada: vale o da fila, e a conta não é 'desta entrada'", () => {
  const r = dinheiroEsperando([
    entrada({ suggested_client_id: "a", suggested_amount: 300, vinculo_sugerido: vinculo("receivable", "r-b") }),
  ], [{ id: "r-b", client_id: "b" }]);
  assertEquals(r.map((e) => [e.clienteId, e.contaId, e.pelaConta]), [["a", null, false]]);
  assertEquals(esperandoDaConta(r, { id: "r-b", client_id: "b" }), []);
});

Deno.test("esperandoDaConta: a que aponta a conta; sem nenhuma, as do cliente que não apontam outra conta", () => {
  const todas = dinheiroEsperando([
    entrada({ suggested_client_id: "cesar", suggested_amount: 5000, suggested_date: "2026-11-19" }),
    entrada({ suggested_amount: 2800, suggested_date: "2026-11-13", vinculo_sugerido: vinculo("receivable", "r-nelson") }),
    entrada({ suggested_client_id: "x", suggested_amount: 100, vinculo_sugerido: vinculo("receivable", "r-x-1") }),
  ], [{ id: "r-nelson", client_id: "nelson" }, { id: "r-x-1", client_id: "x" }]);
  // César: Pix identificado, sem conta apontada → vale para as duas contas dele
  assertEquals(esperandoDaConta(todas, { id: "r-cesar-1", client_id: "cesar" }).map((e) => e.valor), [5000]);
  assertEquals(esperandoDaConta(todas, { id: "r-cesar-2", client_id: "cesar" }).map((e) => e.valor), [5000]);
  // Nelson: valor diferente da conta (R$ 2.800 contra R$ 2.110,06) — conta mesmo assim: é "pode ser", não baixa
  assertEquals(esperandoDaConta(todas, { id: "r-nelson", client_id: "nelson" }).map((e) => e.valor), [2800]);
  // a entrada que aponta a conta 1 do cliente x não segura a conta 2 dele
  assertEquals(esperandoDaConta(todas, { id: "r-x-2", client_id: "x" }), []);
  // quem não tem nada
  assertEquals(esperandoDaConta(todas, { id: "r-bertoldi", client_id: "bertoldi" }), []);
  assertEquals(esperandoDaConta(todas, { id: "r-sem", client_id: null }), []);
});

Deno.test("contasApontadas: sem repetição e sem nulos", () => {
  assertEquals(contasApontadas([
    entrada({ vinculo_sugerido: vinculo("receivable", "r1") }), entrada({ vinculo_sugerido: vinculo("receivable", "r1") }),
    entrada({}), entrada({ vinculo_sugerido: vinculo("receivable", "r2") }),
  ]), ["r1", "r2"]);
});

// ── a leitura ──────────────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
type Qualquer = any;
function banco(linhas: Record<string, Qualquer[]>, falham: string[] = []) {
  const pedidos: Array<{ tabela: string; filtros: Array<[string, string, unknown]> }> = [];
  return {
    pedidos,
    from(tabela: string) {
      let rows = [...(linhas[tabela] ?? [])];
      const pedido = { tabela, filtros: [] as Array<[string, string, unknown]> };
      pedidos.push(pedido);
      const q: Qualquer = {};
      q.select = () => q; q.range = () => q; q.order = () => q;
      q.eq = (c: string, v: unknown) => { pedido.filtros.push(["eq", c, v]); rows = rows.filter((l) => l[c] === v); return q; };
      q.in = (c: string, vs: unknown[]) => { pedido.filtros.push(["in", c, vs]); rows = rows.filter((l) => vs.includes(l[c])); return q; };
      q.then = (ok: Qualquer, ko: Qualquer) =>
        Promise.resolve(falham.includes(tabela) ? { data: null, error: { message: `falha em ${tabela}` } } : { data: rows, error: null }).then(ok, ko);
      return q;
    },
  };
}

Deno.test("lerDinheiroEsperando: só pendentes de entrada; só contas apontadas e abertas; conta paga não segura ninguém", async () => {
  const db = banco({
    finance_review_queue: [
      { status: "pending", kind: "create_receivable", suggested_client_id: null, suggested_amount: 5238.02, suggested_date: "2026-11-13", title: "Receita: boleto", vinculo_sugerido: vinculo("receivable", "r-aberta") },
      { status: "pending", kind: "create_receivable", suggested_client_id: null, suggested_amount: 7600, suggested_date: "2026-10-05", title: "Receita", vinculo_sugerido: vinculo("receivable", "r-paga") },
      { status: "approved", kind: "create_receivable", suggested_client_id: "c9", suggested_amount: 1, suggested_date: "2026-10-05", title: "Receita", vinculo_sugerido: null },
      { status: "pending", kind: "create_payable", suggested_client_id: "c9", suggested_amount: 1, suggested_date: "2026-10-05", title: "Despesa", vinculo_sugerido: null },
    ],
    receivables: [
      { id: "r-aberta", client_id: "apolo", status: "pending" },
      { id: "r-paga", client_id: "nelson", status: "paid" },
    ],
  });
  const r = await lerDinheiroEsperando(db);
  assertEquals(r.map((e) => [e.clienteId, e.valor, e.contaId]), [["apolo", 5238.02, "r-aberta"]]);
  const contas = db.pedidos.find((p) => p.tabela === "receivables")!;
  assertEquals(contas.filtros, [["in", "id", ["r-aberta", "r-paga"]], ["in", "status", ["pending", "partially_paid"]]]);
});

Deno.test("lerDinheiroEsperando: entrada pendente cuja linha do banco já foi conciliada não é dinheiro esperando; sem a linha, conta", async () => {
  const fila = (cliente: string, linha: unknown) => ({
    status: "pending", kind: "create_receivable", suggested_client_id: cliente, suggested_amount: 1000, suggested_date: "2026-11-09", title: "Receita", vinculo_sugerido: null,
    ...(linha === undefined ? {} : { bank_transactions: linha }),
  });
  const r = await lerDinheiroEsperando(banco({
    finance_review_queue: [
      fila("ja-aplicado", { reconciled: true }),
      fila("ja-aplicado-em-lista", [{ reconciled: true }]),
      fila("esperando", { reconciled: false }),
      fila("sem-linha", null),
      fila("sem-o-campo", undefined),
    ],
  }));
  assertEquals(r.map((e) => e.clienteId), ["esperando", "sem-linha", "sem-o-campo"]);
});

Deno.test("lerDinheiroEsperando: sem conta apontada não lê as contas; erro de leitura LANÇA (nunca vira 'nada esperando')", async () => {
  const semVinculo = banco({ finance_review_queue: [{ status: "pending", kind: "create_receivable", suggested_client_id: "c1", suggested_amount: 10, suggested_date: null, title: "", vinculo_sugerido: null }] });
  assertEquals((await lerDinheiroEsperando(semVinculo)).length, 1);
  assertEquals(semVinculo.pedidos.map((p) => p.tabela), ["finance_review_queue"]);

  await assertRejects(() => lerDinheiroEsperando(banco({}, ["finance_review_queue"])), Error, "Não consegui ler os Pix que esperam no Extrato");
  const comVinculo = { finance_review_queue: [{ status: "pending", kind: "create_receivable", suggested_client_id: null, suggested_amount: 10, suggested_date: null, title: "", vinculo_sugerido: vinculo("receivable", "r1") }] };
  await assertRejects(() => lerDinheiroEsperando(banco(comVinculo, ["receivables"])), Error, "Não consegui ler as contas que as entradas do Extrato apontam");
});

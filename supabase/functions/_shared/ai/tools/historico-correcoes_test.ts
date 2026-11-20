// Achados laterais do histórico de documentos (audit/novos-achados.md), corrigidos em 20/11/2026:
//   NOVO-historico-01: edit_service_order_item grava o total da linha LÍQUIDO do desconto da linha (preço × qtd − desconto),
//                      a mesma conta das telas; antes gravava preço × qtd e o total da OS saía maior que o PDF.
//                      Mesma classe no assistente: apply_quote_price (aplicar o preço do fornecedor) também.
//   NOVO-historico-02: apply_service_order_discount recusa OS cancelada ou faturada (assertEditableSo), como as tools de item.
// Banco falso que filtra e grava em memória. Dado sintético.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { quoteTools } from "./quotes.ts";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function bancoFalso(tabelas: Record<string, Linha[]>) {
  const gravacoes: Array<{ op: string; tabela: string; valor?: unknown }> = [];
  function consulta(tabela: string) {
    const filtros: Array<(l: Linha) => boolean> = [];
    let op: "select" | "update" | "insert" = "select";
    // deno-lint-ignore no-explicit-any
    let valor: any = null;
    let unico = false;
    const executar = () => {
      const todas = (tabelas[tabela] ??= []);
      if (op === "insert") { gravacoes.push({ op, tabela, valor }); return { data: null, error: null }; }
      const alvo = todas.filter((l) => filtros.every((f) => f(l)));
      if (op === "update") { alvo.forEach((l) => Object.assign(l, valor)); gravacoes.push({ op, tabela, valor }); }
      const res = alvo.map((l) => ({ ...l }));
      if (unico) return { data: res[0] ?? null, error: null };
      return { data: res, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => q,
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      order: () => q,
      limit: () => q,
      update: (v: unknown) => { op = "update"; valor = v; return q; },
      insert: (v: unknown) => { op = "insert"; valor = v; return q; },
      single: () => { unico = true; return Promise.resolve(executar()); },
      maybeSingle: () => { unico = true; return Promise.resolve(executar()); },
      // deno-lint-ignore no-explicit-any
      then: (ok: any, ko: any) => Promise.resolve(executar()).then(ok, ko),
    };
    return q;
  }
  return { from: consulta, rpc: () => Promise.resolve({ data: null, error: null }), gravacoes, tabelas };
}

const ctxCom = (db: unknown) => ({ sb: db, admin: db, userId: "dono-1", userRole: "admin", jwt: "", appOrigin: "", settings: {} }) as never;
const tool = (nome: string) => serviceOrderTools.find((t) => t.name === nome)!;
const tool2 = (nome: string) => quoteTools.find((t) => t.name === nome)!;

const OS = "11111111-1111-4111-8111-111111111201";

function orcamento(status = "draft") {
  return {
    service_orders: [{ id: OS, service_order_number: "ORÇ-00201", status, grand_total: 1000, discount_amount: 0 }],
    service_order_parts: [
      // 2 × 100 − 30 de desconto da linha = 170
      { id: "p1", service_order_id: OS, created_at: "1", product_id: "pr1", quantity: 2, unit_sale_snapshot: 100, unit_cost_snapshot: 60,
        line_total_sale: 170, discount_amount: 30, products: { name: "Disjuntor 125A" } },
    ],
    service_order_services: [
      // 1 × 800 − 80 = 720
      { id: "s1", service_order_id: OS, created_at: "2", name_snapshot: "Instalação do inversor", quantity: 1, unit_price_snapshot: 800,
        line_total: 720, discount_amount: 80 },
      { id: "s2", service_order_id: OS, created_at: "3", name_snapshot: "Deslocamento", quantity: 1, unit_price_snapshot: 200,
        line_total: 200, discount_amount: null },
    ],
    products: [{ id: "pr1", stock_quantity: 10 }],
    app_settings: [],
  };
}

Deno.test("historico-01: editar a quantidade da PEÇA com desconto grava preço × qtd − desconto", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool("edit_service_order_item").execute({ service_order_id: OS, item_id: "p1", quantity: 3 }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  const p = db.tabelas.service_order_parts[0];
  assertEquals(p.line_total_sale, 270); // 3 × 100 − 30 (antes: 300)
  assertEquals(p.discount_amount, 30); // o desconto da linha não muda
  assertEquals(p.line_total_cost, 180); // custo não leva desconto
  assertEquals(r.depois.total, 270);
  assertEquals(r.depois.desconto_da_linha, 30);
});

Deno.test("historico-01: editar o preço do SERVIÇO com desconto grava preço × qtd − desconto (centavos)", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool("edit_service_order_item").execute({ service_order_id: OS, item_id: "s1", unit_price: 899.99 }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_order_services.find((s) => s.id === "s1")!.line_total, 819.99); // 899,99 − 80 (antes: 899,99)
  assertEquals(r.depois.total, 819.99);
});

Deno.test("historico-01: linha sem desconto continua preço × qtd", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool("edit_service_order_item").execute({ service_order_id: OS, item_id: "s2", quantity: 2 }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_order_services.find((s) => s.id === "s2")!.line_total, 400);
  assertEquals("desconto_da_linha" in r.depois, false);
});

Deno.test("historico-01: desconto maior que o novo bruto → recusa, nada gravado", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool("edit_service_order_item").execute({ service_order_id: OS, item_id: "s1", unit_price: 50 }, ctxCom(db)) as Linha;
  assertStringIncludes(String(r.error), "desconto de R$ 80.00");
  assertEquals(db.gravacoes.length, 0);
});

for (const status of ["cancelled", "invoiced"]) {
  Deno.test(`historico-02: desconto em OS ${status} → recusado, nada gravado`, async () => {
    const db = bancoFalso(orcamento(status));
    const r = await tool("apply_service_order_discount").execute({ id: OS, discount_amount: 150 }, ctxCom(db)) as Linha;
    assert(r.error, JSON.stringify(r));
    assertEquals(db.gravacoes.length, 0);
    assertEquals(db.tabelas.service_orders[0].discount_amount, 0);
  });
}

Deno.test("historico-02: desconto em orçamento aberto continua gravando", async () => {
  const db = bancoFalso(orcamento("draft"));
  const r = await tool("apply_service_order_discount").execute({ id: OS, discount_amount: 150 }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_orders[0].discount_amount, 150);
});

// ─── apply_quote_price: a mesma conta ao aplicar o preço do fornecedor pelo assistente ─────────────
function cotacao(linha: "peca" | "servico") {
  return {
    quote_responses: [{ id: "resp-1", quote_request_id: "qr-1", supplier_id: "sup-1", quote_request_item_id: "qi-1", unit_price: 100, confirmed: false }],
    quote_request_items: [{ id: "qi-1", description: "Bomba de porão", service_order_part_id: linha === "peca" ? "part-1" : null,
      service_order_service_id: linha === "servico" ? "svc-1" : null }],
    quote_requests: [{ id: "qr-1", code: "COT-00007", service_order_id: OS }],
    service_orders: [{ id: OS, status: "draft", grand_total: 300 }],
    // 2 × 150 − 25 de desconto da linha
    service_order_parts: [{ id: "part-1", service_order_id: OS, quantity: 2, unit_cost_snapshot: 80, unit_sale_snapshot: 150,
      line_total_cost: 160, line_total_sale: 275, discount_amount: 25 }],
    service_order_services: [{ id: "svc-1", service_order_id: OS, quantity: 2, unit_price_snapshot: 150, line_total: 275, discount_amount: 25 }],
    suppliers: [{ id: "sup-1", name: "Fornecedor Teste" }],
    receivables: [],
  };
}

Deno.test("historico-01 (apply_quote_price): peça com markup → venda = preço × qtd − desconto; custo sem desconto", async () => {
  const db = bancoFalso(cotacao("peca"));
  const r = await tool2("apply_quote_price").execute({ response_id: "resp-1", markup_percent: 40 }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  const p = db.tabelas.service_order_parts[0];
  assertEquals(p.unit_sale_snapshot, 140);
  assertEquals(p.line_total_sale, 255); // 2 × 140 − 25 (antes: 280)
  assertEquals(p.line_total_cost, 200);
});

Deno.test("historico-01 (apply_quote_price): material de texto livre → total = preço × qtd − desconto", async () => {
  const db = bancoFalso(cotacao("servico"));
  const r = await tool2("apply_quote_price").execute({ response_id: "resp-1", markup_percent: 40 }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_order_services[0].line_total, 255); // 2 × 140 − 25 (antes: 280)
});

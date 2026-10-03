// Leitura que falha não pode virar "não há nada" (auditoria de 02-03/10/2026, depois do combustível
// R$ 0). Cada ferramenta abaixo engolia o `error` de uma leitura secundária e respondia vazio como
// fato: OS sem peças, fornecedor "sem resposta", cliente "nunca cobrado" (cobrar duas vezes), item
// "sem resultado" (valor provisório para produto que existe). E list_low_stock falhava SEMPRE.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { orContem } from "../filtro-or.ts";
import { productTools } from "./products.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { financialTools } from "./financial.ts";
import { quoteTools } from "./quotes.ts";
import { fechamentoTools } from "./fechamento.ts";
import { whatsappTools } from "./whatsapp.ts";

/** Banco de mentira: devolve as linhas da tabela; as tabelas em `falham` respondem com erro. */
function bancoFalso(tabelas: Record<string, unknown[]>, falham: string[] = []) {
  const pedidos: Array<{ tabela: string; chamadas: unknown[][] }> = [];
  const db = {
    pedidos,
    from(tabela: string) {
      const pedido = { tabela, chamadas: [] as unknown[][] };
      pedidos.push(pedido);
      const resultado = () => falham.includes(tabela)
        ? { data: null, error: { message: `falha em ${tabela}` } }
        : { data: tabelas[tabela] ?? [], error: null };
      // deno-lint-ignore no-explicit-any
      const q: any = {};
      for (const m of ["select", "in", "gte", "lte", "lt", "gt", "eq", "not", "or", "order", "range", "limit", "filter", "ilike"]) {
        q[m] = (...a: unknown[]) => { pedido.chamadas.push([m, ...a]); return q; };
      }
      q.maybeSingle = () => {
        const r = resultado();
        return Promise.resolve(r.error ? r : { data: (r.data as unknown[])[0] ?? null, error: null });
      };
      // deno-lint-ignore no-explicit-any
      q.then = (ok: any, erro: any) => Promise.resolve(resultado()).then(ok, erro);
      return q;
    },
  };
  return db;
}

function contexto(db: ReturnType<typeof bancoFalso>) {
  return { sb: db, admin: db, userId: "u", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} } as never;
}

const ferramenta = (lista: Array<{ name: string }>, nome: string) =>
  // deno-lint-ignore no-explicit-any
  lista.find((t) => t.name === nome) as any;

Deno.test("orContem: vírgula e parênteses viram texto (\"cabo 2,5mm\" quebrava a busca)", () => {
  assertEquals(orContem(["name", "sku"], "cabo 2,5mm"), 'name.ilike."%cabo 2,5mm%",sku.ilike."%cabo 2,5mm%"');
  assertEquals(orContem(["name"], "Bomba (12V)"), 'name.ilike."%Bomba (12V)%"');
  // Aspas e barra invertida fechariam o valor antes da hora: saem.
  assertEquals(orContem(["name"], 'cabo 10" \\x'), 'name.ilike."%cabo 10   x%"');
});

Deno.test("list_low_stock: compara estoque com o mínimo de cada produto (antes falhava sempre)", async () => {
  const db = bancoFalso({
    products: [
      { id: "a", name: "Anodo", stock_quantity: 1, minimum_stock: 2, unit: "un" },
      { id: "b", name: "Bomba", stock_quantity: 5, minimum_stock: 2, unit: "un" },
      { id: "c", name: "Cabo", stock_quantity: null, minimum_stock: 3, unit: "m" },
    ],
  });
  const r = await ferramenta(productTools, "list_low_stock").execute({}, contexto(db));
  assertEquals(r.results.map((p: { id: string }) => p.id), ["a", "c"]);
  assertEquals(r.produtos_com_minimo_cadastrado, 3);
  // Nada de filtro coluna-com-coluna (o PostgREST comparava com o texto "minimum_stock").
  assertEquals(db.pedidos[0].chamadas.some((c) => c[0] === "filter"), false);
});

Deno.test("search_products_batch: busca que falhou NÃO vira 'sem resultado'", async () => {
  const db = bancoFalso({}, ["products"]);
  await assertRejects(
    () => ferramenta(productTools, "search_products_batch").execute({ queries: ["cabo 2,5mm"] }, contexto(db)),
    Error,
    'Não consegui buscar "cabo 2,5mm"',
  );
});

Deno.test("search_products_batch: o termo vai entre aspas no filtro", async () => {
  const db = bancoFalso({ products: [] });
  const r = await ferramenta(productTools, "search_products_batch").execute({ queries: ["cabo 2,5mm"] }, contexto(db));
  assertEquals(r.sem_resultado, ["cabo 2,5mm"]);
  const or = db.pedidos[0].chamadas.find((c) => c[0] === "or");
  assertEquals(or, ["or", 'name.ilike."%cabo 2,5mm%",sku.ilike."%cabo 2,5mm%",brand.ilike."%cabo 2,5mm%"']);
});

Deno.test("get_product_price_history: histórico ilegível não vira 'use o catálogo'", async () => {
  const db = bancoFalso({ products: [{ id: "p", name: "Anodo", sale_price: 10 }] }, ["service_order_parts"]);
  await assertRejects(
    () => ferramenta(productTools, "get_product_price_history").execute({ product_id: "p" }, contexto(db)),
    Error,
    "histórico de uso",
  );
});

Deno.test("get_service_order: peças ilegíveis não viram 'OS sem peças'", async () => {
  const db = bancoFalso({ service_orders: [{ id: "os", clients: { name: "X" } }] }, ["service_order_parts"]);
  await assertRejects(
    () => ferramenta(serviceOrderTools, "get_service_order").execute({ id: "os" }, contexto(db)),
    Error,
    "peças da OS",
  );
});

Deno.test("get_delinquency_plan: sem ler as cobranças, não diz 'nunca cobrado'", async () => {
  const vencido = { id: "r", amount: 500, balance_amount: 500, due_date: "2026-01-10", client_id: "c", clients: { name: "Cliente" } };
  const db = bancoFalso({ receivables: [vencido] }, ["collections"]);
  await assertRejects(
    () => ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(db)),
    Error,
    "cobranças já enviadas",
  );
  // E o status 'overdue' também entra.
  const ok = bancoFalso({ receivables: [vencido], collections: [], app_settings: [] });
  await ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(ok));
  const inStatus = ok.pedidos[0].chamadas.find((c) => c[0] === "in");
  assertEquals(inStatus, ["in", "status", ["pending", "partially_paid", "overdue"]]);
});

Deno.test("get_quote_comparison: respostas ilegíveis não viram 'fornecedor sem resposta'", async () => {
  const db = bancoFalso(
    { quote_requests: [{ id: "q", code: "COT-00001", sent_supplier_ids: ["s1"] }], quote_request_items: [] },
    ["quote_responses"],
  );
  await assertRejects(
    () => ferramenta(quoteTools, "get_quote_comparison").execute({ code: "COT-00001" }, contexto(db)),
    Error,
    "respostas dos fornecedores",
  );
});

Deno.test("listar_lancados_sozinhos: fila ilegível não vira 'nada lançado'", async () => {
  const db = bancoFalso({ app_settings: [{ value: "on" }] }, ["finance_review_queue"]);
  await assertRejects(
    () => ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db)),
    Error,
    "lançado sozinho",
  );
});

Deno.test("get_delinquency_plan: cliente com Pix esperando no Extrato sai da cobrança, com o porquê", async () => {
  const vencido = { id: "r", amount: 500, balance_amount: 500, due_date: "2026-01-10", client_id: "c", clients: { name: "Cliente" } };
  const db = bancoFalso({
    receivables: [vencido], collections: [], app_settings: [],
    finance_review_queue: [{ suggested_client_id: "c", suggested_amount: 500, suggested_date: "2026-10-02", title: "Receita: CLIENTE" }],
  });
  const r = await ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(db));
  assertEquals(r.casos, []);
  assertEquals(r.talvez_ja_pago.map((c: { cliente: string; pix_esperando_no_extrato: unknown[] }) => [c.cliente, c.pix_esperando_no_extrato.length]), [["Cliente", 1]]);
  // E a leitura da fila que falha não vira "nenhum Pix esperando".
  const falha = bancoFalso({ receivables: [vencido], collections: [], app_settings: [] }, ["finance_review_queue"]);
  await assertRejects(() => ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(falha)), Error, "Pix que esperam no Extrato");
});

Deno.test("send_collection_reminder: com Pix do cliente esperando no Extrato, não cobra", async () => {
  const db = bancoFalso({
    collections: [{ id: "col", amount: 500, due_date: "2026-09-10", contact_whatsapp: "5547999990000", client_id: "c" }],
    app_settings: [],
    finance_review_queue: [{ suggested_client_id: "c", suggested_amount: 500, suggested_date: "2026-10-02", title: "Receita: CLIENTE" }],
  });
  const original = globalThis.fetch;
  let enviou = false;
  globalThis.fetch = (() => { enviou = true; return Promise.resolve(new Response("{}")); }) as typeof fetch;
  try {
    const r = await ferramenta(whatsappTools, "send_collection_reminder").execute({ collection_id: "col" }, contexto(db));
    assertEquals(/Pix esperando no Extrato/.test(r.error), true);
    assertEquals(enviou, false);
  } finally {
    globalThis.fetch = original;
  }
});

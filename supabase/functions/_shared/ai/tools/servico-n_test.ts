// "Serviço N" nas tools (F0 do porte da via v2): o número é o da via (created_at, id), número sozinho em remover/editar
// item PERGUNTA, e leitura que falha lança. Banco falso que filtra, ordena e grava em memória. Dado sintético.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { fieldOpsTools } from "./field-ops.ts";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function bancoFalso(tabelas: Record<string, Linha[]>, falhas: Record<string, string> = {}) {
  const gravacoes: Array<{ op: string; tabela: string; valor?: unknown }> = [];
  function consulta(tabela: string) {
    const filtros: Array<(l: Linha) => boolean> = [];
    const ordem: Array<[string, boolean]> = [];
    let op: "select" | "update" | "insert" | "delete" = "select";
    // deno-lint-ignore no-explicit-any
    let valor: any = null;
    let unico = false;
    const executar = () => {
      const erro = falhas[`${op}:${tabela}`];
      if (erro) return { data: null, error: { message: erro } };
      const todas = (tabelas[tabela] ??= []);
      if (op === "insert") {
        gravacoes.push({ op, tabela, valor });
        return { data: null, error: null };
      }
      const alvo = todas.filter((l) => filtros.every((f) => f(l)));
      if (op === "update") { alvo.forEach((l) => Object.assign(l, valor)); gravacoes.push({ op, tabela, valor }); }
      if (op === "delete") { tabelas[tabela] = todas.filter((l) => !alvo.includes(l)); gravacoes.push({ op, tabela, valor: alvo.map((l) => l.id) }); }
      const res = alvo.map((l) => ({ ...l }));
      res.sort((a, b) => {
        for (const [c, asc] of ordem) {
          const x = String(a[c] ?? ""), y = String(b[c] ?? "");
          if (x !== y) return (x < y ? -1 : 1) * (asc ? 1 : -1);
        }
        return 0;
      });
      if (unico) return { data: res[0] ?? null, error: null };
      return { data: res, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => q,
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      neq: (c: string, v: unknown) => { filtros.push((l) => l[c] !== v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      order: (c: string, o?: { ascending?: boolean }) => { ordem.push([c, o?.ascending !== false]); return q; },
      limit: () => q,
      update: (v: unknown) => { op = "update"; valor = v; return q; },
      insert: (v: unknown) => { op = "insert"; valor = v; return q; },
      delete: () => { op = "delete"; return q; },
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
const tool = (lista: { name: string }[], nome: string) => lista.find((t) => t.name === nome)! as (typeof serviceOrderTools)[number];

const OS = "11111111-1111-4111-8111-111111111136";
const T = (ms: number) => `2026-11-16T18:00:00.${String(ms).padStart(3, "0")}000+00:00`;

/** O cartão da proposta do assistente: 4 peças (1–4) e 2 de mão de obra (5–6). Na via, a mão de obra é 1 e 2. */
function orcamento() {
  return {
    service_orders: [{ id: OS, service_order_number: "ORÇ-00136", status: "draft", grand_total: 1000 }],
    service_order_parts: [
      { id: "p1", service_order_id: OS, created_at: T(1), product_id: "pr1", quantity: 1, unit_sale_snapshot: 2000, unit_cost_snapshot: 1500, line_total_sale: 2000, products: { name: "Bateria LiFePO4 100Ah" } },
      { id: "p2", service_order_id: OS, created_at: T(2), product_id: "pr2", quantity: 2, unit_sale_snapshot: 50, unit_cost_snapshot: 20, line_total_sale: 100, products: { name: "Terminal 50mm" } },
      { id: "p3", service_order_id: OS, created_at: T(3), product_id: "pr3", quantity: 1, unit_sale_snapshot: 300, unit_cost_snapshot: 200, line_total_sale: 300, products: { name: "Disjuntor 125A" } },
      { id: "p4", service_order_id: OS, created_at: T(4), product_id: "pr4", quantity: 4, unit_sale_snapshot: 10, unit_cost_snapshot: 5, line_total_sale: 40, products: { name: "Abraçadeira" } },
    ],
    service_order_services: [
      // ordem física invertida: o banco ordena por created_at, id
      { id: "s2", service_order_id: OS, created_at: T(6), name_snapshot: "Deslocamento", quantity: 1, unit_price_snapshot: 200, line_total: 200, field_status: null, field_status_note: null },
      { id: "s1", service_order_id: OS, created_at: T(5), name_snapshot: "Instalação do banco de baterias", quantity: 1, unit_price_snapshot: 800, line_total: 800, field_status: null, field_status_note: null },
    ],
  };
}

for (const dito of ["4", "o 4", "tira o 4", "item 4"]) {
  Deno.test(`remover: 4 peças + 2 serviços, depois "${dito}" → needs_choice, nada apagado`, async () => {
    const db = bancoFalso(orcamento());
    const r = await tool(serviceOrderTools, "remove_service_order_item").execute(
      { service_order_id: OS, description: dito === "tira o 4" ? "4" : dito },
      ctxCom(db),
    ) as Linha;
    assertEquals(r.needs_choice, true, JSON.stringify(r));
    assertEquals(r.nada_alterado, true);
    assertStringIncludes(r.message, "não existe o serviço 4");
    // os 2 serviços com o número da via, e as peças à parte, sem número
    assertEquals(r.options.map((o: Linha) => o.descricao), ["1 · Instalação do banco de baterias", "2 · Deslocamento"]);
    assertEquals(r.pecas.map((p: Linha) => p.descricao), ["Bateria LiFePO4 100Ah", "Terminal 50mm", "Disjuntor 125A", "Abraçadeira"]);
    assertEquals(db.gravacoes.length, 0);
    assertEquals(db.tabelas.service_order_parts.length, 4);
    assertEquals(db.tabelas.service_order_services.length, 2);
  });
}

Deno.test("remover: 'serviço 2' existe — mesmo assim pergunta (é o 2 · Deslocamento?) e não apaga", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "serviço 2" }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true);
  assertStringIncludes(r.message, 'O serviço 2 da via é "Deslocamento"');
  assertStringIncludes(r.message, "item_id");
  assertEquals(r.options, [{ item_id: "s2", numero: 2, descricao: "2 · Deslocamento", quantidade: 1, total: 200 }]);
  assertEquals(db.gravacoes.length, 0);
});

Deno.test("editar: '4' com preço novo → needs_choice, nada alterado", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool(serviceOrderTools, "edit_service_order_item").execute(
    { service_order_id: OS, description: "4", unit_price: 1 },
    ctxCom(db),
  ) as Linha;
  assertEquals(r.needs_choice, true);
  assertStringIncludes(r.message, "editar");
  assertEquals(db.gravacoes.length, 0);
  assertEquals(db.tabelas.service_order_parts.find((p) => p.id === "p4")!.unit_sale_snapshot, 10);
});

Deno.test("remover pelo NOME: palavra inteira — 'LiFePO4' é a bateria; 'bater' (pedaço) não apaga nada", async () => {
  const pedaco = bancoFalso(orcamento());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "bater" }, ctxCom(pedaco)) as Linha;
  assertEquals(r.error, "Item não encontrado neste orçamento/OS.");
  assertEquals(pedaco.gravacoes.length, 0);
  // com o item_id o número não importa: é o caminho preferencial
  const peloId = bancoFalso(orcamento());
  const r2 = await tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, item_id: "s2", description: "2", quantity: 2 }, ctxCom(peloId)) as Linha;
  assert(r2.ok, JSON.stringify(r2));
  assertEquals(peloId.tabelas.service_order_services.find((s) => s.id === "s2")!.quantity, 2);
});

Deno.test("leitura das peças com erro LANÇA (não vira 'Item não encontrado'), e nada é apagado", async () => {
  const db = bancoFalso(orcamento(), { "select:service_order_parts": "timeout" });
  await assertRejects(
    () => tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "Abraçadeira" }, ctxCom(db)),
    Error,
    "timeout",
  );
  const db2 = bancoFalso(orcamento(), { "select:service_order_services": "sem rede" });
  await assertRejects(
    () => tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, description: "Abraçadeira", quantity: 2 }, ctxCom(db2)),
    Error,
    "sem rede",
  );
  assertEquals(db.gravacoes.length + db2.gravacoes.length, 0);
});

Deno.test("get_service_order: cada serviço com o numero da via, na ordem created_at, id", async () => {
  const db = bancoFalso({ ...orcamento(), service_order_steps: [] });
  const r = await tool(serviceOrderTools, "get_service_order").execute({ id: OS }, ctxCom(db)) as Linha;
  assertEquals(r.services.map((s: Linha) => [s.numero, s.servico]), [[1, "Instalação do banco de baterias"], [2, "Deslocamento"]]);
});

Deno.test("update_service_order_via: '4' numa OS com LiFePO4 na linha 1 marca a linha 4 (antes marcava a 1, calado)", async () => {
  const nomes = ["Instalação de bateria LiFePO4 200 Ah", "Serviço de revisão do gerador", "Troca do inversor 3000 W", "Fita LED externa", "Deslocamento"];
  const db = bancoFalso({
    service_orders: [{ id: OS, service_order_number: "OS-00140", status: "in_progress", technician_notes: null, internal_notes: null, check_in_at: null, check_out_at: null }],
    service_order_services: nomes.map((n, i) => ({
      id: `l${i + 1}`, service_order_id: OS, created_at: T(i + 1), name_snapshot: n, field_status: "a_fazer", field_status_note: null,
    })).reverse(),
  });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "4", situacao: "feito" }, { servico: "serviço 2", situacao: "feito" }] },
    ctxCom(db),
  ) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.servicos_atualizados.map((s: Linha) => [s.numero, s.servico]), [[2, "Serviço de revisão do gerador"], [4, "Fita LED externa"]]);
  const linha = (id: string) => db.tabelas.service_order_services.find((l) => l.id === id)!;
  assertEquals([linha("l1").field_status, linha("l2").field_status, linha("l4").field_status], ["a_fazer", "feito", "feito"]);
});

Deno.test("update_service_order_via: '200' numa OS de 2 → pergunta com a lista 'N · nome', nada gravado", async () => {
  const db = bancoFalso({
    service_orders: [{ id: OS, service_order_number: "OS-00140", status: "in_progress" }],
    service_order_services: [
      { id: "a", service_order_id: OS, created_at: T(1), name_snapshot: "Bateria 200 Ah", field_status: "a_fazer", field_status_note: null },
      { id: "b", service_order_id: OS, created_at: T(2), name_snapshot: "Deslocamento", field_status: "a_fazer", field_status_note: null },
    ],
  });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "200", situacao: "feito" }] },
    ctxCom(db),
  ) as Linha;
  assertEquals(r.nada_gravado, true);
  assertStringIncludes(r.error, "A OS tem 2 serviços; não existe o 200. Serviços: 1 · Bateria 200 Ah; 2 · Deslocamento.");
  assertEquals(r.servicos_da_os, ["1 · Bateria 200 Ah", "2 · Deslocamento"]);
  assertEquals(db.gravacoes.length, 0);
});

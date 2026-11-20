// Escrita em sequência (F0 do porte da via v2, E15): duplicar pelo assistente copia peças e serviços na ordem da origem
// (created_at, id) e grava created_at estritamente crescente a partir do da OS nova. Sem isto, as linhas de um INSERT
// só empatavam no now() e a ordem da via ficava por conta do id (aleatório). O montador do orçamento está em
// quote-builder_test.ts. Banco falso, dado sintético.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { soOpsTools } from "./so-ops.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { chaveDoInstante } from "../../linhas-da-os.ts";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function bancoDaCopia(origem: Linha, criadaEm: string | null) {
  const insercoes: Array<[string, Linha[]]> = [];
  const db = {
    insercoes,
    rpc: (nome: string) => Promise.resolve({ data: nome === "next_document_number" ? 160 : null, error: null }),
    from(tabela: string) {
      const filtros: Array<[string, unknown]> = [];
      const linhas = () => (tabela === "service_orders" ? [origem] : []).filter((l) => filtros.every(([c, v]) => l[c] === v));
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, order: () => q, limit: () => q, neq: () => q,
        eq: (c: string, v: unknown) => { filtros.push([c, v]); return q; },
        maybeSingle: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        single: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any) => Promise.resolve({ data: linhas(), error: null }).then(ok),
        insert: (v: Linha | Linha[]) => {
          insercoes.push([tabela, Array.isArray(v) ? v : [v]]);
          // deno-lint-ignore no-explicit-any
          const r: any = Promise.resolve({ data: null, error: null });
          r.select = () => ({
            single: () => Promise.resolve({ data: { id: `novo-${tabela}`, service_order_number: "ORÇ-00160", ...(criadaEm ? { created_at: criadaEm } : {}) }, error: null }),
          });
          return r;
        },
        delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
      };
      return q;
    },
  };
  return db;
}

const ctxCom = (db: unknown) => ({ sb: db, admin: db, userId: "dono-1", userRole: "admin", jwt: "", appOrigin: "", settings: {} }) as never;
const duplicar = soOpsTools.find((t) => t.name === "duplicate_service_order")!;
const MESMO = "2026-11-10T12:00:00.5+00:00";

/** A origem como o embutido devolve: sem ordem, com empate (um INSERT só) e um id que desempata. */
function origemEmbaralhada(): Linha {
  return {
    id: "orc-1", service_order_number: "ORÇ-00100", client_id: "c1", vessel_id: "v1", status: "draft",
    service_order_parts: [
      { id: "c-peca", created_at: MESMO, product_id: "pC", quantity: 1, unit_sale_snapshot: 30 },
      { id: "a-peca", created_at: MESMO, product_id: "pA", quantity: 1, unit_sale_snapshot: 10 },
      { id: "z-peca", created_at: "2026-11-10T11:00:00+00:00", product_id: "pZ", quantity: 1, unit_sale_snapshot: 5 },
      { id: "b-peca", created_at: MESMO, product_id: "pB", quantity: 1, unit_sale_snapshot: 20 },
    ],
    service_order_services: [
      { id: "9-serv", created_at: MESMO, name_snapshot: "Teste final", quantity: 1, unit_price_snapshot: 100, line_total: 100 },
      { id: "1-serv", created_at: MESMO, name_snapshot: "Instalação", quantity: 1, unit_price_snapshot: 300, line_total: 300 },
      { id: "5-serv", created_at: MESMO, name_snapshot: "Deslocamento", quantity: 1, unit_price_snapshot: 80, line_total: 80 },
    ],
  };
}

const crescente = (ts: string[]) => ts.every((t, i) => i === 0 || chaveDoInstante(t)! > chaveDoInstante(ts[i - 1])!);

Deno.test("duplicar: a cópia sai na ordem da origem (created_at, id) com created_at em sequência a partir do da OS nova", async () => {
  const BASE = "2026-11-16T18:00:00.123456+00:00";
  const db = bancoDaCopia(origemEmbaralhada(), BASE);
  const r = await duplicar.execute({ service_order_id: "orc-1" }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  const [, pecas] = db.insercoes.find(([t]) => t === "service_order_parts")!;
  const [, servicos] = db.insercoes.find(([t]) => t === "service_order_services")!;
  assertEquals(pecas.map((p) => p.product_id), ["pZ", "pA", "pB", "pC"]);
  assertEquals(servicos.map((s) => s.name_snapshot), ["Instalação", "Deslocamento", "Teste final"]);
  assertEquals(servicos.map((s) => s.created_at), ["2026-11-16T18:00:00.124Z", "2026-11-16T18:00:00.125Z", "2026-11-16T18:00:00.126Z"]);
  assert(crescente(pecas.map((p) => p.created_at)));
  // todas depois da OS nova
  for (const l of [...pecas, ...servicos]) assert(chaveDoInstante(l.created_at)! > chaveDoInstante(BASE)!);
});

Deno.test("duplicar: sem o created_at da OS nova, vale o relógio da edge — e continua estritamente crescente", async () => {
  const db = bancoDaCopia(origemEmbaralhada(), null);
  const antes = Date.now();
  const r = await duplicar.execute({ service_order_id: "orc-1" }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  const [, servicos] = db.insercoes.find(([t]) => t === "service_order_services")!;
  const ts = servicos.map((s) => s.created_at as string);
  assert(crescente(ts));
  assert(Date.parse(ts[0]) > antes);
});

// ═══ create_service_order com items (revisão da F0, ordem-2): as peças na ordem do pedido, em sequência ════════════

/** O banco da criação: produtos do catálogo, o insert da OS devolve o created_at e o das peças pode falhar. */
function bancoDaCriacao(criadaEm: string | null, falhaNasPecas?: string) {
  const insercoes: Array<[string, Linha[]]> = [];
  const atualizacoes: Array<[string, unknown]> = [];
  const produtos: Record<string, Linha> = {
    pA: { cost_price: 10, sale_price: 20, cost_currency: "BRL", stock_quantity: 50 },
    pB: { cost_price: 30, sale_price: 60, cost_currency: "BRL", stock_quantity: 50 },
    pC: { cost_price: 5, sale_price: 9, cost_currency: "BRL", stock_quantity: 50 },
  };
  const db = {
    insercoes,
    atualizacoes,
    rpc: (nome: string) => Promise.resolve({ data: nome === "next_document_number" ? 161 : null, error: null }),
    from(tabela: string) {
      const filtros: Array<[string, unknown]> = [];
      const id = () => filtros.find(([c]) => c === "id")?.[1] as string | undefined;
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, order: () => q, limit: () => q, neq: () => q, in: () => q,
        eq: (c: string, v: unknown) => { filtros.push([c, v]); return q; },
        maybeSingle: () => Promise.resolve({ data: tabela === "products" ? produtos[id() ?? ""] ?? null : null, error: null }),
        single: () => Promise.resolve({ data: null, error: null }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any) => Promise.resolve({ data: [], error: null }).then(ok),
        update: (v: unknown) => { atualizacoes.push([tabela, v]); return q; },
        insert: (v: Linha | Linha[]) => {
          insercoes.push([tabela, Array.isArray(v) ? v : [v]]);
          const erro = tabela === "service_order_parts" && falhaNasPecas ? { message: falhaNasPecas } : null;
          // deno-lint-ignore no-explicit-any
          const r: any = Promise.resolve({ data: null, error: erro });
          r.select = () => ({
            single: () => Promise.resolve({ data: { id: "os-nova", service_order_number: "ORÇ-00161", ...(criadaEm ? { created_at: criadaEm } : {}) }, error: null }),
          });
          return r;
        },
      };
      return q;
    },
  };
  return db;
}

const criar = serviceOrderTools.find((t) => t.name === "create_service_order")!;

Deno.test("create_service_order: as peças na ordem do pedido, com created_at em sequência a partir do da OS nova", async () => {
  const BASE = "2026-11-16T18:00:00.123456+00:00";
  const db = bancoDaCriacao(BASE);
  const r = await criar.execute(
    { client_id: "c1", vessel_id: "v1", items: [{ product_id: "pC", quantity: 1 }, { product_id: "pA", quantity: 2 }, { product_id: "pB", quantity: 3 }] },
    ctxCom(db),
  ) as Linha;
  assert(r.ok, JSON.stringify(r));
  const [, pecas] = db.insercoes.find(([t]) => t === "service_order_parts")!;
  assertEquals(pecas.map((p) => p.product_id), ["pC", "pA", "pB"]);
  assertEquals(pecas.map((p) => p.created_at), ["2026-11-16T18:00:00.124Z", "2026-11-16T18:00:00.125Z", "2026-11-16T18:00:00.126Z"]);
  for (const p of pecas) assert(chaveDoInstante(p.created_at)! > chaveDoInstante(BASE)!);
});

Deno.test("create_service_order: produto que não existe sai da lista e a sequência continua estritamente crescente", async () => {
  const db = bancoDaCriacao(null);
  const r = await criar.execute(
    { client_id: "c1", vessel_id: "v1", items: [{ product_id: "pB", quantity: 1 }, { product_id: "nao-existe", quantity: 1 }, { product_id: "pA", quantity: 1 }] },
    ctxCom(db),
  ) as Linha;
  assert(r.ok, JSON.stringify(r));
  const [, pecas] = db.insercoes.find(([t]) => t === "service_order_parts")!;
  assertEquals(pecas.map((p) => p.product_id), ["pB", "pA"]);
  assert(crescente(pecas.map((p) => p.created_at as string)));
});

Deno.test("create_service_order: o insert das peças falhou → nada sai do estoque e a resposta diz (antes: ok e estoque baixado)", async () => {
  const db = bancoDaCriacao("2026-11-16T18:00:00Z", "permission denied for table service_order_parts");
  const r = await criar.execute(
    { client_id: "c1", vessel_id: "v1", items: [{ product_id: "pA", quantity: 2 }] },
    ctxCom(db),
  ) as Linha;
  assert(!r.ok, JSON.stringify(r));
  assert(String(r.error).includes("ORÇ-00161 foi criado, mas as peças não foram gravadas (permission denied"), r.error);
  assertEquals(db.insercoes.filter(([t]) => t === "inventory_movements").length, 0);
  assertEquals(db.atualizacoes.filter(([t]) => t === "products").length, 0);
});

// NOVO-historico-05 (mesma classe da tela): a cópia levava o total líquido da linha e deixava o desconto dela para trás.
Deno.test("duplicar: o desconto de cada linha vai junto com o total líquido", async () => {
  const origem = origemEmbaralhada();
  origem.service_order_parts[0] = { ...origem.service_order_parts[0], quantity: 2, line_total_sale: 50, discount_pct: 16.67, discount_amount: 10 };
  origem.service_order_services[0] = { ...origem.service_order_services[0], line_total: 90, discount_pct: 10, discount_amount: 10 };
  const db = bancoDaCopia(origem, "2026-11-16T18:00:00Z");
  const r = await duplicar.execute({ service_order_id: "orc-1" }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  const [, pecas] = db.insercoes.find(([t]) => t === "service_order_parts")!;
  const [, servicos] = db.insercoes.find(([t]) => t === "service_order_services")!;
  const pecaC = pecas.find((p) => p.product_id === "pC")!;
  assertEquals([pecaC.line_total_sale, pecaC.discount_pct, pecaC.discount_amount], [50, 16.67, 10]);
  const teste = servicos.find((s) => s.name_snapshot === "Teste final")!;
  assertEquals([teste.line_total, teste.discount_pct, teste.discount_amount], [90, 10, 10]);
  // linha sem desconto na origem sai com 0, não com undefined
  assertEquals(pecas.find((p) => p.product_id === "pA")!.discount_amount, 0);
});

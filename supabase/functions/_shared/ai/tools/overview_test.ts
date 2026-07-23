import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { overviewTools } from "./overview.ts";

// Mock leve do client Supabase: um query-builder encadeável que ignora os filtros
// (.select/.in/.eq/.lt/.limit...) e resolve com as linhas "canned" da tabela. Serve para
// exercitar a lógica JS da macro (agregação, filtro por dias/expiração, ordenação,
// best-effort), que é o que pode quebrar — a filtragem SQL é responsabilidade do Postgres.
function chainable(data: unknown) {
  const result = { data, error: null };
  const proxy: any = new Proxy({}, {
    get(_t, prop) {
      if (prop === "then") {
        return (resolve: (v: unknown) => void, reject: (e: unknown) => void) =>
          data instanceof Error ? reject(data) : resolve(result);
      }
      return () => proxy; // qualquer método do query-builder devolve o mesmo proxy
    },
  });
  return proxy;
}

// canned[table] = linhas (objeto[]) OU sequência de datasets (objeto[][]) consumidos em
// ordem — necessário porque service_orders é consultado 2x (orçamentos parados, depois agenda).
function fakeAdmin(canned: Record<string, unknown>, rpc: Record<string, unknown> = {}) {
  const counters: Record<string, number> = {};
  return {
    from(table: string) {
      let data: any = canned[table] ?? [];
      if (Array.isArray(data) && Array.isArray(data[0])) {
        const i = counters[table] ?? 0;
        counters[table] = i + 1;
        data = data[Math.min(i, data.length - 1)];
      }
      return chainable(data);
    },
    rpc(name: string) {
      const v = rpc[name];
      if (v instanceof Error) return Promise.reject(v);
      return Promise.resolve({ data: v ?? [], error: null });
    },
  };
}

const tool = overviewTools.find((t) => t.name === "get_situation_overview")!;
const ctx = (admin: unknown, userRole = "admin") =>
  ({ sb: admin, admin, userId: "u1", userRole, jwt: "", appOrigin: "", settings: {} }) as any;

const ontem = new Date(Date.now() - 3 * 86400000).toISOString();
const agora = new Date().toISOString();

Deno.test("agrega totais e ordena o topo por maior saldo", async () => {
  const admin = fakeAdmin({
    receivables: [
      { amount: 100, balance_amount: 100, due_date: "2020-01-01", clients: { name: "A" } },
      { amount: 500, balance_amount: 500, due_date: "2020-01-01", clients: { name: "B" } },
      { amount: 9, balance_amount: 0, due_date: "2020-01-01", clients: { name: "C" } }, // saldo 0 → fora
    ],
    service_orders: [[], []],
    payables: [],
  });
  const out: any = await tool.execute({}, ctx(admin));
  assertEquals(out.cobrancas_vencidas.quantidade, 2);
  assertEquals(out.cobrancas_vencidas.total_em_atraso, 600);
  assertEquals(out.cobrancas_vencidas.topo[0].cliente, "B"); // maior saldo primeiro
});

Deno.test("orçamento entra por dias parado OU por expiração; recente e válido fica de fora", async () => {
  const quotes = [
    { service_order_number: "ORÇ-1", grand_total: 1000, updated_at: ontem, quote_validity_date: null, clients: { name: "A" } }, // parado 3d → entra
    { service_order_number: "ORÇ-2", grand_total: 2000, updated_at: agora, quote_validity_date: "2020-01-01", clients: { name: "B" } }, // recente mas expirado → entra
    { service_order_number: "ORÇ-3", grand_total: 3000, updated_at: agora, quote_validity_date: "2999-01-01", clients: { name: "C" } }, // recente e válido → fora
  ];
  const admin = fakeAdmin({ receivables: [], service_orders: [quotes, []], payables: [] });
  const out: any = await tool.execute({ stuck_days: 2 }, ctx(admin));
  assertEquals(out.orcamentos_parados.quantidade, 2);
  assertEquals(out.orcamentos_parados.valor_total, 3000); // 1000 + 2000
});

Deno.test("mensagens: clientes vêm antes de não-clientes no topo", async () => {
  const admin = fakeAdmin(
    { receivables: [], service_orders: [[], []], payables: [] },
    {
      whatsapp_pending_inbox: [
        { contato: "Fornecedor X", is_client: false, last_inbound_at: agora },
        { contato: "Cliente Y", is_client: true, last_inbound_at: agora },
      ],
    },
  );
  const out: any = await tool.execute({}, ctx(admin));
  assertEquals(out.mensagens_esperando.quantidade, 2);
  assertEquals(out.mensagens_esperando.de_clientes, 1);
  assertEquals(out.mensagens_esperando.topo[0].cliente, true); // cliente primeiro
});

Deno.test("técnico é bloqueado (defesa em profundidade)", async () => {
  const admin = fakeAdmin({});
  const out: any = await tool.execute({}, ctx(admin, "technician"));
  assertEquals(typeof out.error, "string");
});

Deno.test("best-effort: um bloco que falha não derruba os outros", async () => {
  const admin = fakeAdmin({
    receivables: new Error("boom"), // este bloco falha
    service_orders: [[], []],
    payables: [{ amount: 300, balance_amount: 300, due_date: "2020-01-01" }],
  });
  const out: any = await tool.execute({}, ctx(admin));
  assertEquals(typeof out.cobrancas_vencidas.erro, "string"); // falhou, mas capturado
  assertEquals(out.contas_a_pagar_7d.total, 300); // os outros seguem
});

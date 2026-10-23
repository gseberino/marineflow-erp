import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
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

Deno.test("expirado pela validade em DIAS (mesma conta do PDF), não só pela data fixa; aguardando sinal não expira", async () => {
  // Até 26/09/2026 só a data fixa contava, e ela quase nunca existe: nada aparecia expirado.
  const emitido40DiasAtras = new Date(Date.now() - 40 * 86400000).toISOString();
  const quotes = [
    { service_order_number: "ORÇ-4", grand_total: 4000, updated_at: agora, quote_status: "sent", created_at: emitido40DiasAtras, quote_validity_days: 7, quote_validity_date: null, clients: { name: "D" } },
    { service_order_number: "ORÇ-5", grand_total: 5000, updated_at: agora, quote_status: "awaiting_deposit", created_at: emitido40DiasAtras, quote_validity_days: 7, quote_validity_date: null, clients: { name: "E" } },
    { service_order_number: "ORÇ-6", grand_total: 6000, updated_at: agora, quote_status: "sent", created_at: agora, quote_validity_days: 7, quote_validity_date: null, clients: { name: "F" } },
  ];
  const admin = fakeAdmin({ receivables: [], service_orders: [quotes, []], payables: [] });
  const out: any = await tool.execute({ stuck_days: 2 }, ctx(admin));
  assertEquals(out.orcamentos_parados.topo.map((q: any) => q.numero), ["ORÇ-4"]);
  assertEquals(out.orcamentos_parados.topo[0].expirado, true);
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

// ───────── O dia de Brasília e a OS em curso (Agenda de Produção, Fase 0, 23/10/2026: D4/D6) ─────────
// A função roda em UTC: entre 21 h e meia-noite de Brasília, toISOString() já dava amanhã. A cobrança
// que vence HOJE aparecia "vencida", o "a pagar em 7 dias" andava um dia e a "agenda de hoje" lia o
// dia em UTC e só pela data de início — a OS que começou ontem e termina amanhã não aparecia.

/** Builder que GRAVA cada chamada (para conferir o filtro montado) e responde pela função dada. */
function adminQueGrava(responder: (tabela: string, chamadas: Array<[string, unknown[]]>) => unknown[]) {
  const porTabela: Record<string, Array<Array<[string, unknown[]]>>> = {};
  return {
    porTabela,
    admin: {
      from(tabela: string) {
        const chamadas: Array<[string, unknown[]]> = [];
        (porTabela[tabela] ??= []).push(chamadas);
        const b: Record<string, unknown> = {};
        for (const m of ["select", "eq", "neq", "in", "not", "lt", "lte", "gt", "gte", "or", "order", "limit", "range"]) {
          b[m] = (...a: unknown[]) => { chamadas.push([m, a]); return b; };
        }
        b.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: responder(tabela, chamadas), error: null }).then(ok);
        return b;
      },
      rpc: () => Promise.resolve({ data: [], error: null }),
    },
  };
}

const usou = (chamadas: Array<[string, unknown[]]>, metodo: string) => chamadas.filter(([m]) => m === metodo).map(([, a]) => a);

Deno.test("às 22:00 de Brasília, 'vencidas' e 'a pagar 7 d' usam o dia de HOJE em Brasília", async () => {
  // 23/10/2026 22:00 em Brasília = 24/10 01:00 UTC.
  const relogio = new FakeTime(new Date("2026-10-24T01:00:00Z"));
  try {
    const { admin, porTabela } = adminQueGrava((tabela) =>
      tabela === "receivables"
        ? [{ amount: 100, balance_amount: 100, due_date: "2026-10-22", client_id: null, clients: { name: "A" } }]
        : []
    );
    const out: any = await tool.execute({}, ctx(admin));
    assertEquals(out.data, "2026-10-23");
    assertEquals(usou(porTabela.receivables[0], "lt"), [["due_date", "2026-10-23"]]);
    // Venceu ontem (22/10): 1 dia de atraso, não 2.
    assertEquals(out.cobrancas_vencidas.topo[0].dias_atraso, 1);
    assertEquals(usou(porTabela.payables[0], "lte"), [["due_date", "2026-10-30"]]);
  } finally {
    relogio.restore();
  }
});

Deno.test("a agenda de hoje inclui a OS em curso (começou ontem, termina amanhã), pelo dia de Brasília", async () => {
  const relogio = new FakeTime(new Date("2026-10-24T01:00:00Z"));
  try {
    const emCurso = {
      service_order_number: "OS-00104", status: "in_progress", clients: { name: "Nelson" },
      scheduled_start_at: "2026-10-22T11:00:00.000Z", scheduled_end_at: "2026-10-24T21:00:00.000Z",
    };
    // Só a leitura da agenda (a que usa o .or da interseção) devolve a OS.
    const { admin, porTabela } = adminQueGrava((tabela, chamadas) =>
      tabela === "service_orders" && usou(chamadas, "or").length ? [emCurso] : []
    );
    const out: any = await tool.execute({}, ctx(admin));
    const leituraDaAgenda = porTabela.service_orders.find((c) => usou(c, "or").length)!;
    assertEquals(usou(leituraDaAgenda, "lt"), [["scheduled_start_at", "2026-10-24T03:00:00.000Z"]]);
    assertEquals(usou(leituraDaAgenda, "or"), [[
      "scheduled_end_at.gt.2026-10-23T03:00:00.000Z,and(scheduled_end_at.is.null,scheduled_start_at.gte.2026-10-23T03:00:00.000Z)",
    ]]);
    assertEquals(usou(leituraDaAgenda, "gte"), []);
    assertEquals(out.agenda_hoje.quantidade, 1);
    assertEquals(out.agenda_hoje.itens[0].numero, "OS-00104");
    assertEquals(out.agenda_hoje.itens[0].fim, "2026-10-24T21:00:00.000Z");
    assertEquals(out.agenda_hoje.itens[0].em_curso_desde_antes_de_hoje, true);
  } finally {
    relogio.restore();
  }
});

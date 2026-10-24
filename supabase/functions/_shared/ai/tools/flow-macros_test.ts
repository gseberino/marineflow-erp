import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { flowMacroTools } from "./flow-macros.ts";

// Mock encadeável: ignora filtros; .maybeSingle()/.single() devolvem a 1ª linha (ou null);
// senão devolve o array. Data === Error faz o await rejeitar (para testar best-effort).
function chainable(data: unknown) {
  const state = { single: false };
  const proxy: any = new Proxy({}, {
    get(_t, prop) {
      if (prop === "then") {
        return (resolve: (v: unknown) => void, reject: (e: unknown) => void) => {
          if (data instanceof Error) return reject(data);
          if (state.single) {
            const arr = Array.isArray(data) ? data : [data];
            return resolve({ data: arr.length ? arr[0] : null, error: null });
          }
          return resolve({ data, error: null });
        };
      }
      if (prop === "single" || prop === "maybeSingle") return () => { state.single = true; return proxy; };
      return () => proxy;
    },
  });
  return proxy;
}

function fakeClient(canned: Record<string, unknown>, rpc: Record<string, unknown> = {}) {
  const counters: Record<string, number> = {};
  return {
    from(table: string) {
      let data: any = canned[table] ?? [];
      if (Array.isArray(data) && Array.isArray(data[0])) { // sequência de datasets por chamada
        const i = counters[table] ?? 0; counters[table] = i + 1;
        data = data[Math.min(i, data.length - 1)];
      }
      return chainable(data);
    },
    rpc(name: string) {
      const v: any = rpc[name];
      if (v && typeof v === "object" && "__rpcError" in v) return Promise.resolve({ data: null, error: { message: v.__rpcError } });
      return Promise.resolve({ data: v ?? null, error: null });
    },
  };
}

const ctx = (client: unknown, userRole = "admin") =>
  ({ sb: client, admin: client, userId: "u1", userRole, jwt: "jwt", appOrigin: "", settings: {} }) as any;

const bulk = flowMacroTools.find((t) => t.name === "send_bulk_collection_reminders")!;
const approve = flowMacroTools.find((t) => t.name === "approve_quote_full")!;

const hojeISO = new Date().toISOString();

// ───────── send_bulk_collection_reminders ─────────

Deno.test("batch: envia para quem não foi cobrado hoje", async () => {
  const origFetch = globalThis.fetch;
  globalThis.fetch = () => Promise.resolve({ ok: true, json: () => Promise.resolve({ messageId: "m1" }) } as any);
  try {
    const client = fakeClient({
      collections: [{ id: "c1", amount: 500, due_date: "2020-01-01", contact_whatsapp: "5547999", contact_name: "Ana", last_auto_sent_at: null }],
    });
    const out: any = await bulk.execute({ collection_ids: ["c1"] }, ctx(client));
    assertEquals(out.enviados, 1);
    assertEquals(out.falhas, 0);
    assertEquals(out.pulados, 0);
  } finally {
    globalThis.fetch = origFetch;
  }
});

Deno.test("batch: pula quem já foi cobrado hoje (sem enviar)", async () => {
  const client = fakeClient({
    collections: [{ id: "c1", amount: 500, due_date: "2020-01-01", contact_whatsapp: "5547999", contact_name: "Ana", last_auto_sent_at: hojeISO }],
  });
  const out: any = await bulk.execute({ collection_ids: ["c1"] }, ctx(client));
  assertEquals(out.pulados, 1);
  assertEquals(out.enviados, 0);
});

Deno.test("batch: sem telefone vira falha (não derruba o lote)", async () => {
  const client = fakeClient({
    collections: [{ id: "c1", amount: 500, due_date: "2020-01-01", contact_whatsapp: null, phone: null, contact_name: "Ana", client_id: "x", last_auto_sent_at: null }],
    clients: [{ whatsapp: null, phone: null }],
  });
  const out: any = await bulk.execute({ collection_ids: ["c1"] }, ctx(client));
  assertEquals(out.falhas, 1);
  assertEquals(out.enviados, 0);
});

Deno.test("batch: técnico é bloqueado", async () => {
  const out: any = await bulk.execute({ collection_ids: ["c1"] }, ctx(fakeClient({}), "technician"));
  assertEquals(typeof out.error, "string");
});

Deno.test("batch: lista vazia retorna erro claro", async () => {
  const out: any = await bulk.execute({ collection_ids: [] }, ctx(fakeClient({})));
  assertEquals(typeof out.error, "string");
});

// ───────── approve_quote_full ─────────

Deno.test("approve: fluxo completo (sinal+conversão, follow-up, agendamento) todos ✔", async () => {
  const client = fakeClient(
    {
      service_orders: [{ service_order_number: "OS-1", client_id: "c1", status: "open" }],
      app_users: [{ phone_normalized: "5547999", full_name: "Guga Seb" }],
      whatsapp_scheduled_sends: [],
      service_order_technicians: [],
    },
    { register_deposit_and_convert: { converted: true } },
  );
  const out: any = await approve.execute(
    { service_order_id: "so1", deposit_amount: 1000, payment_date: "2026-07-22", payment_method: "pix", follow_up_in_days: 3, scheduled_start_at: "2026-07-25T09:00:00", technician_user_id: "t1" },
    ctx(client),
  );
  assertEquals(out.ok, true);
  assertEquals(out.passos.every((p: any) => p.status === "✔"), true);
  assertEquals(out.passos.length, 3);
});

Deno.test("approve: se a conversão falha, para e não agenda nada", async () => {
  const client = fakeClient(
    { service_orders: [{ service_order_number: "OS-1" }] },
    { register_deposit_and_convert: { __rpcError: "saldo insuficiente" } },
  );
  const out: any = await approve.execute(
    { service_order_id: "so1", deposit_amount: 1000, payment_date: "2026-07-22", payment_method: "pix", follow_up_in_days: 3, scheduled_start_at: "2026-07-25T09:00:00" },
    ctx(client),
  );
  assertEquals(out.ok, false);
  assertEquals(out.passos.length, 1);
  assertEquals(out.passos[0].status, "✖");
});

Deno.test("approve: follow-up sem telefone do dono vira ✖, mas a conversão fica ✔ (report-only)", async () => {
  const client = fakeClient(
    {
      service_orders: [{ service_order_number: "OS-1", client_id: "c1" }],
      app_users: [{ phone_normalized: null, full_name: "Guga" }],
    },
    { register_deposit_and_convert: { converted: true } },
  );
  const out: any = await approve.execute(
    { service_order_id: "so1", deposit_amount: 1000, payment_date: "2026-07-22", payment_method: "pix", follow_up_in_days: 2 },
    ctx(client),
  );
  assertEquals(out.ok, true);
  assertEquals(out.passos[0].status, "✔"); // conversão ok
  assertEquals(out.passos[1].status, "✖"); // follow-up falhou, mas não desfez nada
});

Deno.test("approve: técnico é bloqueado", async () => {
  const out: any = await approve.execute(
    { service_order_id: "so1", deposit_amount: 1000, payment_date: "2026-07-22", payment_method: "pix" },
    ctx(fakeClient({}), "technician"),
  );
  assertEquals(typeof out.error, "string");
});

// ───────── approve_quote_full, passo 3 (Agenda de Produção, Fase 0, 23/10/2026: D8/D8b) ─────────
// O passo forçava 'scheduled' só com técnico (sem técnico, a OS convertida 'open' ficava sem
// status de agendada) e vinculava o técnico com `.upsert(...).catch(() => null)` — o builder do
// PostgREST não tem .catch: a linha lançava TypeError com o status já gravado e o passo saía ✖.
// O banco falso daqui grava as chamadas e, como o real, NÃO tem .catch.

// Fase 2 (P4, 24/10/2026): o status não vai mais no update — vai pela porta única do banco
// (os_transicionar_status, via 'aprovacao'); com a agenda automática ligada, a data também não: é
// agenda_marcar_os (via 'aprovacao'). O passo leva a frase da porta ou da agenda, ✔ ou ✖, nunca calado.

function bancoQueGrava(
  statusDepoisDaConversao: string,
  erroNoVinculo: string | null = null,
  /** a releitura da OS depois da conversão falha (erro) ou não acha a linha (null) */
  releitura: "ok" | "erro" | "vazia" = "ok",
  /** agenda_config.modo_proposta e as respostas da porta e de agenda_marcar_os */
  agenda: { modo?: string; porta?: Record<string, unknown>; erroPorta?: string; marcar?: Record<string, unknown> } = {},
) {
  const updates: Record<string, unknown>[] = [];
  const upserts: Record<string, unknown>[] = [];
  const builders: Record<string, unknown>[] = [];
  const rpcs: Array<{ nome: string; params: Record<string, unknown> }> = [];
  const from = (tabela: string) => {
    let upd: Record<string, unknown> | null = null;
    let ups: Record<string, unknown> | null = null;
    let colunas = "";
    const b: Record<string, unknown> = {};
    for (const m of ["eq", "in", "neq", "order", "limit", "maybeSingle", "single", "insert"]) b[m] = () => b;
    b.select = (c?: string) => { colunas = c ?? ""; return b; };
    b.update = (p: Record<string, unknown>) => { upd = p; updates.push(p); return b; };
    b.upsert = (p: Record<string, unknown>) => { ups = p; upserts.push(p); return b; };
    b.then = (ok: (v: unknown) => unknown) => {
      if (tabela === "agenda_config") return Promise.resolve({ data: { modo_proposta: agenda.modo ?? "desligado" }, error: null }).then(ok);
      if (tabela === "payees") return Promise.resolve({ data: [{ id: "payee-t1" }], error: null }).then(ok);
      if (ups && erroNoVinculo) return Promise.resolve({ data: null, error: { message: erroNoVinculo } }).then(ok);
      if (tabela === "service_orders" && !upd) {
        // Só a releitura de depois da conversão (a que traz o status) falha; a leitura do saldo, antes, não.
        const ehAReleitura = colunas.includes("status");
        if (ehAReleitura && releitura === "erro") return Promise.resolve({ data: null, error: { message: "canceling statement due to statement timeout" } }).then(ok);
        if (ehAReleitura && releitura === "vazia") return Promise.resolve({ data: null, error: null }).then(ok);
        return Promise.resolve({ data: { service_order_number: "OS-00120", client_id: "c1", status: statusDepoisDaConversao }, error: null }).then(ok);
      }
      return Promise.resolve({ data: tabela === "service_orders" ? null : [], error: null }).then(ok);
    };
    builders.push(b);
    return b;
  };
  const client = {
    from,
    rpc: (nome: string, params: Record<string, unknown>) => {
      rpcs.push({ nome, params });
      if (nome === "os_transicionar_status") {
        if (agenda.erroPorta) return Promise.resolve({ data: null, error: { message: agenda.erroPorta } });
        return Promise.resolve({
          data: agenda.porta ?? { ok: true, mudou: true, de: statusDepoisDaConversao, para: "scheduled", texto: "OS-00120: de aberta para agendada." },
          error: null,
        });
      }
      if (nome === "agenda_marcar_os") {
        return Promise.resolve({ data: agenda.marcar ?? { ok: true, texto: "Mudei: OS-00120: ter 27/10, Roberto o dia todo." }, error: null });
      }
      return Promise.resolve({ data: { converted: true }, error: null });
    },
  };
  return { client, updates, upserts, builders, rpcs };
}

const daPorta = (b: { rpcs: Array<{ nome: string; params: Record<string, unknown> }> }) =>
  b.rpcs.filter((r) => r.nome === "os_transicionar_status").map((r) => r.params);

const pedido = (extra: Record<string, unknown>) => ({
  service_order_id: "so1", deposit_amount: 1000, payment_date: "2026-10-23", payment_method: "pix",
  scheduled_start_at: "2026-10-27T08:00:00", ...extra,
});

const agendamento = (out: any) => out.passos.find((p: any) => p.passo === "agendamento");

Deno.test("approve: OS convertida 'open' vira Agendada no passo 3 pela porta (via aprovacao), mesmo sem técnico", async () => {
  const b = bancoQueGrava("open");
  const out: any = await approve.execute(pedido({}), ctx(b.client));
  assertEquals(agendamento(out).status, "✔");
  assertEquals(agendamento(out).status_da_os, "scheduled");
  const upd = b.updates.find((u) => "scheduled_start_at" in u)!;
  assertEquals("status" in upd, false, "o status não vai no update: quem decide é a porta");
  assertEquals(upd.scheduled_start_at, "2026-10-27T08:00:00-03:00");
  assertEquals(daPorta(b), [{ p_os: "so1", p_para: "scheduled", p_via: "aprovacao", p_autor: "u1" }]);
  assertEquals(b.upserts, []);
});

Deno.test("approve: o status relido depois da conversão manda — OS aguardando peça não regride (a porta diz por quê)", async () => {
  const b = bancoQueGrava("awaiting_parts", null, "ok", {
    porta: { ok: true, mudou: false, de: "awaiting_parts", para: "awaiting_parts", texto: "Ainda falta \"Cabo\" na mão: a OS continua aguardando peças." },
  });
  const out: any = await approve.execute(pedido({ technician_user_id: "t1" }), ctx(b.client));
  const passo = agendamento(out);
  assertEquals(passo.status, "✔");
  assertEquals(passo.status_da_os, "awaiting_parts");
  assertEquals(passo.texto, "Ainda falta \"Cabo\" na mão: a OS continua aguardando peças.");
  const upd = b.updates.find((u) => "scheduled_start_at" in u)!;
  assertEquals("status" in upd, false);
});

Deno.test("approve: erro da porta → passo ✖ que diz que a data ficou e o status não (nunca ✔ calado)", async () => {
  const b = bancoQueGrava("open", null, "ok", { erroPorta: "Você não pode mudar o status desta OS." });
  const out: any = await approve.execute(pedido({}), ctx(b.client));
  const passo = agendamento(out);
  assertEquals(passo.status, "✖");
  assertEquals(passo.erro, "a data foi gravada, mas o status não mudou: Você não pode mudar o status desta OS.");
  assertEquals(out.passos[0].status, "✔");
});

Deno.test("approve com a agenda automática ligada: agenda_marcar_os (via aprovacao, o dia de Brasília), nenhum update nem porta", async () => {
  const b = bancoQueGrava("open", null, "ok", { modo: "ligado" });
  const out: any = await approve.execute(pedido({ technician_user_id: "t1" }), ctx(b.client));
  const passo = agendamento(out);
  assertEquals(passo.status, "✔");
  assertEquals(passo.agenda, "Mudei: OS-00120: ter 27/10, Roberto o dia todo.");
  assertEquals(b.updates.filter((u) => "scheduled_start_at" in u), []);
  assertEquals(daPorta(b), []);
  assertEquals(b.rpcs.filter((r) => r.nome === "agenda_marcar_os").map((r) => r.params), [{
    p_autor: "u1", p_os: "so1", p_de: "2026-10-27", p_ate: "2026-10-27", p_pessoa: "payee-t1", p_via: "aprovacao",
  }]);
});

Deno.test("approve com a agenda automática ligada: não cabe → passo ✖ com a frase da agenda", async () => {
  const b = bancoQueGrava("open", null, "ok", {
    modo: "ligado", marcar: { ok: false, texto: "Não cabe ter 27/10: o Roberto já está no Vanderlei. O primeiro dia que dá é qua 28/10." },
  });
  const out: any = await approve.execute(pedido({}), ctx(b.client));
  const passo = agendamento(out);
  assertEquals(passo.status, "✖");
  assertEquals(passo.erro, "Não cabe ter 27/10: o Roberto já está no Vanderlei. O primeiro dia que dá é qua 28/10.");
  assertEquals(b.upserts, []);
});

Deno.test("approve: erro ao vincular o técnico → passo ✔ com aviso (sem TypeError; builder sem .catch)", async () => {
  const b = bancoQueGrava("open", "duplicate key value violates unique constraint");
  const out: any = await approve.execute(pedido({ technician_user_id: "t1" }), ctx(b.client));
  assertEquals(b.builders.every((x) => typeof x.catch === "undefined"), true);
  assertEquals(b.upserts, [{ service_order_id: "so1", user_id: "t1" }]);
  const passo = agendamento(out);
  assertEquals(passo.status, "✔");
  assertEquals(passo.status_da_os, "scheduled");
  assertEquals(String(passo.aviso).includes("técnico não ficou vinculado"), true);
  assertEquals(out.ok, true);
});

// Revisão de 23/10/2026: a releitura da OS depois da conversão engolia o erro. Sem o status,
// statusAoAgendar('') dava null: a data era gravada, a OS ficava 'open' e o passo saía ✔ calado — e
// na rodada seguinte a R1 fechava a tarefa com "OS foi agendada" com a OS ainda Aberta.
for (const releitura of ["erro", "vazia"] as const) {
  Deno.test(`approve: releitura da OS ${releitura === "erro" ? "com erro" : "sem linha"} → agendamento ✖, nada gravado, conversão ✔`, async () => {
    const b = bancoQueGrava("open", null, releitura);
    const out: any = await approve.execute(pedido({ technician_user_id: "t1" }), ctx(b.client));
    const passo = agendamento(out);
    assertEquals(passo.status, "✖");
    assertEquals(String(passo.erro).includes("não consegui ler o status da OS depois da conversão"), true);
    assertEquals(b.updates.filter((u) => "scheduled_start_at" in u), []);
    assertEquals(b.upserts, []);
    assertEquals(out.passos[0].status, "✔"); // a conversão ficou (report-only)
    assertEquals(out.ok, true);
  });
}

Deno.test("approve: sem data pedida, a releitura com erro não inventa passo de agendamento", async () => {
  const b = bancoQueGrava("open", null, "erro");
  const out: any = await approve.execute(pedido({ scheduled_start_at: undefined }), ctx(b.client));
  assertEquals(agendamento(out), undefined);
  assertEquals(out.passos.map((p: any) => p.status), ["✔"]);
});

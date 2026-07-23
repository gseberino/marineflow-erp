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
      service_orders: [{ service_order_number: "OS-1", client_id: "c1" }],
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

import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { donoDoWhatsApp } from "./dono.ts";

function adminCom(resposta: { data: unknown; error?: unknown }) {
  const passos: Array<[string, ...unknown[]]> = [];
  const q: Record<string, unknown> = {};
  for (const m of ["select", "eq", "not", "order", "limit"]) {
    q[m] = (...args: unknown[]) => { passos.push([m, ...args]); return q; };
  }
  q.then = (ok: (v: unknown) => unknown, falha?: (e: unknown) => unknown) =>
    Promise.resolve({ error: null, ...resposta }).then(ok, falha);
  return {
    passos,
    admin: { from: (t: string) => { passos.push(["from", t]); return q; } },
  };
}

Deno.test("donoDoWhatsApp: a regra do lembretes-de-revisao (admin ativo, WhatsApp, telefone, mais antigo)", async () => {
  const { admin, passos } = adminCom({ data: [{ id: "u-1", phone_normalized: "5547999990000" }] });
  assertEquals(await donoDoWhatsApp(admin), { id: "u-1", phone: "5547999990000" });
  assertEquals(passos, [
    ["from", "app_users"],
    ["select", "id, phone_normalized"],
    ["eq", "role", "admin"],
    ["eq", "active", true],
    ["eq", "ai_whatsapp_enabled", true],
    ["not", "phone_normalized", "is", null],
    ["order", "created_at", { ascending: true }],
    ["limit", 1],
  ]);
});

Deno.test("donoDoWhatsApp: sem admin habilitado = null", async () => {
  assertEquals(await donoDoWhatsApp(adminCom({ data: [] }).admin), null);
  assertEquals(await donoDoWhatsApp(adminCom({ data: null }).admin), null);
});

Deno.test("donoDoWhatsApp: erro de leitura lança", async () => {
  await assertRejects(() => donoDoWhatsApp(adminCom({ data: null, error: { message: "timeout" } }).admin), Error, "timeout");
});

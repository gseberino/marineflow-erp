// Número da OS no lugar do uuid (11/10/2026). O dono fala "ORÇ-00112"; ~46 tools só aceitavam o
// uuid e respondiam "invalid input syntax for type uuid" (get_service_order 5x em 30 dias, com
// ORÇ-00107, ORÇ-00112 e ORÇ-00113; add_material_to_order com ORÇ-00103). A troca fica num ponto
// só — executarChamadaDeTool — pelo mesmo acharOS das tools que já entendiam o número.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { trocarNumeroDaOsPeloId } from "./os-referencia.ts";
import { executarChamadaDeTool } from "../agent.ts";
import { serviceOrderTools } from "./service-orders.ts";

const UUID_ORC = "11111111-1111-4111-8111-111111111112";
const UUID_OS = "22222222-2222-4222-8222-222222222112";

/** service_orders mínimo para localizarOrdem: .select().in("service_order_number", candidatos). */
function sbComOrdens(ordens: { id: string; service_order_number: string; status: string }[]) {
  const consultas: unknown[] = [];
  const sb = {
    from: (_t: string) => ({
      select: () => ({
        in: (_c: string, vals: string[]) => {
          consultas.push(vals);
          return Promise.resolve({ data: ordens.filter((o) => vals.includes(o.service_order_number)), error: null });
        },
      }),
    }),
  };
  return { sb, consultas };
}
const ORC_112 = { id: UUID_ORC, service_order_number: "ORÇ-00112", status: "draft" };
const OS_112 = { id: UUID_OS, service_order_number: "OS-00112", status: "open" };

Deno.test("ORÇ-00112 no id do get_service_order vira o uuid", async () => {
  const { sb } = sbComOrdens([ORC_112, OS_112]);
  assertEquals(await trocarNumeroDaOsPeloId("get_service_order", { id: "ORÇ-00112" }, sb), { input: { id: UUID_ORC } });
});

Deno.test("service_order_id, linked_service_order_id e os_id: número vira uuid em qualquer tool", async () => {
  const { sb } = sbComOrdens([ORC_112, OS_112]);
  assertEquals(
    await trocarNumeroDaOsPeloId("add_material_to_order", { service_order_id: "OS-00112", quantity: 2 }, sb),
    { input: { service_order_id: UUID_OS, quantity: 2 } },
  );
  assertEquals(await trocarNumeroDaOsPeloId("create_payable", { linked_service_order_id: "os 112" }, sb), { input: { linked_service_order_id: UUID_OS } });
  assertEquals(await trocarNumeroDaOsPeloId("consultar_comprovantes", { os_id: "orc 112" }, sb), { input: { os_id: UUID_ORC } });
});

Deno.test("'112' que existe como ORÇ e como OS volta erro com as opções, sem trocar nada", async () => {
  const { sb } = sbComOrdens([ORC_112, OS_112]);
  const r = await trocarNumeroDaOsPeloId("add_material_to_order", { service_order_id: "112" }, sb) as { error: string; opcoes?: string[] };
  assert(r.error.includes("ORÇ-00112") && r.error.includes("OS-00112"), r.error);
  assertEquals(r.opcoes, ["ORÇ-00112", "OS-00112"]);
});

Deno.test("número que não existe volta erro (não segue para a tool)", async () => {
  const { sb } = sbComOrdens([]);
  const r = await trocarNumeroDaOsPeloId("get_service_order", { id: "ORÇ-00999" }, sb) as { error: string };
  assert(r.error.includes("ORÇ-00999"), r.error);
});

Deno.test("uuid, 'ultimo', texto sem número e o id de outras tools ficam como estão, sem consultar", async () => {
  const { sb, consultas } = sbComOrdens([ORC_112, OS_112]);
  const casos: [string, Record<string, unknown>][] = [
    ["get_service_order", { id: UUID_OS }],
    ["add_material_to_order", { service_order_id: "ultimo" }],
    ["add_material_to_order", { service_order_id: "a OS do barco 2" }],
    ["update_task", { id: "112" }],
    ["get_service_order", {}],
  ];
  for (const [tool, input] of casos) {
    const r = await trocarNumeroDaOsPeloId(tool, input, sb) as { input: unknown };
    assertEquals(r.input, input, `${tool} ${JSON.stringify(input)}`);
  }
  assertEquals(consultas, []);
});

Deno.test("executarChamadaDeTool: get_service_order com ORÇ-00112 chega ao execute com o uuid", async () => {
  const recebidos: unknown[] = [];
  const real = serviceOrderTools.find((t) => t.name === "get_service_order")!;
  const falsa = { ...real, execute: async (args: unknown) => (recebidos.push(args), { ok: true }) };
  const { sb } = sbComOrdens([ORC_112, OS_112]);
  const auditoria: any[] = [];
  const admin = { from: () => ({ insert: (row: unknown) => (auditoria.push(row), Promise.resolve({ data: null, error: null })) }) };
  const amb = {
    toolsByName: { get_service_order: falsa },
    alcancaveisPelaRede: {},
    toolCtx: { sb, admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} },
    sessionId: "s1",
  } as any;
  const r = await executarChamadaDeTool({ name: "get_service_order", input: { id: "ORÇ-00112" } }, amb);
  assertEquals(r.toolResult, { ok: true });
  assertEquals(recebidos, [{ id: UUID_ORC }]);

  // Ambíguo: nada roda e o modelo recebe as opções.
  const amb2 = { ...amb, toolCtx: { ...amb.toolCtx } };
  const r2 = await executarChamadaDeTool({ name: "get_service_order", input: { id: "112" } }, amb2);
  assertEquals((r2.toolResult as any).opcoes, ["ORÇ-00112", "OS-00112"]);
  assertEquals(recebidos.length, 1);
});

Deno.test("get_service_order: cada peça traz o product_id (para o histórico de preço), além do item_id", async () => {
  const real = serviceOrderTools.find((t) => t.name === "get_service_order")!;
  const selects: Record<string, string> = {};
  const linhas: Record<string, unknown> = {
    service_orders: { id: UUID_OS, service_order_number: "OS-00112", clients: { name: "C" }, vessels: { name: "B" } },
    service_order_parts: [{ id: "item-1", product_id: "prod-1", quantity: 1, line_total_sale: 10, products: { name: "Bomba" } }],
    service_order_services: [],
    service_order_steps: [],
  };
  const sb = {
    from: (t: string) => {
      const result = { data: linhas[t] ?? [], error: null };
      const p: any = new Proxy({}, {
        get(_x, prop) {
          if (prop === "then") return (ok: (v: unknown) => unknown) => Promise.resolve(result).then(ok);
          if (prop === "maybeSingle") return () => Promise.resolve(result);
          if (prop === "select") return (s: string) => ((selects[t] = s), p);
          return () => p;
        },
      });
      return p;
    },
  };
  const r = await real.execute({ id: UUID_OS }, { sb, admin: sb, userId: "u1", userRole: "admin", settings: {} } as never) as any;
  assert(selects.service_order_parts.includes("product_id"), selects.service_order_parts);
  assertEquals(r.parts[0].item_id, "item-1");
  assertEquals(r.parts[0].product_id, "prod-1");
});

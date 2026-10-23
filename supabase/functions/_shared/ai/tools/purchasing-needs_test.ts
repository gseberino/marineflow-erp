// get_purchase_needs e o que vem a caminho (Agenda de Produção, Fase 0, P5 — 24/10/2026).
//
// A RPC get_os_purchase_needs passou a anexar em `items` o que foi pedido em OC de texto livre da
// própria OS e ainda não chegou (origin 'purchase_order', shortage 0). O que estes testes protegem:
//  1. o `a_caminho` sai da resposta da RPC, com o número da OC;
//  2. `faltando`, `itens_em_falta`, `precisa_comprar` e `custo_estimado` NÃO mudam por causa dele;
//  3. a descrição da tool diz que a_caminho não é "na mão" (tool registrada ≠ tool ensinada);
//  4. erro da RPC lança (não vira "nada a comprar").
import { assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { purchasingTools } from "./purchasing.ts";

const tool = purchasingTools.find((t) => t.name === "get_purchase_needs")!;
const OS_00104 = "00000000-0000-0000-0000-000000000104";

function ctxCom(resposta: { data: unknown; error: unknown }) {
  const chamadas: Array<{ nome: string; args: unknown }> = [];
  const sb = {
    rpc: (nome: string, args: unknown) => {
      chamadas.push({ nome, args });
      return Promise.resolve(resposta);
    },
  };
  // deno-lint-ignore no-explicit-any
  const ctx: any = { sb, admin: sb, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} };
  return { ctx, chamadas };
}

/** O formato que a RPC devolve para a OS-00104 depois das migrations 150100/150200 (f23, 23/10/2026). */
const OS104_DEPOIS = {
  serviceOrderId: OS_00104,
  items: [{
    sourceId: "poi-1", origin: "purchase_order", productId: null,
    description: "Compressor 12V de geladeira SS65", unit: null, required: 1,
    available: 0, onOrder: 1, shortage: 0, status: "on_order", unitCost: 0, purchaseOrderNumber: "OC-00004",
  }],
  shortages: [],
  shortageCount: 0,
  estimatedCost: 0,
  needsPurchase: false,
};

Deno.test("get_purchase_needs: o item a caminho sai em a_caminho, com a OC", async () => {
  const { ctx, chamadas } = ctxCom({ data: OS104_DEPOIS, error: null });
  // deno-lint-ignore no-explicit-any
  const r: any = await tool.execute({ service_order_id: OS_00104 }, ctx);
  assertEquals(chamadas, [{ nome: "get_os_purchase_needs", args: { p_so_id: OS_00104 } }]);
  assertEquals(r.a_caminho, [{ descricao: "Compressor 12V de geladeira SS65", quantidade: 1, ordem_de_compra: "OC-00004" }]);
  assertEquals(r.todos_os_itens, 1);
});

Deno.test("get_purchase_needs: a_caminho não mexe em faltando, contagem, custo nem precisa_comprar", async () => {
  const peca = {
    sourceId: "sop-1", origin: "part", productId: "p1", description: "Fusível MIDI 100A", unit: "un",
    required: 2, available: 0, onOrder: 0, shortage: 2, status: "missing", unitCost: 30,
  };
  const caminho = OS104_DEPOIS.items[0];
  const semCaminho = { ...OS104_DEPOIS, items: [peca], shortages: [peca], shortageCount: 1, estimatedCost: 60, needsPurchase: true };
  const comCaminho = { ...semCaminho, items: [peca, caminho] };

  // deno-lint-ignore no-explicit-any
  const sem: any = await tool.execute({ service_order_id: OS_00104 }, ctxCom({ data: semCaminho, error: null }).ctx);
  // deno-lint-ignore no-explicit-any
  const com: any = await tool.execute({ service_order_id: OS_00104 }, ctxCom({ data: comCaminho, error: null }).ctx);

  assertEquals(com.faltando, sem.faltando);
  assertEquals(com.itens_em_falta, 1);
  assertEquals(com.precisa_comprar, true);
  assertEquals(com.custo_estimado, 60);
  assertEquals(sem.a_caminho, []);
  assertEquals(com.a_caminho.length, 1);
});

Deno.test("get_purchase_needs: OS-00104 depois do P5 não precisa comprar, mas tem o compressor a caminho", async () => {
  // deno-lint-ignore no-explicit-any
  const r: any = await tool.execute({ service_order_id: OS_00104 }, ctxCom({ data: OS104_DEPOIS, error: null }).ctx);
  assertEquals(r.precisa_comprar, false);
  assertEquals(r.itens_em_falta, 0);
  assertEquals(r.faltando, []);
  assertEquals(r.a_caminho[0].ordem_de_compra, "OC-00004");
});

Deno.test("get_purchase_needs: peça do catálogo já pedida não entra em a_caminho (só texto livre de OC da OS)", async () => {
  const pedida = {
    sourceId: "sop-2", origin: "part", productId: "p2", description: "Cerbo GX", unit: "un",
    required: 1, available: 0, onOrder: 1, shortage: 0, status: "on_order", unitCost: 1500,
  };
  const data = { ...OS104_DEPOIS, items: [pedida] };
  // deno-lint-ignore no-explicit-any
  const r: any = await tool.execute({ service_order_id: OS_00104 }, ctxCom({ data, error: null }).ctx);
  assertEquals(r.a_caminho, []);
});

Deno.test("get_purchase_needs: a descrição ensina que a_caminho não é 'na mão'", () => {
  assertStringIncludes(tool.description, "a_caminho");
  assertStringIncludes(tool.description, "NÃO quer dizer que está na mão");
  assertStringIncludes(tool.description, "pergunte se chegou");
});

Deno.test("get_purchase_needs: erro da RPC lança (não vira 'nada a comprar')", async () => {
  await assertRejects(
    () => tool.execute({ service_order_id: OS_00104 }, ctxCom({ data: null, error: { message: "relation v_oc_itens_a_caminho does not exist" } }).ctx),
  );
});

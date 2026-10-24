// get_purchase_needs e o que vem a caminho (Agenda de Produção, Fase 0, P5 — 24/10/2026).
//
// A RPC get_os_purchase_needs passou a anexar em `items` o que foi pedido em OC de texto livre da
// própria OS e ainda não chegou (origin 'purchase_order', shortage 0). O que estes testes protegem:
//  1. o `a_caminho` sai da resposta da RPC, com o número da OC;
//  2. `faltando`, `itens_em_falta`, `precisa_comprar` e `custo_estimado` NÃO mudam por causa dele;
//  3. a descrição da tool diz que a_caminho não é "na mão" (tool registrada ≠ tool ensinada);
//  4. erro da RPC lança (não vira "nada a comprar");
//  5. (Fase 1, P2) o que o dono disse em os_material chega como `informado` (no item e em `informados`), a
//     descrição ensina o que cada valor quer dizer, e o item que ele disse que chegou sai de a_caminho.
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
  assertEquals(r.a_caminho, [{ descricao: "Compressor 12V de geladeira SS65", quantidade: 1, ordem_de_compra: "OC-00004", informado: null }]);
  assertEquals(r.informados, []);
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

// ── O que o dono disse (os_material, Fase 1, P2) ─────────────────────────────────────────────────────
// O formato que a RPC devolve para o cenário M de supabase/tests/agenda_fase1_material.sql (casos B).
const CENARIO_M = {
  serviceOrderId: "os-m",
  items: [
    { sourceId: "m1", origin: "part", productId: "p1", description: "Cerbo", unit: "un", required: 1, available: 1,
      onOrder: 0, shortage: 0, status: "ok", unitCost: 1900, informado: "na_mao" },
    { sourceId: "m2", origin: "part", productId: "p2", description: "Fusível", unit: "un", required: 8, available: 3,
      onOrder: 0, shortage: 5, status: "partial", unitCost: 25, informado: "parcial" },
    { sourceId: "m4", origin: "part", productId: "p4", description: "Painel", unit: "un", required: 1, available: 0,
      onOrder: 1, shortage: 0, status: "on_order", unitCost: 1250, informado: "a_caminho" },
    { sourceId: "m5", origin: "free_text", productId: null, description: "Conector", unit: null, required: 2,
      available: 0, onOrder: 2, shortage: 0, status: "on_order", unitCost: 120, informado: "comprado" },
    { sourceId: "poi-1", origin: "purchase_order", productId: null, description: "Compressor", unit: null, required: 1,
      available: 1, onOrder: 0, shortage: 0, status: "ok", unitCost: 0, purchaseOrderNumber: "OC-00004", informado: "na_mao" },
  ],
  shortages: [] as unknown[],
  shortageCount: 1,
  estimatedCost: 125,
  needsPurchase: true,
};
CENARIO_M.shortages = [CENARIO_M.items[1]];

Deno.test("get_purchase_needs: informado por item em faltando e a lista informados com tudo que o dono disse", async () => {
  // deno-lint-ignore no-explicit-any
  const r: any = await tool.execute({ service_order_id: "os-m" }, ctxCom({ data: CENARIO_M, error: null }).ctx);
  assertEquals(r.itens_em_falta, 1);
  assertEquals(r.custo_estimado, 125);
  assertEquals(r.faltando.map((i: { descricao: string; informado: string | null }) => [i.descricao, i.informado]), [["Fusível", "parcial"]]);
  assertEquals(r.informados, [
    { descricao: "Cerbo", informado: "na_mao", situacao: "ok", quantidade_faltando: 0 },
    { descricao: "Fusível", informado: "parcial", situacao: "partial", quantidade_faltando: 5 },
    { descricao: "Painel", informado: "a_caminho", situacao: "on_order", quantidade_faltando: 0 },
    { descricao: "Conector", informado: "comprado", situacao: "on_order", quantidade_faltando: 0 },
    { descricao: "Compressor", informado: "na_mao", situacao: "ok", quantidade_faltando: 0 },
  ]);
});

Deno.test("get_purchase_needs: o compressor que o dono disse que chegou sai de a_caminho", async () => {
  // deno-lint-ignore no-explicit-any
  const r: any = await tool.execute({ service_order_id: "os-m" }, ctxCom({ data: CENARIO_M, error: null }).ctx);
  assertEquals(r.a_caminho, []);
  // Sem o fato do dono, o mesmo item continua a caminho (o comportamento da Fase 0).
  const semFato = { ...OS104_DEPOIS, items: [{ ...CENARIO_M.items[4], available: 0, onOrder: 1, status: "on_order", informado: undefined }] };
  // deno-lint-ignore no-explicit-any
  const s: any = await tool.execute({ service_order_id: OS_00104 }, ctxCom({ data: semFato, error: null }).ctx);
  assertEquals(s.a_caminho, [{ descricao: "Compressor", quantidade: 1, ordem_de_compra: "OC-00004", informado: null }]);
});

Deno.test("get_purchase_needs: a descrição ensina o campo informado (tool registrada ≠ tool ensinada)", () => {
  assertStringIncludes(tool.description, "'informado'");
  assertStringIncludes(tool.description, "'comprado' ou 'a_caminho' conta como já pedido");
  assertStringIncludes(tool.description, "'na_mao' como disponível");
  assertStringIncludes(tool.description, "'parcial'");
  assertStringIncludes(tool.description, "dispensou não aparece");
});

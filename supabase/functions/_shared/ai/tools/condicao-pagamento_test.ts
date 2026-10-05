// definir_condicao_pagamento (05/10/2026). Caso real: o dono pediu, no ORÇ-00112 (Nelson), "sinal só
// dos materiais e o saldo da mão de obra na conclusão"; sem a ferramenta, o texto foi para as
// observações. O que se protege: grava os MESMOS campos do seletor da tela; entre condições prontas
// duplicadas vale a que tem parcelas; parcelas próprias fecham 100% por categoria; OS cancelada ou
// faturada não muda; e o sinal/saldo devolvidos são os da conta única (os do PDF).
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { acharPreset, condicaoPagamentoTools, descreverParcelas, parcelasDoPedido } from "./condicao-pagamento.ts";

const tool = condicaoPagamentoTools[0];
const sp = (t: unknown) => String(t).replace(/ /g, " ");

const PRESETS = [
  { id: "p-vazio", label: "À vista", installments: [] },
  { id: "p-avista", label: "À vista", installments: [{ label: "À vista", tipo: "aprovacao", services_pct: 100, parts_pct: 100, expenses_pct: 100 }] },
  {
    id: "p-materiais",
    label: "100% Materiais na aprovação + Serviço na entrega",
    installments: [
      { label: "Sinal", tipo: "aprovacao", parts_pct: 100, services_pct: 0, expenses_pct: 0 },
      { label: "Serviços", tipo: "entrega", parts_pct: 0, services_pct: 100, expenses_pct: 0 },
    ],
  },
  { id: "p-faturado", label: "Faturado mensalmente", installments: [] },
];

// ORÇ-00112 de verdade: produtos 8.164,23, mão de obra 3.100,00, desconto 764,23, total 10.500,00.
const NELSON = {
  id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", service_order_number: "ORÇ-00112", status: "draft", signed_at: null,
  grand_total: 10500, labor_cost_total: 3100, parts_cost_total: 8164.23, operational_cost_total: 0, travel_cost_total: 0,
  is_travel_billable: true, subcontract_cost_total: 0, discount_amount: 764.23, tax_amount: 0,
  payment_conditions: null, payment_condition_preset_id: null, custom_payment_installments: null,
};

function banco(ordem: Record<string, unknown>) {
  const updates: Record<string, unknown>[] = [];
  const sb = {
    from(tabela: string) {
      const filtros: [string, unknown][] = [];
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { filtros.push([c, v]); return q; },
        update: (v: Record<string, unknown>) => { updates.push(v); return { eq: () => Promise.resolve({ error: null }) }; },
        maybeSingle: () => Promise.resolve({ data: filtros.every(([c, v]) => ordem[c] === v) ? ordem : null, error: null }),
        then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: tabela === "payment_condition_presets" ? PRESETS : [], error: null }).then(ok),
      };
      return q;
    },
  };
  const ctx = (userRole = "admin") => ({ sb, admin: sb, userId: "u1", userRole, jwt: "", appOrigin: "", settings: {} }) as never;
  return { ctx, updates };
}

Deno.test("caso do Nelson: condição pronta grava os campos da tela e devolve sinal e saldo do PDF", async () => {
  const b = banco(NELSON);
  const r = await tool.execute({ service_order_id: "ORÇ-00112", condicao: "100% materiais na aprovação + serviço na entrega" }, b.ctx()) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(b.updates[0], {
    payment_condition_preset_id: "p-materiais",
    payment_conditions: "100% Materiais na aprovação + Serviço na entrega",
    custom_payment_installments: null,
  });
  assertEquals(sp(r.sinal), "R$ 7.610,32");
  assertEquals(r.saldo.length, 1);
  assertEquals(sp(r.saldo[0].valor), "R$ 2.889,68");
  assertEquals(r.saldo[0].quando, "na entrega");
  assertEquals(r.avisos, undefined, "sinal + saldo fecham o total");
});

Deno.test("condições prontas duplicadas: vale a que tem parcelas", () => {
  assertEquals(acharPreset(PRESETS, "à vista")?.id, "p-avista");
  assertEquals(acharPreset(PRESETS, "Faturado mensalmente")?.id, "p-faturado");
  assertEquals(acharPreset(PRESETS, "não existe"), null);
});

Deno.test("condição que não existe: não grava e devolve as prontas para oferecer", async () => {
  const b = banco(NELSON);
  const r = await tool.execute({ service_order_id: NELSON.id, condicao: "70/30" }, b.ctx()) as any;
  assertStringIncludes(r.error, "Não há condição pronta");
  assertEquals(r.condicoes_prontas, ["À vista", "100% Materiais na aprovação + Serviço na entrega", "Faturado mensalmente"]);
  assertEquals(b.updates.length, 0);
});

Deno.test("parcelas próprias: gravam como 'Personalizado' da tela, com texto descritivo", async () => {
  const b = banco(NELSON);
  const r = await tool.execute({
    service_order_id: NELSON.id,
    parcelas: [
      { quando: "aprovacao", materiais_pct: 100, mao_de_obra_pct: 50 },
      { quando: "entrega", mao_de_obra_pct: 50 },
    ],
  }, b.ctx()) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  const u = b.updates[0] as any;
  assertEquals(u.payment_condition_preset_id, null);
  assertEquals(u.custom_payment_installments[0], { label: "Sinal", services_pct: 50, parts_pct: 100, expenses_pct: 0, days_after_approval: 0, tipo: "aprovacao" });
  assertEquals(u.payment_conditions, "100% materiais + 50% mão de obra na aprovação · 50% mão de obra na entrega");
});

Deno.test("parcelas: categoria passando de 100% é recusada; faltando, avisa que não fecha o total", async () => {
  assertStringIncludes((parcelasDoPedido([{ quando: "aprovacao", materiais_pct: 80 }, { quando: "entrega", materiais_pct: 40 }]) as any).error, "passa de 100%");
  assertStringIncludes((parcelasDoPedido([{ quando: "depois" }]) as any).error, "aprovacao, entrega ou prazo");
  assertStringIncludes((parcelasDoPedido([{ quando: "prazo", materiais_pct: 100 }]) as any).error, "informe 'dias'");
  const b = banco(NELSON);
  const r = await tool.execute({ service_order_id: NELSON.id, parcelas: [{ quando: "aprovacao", materiais_pct: 100 }] }, b.ctx()) as any;
  assert(r.avisos?.[0]?.includes("alguma categoria não chega a 100%"), JSON.stringify(r));
});

Deno.test("só texto: limpa condição pronta e parcelas; um jeito por vez", async () => {
  const b = banco(NELSON);
  const r = await tool.execute({ service_order_id: NELSON.id, texto: "Faturado no dia 10" }, b.ctx()) as any;
  assertEquals(b.updates[0], { payment_condition_preset_id: null, payment_conditions: "Faturado no dia 10", custom_payment_installments: null });
  assertStringIncludes(r.observacao, "sem programação");
  const dois = await banco(NELSON).ctx;
  const r2 = await tool.execute({ service_order_id: NELSON.id, condicao: "À vista", parcelas: [{ quando: "aprovacao" }] }, dois()) as any;
  assertStringIncludes(r2.error, "Use UM jeito");
});

Deno.test("cancelada ou faturada não muda; assinada muda e avisa da reassinatura; técnico barrado", async () => {
  for (const status of ["cancelled", "invoiced"]) {
    const b = banco({ ...NELSON, status });
    const r = await tool.execute({ service_order_id: NELSON.id, condicao: "À vista" }, b.ctx()) as any;
    assert(r.error, status);
    assertEquals(b.updates.length, 0);
  }
  const assinada = banco({ ...NELSON, signed_at: "2026-10-01T10:00:00Z" });
  const r = await tool.execute({ service_order_id: NELSON.id, condicao: "À vista" }, assinada.ctx()) as any;
  assert(r.avisos.some((a: string) => a.includes("assinar de novo")));
  const tec = banco(NELSON);
  const t = await tool.execute({ service_order_id: NELSON.id, condicao: "À vista" }, tec.ctx("technician")) as any;
  assert(t.error);
  assertEquals(tec.updates.length, 0);
});

Deno.test("descrição das parcelas para o campo de texto", () => {
  assertEquals(descreverParcelas([{ tipo: "prazo", days_after_approval: 30, services_pct: 100, parts_pct: 0, expenses_pct: 0 }]), "100% mão de obra em 30 dias");
});

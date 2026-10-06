// Correções de 06/10/2026 — o que o assistente já fazia, mas falhava (auditoria com dado de
// produção). Cada teste trava o caso real que levou à correção.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { montarParcelasDoSaldo, descreverSaldo } from "./saldo-do-sinal.ts";
import { computeSchedule } from "../../banking/quote-deposit.ts";
import { financialTools } from "./financial.ts";
import { flowMacroTools } from "./flow-macros.ts";
import { soOpsTools } from "./so-ops.ts";
import { textoDaProximaPendencia } from "../whatsapp-channel.ts";

// OS-00112 como estava em produção: total R$ 10.500, sinal pago R$ 7.600.
const OS_00112 = {
  service_order_number: "ORÇ-00112", scheduled_end_at: null, grand_total: 10500,
  labor_cost_total: 3100, parts_cost_total: 8164.23, operational_cost_total: 0, travel_cost_total: 0,
  is_travel_billable: true, subcontract_cost_total: 0, discount_amount: 764.23, tax_amount: 0,
};
const MATERIAIS_NA_APROVACAO = [
  { label: "Materiais na aprovação", parts_pct: 100, services_pct: 0, expenses_pct: 100, tipo: "aprovacao" as const },
  { label: "Serviço na entrega", parts_pct: 0, services_pct: 100, expenses_pct: 0, tipo: "entrega" as const },
];

Deno.test("saldo do sinal: sinal igual ao da condição → parcelas da condição, como a tela", () => {
  const plano = computeSchedule(OS_00112, MATERIAIS_NA_APROVACAO);
  const r = montarParcelasDoSaldo(OS_00112, MATERIAIS_NA_APROVACAO, plano.signalAmount, "2026-10-06");
  assertEquals(r.origem, "condicao");
  assertEquals(r.parcelas.length, 1);
  assertEquals(r.parcelas[0].amount, plano.balance[0].amount);
  assertEquals(r.parcelas[0].description, "Serviço na entrega — OS-00112");
  // "na entrega" sem data prevista: pagamento + 30 dias, e se reajusta à conclusão real.
  assertEquals(r.parcelas[0].due_date, "2026-11-05");
  assertEquals(r.parcelas[0].due_on_completion, true);
});

Deno.test("saldo do sinal: o caso da OS-00112 — sinal fora da condição vira o restante na entrega", () => {
  const r = montarParcelasDoSaldo(OS_00112, MATERIAIS_NA_APROVACAO, 7600, "2026-10-06");
  assertEquals(r.origem, "restante");
  assertEquals(r.parcelas, [{ description: "Saldo — OS-00112", amount: 2900, due_date: "2026-11-05", due_on_completion: true }]);
  assertStringIncludes(descreverSaldo(r.parcelas).replace(/\s/g, " "), "R$ 2.900,00 na entrega");
});

Deno.test("saldo do sinal: sem condição, ou com sinal cobrindo tudo", () => {
  assertEquals(montarParcelasDoSaldo(OS_00112, null, 7600, "2026-10-06").parcelas[0].amount, 2900);
  const tudo = montarParcelasDoSaldo(OS_00112, null, 10500, "2026-10-06");
  assertEquals(tudo.origem, "nenhum");
  assertEquals(tudo.parcelas, []);
  // Parcela com prazo vence em pagamento + N dias, sem reajuste na conclusão.
  const prazo = montarParcelasDoSaldo(
    { ...OS_00112, scheduled_end_at: "2026-10-20T15:00:00Z" },
    [MATERIAIS_NA_APROVACAO[0], { label: "30 dias", services_pct: 100, tipo: "prazo", days_after_approval: 30 }],
    computeSchedule(OS_00112, MATERIAIS_NA_APROVACAO).signalAmount, "2026-10-06",
  );
  assertEquals(prazo.parcelas[0].due_date, "2026-11-05");
  assertEquals(prazo.parcelas[0].due_on_completion, false);
});

// Banco falso: tabelas por nome, filtro por igualdade, RPCs registradas.
// deno-lint-ignore no-explicit-any
function bancoFalso(tabelas: Record<string, any[]>, rpcs: Record<string, any> = {}, falhaNoInsert: Record<string, string> = {}) {
  // deno-lint-ignore no-explicit-any
  const chamadas: { rpc: [string, any][]; insert: [string, any][]; delete: string[] } = { rpc: [], insert: [], delete: [] };
  const db = {
    chamadas,
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, p: any) { chamadas.rpc.push([nome, p]); return Promise.resolve({ data: rpcs[nome] ?? { ok: true }, error: null }); },
    from(tabela: string) {
      const filtros: [string, unknown][] = [];
      const linhas = () => (tabelas[tabela] ?? []).filter((l) => filtros.every(([c, v]) => l[c] === v));
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, order: () => q, limit: () => q,
        eq: (c: string, v: unknown) => { filtros.push([c, v]); return q; },
        maybeSingle: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        single: () => Promise.resolve({ data: linhas()[0] ?? null, error: null }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any) => Promise.resolve({ data: linhas(), error: null }).then(ok),
        // deno-lint-ignore no-explicit-any
        insert: (v: any) => {
          chamadas.insert.push([tabela, v]);
          const erro = falhaNoInsert[tabela] ? { message: falhaNoInsert[tabela] } : null;
          // deno-lint-ignore no-explicit-any
          const r: any = Promise.resolve({ data: null, error: erro });
          r.select = () => ({ single: () => Promise.resolve({ data: erro ? null : { id: `novo-${tabela}`, ...v }, error: erro }) });
          return r;
        },
        delete: () => { chamadas.delete.push(tabela); return { eq: () => Promise.resolve({ error: null }) }; },
      };
      return q;
    },
  };
  return db;
}
const ctxCom = (db: unknown) => ({ sb: db, admin: db, userId: "dono-1", userRole: "admin", jwt: "", appOrigin: "", settings: {} }) as never;
const tool = (nome: string) => [...financialTools, ...flowMacroTools, ...soOpsTools].find((t) => t.name === nome)!;

Deno.test("register_deposit_and_convert e approve_quote_full mandam o saldo e criam a cobrança", async () => {
  for (const [nome, valor] of [["register_deposit_and_convert", "amount"], ["approve_quote_full", "deposit_amount"]] as const) {
    const db = bancoFalso({ service_orders: [{ id: "os-112", ...OS_00112 }] });
    const r = await tool(nome).execute({ service_order_id: "os-112", [valor]: 7600, payment_date: "2026-10-06", payment_method: "pix" }, ctxCom(db)) as any;
    assert(r.ok, `${nome}: ${JSON.stringify(r)}`);
    const [rpc, p] = db.chamadas.rpc[0];
    assertEquals(rpc, "register_deposit_and_convert");
    assertEquals(p.p_balance_installments, [{ description: "Saldo — OS-00112", amount: 2900, due_date: "2026-11-05", due_on_completion: true }], nome);
    assertEquals(p.p_create_collections, true, nome);
  }
});

Deno.test("register_payment manda quem pediu — sem isso o banco respondia 'acesso negado'", async () => {
  const db = bancoFalso({});
  const r = await tool("register_payment").execute({ receivable_id: "r1", amount: 100, payment_date: "2026-10-06", payment_method: "pix" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.chamadas.rpc[0][0], "register_payment_and_update_balance");
  assertEquals(db.chamadas.rpc[0][1].p_autor, "dono-1");
});

Deno.test("duplicar: número do contador, peças com o preço de venda e, se algo falhar, nada fica gravado", async () => {
  const origem = {
    id: "orc-1", service_order_number: "ORÇ-00100", client_id: "c1", vessel_id: "v1", status: "invoiced",
    problem_description: "Trocar baterias", quote_validity_date: "2026-09-01", share_token: "tok", grand_total: 999,
    service_order_parts: [{ product_id: "p1", quantity: 2, unit_cost_snapshot: 10, unit_sale_snapshot: 15, line_total_cost: 20, line_total_sale: 30, currency_snapshot: "BRL", notes: null }],
    service_order_services: [{ service_id: "s1", name_snapshot: "Instalação", quantity: 1, unit_price_snapshot: 300, line_total: 300 }],
  };
  const db = bancoFalso({ service_orders: [origem] }, { next_document_number: 114 }, { service_order_services: "falhou de propósito" });
  const r = await tool("duplicate_service_order").execute({ service_order_id: "orc-1" }, ctxCom(db)) as any;

  const [, cabecalho] = db.chamadas.insert.find(([t]) => t === "service_orders")!;
  assertEquals(cabecalho.service_order_number, "ORÇ-00114");
  assertEquals(cabecalho.status, "draft");
  assertEquals(cabecalho.problem_description, "Trocar baterias");
  assertEquals(cabecalho.created_by, "dono-1");
  for (const fora of ["share_token", "grand_total", "quote_validity_date", "service_order_parts"]) assertEquals(fora in cabecalho, false, fora);
  const [, pecas] = db.chamadas.insert.find(([t]) => t === "service_order_parts")!;
  assertEquals(pecas[0].unit_sale_snapshot, 15);
  // O serviço falhou: a cópia inteira é desfeita e a resposta não diz que copiou.
  assertStringIncludes(r.error, "não foi feita");
  assertEquals(db.chamadas.delete.includes("service_orders"), true);
});

Deno.test("WhatsApp: depois de decidir, o próximo pedido da leva aparece com quantos faltam", () => {
  const t = textoDaProximaPendencia({ title: "Registrar diária", summary: "- Roberto, dia inteiro", risk_level: "medium" }, 3);
  assertStringIncludes(t, "Próximo pedido (faltam 3):");
  assertStringIncludes(t, "⚠️ Registrar diária");
  assertStringIncludes(t, "Responda *sim*");
  const ultimo = textoDaProximaPendencia({ title: "Dar baixa", summary: "", risk_level: "high" }, 1);
  assertStringIncludes(ultimo, "Último pedido que falta:");
  assertStringIncludes(ultimo, "sim <SEU PIN>");
});

// get_os_profitability lê a MESMA view da tela "Lucro por OS" (vw_os_profitability) — o assistente
// e a tela não podem dizer margens diferentes. Até 29/09/2026 a tool somava por conta própria, sem
// mão de obra e com o preço de VENDA das peças no lugar do custo.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/reports_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { reportTools } from "./reports.ts";

const linha = {
  service_order_number: "OS-00075", revenue: 1000, parts_cost: 200, travel_cost: 50, operational_cost: 30,
  commission_cost: 20, labor_cost_real: 170, labor_days: 1, labor_sold: 600, hours_sold: 4, net_profit: 530, net_margin_percent: 53,
};

function ctx(cargo: string, row: Record<string, unknown> | null = linha) {
  const lidas: string[] = [];
  const admin = {
    from(tabela: string) {
      lidas.push(tabela);
      const q: any = { select() { return q; }, eq() { return q; }, maybeSingle: () => Promise.resolve({ data: row, error: null }) };
      return q;
    },
  };
  return { c: { admin, sb: admin, userId: "u", userRole: cargo as any, jwt: "", appOrigin: "", settings: {} }, lidas };
}
const tool = reportTools.find((t) => t.name === "get_os_profitability")!;

Deno.test("lê a view da tela, desconta a mão de obra das diárias e soma o custo que fecha com o lucro", async () => {
  const { c, lidas } = ctx("admin");
  const r = await tool.execute({ service_order_id: "os75" }, c as never) as Record<string, any>;
  assertEquals(lidas, ["vw_os_profitability"]);
  assertEquals(r.custos.mao_de_obra_diarias, 170);
  assertEquals(r.custos.pecas, 200);
  assertEquals(r.custo_total, 470);
  assertEquals(r.receita - r.custo_total, r.lucro);
  assertEquals(r.mao_de_obra, { vendida: 600, horas_vendidas: 4, custo_real_diarias: 170, dias_de_diarista: 1 });
});

Deno.test("vendedor vê a margem, mas não quantos dias de diarista (detalhe de pagamento de pessoa)", async () => {
  const r = await tool.execute({ service_order_id: "os75" }, ctx("seller").c as never) as Record<string, any>;
  assertEquals(r.mao_de_obra.dias_de_diarista, undefined);
  assertEquals(r.custos.mao_de_obra_diarias, 170);
});

Deno.test("OS sem diária ligada avisa que a mão de obra não está descontada", async () => {
  const r = await tool.execute({ service_order_id: "os1" }, ctx("admin", { ...linha, labor_cost_real: 0, labor_days: 0 }).c as never) as Record<string, any>;
  assertStringIncludes(String(r.observacao), "Nenhuma diária de freelancer ligada");
});

Deno.test("técnico não vê lucratividade; OS inexistente vira erro, não zero", async () => {
  const tec = await tool.execute({ service_order_id: "os75" }, ctx("technician").c as never) as { error?: string };
  assertEquals(typeof tec.error, "string");
  const nada = await tool.execute({ service_order_id: "x" }, ctx("admin", null).c as never) as { error?: string };
  assertEquals(nada.error, "OS não encontrada.");
});

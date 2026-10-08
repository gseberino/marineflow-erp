// R14 reescrita sobre v_maintenance_plans_due (07/10/2026): mesma chave de antes, a tarefa nasce
// no dia em que a janela abre, e some quando o ciclo muda, o plano é adiado, ganha OS ou é desligado.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { candidatoDaR14, type PlanoDaR14, resolucaoDaR14 } from "./rules.ts";

const p = (o: Partial<PlanoDaR14> = {}): PlanoDaR14 => ({
  plan_id: "plano-1", plan_name: "Revisão das baterias", vessel_id: "barco-1", vessel_name: "Mar Azul",
  client_id: "cli-1", client_name: "Carlos", scope: "Teste de capacidade", estimated_value: 1500,
  last_service_at: "2025-10-28", next_due_on: "2026-10-28", window_opens_on: "2026-10-07",
  situacao: "na_janela", tem_os_agendada: false, ...o,
});

Deno.test("R14: a tarefa usa a MESMA chave de antes e nasce às 08:00 do dia em que a janela abre", () => {
  const c = candidatoDaR14(p(), "2026-10-07")!;
  assertEquals(c.automation_key, "r14:plan:plano-1:2025-10-28");
  assertEquals(c.title, "Propor revisão: Revisão das baterias — Mar Azul");
  assertEquals(c.due_at, "2026-10-07T11:00:00Z");
  assertEquals(c.priority, "normal");
  assertEquals([c.related_entity_type, c.related_entity_id, c.client_id], ["vessel", "barco-1", "cli-1"]);
  assertEquals(c.notes!.includes("Vence 28/10/2026.") && c.notes!.includes("R$"), true);
  // Nunca atendido: o bucket é 'first' (como antes). Vencida: prioridade alta.
  assertEquals(candidatoDaR14(p({ last_service_at: null, situacao: "vencida" }), "2026-10-07")!.automation_key, "r14:plan:plano-1:first");
  assertEquals(candidatoDaR14(p({ situacao: "vencida" }), "2026-10-07")!.priority, "high");
});

Deno.test("R14: fora da janela, adiado ou com OS agendada não cria tarefa", () => {
  assertEquals(candidatoDaR14(p({ window_opens_on: "2026-10-08" }), "2026-10-07"), null);
  assertEquals(candidatoDaR14(p({ situacao: "adiada" }), "2026-10-07"), null);
  assertEquals(candidatoDaR14(p({ tem_os_agendada: true }), "2026-10-07"), null);
});

Deno.test("R14: resolve quando o serviço é registrado, o plano é adiado, ganha OS ou é desligado", () => {
  const vivo = { last_service_at: "2025-10-28", snoozed_until: null, tem_os_agendada: false };
  assertEquals(resolucaoDaR14("2025-10-28", { active: true }, vivo, "2026-10-07"), null);
  assertEquals(resolucaoDaR14("2025-10-28", null, null, "2026-10-07"), "Plano não existe mais");
  assertEquals(resolucaoDaR14("2025-10-28", { active: false }, null, "2026-10-07"), "Plano desativado");
  assertEquals(resolucaoDaR14("2025-10-28", { active: true }, { ...vivo, last_service_at: "2026-10-05" }, "2026-10-07"), "Serviço registrado no plano");
  assertEquals(resolucaoDaR14("first", { active: true }, { ...vivo, last_service_at: null }, "2026-10-07"), null);
  assertEquals(resolucaoDaR14("2025-10-28", { active: true }, { ...vivo, snoozed_until: "2026-12-01" }, "2026-10-07"), "Adiado até 01/12/2026");
  assertEquals(resolucaoDaR14("2025-10-28", { active: true }, { ...vivo, tem_os_agendada: true, os_agendada_numero: "OS-00140" }, "2026-10-07"), "OS-00140 aberta para a embarcação");
});

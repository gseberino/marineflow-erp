import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  RULES, isRuleEnabled, ruleById, ruleIdFromKey, entityIdFromKey, keyOf, fmtBRL, fmtDate, dueAt,
  isManualDismissal, dismissCooldownDays,
} from "./rules.ts";

Deno.test("isManualDismissal: conclusão MANUAL recente bloqueia recriação", () => {
  const cutoff = "2026-07-17T00:00:00Z";
  // humano concluiu ontem → bloqueia
  assertEquals(isManualDismissal(
    { status: "done", completed_by: "user-1", completed_at: "2026-07-23T10:00:00Z", updated_at: null }, cutoff), true);
  // auto-resolução (completed_by null) → NÃO bloqueia (condição sumiu; se voltar é novo)
  assertEquals(isManualDismissal(
    { status: "done", completed_by: null, completed_at: "2026-07-23T10:00:00Z", updated_at: null }, cutoff), false);
  // conclusão manual ANTIGA (antes do cutoff) → não bloqueia mais
  assertEquals(isManualDismissal(
    { status: "done", completed_by: "user-1", completed_at: "2026-07-10T10:00:00Z", updated_at: null }, cutoff), false);
  // cancelada recentemente → bloqueia (dispensa explícita)
  assertEquals(isManualDismissal(
    { status: "cancelled", completed_by: null, completed_at: null, updated_at: "2026-07-23T10:00:00Z" }, cutoff), true);
  // viva não entra (função só recebe done/cancelled, mas por segurança)
  assertEquals(isManualDismissal(
    { status: "pending", completed_by: null, completed_at: null, updated_at: "2026-07-23T10:00:00Z" }, cutoff), false);
});

Deno.test("dismissCooldownDays: default 7, override por setting", () => {
  assertEquals(dismissCooldownDays({}), 7);
  assertEquals(dismissCooldownDays({ task_rule_dismiss_cooldown_days: "3" }), 3);
  assertEquals(dismissCooldownDays({ task_rule_dismiss_cooldown_days: "0" }), 0);
  assertEquals(dismissCooldownDays({ task_rule_dismiss_cooldown_days: "lixo" }), 7);
});

Deno.test("keyOf/entityIdFromKey/ruleIdFromKey: ida e volta", () => {
  const k = keyOf("r3", "recv", "abc-123");
  assertEquals(k, "r3:recv:abc-123");
  assertEquals(ruleIdFromKey(k), "r3");
  assertEquals(entityIdFromKey(k), "abc-123");
  assertEquals(ruleIdFromKey(keyOf("r2", "so", "x", "2026-W30")), "r2");
});

Deno.test("isRuleEnabled: default quando setting ausente, override quando presente", () => {
  const r1 = ruleById("r1")!;
  assertEquals(isRuleEnabled({}, r1), true);
  assertEquals(isRuleEnabled({ task_rule_r1_enabled: "false" }, r1), false);
  assertEquals(isRuleEnabled({ task_rule_r1_enabled: "true" }, r1), true);
});

Deno.test("todas as regras têm id único e formato rN", () => {
  const ids = RULES.map((r) => r.id);
  assertEquals(new Set(ids).size, ids.length);
  for (const id of ids) {
    if (!/^r\d+$/.test(id)) throw new Error(`id inválido: ${id}`);
  }
});

Deno.test("fmtBRL/fmtDate/dueAt: formatos estáveis", () => {
  assertEquals(fmtDate("2026-07-30"), "30/07/2026");
  assertEquals(dueAt("2026-07-30"), "2026-07-30T11:00:00Z");
  // fmtBRL usa NBSP entre R$ e o número — comparar sem depender do espaço exato
  assertEquals(fmtBRL(1234.5).replace(/\s/g, ""), "R$1.234,50");
});

Deno.test("isResolved: recebível pago resolve, pendente não (mock de db)", async () => {
  const r3 = ruleById("r3")!;
  const mkDb = (row: unknown) => ({
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
    }),
  });
  assertEquals(
    await r3.isResolved(mkDb({ status: "paid", balance_amount: 0 }), { automation_key: "r3:recv:x" }),
    "Pagamento registrado",
  );
  assertEquals(
    await r3.isResolved(mkDb({ status: "pending", balance_amount: 100 }), { automation_key: "r3:recv:x" }),
    null,
  );
  assertEquals(
    await r3.isResolved(mkDb(null), { automation_key: "r3:recv:x" }),
    "Recebível não existe mais",
  );
});

Deno.test("isResolved r1: OS agendada ou status mudado resolve", async () => {
  const r1 = ruleById("r1")!;
  const mkDb = (row: unknown) => ({
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
    }),
  });
  assertEquals(
    await r1.isResolved(mkDb({ status: "approved", scheduled_start_at: "2026-07-30T12:00:00Z" }), { automation_key: "r1:so:x" }),
    "OS foi agendada",
  );
  assertEquals(
    await r1.isResolved(mkDb({ status: "cancelled", scheduled_start_at: null }), { automation_key: "r1:so:x" }),
    "OS mudou para cancelled",
  );
  assertEquals(
    await r1.isResolved(mkDb({ status: "approved", scheduled_start_at: null }), { automation_key: "r1:so:x" }),
    null,
  );
});

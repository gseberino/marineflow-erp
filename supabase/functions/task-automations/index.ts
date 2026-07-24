// Edge Function: task-automations — o motor da Agenda & Tarefas 2.0.
// Cron */15min. Faz, nesta ordem:
//   1. Regras R1..R12: criam tarefas (dedupe por automation_key) e auto-resolvem
//      as que a condição sumiu ("Resolvido automaticamente: ...").
//   2. R10: lembrete interno (WhatsApp equipe) de OS agendada para amanhã.
//   3. R9 (nasce OFF): lembrete de agendamento ao CLIENTE — substitui a antiga
//      scheduling-automations (que estava quebrada com colunas pré-rename).
//   4. Processa task_reminders vencidos → app_notifications + WhatsApp interno.
//   5. Materializa recorrências (rrule) para os próximos 30 dias.
// Plano: plans/marineflow-agenda-tarefas.md §6-§7.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  RULES, isRuleEnabled, ruleById, ruleIdFromKey, isManualDismissal, dismissCooldownDays,
  type RuleCandidate,
} from "./rules.ts";
import { expandOccurrences } from "../_shared/recurrence.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

// deno-lint-ignore no-explicit-any
type Db = any; // mesmo padrão das demais functions: client supabase-js sem schema tipado

async function loadSettings(db: Db): Promise<Record<string, string>> {
  const { data } = await db.from("app_settings").select("key, value");
  return Object.fromEntries((data || []).map((s: any) => [s.key, s.value]));
}

async function audit(db: Db, event_type: string, payload: unknown) {
  try {
    await db.from("ai_operator_audit").insert({
      actor_kind: "system", event_type, event_category: "data", payload,
    });
  } catch (_) { /* auditoria nunca derruba o motor */ }
}

/** Resolve 'admin'/'financial' para um app_user ativo; uuid passa direto. */
async function resolveAssignee(db: Db, who: string | null, cache: Map<string, string | null>): Promise<string | null> {
  if (!who) return null;
  if (who !== "admin" && who !== "financial") return who;
  if (cache.has(who)) return cache.get(who)!;
  const { data } = await db.from("app_users")
    .select("id").eq("active", true).eq("role", who)
    .order("created_at", { ascending: true }).limit(1).maybeSingle();
  const id = (data as any)?.id ?? null;
  cache.set(who, id);
  return id;
}

async function createTaskFromCandidate(db: Db, c: RuleCandidate, assigneeId: string | null): Promise<boolean> {
  const { error } = await db.from("agenda_tasks").insert({
    title: c.title,
    kind: "task",
    status: "pending",
    priority: c.priority,
    source: "automation",
    automation_key: c.automation_key,
    assignee_user_id: assigneeId,
    due_at: c.due_at,
    related_entity_type: c.related_entity_type,
    related_entity_id: c.related_entity_id,
    client_id: c.client_id ?? null,
    notes: c.notes ?? null,
  });
  if (error) {
    // 23505 = já existe tarefa viva para esta chave (dedupe) — esperado
    if ((error as any).code === "23505") return false;
    throw error;
  }
  return true;
}

async function runRules(db: Db, settings: Record<string, string>) {
  const created: string[] = [];
  const resolved: string[] = [];
  const assigneeCache = new Map<string, string | null>();

  const cooldownDays = dismissCooldownDays(settings);
  const cutoffISO = new Date(Date.now() - cooldownDays * 86400000).toISOString();

  for (const rule of RULES) {
    if (!isRuleEnabled(settings, rule)) continue;
    try {
      let candidates = await rule.find(db);

      // Dispensa manual: não recriar o que um humano concluiu/cancelou há pouco
      // com a condição ainda de pé (senão a tarefa "volta do nada" a cada 15min).
      if (candidates.length > 0 && cooldownDays > 0) {
        const keys = candidates.map((c) => c.automation_key);
        const { data: closed } = await db.from("agenda_tasks")
          .select("automation_key, status, completed_by, completed_at, updated_at")
          .in("automation_key", keys)
          .in("status", ["done", "cancelled"]);
        const dismissed = new Set(
          ((closed as any[]) || [])
            .filter((r) => isManualDismissal(r, cutoffISO))
            .map((r) => r.automation_key),
        );
        candidates = candidates.filter((c) => !dismissed.has(c.automation_key));
      }

      for (const c of candidates) {
        const assigneeId = await resolveAssignee(db, c.assignee, assigneeCache);
        const inserted = await createTaskFromCandidate(db, c, assigneeId);
        if (inserted) {
          created.push(c.automation_key);
          // lembrete padrão no app quando a tarefa tem prazo
          if (c.due_at && assigneeId) {
            const { data: t } = await db.from("agenda_tasks")
              .select("id").eq("automation_key", c.automation_key)
              .in("status", ["pending", "in_progress"]).maybeSingle();
            if (t) {
              await db.from("task_reminders").insert({
                task_id: (t as any).id, remind_at: c.due_at, channel: "app",
              });
            }
          }
        }
      }
    } catch (e) {
      console.error(`rule ${rule.id} find/create failed:`, e);
    }
  }

  // Auto-resolução: reavalia TODAS as tarefas vivas de automação (mesmo de regra
  // desabilitada — desligar a regra não deve deixar tarefa fantasma para sempre)
  const { data: live } = await db.from("agenda_tasks")
    .select("id, automation_key, notes")
    .eq("source", "automation")
    .not("automation_key", "is", null)
    .in("status", ["pending", "in_progress"])
    .limit(300);
  for (const task of (live as any[]) || []) {
    const rule = ruleById(ruleIdFromKey(task.automation_key));
    if (!rule) continue;
    try {
      const reason = await rule.isResolved(db, task);
      if (reason) {
        await db.from("agenda_tasks").update({
          status: "done",
          completed_at: new Date().toISOString(),
          notes: [task.notes, `Resolvido automaticamente: ${reason}`].filter(Boolean).join("\n"),
        }).eq("id", task.id).in("status", ["pending", "in_progress"]);
        resolved.push(task.automation_key);
      }
    } catch (e) {
      console.error(`rule ${rule.id} isResolved failed:`, e);
    }
  }

  return { created, resolved };
}

/** R10 — lembrete interno de OS agendada para amanhã (equipe, nunca cliente). */
async function runTechnicianReminders(db: Db, settings: Record<string, string>) {
  if ((settings["task_rule_r10_enabled"] ?? "true") !== "true") return { sent: 0 };
  const start = new Date(); start.setUTCHours(0, 0, 0, 0);
  const from = new Date(start.getTime() + 86400000);
  const to = new Date(start.getTime() + 2 * 86400000);

  const { data: orders } = await db.from("service_orders")
    .select("id, service_order_number, scheduled_start_at, clients(name), vessels(name), service_order_technicians(user_id, app_users(id, full_name, phone_normalized, ai_whatsapp_enabled))")
    .eq("status", "scheduled")
    .gte("scheduled_start_at", from.toISOString())
    .lt("scheduled_start_at", to.toISOString());

  let sent = 0;
  for (const o of (orders as any[]) || []) {
    for (const t of o.service_order_technicians || []) {
      const u = t.app_users;
      if (!u?.ai_whatsapp_enabled || !u?.phone_normalized) continue;
      // dedupe: 1 lembrete interno por OS+dia (source_ref_id = OS)
      const { data: dup } = await db.from("whatsapp_send_queue")
        .select("id").eq("source", "agenda-r10").eq("source_ref_id", o.id)
        .eq("phone_normalized", u.phone_normalized)
        .gte("created_at", start.toISOString()).limit(1);
      if (dup && dup.length > 0) continue;
      const hora = new Date(o.scheduled_start_at).toLocaleTimeString("pt-BR", {
        hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo",
      });
      await db.from("whatsapp_send_queue").insert({
        phone_normalized: u.phone_normalized,
        message: `🔧 Lembrete: amanhã às ${hora} você tem a OS ${o.service_order_number}` +
          ` — ${o.clients?.name || "cliente"}${o.vessels?.name ? ` (${o.vessels.name})` : ""}.`,
        source: "agenda-r10",
        source_ref_id: o.id,
        priority: 4,
      });
      sent++;
    }
  }
  return { sent };
}

/** R9 — lembrete de agendamento ao CLIENTE (OFF por padrão; test-mode preservado). */
async function runClientReminders(db: Db, settings: Record<string, string>) {
  if ((settings["task_rule_r9_enabled"] ?? "false") !== "true") return { sent: 0, skipped: "disabled" };

  const testMode = (settings["wa_test_mode"] ?? settings["zapi_test_mode"]) === "true";
  const testNumber = ((settings["wa_test_number"] ?? settings["zapi_test_number"]) || "").replace(/\D/g, "");
  if (testMode && !testNumber) return { sent: 0, skipped: "test_mode_without_number" };

  const now = new Date();
  const tomorrow = new Date(now.getTime() + 86400000);
  const { data: orders } = await db.from("service_orders")
    .select("id, service_order_number, scheduled_start_at, clients(name, phone, whatsapp), vessels(name)")
    .eq("status", "scheduled")
    .is("reminder_sent_at", null)
    .gte("scheduled_start_at", now.toISOString())
    .lte("scheduled_start_at", tomorrow.toISOString());

  let sent = 0;
  for (const o of (orders as any[]) || []) {
    const phone = ((o.clients?.whatsapp || o.clients?.phone || "") as string).replace(/\D/g, "");
    if (!phone || phone.length < 10) continue;
    const target = testMode ? testNumber : phone;
    const dia = new Date(o.scheduled_start_at).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
    const hora = new Date(o.scheduled_start_at).toLocaleTimeString("pt-BR", {
      hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo",
    });
    await db.from("whatsapp_send_queue").insert({
      phone_normalized: target,
      message: `Olá${o.clients?.name ? `, ${o.clients.name}` : ""}! Lembrete do seu atendimento agendado para ${dia} às ${hora}` +
        `${o.vessels?.name ? ` (${o.vessels.name})` : ""}. Qualquer imprevisto, é só responder por aqui. — HBR Marine`,
      source: "agenda-r9",
      source_ref_id: o.id,
      priority: 4,
    });
    await db.from("service_orders").update({ reminder_sent_at: new Date().toISOString() }).eq("id", o.id);
    sent++;
  }
  return { sent };
}

/** R13 — pesquisa de satisfação D+1 após concluir OS (nasce OFF; test-mode aware). */
async function runPostServiceSurvey(db: Db, settings: Record<string, string>) {
  if ((settings["task_rule_r13_enabled"] ?? "false") !== "true") return { sent: 0, skipped: "disabled" };

  const testMode = (settings["wa_test_mode"] ?? settings["zapi_test_mode"]) === "true";
  const testNumber = ((settings["wa_test_number"] ?? settings["zapi_test_number"]) || "").replace(/\D/g, "");
  if (testMode && !testNumber) return { sent: 0, skipped: "test_mode_without_number" };

  // OS concluídas entre D-2 e D-1 (janela de 1 dia, com margem p/ o cron não perder)
  const from = new Date(Date.now() - 2 * 86400000).toISOString();
  const to = new Date(Date.now() - 1 * 86400000).toISOString();
  const { data: orders } = await db.from("service_orders")
    .select("id, service_order_number, updated_at, clients(name, phone, whatsapp), vessels(name)")
    .eq("status", "completed")
    .gte("updated_at", from)
    .lte("updated_at", to);

  let sent = 0;
  for (const o of (orders as any[]) || []) {
    const phone = ((o.clients?.whatsapp || o.clients?.phone || "") as string).replace(/\D/g, "");
    if (!phone || phone.length < 10) continue;
    const { data: dup } = await db.from("whatsapp_send_queue")
      .select("id").eq("source", "agenda-r13").eq("source_ref_id", o.id).limit(1);
    if (dup && dup.length > 0) continue;
    await db.from("whatsapp_send_queue").insert({
      phone_normalized: testMode ? testNumber : phone,
      message: `Olá${o.clients?.name ? `, ${o.clients.name}` : ""}! O serviço${o.vessels?.name ? ` na ${o.vessels.name}` : ""} foi concluído. ` +
        `Como foi sua experiência, de 0 a 10? Sua resposta nos ajuda muito — e qualquer ajuste, é só falar por aqui. — HBR Marine`,
      source: "agenda-r13",
      source_ref_id: o.id,
      priority: 5,
    });
    sent++;
  }
  return { sent };
}

/** Processa task_reminders vencidos → sino in-app + WhatsApp interno. */
async function processReminders(db: Db) {
  const { data: due } = await db.from("task_reminders")
    .select("id, remind_at, channel, agenda_tasks(id, title, status, assignee_user_id, due_at, scheduled_start_at)")
    .is("sent_at", null)
    .lte("remind_at", new Date().toISOString())
    .limit(100);

  let appN = 0, waN = 0;
  for (const r of (due as any[]) || []) {
    // trava otimista: só processa quem ainda está sent_at IS NULL
    const { data: claimed } = await db.from("task_reminders")
      .update({ sent_at: new Date().toISOString() })
      .eq("id", r.id).is("sent_at", null).select("id");
    if (!claimed || claimed.length === 0) continue;

    const task = r.agenda_tasks;
    if (!task || task.status === "done" || task.status === "cancelled") continue;

    const userId = task.assignee_user_id;
    if (r.channel === "app") {
      if (!userId) continue;
      await db.from("app_notifications").insert({
        user_id: userId,
        type: "task_reminder",
        title: "Lembrete de tarefa",
        body: task.title,
        navigate_to: "/agenda",
      });
      appN++;
    } else if (r.channel === "whatsapp") {
      if (!userId) continue;
      const { data: u } = await db.from("app_users")
        .select("phone_normalized, ai_whatsapp_enabled").eq("id", userId).maybeSingle();
      // canal interno APENAS: exige ai_whatsapp_enabled (nunca cliente)
      if (!(u as any)?.ai_whatsapp_enabled || !(u as any)?.phone_normalized) continue;
      await db.from("whatsapp_send_queue").insert({
        phone_normalized: (u as any).phone_normalized,
        message: `⏰ Lembrete: ${task.title}`,
        source: "task-reminder",
        source_ref_id: task.id,
        priority: 4,
      });
      waN++;
    }
  }
  return { app: appN, whatsapp: waN };
}

/** Materializa ocorrências de tarefas recorrentes (rrule) nos próximos 30 dias. */
async function materializeRecurrences(db: Db) {
  const { data: parents } = await db.from("agenda_tasks")
    .select("*")
    .not("rrule", "is", null)
    .is("recurrence_parent_id", null)
    .neq("status", "cancelled")
    .limit(100);

  const windowStart = new Date();
  const windowEnd = new Date(Date.now() + 30 * 86400000);
  let created = 0;

  for (const p of (parents as any[]) || []) {
    const anchorISO = p.scheduled_start_at || p.due_at;
    if (!anchorISO) continue;
    const dtstart = new Date(anchorISO);
    const durationMs = p.scheduled_start_at && p.scheduled_end_at
      ? new Date(p.scheduled_end_at).getTime() - new Date(p.scheduled_start_at).getTime()
      : 0;

    for (const occ of expandOccurrences(p.rrule, dtstart, windowStart, windowEnd, 40)) {
      const dayKey = occ.toISOString().slice(0, 10);
      const { error } = await db.from("agenda_tasks").insert({
        title: p.title,
        description: p.description,
        kind: p.kind,
        status: "pending",
        priority: p.priority,
        source: "recurrence",
        automation_key: `rec:${p.id}:${dayKey}`,
        recurrence_parent_id: p.id,
        assignee_user_id: p.assignee_user_id,
        scheduled_start_at: p.scheduled_start_at ? occ.toISOString() : null,
        scheduled_end_at: p.scheduled_start_at && durationMs
          ? new Date(occ.getTime() + durationMs).toISOString() : null,
        due_at: p.scheduled_start_at ? null : occ.toISOString(),
        all_day: p.all_day,
        location: p.location,
        client_id: p.client_id,
        related_entity_type: p.related_entity_type,
        related_entity_id: p.related_entity_id,
        is_private: p.is_private,
        checklist: Array.isArray(p.checklist)
          ? p.checklist.map((c: any) => ({ ...c, done: false }))
          : [],
        created_by: p.created_by,
      });
      // 23505 = ocorrência do dia já materializada; 23P01 = conflito de horário — pula
      if (!error) created++;
      else if (!["23505", "23P01"].includes((error as any).code)) {
        console.error("recurrence insert failed:", error);
      }
    }
  }
  return { created };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    const settings = await loadSettings(db);
    const rules = await runRules(db, settings);
    const r10 = await runTechnicianReminders(db, settings);
    const r9 = await runClientReminders(db, settings);
    const r13 = await runPostServiceSurvey(db, settings);
    const reminders = await processReminders(db);
    const recurrence = await materializeRecurrences(db);

    const summary = { rules, r10, r9, r13, reminders, recurrence };
    if (rules.created.length || rules.resolved.length || recurrence.created) {
      await audit(db, "task_automations_run", summary);
    }
    return new Response(JSON.stringify({ success: true, ...summary }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("task-automations failed:", e);
    return new Response(JSON.stringify({ success: false, error: String(e) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

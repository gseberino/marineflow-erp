// Edge Function: ai-daily-briefing
// Runs at 07:30 BRT every day (cron: 30 10 * * *).
// Generates a structured morning intelligence briefing from:
//   - Active business alerts (critical + warning)
//   - Due agent tasks
//   - Today's agenda
//   - Recent OS activity (completed / new quotes yesterday)
// Stored in ai_daily_briefings and optionally sent via WhatsApp to admin.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const respHeaders = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" };

function brl(v: unknown): string {
  return Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: { "Access-Control-Allow-Origin": "*" } });

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Auth
  const secret = req.headers.get("x-cron-secret") ?? "";
  const { data: setting } = await admin.from("app_settings").select("value").eq("key", "cron_worker_secret").single();
  if (!setting || secret !== String(setting.value)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: respHeaders });
  }

  const now = new Date();
  // BRT = UTC-3
  const brtNow = new Date(now.getTime() - 3 * 3600 * 1000);
  const todayBRT = brtNow.toISOString().split("T")[0];
  const tomorrowBRT = new Date(brtNow.getTime() + 86400000).toISOString().split("T")[0];
  const yesterdayBRT = new Date(brtNow.getTime() - 86400000).toISOString().split("T")[0];
  const todayStart = `${todayBRT}T00:00:00-03:00`;
  const todayEnd   = `${todayBRT}T23:59:59-03:00`;

  // Load app settings for company name
  const { data: settingsRows } = await admin.from("app_settings").select("key, value");
  const settings: Record<string, string> = {};
  (settingsRows || []).forEach((r: any) => { if (r.key) settings[r.key] = String(r.value ?? ""); });
  const company = settings.company_name || "MarineFlow";

  const sections: Record<string, any> = {};

  // ── 1. Critical alerts ────────────────────────────────────────────────────
  const { data: critAlerts } = await admin
    .from("ai_business_alerts")
    .select("alert_type, title, description, entity_number")
    .eq("severity", "critical")
    .is("resolved_at", null)
    .order("last_seen_at", { ascending: false })
    .limit(10);

  // ── 2. Warning alerts ────────────────────────────────────────────────────
  const { data: warnAlerts } = await admin
    .from("ai_business_alerts")
    .select("alert_type, title, description, entity_number")
    .eq("severity", "warning")
    .is("resolved_at", null)
    .order("last_seen_at", { ascending: false })
    .limit(8);

  // ── 3. Agent tasks due today or overdue ──────────────────────────────────
  const { data: dueTasks } = await admin
    .from("ai_agent_tasks")
    .select("title, description, due_at, priority, entity_number")
    .eq("status", "pending")
    .lte("due_at", todayEnd)
    .order("due_at", { ascending: true })
    .limit(10);

  // ── 4. Today's agenda ────────────────────────────────────────────────────
  const { data: todayAgenda } = await admin
    .from("agenda_tasks")
    .select("title, scheduled_start_at, location, clients(full_name_or_company_name), app_users(full_name)")
    .gte("scheduled_start_at", todayStart)
    .lte("scheduled_start_at", todayEnd)
    .not("status", "eq", "cancelled")
    .order("scheduled_start_at", { ascending: true })
    .limit(10);

  // ── 5. OS completed yesterday ────────────────────────────────────────────
  const { data: completedYesterday } = await admin
    .from("service_orders")
    .select("service_order_number, grand_total, clients(full_name_or_company_name)")
    .eq("status", "completed")
    .gte("updated_at", `${yesterdayBRT}T00:00:00-03:00`)
    .lt("updated_at", todayStart)
    .limit(5);

  // ── 6. New quotes created yesterday ─────────────────────────────────────
  const { data: newQuotes } = await admin
    .from("service_orders")
    .select("service_order_number, grand_total, clients(full_name_or_company_name)")
    .in("status", ["draft", "awaiting_client"])
    .gte("created_at", `${yesterdayBRT}T00:00:00-03:00`)
    .lt("created_at", todayStart)
    .limit(5);

  // ── Build sections ────────────────────────────────────────────────────────
  sections.critical_alerts = critAlerts || [];
  sections.warning_alerts  = warnAlerts || [];
  sections.tasks_due       = dueTasks || [];
  sections.agenda_today    = (todayAgenda || []).map((a: any) => ({
    title: a.title,
    time: new Date(a.scheduled_start_at).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }),
    client: a.clients?.full_name_or_company_name,
    technician: a.app_users?.full_name,
    location: a.location,
  }));
  sections.completed_yesterday = (completedYesterday || []).map((so: any) => ({
    number: so.service_order_number,
    client: so.clients?.full_name_or_company_name,
    value: so.grand_total ? `R$ ${brl(so.grand_total)}` : null,
  }));
  sections.new_quotes = (newQuotes || []).map((so: any) => ({
    number: so.service_order_number,
    client: so.clients?.full_name_or_company_name,
    value: so.grand_total ? `R$ ${brl(so.grand_total)}` : null,
  }));

  // ── Build summary text ────────────────────────────────────────────────────
  const lines: string[] = [
    `📊 *Briefing ${company} — ${brtNow.toLocaleDateString("pt-BR", { weekday: "long", day: "numeric", month: "long" })}*`,
    "",
  ];

  const critCount = sections.critical_alerts.length;
  const warnCount = sections.warning_alerts.length;
  const taskCount = sections.tasks_due.length;
  const agendaCount = sections.agenda_today.length;

  if (critCount > 0) {
    lines.push(`🔴 *${critCount} alerta(s) CRÍTICO(S):*`);
    for (const a of sections.critical_alerts) {
      lines.push(`  • ${a.title}`);
    }
    lines.push("");
  }
  if (warnCount > 0) {
    lines.push(`🟡 *${warnCount} aviso(s):*`);
    for (const a of sections.warning_alerts) {
      lines.push(`  • ${a.title}`);
    }
    lines.push("");
  }
  if (taskCount > 0) {
    lines.push(`📌 *${taskCount} tarefa(s) vencida(s)/vencendo:*`);
    for (const t of sections.tasks_due) {
      const overdue = new Date(t.due_at) < now;
      lines.push(`  • ${overdue ? "⚠️ " : ""}${t.title}`);
    }
    lines.push("");
  }
  if (agendaCount > 0) {
    lines.push(`📅 *Agenda de hoje (${agendaCount} compromisso${agendaCount !== 1 ? "s" : ""}):*`);
    for (const a of sections.agenda_today) {
      lines.push(`  • ${a.time} — ${a.title}${a.client ? ` (${a.client})` : ""}${a.location ? ` @ ${a.location}` : ""}`);
    }
    lines.push("");
  }
  if (sections.completed_yesterday.length > 0) {
    lines.push(`✅ *Concluídos ontem:*`);
    for (const so of sections.completed_yesterday) {
      lines.push(`  • ${so.number} — ${so.client || "—"}${so.value ? ` | ${so.value}` : ""}`);
    }
    lines.push("");
  }
  if (sections.new_quotes.length > 0) {
    lines.push(`📝 *Orçamentos criados ontem:*`);
    for (const so of sections.new_quotes) {
      lines.push(`  • ${so.number} — ${so.client || "—"}${so.value ? ` | ${so.value}` : ""}`);
    }
    lines.push("");
  }
  if (critCount === 0 && warnCount === 0 && taskCount === 0) {
    lines.push("✨ Tudo tranquilo! Nenhum alerta crítico no momento.");
    lines.push("");
  }

  const summaryText = lines.join("\n").trim();

  // ── Upsert into ai_daily_briefings ───────────────────────────────────────
  const { error: upsertErr } = await admin.from("ai_daily_briefings").upsert({
    date: todayBRT,
    summary_text: summaryText,
    critical_count: critCount,
    warning_count: warnCount,
    tasks_due_count: taskCount,
    agenda_count: agendaCount,
    sections,
    generated_at: now.toISOString(),
    whatsapp_sent: false,
  }, { onConflict: "date" });

  if (upsertErr) {
    console.error("[ai-daily-briefing] upsert error:", upsertErr);
    return new Response(JSON.stringify({ ok: false, error: upsertErr.message }), { headers: respHeaders });
  }

  // ── Optionally send via WhatsApp to admin ─────────────────────────────────
  // Uses app_settings.briefing_whatsapp_phone if set
  const adminPhone = settings.briefing_whatsapp_phone || "";
  if (adminPhone) {
    try {
      const r = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-send-text`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: Deno.env.get("SUPABASE_ANON_KEY") || "",
        },
        body: JSON.stringify({ phone: adminPhone, message: summaryText }),
      });
      if (r.ok) {
        await admin
          .from("ai_daily_briefings")
          .update({ whatsapp_sent: true, whatsapp_sent_at: new Date().toISOString() })
          .eq("date", todayBRT);
      }
    } catch (e) {
      console.warn("[ai-daily-briefing] WhatsApp send failed:", e);
    }
  }

  console.log(`[ai-daily-briefing] Generated for ${todayBRT}: ${critCount} critical, ${warnCount} warnings, ${taskCount} tasks`);
  return new Response(
    JSON.stringify({ ok: true, date: todayBRT, critical_count: critCount, warning_count: warnCount }),
    { headers: respHeaders }
  );
});

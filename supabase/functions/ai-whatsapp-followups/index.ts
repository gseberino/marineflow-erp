// Edge Function: ai-whatsapp-followups
// Cron: every 30 min (*/30 * * * *)
// Processes pending ai_agent_tasks with task_type IN ('whatsapp_followup','quote_followup','satisfaction_followup')
// that are due (due_at <= now()), sends the WhatsApp, marks done, logs to ai_lifecycle_events.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const respHeaders = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: { "Access-Control-Allow-Origin": "*" } });

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Auth: cron_worker_secret in x-cron-secret header
  const secret = req.headers.get("x-cron-secret") ?? "";
  const { data: setting } = await admin
    .from("app_settings")
    .select("value")
    .eq("key", "cron_worker_secret")
    .single();
  if (!setting || secret !== String(setting.value)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: respHeaders });
  }

  const now = new Date();
  const stats = { processed: 0, sent: 0, failed: 0, skipped: 0 };

  const { data: tasks } = await admin
    .from("ai_agent_tasks")
    .select("id, title, description, task_type, entity_type, entity_id, entity_number, metadata")
    .in("task_type", ["whatsapp_followup", "quote_followup", "satisfaction_followup"])
    .eq("status", "pending")
    .lte("due_at", now.toISOString())
    .limit(20);

  for (const task of tasks ?? []) {
    stats.processed++;
    const meta = (task.metadata as Record<string, any>) || {};

    // ── Resolve phone ─────────────────────────────────────────────────────────
    let phone: string | null = meta.phone || null;
    let clientName: string | null = meta.client_name || null;
    const clientId: string | null = meta.client_id || null;

    if (!phone && clientId) {
      const { data: c } = await admin
        .from("clients")
        .select("whatsapp, phone, full_name_or_company_name")
        .eq("id", clientId)
        .maybeSingle();
      phone = c?.whatsapp || c?.phone || null;
      if (!clientName && c?.full_name_or_company_name) clientName = c.full_name_or_company_name;
    }

    // Fallback: look up via service_order → client
    if (!phone && task.entity_type === "service_order" && task.entity_id) {
      const { data: so } = await admin
        .from("service_orders")
        .select("client_id, clients(whatsapp, phone, full_name_or_company_name)")
        .eq("id", task.entity_id)
        .maybeSingle();
      if (so) {
        const c = (so.clients as any);
        phone = c?.whatsapp || c?.phone || null;
        if (!clientName && c?.full_name_or_company_name) clientName = c.full_name_or_company_name;
      }
    }

    if (!phone) {
      console.warn(`[ai-whatsapp-followups] task ${task.id} (${task.title}): no phone — skipping`);
      stats.skipped++;
      continue;
    }

    // ── Build message ─────────────────────────────────────────────────────────
    const greeting = `Olá${clientName ? ` ${clientName}` : ""}!`;
    const message: string =
      meta.message ||
      (task.entity_number
        ? `${greeting} Passando para lembrá-lo(a) sobre a OS ${task.entity_number}. ${task.description}`
        : `${greeting} ${task.description}`);

    const cleanPhone = String(phone).replace(/\D/g, "");

    // ── Send WhatsApp via whatsapp-send-text ──────────────────────────────────
    let sendOk = false;
    try {
      const r = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-send-text`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: ANON_KEY,
        },
        body: JSON.stringify({ phone: cleanPhone, message }),
      });
      sendOk = r.ok;
      if (!r.ok) {
        const body = await r.text().catch(() => "");
        console.error(
          `[ai-whatsapp-followups] task ${task.id} send failed: HTTP ${r.status} — ${body.slice(0, 200)}`
        );
      }
    } catch (e) {
      console.error(`[ai-whatsapp-followups] task ${task.id} send error:`, e);
    }

    if (sendOk) {
      stats.sent++;
      // Mark done
      await admin
        .from("ai_agent_tasks")
        .update({
          status: "done",
          metadata: { ...meta, sent_at: now.toISOString(), sent_to_phone: cleanPhone },
        })
        .eq("id", task.id);

      // Resolve the corresponding business alert
      await admin
        .from("ai_business_alerts")
        .update({ resolved_at: now.toISOString() })
        .eq("entity_id", task.id)
        .eq("alert_type", "agent_task_due")
        .is("resolved_at", null);

      // Log to ai_lifecycle_events if linked to an OS
      if (task.entity_type === "service_order" && task.entity_id) {
        await admin
          .from("ai_lifecycle_events")
          .insert({
            entity_type: "service_order",
            entity_id: task.entity_id,
            event_type: "whatsapp_followup_sent",
            new_value: task.task_type,
            metadata: {
              phone: cleanPhone,
              task_id: task.id,
              task_title: task.title,
              message_preview: message.slice(0, 120),
            },
          })
          .catch((e: any) =>
            console.warn("[ai-whatsapp-followups] lifecycle log error:", e?.message)
          );
      }
    } else {
      stats.failed++;
    }
  }

  console.log(`[ai-whatsapp-followups] ${JSON.stringify(stats)}`);
  return new Response(
    JSON.stringify({ ok: stats.failed === 0, ...stats }),
    { headers: respHeaders }
  );
});

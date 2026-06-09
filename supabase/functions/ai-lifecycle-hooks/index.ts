// Edge Function: ai-lifecycle-hooks
// Called by a PostgreSQL trigger whenever a service_order status changes.
// Logs the event and immediately resolves stale business alerts so the agent
// doesn't need to wait for the next hourly monitor run.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const respHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
};

// Alert types that reference a service_order entity_id
const SO_ALERT_TYPES = [
  "os_awaiting_client_long",
  "os_awaiting_parts_long",
  "os_completed_not_invoiced",
  "os_no_technician",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*" } });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Auth: same secret as cron workers
  const secret = req.headers.get("x-trigger-secret") ?? "";
  const { data: setting } = await admin
    .from("app_settings")
    .select("value")
    .eq("key", "cron_worker_secret")
    .single();
  if (!setting || secret !== String(setting.value)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: respHeaders,
    });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: respHeaders,
    });
  }

  const {
    service_order_id,
    service_order_number,
    old_status,
    new_status,
    client_id,
    invoicing_status,
    grand_total,
  } = body;

  if (!service_order_id || !old_status || !new_status) {
    return new Response(JSON.stringify({ error: "Missing required fields" }), {
      status: 400,
      headers: respHeaders,
    });
  }

  const now = new Date().toISOString();
  const actions: string[] = [];

  // ── 1. Log the lifecycle event ───────────────────────────────────────────
  const { error: logErr } = await admin.from("ai_lifecycle_events").insert({
    entity_type: "service_order",
    entity_id: service_order_id,
    entity_number: service_order_number,
    event_type: "status_change",
    old_value: old_status,
    new_value: new_status,
    metadata: { client_id, invoicing_status, grand_total },
  });
  if (!logErr) actions.push("logged_event");

  // ── 2. Resolve alerts whose condition no longer applies ──────────────────
  async function resolveAlert(alertType: string): Promise<void> {
    const { error } = await admin
      .from("ai_business_alerts")
      .update({ resolved_at: now })
      .eq("alert_type", alertType)
      .eq("entity_id", service_order_id)
      .is("resolved_at", null);
    if (!error) actions.push(`resolved:${alertType}`);
  }

  async function resolveAllSoAlerts(): Promise<void> {
    const { error } = await admin
      .from("ai_business_alerts")
      .update({ resolved_at: now })
      .eq("entity_id", service_order_id)
      .in("alert_type", SO_ALERT_TYPES)
      .is("resolved_at", null);
    if (!error) actions.push("resolved:all_so_alerts");
  }

  // Approved / invoiced / cancelled → clear "awaiting client" alert
  if (["approved", "invoiced", "cancelled", "in_progress"].includes(new_status)) {
    await resolveAlert("os_awaiting_client_long");
  }

  // In_progress / completed / cancelled → clear "awaiting parts"
  if (["in_progress", "completed", "invoiced", "cancelled"].includes(new_status)) {
    await resolveAlert("os_awaiting_parts_long");
  }

  // Invoiced / cancelled → clear "completed not invoiced"
  if (["invoiced", "cancelled"].includes(new_status)) {
    await resolveAlert("os_completed_not_invoiced");
  }

  // Cancelled → clear everything
  if (new_status === "cancelled") {
    await resolveAllSoAlerts();
  }

  // Technician assigned elsewhere resolves os_no_technician —
  // but that's triggered by service_order_technicians inserts, not status changes.
  // The hourly cron handles that case.

  // ── 3. Immediately flag completed-but-not-invoiced if transitioned now ──
  // (Don't wait for the hourly cron — surface it right away)
  if (new_status === "completed" && invoicing_status === "not_invoiced" && grand_total) {
    const { data: clientData } = await admin
      .from("clients")
      .select("full_name_or_company_name")
      .eq("id", client_id)
      .maybeSingle();
    const clientName = clientData?.full_name_or_company_name ?? "—";
    const brl = Number(grand_total).toLocaleString("pt-BR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
    await admin.from("ai_business_alerts").upsert(
      {
        alert_type: "os_completed_not_invoiced",
        severity: "warning",
        title: `OS ${service_order_number} concluída — faturar`,
        description: `OS ${service_order_number} (${clientName}) acabou de ser concluída. Valor: R$ ${brl}. Fature para não perder o prazo.`,
        entity_type: "service_order",
        entity_id: service_order_id,
        entity_number: service_order_number,
        metadata: { grand_total, triggered_by: "lifecycle_hook" },
        last_seen_at: now,
        resolved_at: null,
      },
      { onConflict: "alert_type,entity_id" }
    );
    actions.push("created:os_completed_not_invoiced");
  }

  console.log(
    `[ai-lifecycle-hooks] ${service_order_number}: ${old_status} → ${new_status} | ${actions.join(", ")}`
  );

  return new Response(
    JSON.stringify({ ok: true, transition: `${old_status}→${new_status}`, actions }),
    { headers: respHeaders }
  );
});

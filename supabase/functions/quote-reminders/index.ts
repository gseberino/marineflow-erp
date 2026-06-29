// Edge Function: quote-reminders
// Runs daily via cron at 09:00 BRT.
// 1. FOLLOW-UP: quotes stuck in sent/awaiting_approval for > quote_followup_days → queue WhatsApp follow-up
// 2. EXPIRY:    quotes stuck in sent/awaiting_approval/awaiting_deposit for > quote_expiry_days → mark rejected

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL    = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin           = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Load configurable thresholds from app_settings
    const { data: settings } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["quote_followup_days", "quote_expiry_days"]);

    const sMap = Object.fromEntries((settings || []).map((s: any) => [s.key, Number(s.value)]));
    const followupDays = sMap["quote_followup_days"] ?? 7;
    const expiryDays   = sMap["quote_expiry_days"]   ?? 30;

    const now = new Date();

    // Helper: date N days ago as ISO string
    const daysAgo = (n: number) => new Date(now.getTime() - n * 86400000).toISOString();

    const results = { followups: 0, expired: 0, errors: 0 };

    // ── 1. EXPIRY ──────────────────────────────────────────────────────────────
    // Quotes older than expiry_days with no conversion → mark rejected
    const { data: expiredQuotes, error: expErr } = await admin
      .from("service_orders")
      .select("id, service_order_number")
      .eq("status", "draft")
      .is("converted_to_os_at", null)
      .in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"])
      .lt("created_at", daysAgo(expiryDays));

    if (expErr) throw expErr;

    for (const q of expiredQuotes || []) {
      const { error } = await admin
        .from("service_orders")
        .update({ quote_status: "rejected" } as any)
        .eq("id", q.id);
      if (error) { results.errors++; console.error("expiry update failed", q.id, error); }
      else results.expired++;
    }

    // ── 2. FOLLOW-UP ───────────────────────────────────────────────────────────
    // Quotes stuck in sent/awaiting_approval for > followup_days → queue reminder
    const { data: stuckQuotes, error: stuckErr } = await admin
      .from("service_orders")
      .select(`
        id, service_order_number, grand_total, share_token,
        clients(name, whatsapp, phone)
      `)
      .eq("status", "draft")
      .is("converted_to_os_at", null)
      .in("quote_status", ["sent", "awaiting_approval"])
      .lt("updated_at", daysAgo(followupDays));

    if (stuckErr) throw stuckErr;

    for (const q of stuckQuotes || []) {
      const client: any = q.clients;
      const phone = client?.whatsapp || client?.phone;
      if (!phone || !q.share_token) continue;

      const url     = `${SUPABASE_URL.replace("supabase.co", "supabase.co")}/view/${q.share_token}`;
      const message = `Olá${client?.name ? " " + client.name.split(" ")[0] : ""}! Passando para lembrar do orçamento *${q.service_order_number}* que enviamos. Ficou alguma dúvida ou podemos ajudar em algo? 😊\n${url}`;

      const { error: qErr } = await admin.from("whatsapp_send_queue").insert({
        service_order_id: q.id,
        phone,
        message,
        kind:    "text",
        context: "quote_followup",
        status:  "pending",
      });

      if (qErr) { results.errors++; console.error("queue insert failed", q.id, qErr); }
      else {
        results.followups++;
        // Advance quote_status so we don't send duplicate reminders today
        await admin
          .from("service_orders")
          .update({ quote_status: "awaiting_approval" } as any)
          .eq("id", q.id)
          .eq("quote_status" as any, "sent");
      }
    }

    console.log("quote-reminders done", results);
    return jr({ ok: true, ...results });

  } catch (err: any) {
    console.error("quote-reminders error", err);
    return jr({ error: err.message }, 500);
  }
});

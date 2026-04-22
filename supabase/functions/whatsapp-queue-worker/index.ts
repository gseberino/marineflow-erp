// Edge Function: whatsapp-queue-worker
// Roda via cron a cada minuto. Pega mensagens pendentes da fila
// (whatsapp_send_queue), aplica rate limit (max por execução +
// limite global por hora) e envia via Z-API com delay entre cada uma.
//
// Settings (app_settings):
//   whatsapp_queue_enabled       (bool string)  default 'true'
//   whatsapp_queue_max_per_run   (int)          default 5
//   whatsapp_queue_delay_ms      (int)          default 1500
//   whatsapp_queue_max_per_hour  (int)          default 60

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function getSetting(
  admin: ReturnType<typeof createClient>,
  key: string,
  fallback: string,
): Promise<string> {
  const { data } = await admin.from("app_settings").select("value").eq("key", key).maybeSingle();
  return ((data?.value as string) ?? "") || fallback;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const INSTANCE_ID = Deno.env.get("ZAPI_INSTANCE_ID");
    const TOKEN = Deno.env.get("ZAPI_TOKEN");
    const CLIENT_TOKEN = Deno.env.get("ZAPI_CLIENT_TOKEN");
    if (!INSTANCE_ID || !TOKEN) return jr({ error: "Z-API não configurado" }, 500);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const enabled = await getSetting(admin, "whatsapp_queue_enabled", "true");
    if (enabled !== "true") {
      return jr({ ok: true, skipped: "queue_disabled" });
    }

    const maxPerRun = Math.max(1, parseInt(await getSetting(admin, "whatsapp_queue_max_per_run", "5"), 10));
    const delayMs = Math.max(0, parseInt(await getSetting(admin, "whatsapp_queue_delay_ms", "1500"), 10));
    const maxPerHour = Math.max(1, parseInt(await getSetting(admin, "whatsapp_queue_max_per_hour", "60"), 10));

    // Rate limit global: contar enviados na última hora
    const sinceHour = new Date(Date.now() - 60 * 60_000).toISOString();
    const { count: sentLastHour } = await admin
      .from("whatsapp_send_queue")
      .select("id", { count: "exact", head: true })
      .eq("status", "sent")
      .gte("sent_at", sinceHour);

    const remainingHourly = Math.max(0, maxPerHour - (sentLastHour || 0));
    if (remainingHourly === 0) {
      return jr({
        ok: true,
        skipped: "hourly_limit_reached",
        sent_last_hour: sentLastHour,
        max_per_hour: maxPerHour,
      });
    }

    const batchSize = Math.min(maxPerRun, remainingHourly);

    // Pega lote: pending + scheduled_for <= now, prioridade ASC, mais antigos primeiro
    const nowIso = new Date().toISOString();
    const { data: batch, error: fetchErr } = await admin
      .from("whatsapp_send_queue")
      .select("*")
      .eq("status", "pending")
      .lte("scheduled_for", nowIso)
      .order("priority", { ascending: true })
      .order("created_at", { ascending: true })
      .limit(batchSize);

    if (fetchErr) return jr({ error: fetchErr.message }, 500);
    if (!batch || batch.length === 0) {
      return jr({ ok: true, processed: 0, remaining_hourly: remainingHourly });
    }

    // Marca todos como 'sending' já (lock otimista)
    const ids = batch.map((b: any) => b.id);
    await admin
      .from("whatsapp_send_queue")
      .update({ status: "sending", processing_started_at: nowIso })
      .in("id", ids)
      .eq("status", "pending");

    const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;
    const zHeaders: Record<string, string> = { "Content-Type": "application/json" };
    if (CLIENT_TOKEN) zHeaders["Client-Token"] = CLIENT_TOKEN;

    const results: any[] = [];
    for (let i = 0; i < batch.length; i++) {
      const item: any = batch[i];
      try {
        const res = await fetch(`${base}/send-text`, {
          method: "POST",
          headers: zHeaders,
          body: JSON.stringify({ phone: item.phone_normalized, message: item.message }),
        });
        const body = await res.json().catch(() => ({}));
        const ok = res.ok && !(body as any).error;

        if (ok) {
          await admin.from("whatsapp_send_queue").update({
            status: "sent",
            sent_at: new Date().toISOString(),
            zapi_message_id: (body as any)?.messageId || (body as any)?.id || null,
            attempts: (item.attempts || 0) + 1,
          }).eq("id", item.id);
          results.push({ id: item.id, ok: true });
        } else {
          const newAttempts = (item.attempts || 0) + 1;
          const giveUp = newAttempts >= (item.max_attempts || 3);
          await admin.from("whatsapp_send_queue").update({
            status: giveUp ? "failed" : "pending",
            attempts: newAttempts,
            failed_reason: (body as any)?.error || `HTTP ${res.status}`,
            scheduled_for: giveUp ? item.scheduled_for : new Date(Date.now() + 5 * 60_000).toISOString(),
            processing_started_at: null,
          }).eq("id", item.id);
          results.push({ id: item.id, ok: false, error: (body as any)?.error || `HTTP ${res.status}`, give_up: giveUp });
        }
      } catch (e) {
        const newAttempts = (item.attempts || 0) + 1;
        const giveUp = newAttempts >= (item.max_attempts || 3);
        await admin.from("whatsapp_send_queue").update({
          status: giveUp ? "failed" : "pending",
          attempts: newAttempts,
          failed_reason: e instanceof Error ? e.message : String(e),
          scheduled_for: giveUp ? item.scheduled_for : new Date(Date.now() + 5 * 60_000).toISOString(),
          processing_started_at: null,
        }).eq("id", item.id);
        results.push({ id: item.id, ok: false, error: e instanceof Error ? e.message : String(e), give_up: giveUp });
      }

      // delay entre envios (não no último)
      if (i < batch.length - 1 && delayMs > 0) await sleep(delayMs);
    }

    return jr({
      ok: true,
      processed: results.length,
      sent_last_hour_before: sentLastHour,
      max_per_hour: maxPerHour,
      remaining_hourly_after: Math.max(0, remainingHourly - results.filter((r) => r.ok).length),
      results,
    });
  } catch (err) {
    console.error("whatsapp-queue-worker error", err);
    return jr({ error: err instanceof Error ? err.message : "Unknown error" }, 500);
  }
});

// Edge Function: whatsapp-queue-worker
// Roda via cron a cada minuto. Pega mensagens pendentes da fila
// (whatsapp_send_queue), aplica rate limit (max por execução +
// limite global por hora) e envia via provider ativo com delay entre cada uma.
//
// Settings (app_settings):
//   whatsapp_queue_enabled       (bool string)  default 'true'
//   whatsapp_queue_max_per_run   (int)          default 5
//   whatsapp_queue_delay_ms      (int)          default 1500
//   whatsapp_queue_max_per_hour  (int)          default 60

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { enviarLote } from "./enviar.ts";

// O tipo de createClient sem o esquema gerado não casa com o cliente criado aqui (TS2345).
// deno-lint-ignore no-explicit-any
type DbClient = any;

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
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
  admin: DbClient,
  key: string,
  fallback: string,
): Promise<string> {
  const { data } = await admin.from("app_settings").select("value").eq("key", key).maybeSingle();
  return ((data?.value as string) ?? "") || fallback;
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Autenticação ANTES de qualquer I/O: sem o segredo do cron, ninguém dispara a
  // fila (o que faria sair mensagem de verdade e esgotar o limite por hora).
  const recusa = verificarCronSecret(req, corsHeaders, "whatsapp-queue-worker");
  if (recusa) return recusa;

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

    // Marca todos como 'sending' (lock otimista)
    const ids = batch.map((b: any) => b.id);
    await admin
      .from("whatsapp_send_queue")
      .update({ status: "sending", processing_started_at: nowIso })
      .in("id", ids)
      .eq("status", "pending");

    const provider = createWhatsAppProvider();
    // O laço do envio mora em enviar.ts (Agenda de Produção, Fase 3, P7b): o mesmo de antes para toda origem, e a janela
    // da agenda conferida na hora para as linhas da agenda (NOVO-agenda-26).
    const results = await enviarLote(admin, provider, batch, { delayMs });

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

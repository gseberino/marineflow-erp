// Edge Function: whatsapp-process-scheduled
// Executada periodicamente pelo pg_cron. Busca agendamentos com next_run_at <= now()
// status='pending', invoca whatsapp-send para cada um, e calcula a próxima execução
// se for recorrente.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Pega lote de agendamentos pendentes
    const nowIso = new Date().toISOString();

    // ── Zombie recovery ──────────────────────────────────────────────────────
    // If a job got stuck in 'processing' for more than 10 minutes (e.g. due to
    // a function timeout or provider hang), reset it back to 'pending' so it can
    // be retried on the next cron tick. Without this, a timed-out job stays
    // in 'processing' forever and is never retried.
    const zombieThreshold = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    await admin
      .from("whatsapp_scheduled_sends")
      .update({ status: "pending", last_error: "Recovered from stuck processing state (timeout)" })
      .eq("status", "processing")
      .lt("updated_at", zombieThreshold);
    // ─────────────────────────────────────────────────────────────────────────

    const { data: due, error: dueErr } = await admin
      .from("whatsapp_scheduled_sends")
      .select("*")
      .eq("status", "pending")
      .lte("next_run_at", nowIso)
      .order("next_run_at", { ascending: true })
      .limit(20);

    if (dueErr) return jr({ error: dueErr.message }, 500);
    if (!due || due.length === 0) return jr({ processed: 0 });

    // Lê URL pública do app a partir de app_settings (com fallback para env var)
    const { data: urlSetting } = await admin
      .from("app_settings")
      .select("value")
      .eq("key", "app_public_url")
      .maybeSingle();
    const baseUrl = String(urlSetting?.value || Deno.env.get("APP_PUBLIC_URL") || "https://hbrmarine.online");

    let processed = 0;
    let succeeded = 0;
    let failed = 0;

    for (const job of due) {
      processed++;

      // Marca como processing
      await admin
        .from("whatsapp_scheduled_sends")
        .update({ status: "processing", attempt_count: (job.attempt_count || 0) + 1 })
        .eq("id", job.id);

      // Se baseUrl não foi configurada, marca como failed e pula (sem exceção)
      if (!baseUrl) {
        failed++;
        await admin
          .from("whatsapp_scheduled_sends")
          .update({
            status: "failed",
            last_error: "APP_PUBLIC_URL não configurada. Configure em Configurações → Empresa.",
          })
          .eq("id", job.id);
        continue;
      }

      try {
        console.log('[whatsapp-process-scheduled] iniciando processamento', new Date().toISOString());
        // Chama whatsapp-send via fetch interno
        const sendUrl = `${SUPABASE_URL}/functions/v1/whatsapp-send`;
        const payload: Record<string, unknown> = {
          phone: job.phone,
          message: job.message,
          context: job.context || (job.target_kind === 'service_order' ? 'service_order' : 'billing'),
        };
        if (job.service_order_id) payload.service_order_id = job.service_order_id;
        if (job.receivable_id) payload.receivable_id = job.receivable_id;

        if (job.send_mode === "text") {
          // Envio de texto puro — a mensagem já está em payload.message
          payload.kind = "text";
        } else if (job.send_mode === "link") {
          // precisa do share_token
          let shareToken: string | null = null;
          if (job.service_order_id) {
            const { data: so } = await admin
              .from("service_orders")
              .select("share_token")
              .eq("id", job.service_order_id)
              .maybeSingle();
            shareToken = so?.share_token || null;
          }
          if (!shareToken) throw new Error("share_token indisponível para envio link");
          payload.kind = "link";
          payload.link_url = `${baseUrl}/view/${shareToken}`;
          payload.link_title = job.link_title || "";
          payload.link_description = job.link_description || "";
        } else {
          // document mode: requer URL pré-existente — agendamento de PDF não regenera
          // (geração de PDF acontece no client). Para agendamentos de documento, exigimos
          // que o usuário tenha um PDF estático armazenado (futuro). Por ora, fallback para link.
          let shareToken: string | null = null;
          if (job.service_order_id) {
            const { data: so } = await admin
              .from("service_orders")
              .select("share_token")
              .eq("id", job.service_order_id)
              .maybeSingle();
            shareToken = so?.share_token || null;
          }
          if (!shareToken) throw new Error("share_token indisponível");
          payload.kind = "link";
          payload.link_url = `${baseUrl}/view/${shareToken}`;
          payload.link_title = job.link_title || "";
          payload.link_description = job.link_description || "";
        }

        const res = await fetch(sendUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${SERVICE_ROLE}`,
          },
          body: JSON.stringify(payload),
        });
        const body = await res.json().catch(() => ({}));
        const ok = res.ok && !(body as any).error;

        if (!ok) throw new Error((body as any).error || `HTTP ${res.status}`);

        succeeded++;

        // Calcula próxima execução se for recorrente
        let nextRun: string | null = null;
        let newStatus = "sent";
        if (job.recurrence_type !== "once") {
          const { data: nextRes } = await admin.rpc("compute_next_run", {
            _from: nowIso,
            _recurrence_type: job.recurrence_type,
            _days_of_week: job.recurrence_days_of_week,
            _day_of_month: job.recurrence_day_of_month,
          });
          if (nextRes) {
            const nextDate = new Date(nextRes as string);
            // respeita end_date
            if (!job.recurrence_end_date || nextDate <= new Date(job.recurrence_end_date)) {
              nextRun = nextDate.toISOString();
              newStatus = "pending";
            }
          }
        }

        await admin
          .from("whatsapp_scheduled_sends")
          .update({
            status: newStatus,
            last_run_at: nowIso,
            next_run_at: nextRun || job.next_run_at,
            last_error: null,
            last_response: body,
            attempt_count: 0,
          })
          .eq("id", job.id);
      } catch (err) {
        failed++;
        const errMsg = err instanceof Error ? err.message : String(err);
        const shouldRetry =
          job.auto_retry && (job.attempt_count || 0) + 1 < (job.max_attempts || 3);
        await admin
          .from("whatsapp_scheduled_sends")
          .update({
            status: shouldRetry ? "pending" : "failed",
            last_error: errMsg,
            // Se retry: tenta de novo em 5min; senão mantém next_run_at
            next_run_at: shouldRetry
              ? new Date(Date.now() + 5 * 60 * 1000).toISOString()
              : job.next_run_at,
          })
          .eq("id", job.id);
      }
    }

    return jr({ processed, succeeded, failed });
  } catch (err) {
    console.error("whatsapp-process-scheduled error", err);
    return jr({ error: err instanceof Error ? err.message : "Unknown error" }, 500);
  }
});

// Edge Function: ai-business-monitor (Fase 5)
// Vigia sinais do negócio de hora em hora e avisa a EQUIPE (usuários com IA habilitada)
// por WhatsApp. Deduplicado por dia via ai_operator_alerts_log, então mesmo rodando de
// hora em hora, cada sinal alerta no máximo uma vez por dia.
//
// Sinais v1:
//   (1) Recebíveis que venceram HOJE (precisam de cobrança).
//   (2) Orçamentos parados há mais de 7 dias sem resposta.
// Destinatários são INTERNOS → envio pela fila (whatsapp_send_queue).
// Agendado via pg_cron (jobid 5, ai-business-monitor, hora em hora) — DESATIVADO até validação.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) return jr({ error: "Unauthorized" }, 401);

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: cn } = await admin.from("app_settings").select("value").eq("key", "company_name").maybeSingle();
    const companyName = (cn?.value as string) || "MarineFlow";

    const { data: recipients } = await admin
      .from("app_users").select("phone_normalized")
      .eq("ai_whatsapp_enabled", true).eq("active", true).not("phone_normalized", "is", null);
    if (!recipients || recipients.length === 0) return jr({ ok: true, sent: 0, reason: "no_recipients" });

    const now = new Date();
    const todayISO = now.toISOString().slice(0, 10);
    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

    async function claim(alert_key: string, meta: any): Promise<boolean> {
      const { data } = await admin.from("ai_operator_alerts_log")
        .upsert({ alert_key, meta }, { onConflict: "alert_key", ignoreDuplicates: true }).select("id");
      return (data?.length ?? 0) > 0;
    }

    const alerts: string[] = [];

    // (1) Recebíveis vencidos HOJE
    const { data: dueToday } = await admin
      .from("receivables").select("balance_amount, amount")
      .in("status", ["pending", "partially_paid"]).eq("is_deposit", false).eq("due_date", todayISO);
    if ((dueToday?.length ?? 0) > 0 && await claim(`overdue_today:${todayISO}`, { n: dueToday!.length })) {
      const sum = dueToday!.reduce((a: number, r: any) => a + Number(r.balance_amount ?? r.amount ?? 0), 0);
      alerts.push(`💸 *${dueToday!.length}* recebível(is) vence(m) hoje — total ${fmt.format(sum)}. Vale acionar a cobrança.`);
    }

    // (2) Orçamentos parados há mais de 7 dias
    const d7 = new Date(now.getTime() - 7 * 864e5).toISOString();
    const { count: staleQuotes } = await admin
      .from("service_orders").select("id", { count: "exact", head: true })
      .eq("status", "draft").in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"])
      .lt("created_at", d7);
    if ((staleQuotes ?? 0) > 0 && await claim(`stale_quotes:${todayISO}`, { n: staleQuotes })) {
      alerts.push(`📄 *${staleQuotes}* orçamento(s) parado(s) há mais de 7 dias sem resposta. Talvez valha um follow-up.`);
    }

    if (alerts.length === 0) return jr({ ok: true, queued: 0, note: "sem sinais novos hoje" });

    const message = [`🔔 *Alerta ${companyName}*`, "", ...alerts, "", "_Me chame aqui se quiser que eu ajude com qualquer um desses._"].join("\n");
    const rows = recipients.map((r: any) => ({ phone_normalized: String(r.phone_normalized), message, source: "ai_monitor", priority: 5 }));
    const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
    if (qErr) throw qErr;

    return jr({ ok: true, queued: inserted?.length ?? 0, signals: alerts.length });
  } catch (e: any) {
    console.error("[ai-business-monitor] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

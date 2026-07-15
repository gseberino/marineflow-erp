// Edge Function: ai-daily-briefing (Fase 5)
// Envia um resumo matinal por WhatsApp para os usuários com o canal de IA habilitado
// (app_users.ai_whatsapp_enabled = true). Determinístico: junta os números-chave do dia
// (recebíveis vencidos, orçamentos aguardando, agendamentos de hoje, aprovações pendentes)
// e enfileira a mensagem em whatsapp_send_queue (o whatsapp-queue-worker entrega).
//
// Destinatários são INTERNOS (a própria equipe), então o envio direto pela fila é adequado.
// Agendado via pg_cron (jobid 6, ai-daily-briefing, 10:30 UTC) — DESATIVADO até validação.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret) {
    const incoming = req.headers.get("x-cron-secret");
    if (incoming !== cronSecret) return jr({ error: "Unauthorized" }, 401);
  }

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: cn } = await admin.from("app_settings").select("value").eq("key", "company_name").maybeSingle();
    const companyName = (cn?.value as string) || "MarineFlow";

    // Destinatários: quem usa a IA (canal habilitado) e está ativo, com número.
    const { data: recipients } = await admin
      .from("app_users")
      .select("full_name, phone_normalized")
      .eq("ai_whatsapp_enabled", true)
      .eq("active", true)
      .not("phone_normalized", "is", null);

    if (!recipients || recipients.length === 0) return jr({ ok: true, sent: 0, reason: "no_recipients" });

    const now = new Date();
    const todayISO = now.toISOString().slice(0, 10);
    const dayStart = `${todayISO}T00:00:00`;
    const tomorrow = new Date(now.getTime() + 86400000).toISOString().slice(0, 10);
    const dayEnd = `${tomorrow}T00:00:00`;

    // ── Métricas do dia ──
    const { data: overdueRows } = await admin
      .from("receivables")
      .select("balance_amount, amount")
      .in("status", ["pending", "partially_paid"])
      .eq("is_deposit", false)
      .lt("due_date", todayISO);
    const overdueCount = overdueRows?.length ?? 0;
    const overdueSum = (overdueRows || []).reduce((a: number, r: any) => a + Number(r.balance_amount ?? r.amount ?? 0), 0);

    const { count: quotesCount } = await admin
      .from("service_orders")
      .select("id", { count: "exact", head: true })
      .eq("status", "draft")
      .in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"]);

    const { count: scheduledCount } = await admin
      .from("service_orders")
      .select("id", { count: "exact", head: true })
      .gte("scheduled_start_at", dayStart)
      .lt("scheduled_start_at", dayEnd);

    const { count: pendingCount } = await admin
      .from("ai_operator_pending_actions")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending");

    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
    const dateBR = now.toLocaleDateString("pt-BR", { weekday: "long", day: "2-digit", month: "long" });

    const linhas = [
      `☀️ *Bom dia! Resumo de ${dateBR}*`,
      "",
      `📅 Agendamentos hoje: *${scheduledCount ?? 0}*`,
      `📄 Orçamentos aguardando resposta: *${quotesCount ?? 0}*`,
      `💸 Recebíveis vencidos: *${overdueCount}*${overdueCount > 0 ? ` (${fmt.format(overdueSum)})` : ""}`,
      `✅ Aprovações da IA pendentes: *${pendingCount ?? 0}*`,
      "",
      `_Enviado pelo assistente de ${companyName}. Responda por aqui para pedir qualquer coisa._`,
    ];
    const message = linhas.join("\n");

    // Enfileira uma mensagem por destinatário. O whatsapp-queue-worker (cron de 1min) entrega.
    const rows = recipients.map((rec: any) => ({
      phone_normalized: String(rec.phone_normalized),
      message,
      source: "ai_briefing",
      priority: 4,
    }));
    const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
    if (qErr) throw qErr;

    return jr({
      ok: true,
      queued: inserted?.length ?? 0,
      metrics: { scheduled: scheduledCount ?? 0, quotes: quotesCount ?? 0, overdue: overdueCount, overdue_sum: overdueSum, pending: pendingCount ?? 0 },
    });
  } catch (e: any) {
    console.error("[ai-daily-briefing] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

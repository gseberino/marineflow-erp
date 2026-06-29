// Edge Function: receivable-reminders
// Runs daily via pg_cron at 11:00 UTC (08:00 BRT).
// Sends WhatsApp reminders for receivables due in 3 days that haven't received a reminder yet.
// Mirrors the pattern of scheduling-automations: calls whatsapp-send directly.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import { normalizePhoneNumber } from "../_shared/whatsapp/normalize.ts";

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

  // Verifica segredo de cron
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret) {
    const incoming = req.headers.get("x-cron-secret");
    if (incoming !== cronSecret) {
      return jr({ error: "Unauthorized" }, 401);
    }
  }

  try {
    const SUPABASE_URL  = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin         = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Carrega configurações operacionais (modo de teste)
    const { data: settings } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["wa_test_mode", "wa_test_number", "zapi_test_mode", "zapi_test_number",
                   "receivable_reminder_days_before", "company_name"]);
    const settingsMap = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));

    const testMode   = (settingsMap["wa_test_mode"] ?? settingsMap["zapi_test_mode"]) === "true";
    const testNumber = ((settingsMap["wa_test_number"] ?? settingsMap["zapi_test_number"]) || "").replace(/\D/g, "");
    const companyName = settingsMap["company_name"] || "MarineFlow";

    // Modo de teste ativo sem número → aborta para não vazar dados
    if (testMode && !testNumber) {
      console.warn("[receivable-reminders] TEST MODE ativo mas sem número de redirecionamento. Abortando.");
      return jr({ ok: false, skipped: 0, reason: "test_mode_no_number" });
    }

    const daysBefore = parseInt(settingsMap["receivable_reminder_days_before"] || "3", 10);
    const targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + daysBefore);
    const targetISO = targetDate.toISOString().slice(0, 10); // YYYY-MM-DD

    // Busca recebíveis que vencem em exactly `daysBefore` dias e ainda não receberam lembrete
    const { data: receivables, error } = await admin
      .from("receivables")
      .select(`
        id, amount, balance_amount, due_date, description, service_order_id,
        clients!receivables_client_id_fkey(name, whatsapp, phone),
        service_orders!receivables_service_order_id_fkey(service_order_number)
      `)
      .in("status", ["pending", "partially_paid"])
      .eq("due_date", targetISO)
      .is("reminder_sent_at", null)
      .is("is_deposit", false); // Não enviar lembrete para sinais/depósitos

    if (error) throw error;

    const provider = createWhatsAppProvider();
    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

    let sent = 0, skipped = 0, errors = 0;

    for (const rec of receivables || []) {
      const client: any = rec.clients;
      const originalPhone = (client?.whatsapp || client?.phone || "").replace(/\D/g, "");

      if (!originalPhone || originalPhone.length < 10) {
        skipped++;
        console.log(`[receivable-reminders] skipped ${rec.id} — sem telefone`);
        continue;
      }

      const phoneClean = testMode && testNumber ? testNumber : normalizePhoneNumber(originalPhone);

      const dueDate  = new Date(rec.due_date + "T12:00:00");
      const dueDateBR = dueDate.toLocaleDateString("pt-BR");
      const clientFirstName = (client?.name || "").split(" ")[0] || "Cliente";
      const soNumber = (rec as any).service_orders?.service_order_number || "";
      const description = rec.description || (soNumber ? `OS ${soNumber}` : "cobrança pendente");
      const balanceValue = Number(rec.balance_amount || rec.amount);

      const message =
        `Olá ${clientFirstName}! 👋 Lembramos que o pagamento de *${fmt.format(balanceValue)}* ` +
        `referente a *${description}* vence em *${daysBefore} dia${daysBefore !== 1 ? "s" : ""}* ` +
        `(*${dueDateBR}*). Em caso de dúvidas, entre em contato. — *${companyName}*`;

      if (testMode) {
        console.log(`[receivable-reminders] TEST MODE: enviando para ${testNumber} (original: ${originalPhone})`);
      }

      try {
        await provider.sendText(phoneClean, message);
        await admin
          .from("receivables")
          .update({ reminder_sent_at: new Date().toISOString() })
          .eq("id", rec.id);
        sent++;
      } catch (sendErr: any) {
        errors++;
        console.error(`[receivable-reminders] erro no envio ${rec.id}:`, sendErr?.message || sendErr);
      }
    }

    console.log(`[receivable-reminders] done — sent:${sent} skipped:${skipped} errors:${errors}`);
    return jr({ ok: true, sent, skipped, errors, target_date: targetISO });

  } catch (err: any) {
    console.error("[receivable-reminders] fatal error", err);
    return jr({ error: err.message }, 500);
  }
});

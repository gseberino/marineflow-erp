// Edge Function: scheduling-automations
// Cron job que envia lembretes de agendamento via WhatsApp.
// REGRA DE SEGURANÇA: Se zapi_test_mode = "true" no app_settings,
// TODOS os envios são redirecionados para o número de teste.
// Isso garante que NENHUM cliente receba mensagens durante testes.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const now = new Date();
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);

    // Carregar configurações operacionais de modo de teste.
    const { data: settings } = await supabase
      .from("app_settings")
      .select("key, value")
      .in("key", ["zapi_test_mode", "zapi_test_number"]);
    const settingsMap = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));

    // ========================================================
    // PROTEÇÃO DE MODO DE TESTE - LÊ DO BANCO (app_settings)
    // Se testMode = true, NENHUMA mensagem vai para clientes reais.
    // Todas são redirecionadas para testNumber.
    // ========================================================
    const testMode = settingsMap["zapi_test_mode"] === "true";
    const testNumber = (settingsMap["zapi_test_number"] || "").replace(/\D/g, "");

    // Validação crítica: se modo de teste ativo mas sem número, bloqueia envios
    if (testMode && !testNumber) {
      console.warn("TEST MODE ACTIVE but no test number configured. Aborting all sends to protect clients.");
      return new Response(JSON.stringify({
        success: false,
        sent: 0,
        warning: "Modo de teste ativo sem número de redirecionamento. Configure o número em Configurações → WhatsApp para continuar.",
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const provider = createWhatsAppProvider();

    // 1. Buscar OS agendadas para amanhã que ainda não receberam lembrete
    const { data: orders, error } = await supabase
      .from("service_orders")
      .select(`
        id,
        service_order_number,
        scheduled_start_at,
        clients (full_name_or_company_name, phone, whatsapp),
        vessels (boat_name)
      `)
      .eq("status", "scheduled")
      .is("reminder_sent_at", null)
      .gte("scheduled_start_at", now.toISOString())
      .lte("scheduled_start_at", tomorrow.toISOString());

    if (error) throw error;

    let sentCount = 0;
    const log: any[] = [];

    for (const order of (orders || [])) {
      const client = (order as any).clients;
      const vessel = (order as any).vessels;
      const originalPhone = (client?.whatsapp || client?.phone || "").replace(/\D/g, "");

      if (!originalPhone || originalPhone.length < 10) {
        log.push({ order_id: order.id, skipped: "no_phone" });
        continue;
      }

      // REDIRECIONAMENTO: Se testMode, usa testNumber. SEMPRE.
      const targetPhone = testMode ? testNumber : originalPhone;

      const scheduledDate = new Date((order as any).scheduled_start_at).toLocaleDateString("pt-BR");
      const vesselName = vessel?.boat_name || "sua embarcação";
      const clientName = client?.full_name_or_company_name || "Cliente";

      let message = `Olá, ${clientName}! ⚓\n\nPassando para lembrar do seu agendamento conosco amanhã (${scheduledDate}) para a unidade *${vesselName}*.\n\nNos vemos em breve! ⚡`;

      // Em modo de teste, adiciona aviso no início da mensagem
      if (testMode) {
        message = `🧪 [MODO DE TESTE - destinatário real: +${originalPhone}]\n\n${message}`;
      }

      try {
        const result = await provider.sendText(targetPhone, message);

        if (result.ok) {
          await supabase.from("service_orders").update({
            reminder_sent_at: new Date().toISOString(),
          }).eq("id", (order as any).id);
          sentCount++;
          log.push({
            order_id: (order as any).id,
            original_phone: originalPhone,
            sent_to: targetPhone,
            test_mode: testMode,
            status: "sent",
          });
        } else {
          log.push({
            order_id: (order as any).id,
            original_phone: originalPhone,
            sent_to: targetPhone,
            test_mode: testMode,
            status: "failed",
            provider_error: result.error,
          });
        }
      } catch (sendErr: any) {
        log.push({
          order_id: (order as any).id,
          status: "error",
          error: sendErr?.message,
        });
      }
    }

    return new Response(JSON.stringify({
      success: true,
      sent: sentCount,
      total_orders: (orders || []).length,
      test_mode_active: testMode,
      test_number_used: testMode ? testNumber : null,
      log,
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (err: any) {
    console.error("scheduling-automations error:", err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

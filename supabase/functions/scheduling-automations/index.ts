import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const now = new Date();
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);

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

    const { data: settings } = await supabase.from("app_settings").select("key, value");
    const settingsMap = Object.fromEntries((settings || []).map(s => [s.key, s.value]));
    const testMode = settingsMap["zapi_test_mode"] === "true";
    const testNumber = settingsMap["zapi_test_number"]?.replace(/\D/g, "");

    let sentCount = 0;

    for (const order of (orders || [])) {
      const client = order.clients;
      let phone = (client?.whatsapp || client?.phone || "").replace(/\D/g, "");
      
      if (testMode && testNumber) {
        console.log(`Scheduling Automation: Test Mode Active. Redirecting from ${phone} to ${testNumber}`);
        phone = testNumber;
      }
      
      if (phone && phone.length >= 10) {
        // Enviar via Z-API (usando a lógica que já temos no sistema)
        // Nota: Precisamos das credenciais Z-API configuradas no Secrets do Supabase
        const instanceId = Deno.env.get("ZAPI_INSTANCE_ID");
        const token = Deno.env.get("ZAPI_TOKEN");

        if (instanceId && token) {
          const message = `Olá, ${client.full_name_or_company_name}! ⚓\n\nPassando para lembrar do seu agendamento conosco amanhã (${new Date(order.scheduled_start_at).toLocaleDateString('pt-BR')}) para a unidade *${order.vessels?.boat_name || 'sua embarcação'}*.\n\nNos vemos em breve! ⚡`;
          
          const zapiRes = await fetch(`https://api.z-api.io/instances/${instanceId}/token/${token}/send-text`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ phone, message })
          });

          if (zapiRes.ok) {
            await supabase.from("service_orders").update({
              reminder_sent_at: new Date().toISOString()
            }).eq("id", order.id);
            sentCount++;
          }
        }
      }
    }

    return new Response(JSON.stringify({ success: true, sent: sentCount }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});

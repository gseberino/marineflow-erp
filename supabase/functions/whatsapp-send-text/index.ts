// Edge Function: whatsapp-send-text
// Envia mensagem de texto a partir do painel (Inbox).
// Requer usuário autenticado (verify_jwt = true por padrão da plataforma).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import { normalizePhoneNumber } from "../_shared/whatsapp/normalize.ts";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Auth do chamador
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    let userId: string | null = null;
    if (jwt) {
      const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
      });
      const { data } = await userClient.auth.getUser();
      userId = data?.user?.id || null;
    }
    if (!userId) return jr({ error: "Não autenticado" }, 401);

    const { phone, message } = await req.json().catch(() => ({}));
    const cleanPhone = normalizePhoneNumber(String(phone || ""));
    const text = String(message || "").trim();
    if (!cleanPhone || cleanPhone.length < 10) return jr({ error: "Telefone inválido" }, 400);
    if (!text) return jr({ error: "Mensagem vazia" }, 400);

    const provider = createWhatsAppProvider();
    const result = await provider.sendText(cleanPhone, text);

    if (!result.ok) return jr({ error: result.error }, 502);

    await admin.from("whatsapp_messages").insert({
      direction: "outbound",
      phone_normalized: cleanPhone,
      message_type: "text",
      body: text,
      zapi_message_id: result.providerMessageId || null,
      delivery_status: "sent",
      sent_by: userId,
    });
    await admin
      .from("whatsapp_leads")
      .update({ unread_count: 0, last_outbound_at: new Date().toISOString() })
      .eq("phone_normalized", cleanPhone);

    return jr({ ok: true, messageId: result.providerMessageId || null });
  } catch (e: any) {
    console.error("whatsapp-send-text error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

// Edge Function: whatsapp-send-text
// Envia mensagem de texto via Z-API a partir do painel (Inbox).
// Requer usuário autenticado (verify_jwt = true por padrão da plataforma).
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Load credentials from app_settings (DB) with env fallback — same pattern as whatsapp-send
    const { data: settings } = await admin.from("app_settings").select("key, value");
    const sm = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));
    const INSTANCE_ID = sm["zapi_instance_id"] || Deno.env.get("ZAPI_INSTANCE_ID");
    const TOKEN = sm["zapi_token"] || Deno.env.get("ZAPI_TOKEN");
    const CLIENT_TOKEN = sm["zapi_client_token"] || Deno.env.get("ZAPI_CLIENT_TOKEN");
    if (!INSTANCE_ID || !TOKEN) return jr({ error: "Z-API não configurado. Configure em Configurações → WhatsApp." }, 500);

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
    const cleanPhone = String(phone || "").replace(/\D/g, "");
    const text = String(message || "").trim();
    if (!cleanPhone || cleanPhone.length < 10) return jr({ error: "Telefone inválido" }, 400);
    if (!text) return jr({ error: "Mensagem vazia" }, 400);

    const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (CLIENT_TOKEN) headers["Client-Token"] = CLIENT_TOKEN;

    const res = await fetch(`${base}/send-text`, {
      method: "POST",
      headers,
      body: JSON.stringify({ phone: cleanPhone, message: text }),
    });
    const data = await res.json().catch(() => ({}));
    const ok = res.ok && !(data as any).error;
    if (!ok) return jr({ error: (data as any).error || `HTTP ${res.status}` }, 502);

    // Registra mensagem outbound + zera unread do lead
    await admin.from("whatsapp_messages").insert({
      direction: "outbound",
      phone_normalized: cleanPhone,
      message_type: "text",
      body: text,
      zapi_message_id: (data as any).messageId || (data as any).id || null,
      delivery_status: "sent",
      sent_by: userId,
    });
    await admin
      .from("whatsapp_leads")
      .update({ unread_count: 0, last_outbound_at: new Date().toISOString() })
      .eq("phone_normalized", cleanPhone);

    return jr({ ok: true, messageId: (data as any).messageId || null });
  } catch (e: any) {
    console.error("whatsapp-send-text error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

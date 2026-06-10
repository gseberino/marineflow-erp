// Edge Function: whatsapp-status-worker
// Processa agendamentos de Status do WhatsApp via Z-API.
// Roda periodicamente (cron) para verificar posts pendentes.
//
// NOTE (B4): WhatsApp Status (Stories) endpoints (/send-text-status,
// /send-image-status, /send-video-status) are Z-API-specific and have no
// equivalent in the WhatsAppProvider interface (secondary feature, low usage).
// This function retains direct Z-API calls until Evolution support is confirmed
// and a sendStatus() method is added to the interface in a future task.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    // 1. Busca status pendentes que já passaram do horário
    const { data: pending, error: fetchError } = await supabase
      .from("whatsapp_status_scheduled")
      .select("*")
      .eq("status", "pending")
      .lte("scheduled_at", new Date().toISOString())
      .limit(5); // Processa em pequenos lotes para evitar timeout

    if (fetchError) throw fetchError;
    if (!pending || pending.length === 0) {
      return new Response(JSON.stringify({ message: "No pending status to process" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Carrega credenciais da Z-API
    const { data: settings } = await supabase.from("app_settings").select("key, value");
    const settingsMap = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));

    const INSTANCE_ID = settingsMap["zapi_instance_id"];
    const TOKEN = settingsMap["zapi_token"];
    const CLIENT_TOKEN = settingsMap["zapi_client_token"];

    if (!INSTANCE_ID || !TOKEN) {
      throw new Error("Z-API credentials not configured");
    }

    const results = [];

    for (const item of pending) {
      try {
        // Marca como processando para evitar duplicidade
        await supabase.from("whatsapp_status_scheduled").update({ status: "processing" }).eq("id", item.id);

        let endpoint = "";
        let payload: any = {};

        const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;

        if (item.content_type === "text") {
          endpoint = `${base}/send-text-status`;
          payload = {
            message: item.text_content,
            backgroundColor: item.background_color || "#746764",
            font: item.font_type || 0
          };
        } else if (item.content_type === "image") {
          endpoint = `${base}/send-image-status`;
          payload = {
            image: item.media_url,
            caption: item.text_content || ""
          };
        } else if (item.content_type === "video") {
          endpoint = `${base}/send-video-status`;
          payload = {
            video: item.media_url,
            caption: item.text_content || ""
          };
        }

        const headers: any = { "Content-Type": "application/json" };
        if (CLIENT_TOKEN) headers["Client-Token"] = CLIENT_TOKEN;

        const res = await fetch(endpoint, {
          method: "POST",
          headers,
          body: JSON.stringify(payload)
        });

        const zapiRes = await res.json().catch(() => ({}));

        if (res.ok && !zapiRes.error) {
          await supabase.from("whatsapp_status_scheduled").update({
            status: "sent",
            zapi_message_id: zapiRes.messageId || zapiRes.id,
            error_message: null
          }).eq("id", item.id);
          results.push({ id: item.id, success: true });
        } else {
          throw new Error(zapiRes.error || `HTTP ${res.status}`);
        }

      } catch (err: any) {
        console.error(`Error processing status ${item.id}:`, err);
        await supabase.from("whatsapp_status_scheduled").update({
          status: "failed",
          error_message: err.message
        }).eq("id", item.id);
        results.push({ id: item.id, success: false, error: err.message });
      }
    }

    return new Response(JSON.stringify({ results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err: any) {
    console.error("whatsapp-status-worker error", err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Edge Function: whatsapp-status-worker
// Processa agendamentos de Status do WhatsApp via Evolution API
// Roda periodicamente (cron) para verificar posts pendentes.

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

    // 2. Carrega credenciais Evolution API de backend secrets/environment.
    const EVO_URL = (Deno.env.get("EVOLUTION_API_URL") || "").replace(/\/$/, "");
    const EVO_KEY = Deno.env.get("EVOLUTION_API_KEY") || "";
    const EVO_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") || "";

    if (!EVO_URL || !EVO_KEY || !EVO_INSTANCE) {
      throw new Error("Evolution API credentials not configured");
    }

    const evoHeaders = {
      "Content-Type": "application/json",
      "apikey": EVO_KEY,
    };

    const results = [];

    for (const item of pending) {
      try {
        // Marca como processando para evitar duplicidade
        await supabase.from("whatsapp_status_scheduled").update({ status: "processing" }).eq("id", item.id);

        let payload: any = {};

        if (item.content_type === "text") {
          payload = {
            type: "text",
            content: item.text_content,
            backgroundColor: item.background_color || "#746764",
            font: item.font_type || 1,
            allContacts: true,
          };
        } else if (item.content_type === "image") {
          payload = {
            type: "image",
            content: item.media_url,
            caption: item.text_content || "",
            allContacts: true,
          };
        } else if (item.content_type === "video") {
          payload = {
            type: "video",
            content: item.media_url,
            caption: item.text_content || "",
            allContacts: true,
          };
        }

        const res = await fetch(`${EVO_URL}/message/sendStatus/${EVO_INSTANCE}`, {
          method: "POST",
          headers: evoHeaders,
          body: JSON.stringify(payload),
        });

        const evoRes = await res.json().catch(() => ({}));

        if (res.ok && !evoRes.error) {
          const key = evoRes.key as Record<string, unknown> | undefined;
          const msgId = String(key?.id ?? evoRes.id ?? evoRes.messageId ?? "");
          await supabase.from("whatsapp_status_scheduled").update({
            status: "sent",
            zapi_message_id: msgId || null,
            error_message: null,
          }).eq("id", item.id);
          results.push({ id: item.id, success: true });
        } else {
          throw new Error(String(evoRes.error ?? evoRes.message ?? `HTTP ${res.status}`));
        }

      } catch (err: any) {
        console.error(`Error processing status ${item.id}:`, err);
        await supabase.from("whatsapp_status_scheduled").update({
          status: "failed",
          error_message: err.message,
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

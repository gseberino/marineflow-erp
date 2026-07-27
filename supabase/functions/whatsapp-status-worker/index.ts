// Edge Function: whatsapp-status-worker
// Processa agendamentos de Status/Stories do WhatsApp via o provider ativo (Evolution).
// Roda periodicamente (cron) para publicar os status pendentes cujo horário chegou.
//
// Correções (P0): antes gravava na coluna inexistente `wa_message_id` (a coluna real é
// `zapi_message_id`), o que faria o 1º post real falhar; e chamava a Evolution direto por
// fetch. Agora roteia pelo EvolutionProvider.sendStatus (fonte única, mesmo tratamento de erro).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import type { StatusContent } from "../_shared/whatsapp/types.ts";

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

    // 1. Status pendentes cujo horário já passou (lotes pequenos p/ não estourar timeout).
    const { data: pending, error: fetchError } = await supabase
      .from("whatsapp_status_scheduled")
      .select("*")
      .eq("status", "pending")
      .lte("scheduled_at", new Date().toISOString())
      .limit(5);

    if (fetchError) throw fetchError;
    if (!pending || pending.length === 0) {
      return new Response(JSON.stringify({ message: "No pending status to process" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Provider ativo (Evolution). Guard: precisa suportar sendStatus.
    const provider = createWhatsAppProvider();
    const sendStatus = provider.sendStatus?.bind(provider);
    if (!sendStatus) {
      throw new Error("O provider de WhatsApp ativo não suporta publicação de status.");
    }

    const results: Array<{ id: string; success: boolean; error?: string }> = [];

    for (const item of pending as any[]) {
      try {
        // Marca como processando para evitar duplicidade entre execuções do cron.
        await supabase.from("whatsapp_status_scheduled").update({ status: "processing" }).eq("id", item.id);

        const content: StatusContent = item.content_type === "text"
          ? {
              type: "text",
              content: item.text_content ?? "",
              backgroundColor: item.background_color || undefined,
              font: item.font_type || undefined,
              allContacts: true,
            }
          : {
              type: item.content_type === "video" ? "video" : "image",
              content: item.media_url ?? "",
              caption: item.text_content || "",
              allContacts: true,
            };

        const r = await sendStatus(content);

        if (r.ok) {
          await supabase.from("whatsapp_status_scheduled").update({
            status: "sent",
            zapi_message_id: r.providerMessageId || null,
            error_message: null,
          }).eq("id", item.id);
          results.push({ id: item.id, success: true });
        } else {
          throw new Error(r.error);
        }
      } catch (err: any) {
        console.error(`Error processing status ${item.id}:`, err);
        await supabase.from("whatsapp_status_scheduled").update({
          status: "failed",
          error_message: err?.message ?? String(err),
        }).eq("id", item.id);
        results.push({ id: item.id, success: false, error: err?.message ?? String(err) });
      }
    }

    return new Response(JSON.stringify({ results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    console.error("whatsapp-status-worker error", err);
    return new Response(JSON.stringify({ error: err?.message ?? String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

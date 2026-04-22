// Edge Function: whatsapp-reprocess-messages
// Reprocess WhatsApp messages flagged as 'other' / "[mensagem não reconhecida]"
// by re-applying the latest parser over their stored raw_payload.
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

function extractBodyAndType(p: any): { body: string; messageType: string } {
  if (typeof p?.text === "string") return { body: String(p.text), messageType: "text" };
  if (p?.text?.message) return { body: String(p.text.message), messageType: "text" };
  if (typeof p?.message === "string") return { body: String(p.message), messageType: "text" };
  if (p?.message?.conversation) return { body: String(p.message.conversation), messageType: "text" };
  if (p?.message?.extendedTextMessage?.text) return { body: String(p.message.extendedTextMessage.text), messageType: "text" };
  if (p?.body) return { body: String(p.body), messageType: "text" };
  if (p?.caption) return { body: String(p.caption), messageType: "text" };
  if (p?.image) return { body: p.image.caption || "[imagem]", messageType: "image" };
  if (p?.audio) return { body: "[áudio]", messageType: "audio" };
  if (p?.video) return { body: p.video.caption || "[vídeo]", messageType: "video" };
  if (p?.document) return { body: p.document.caption || `[documento] ${p.document.fileName || ""}`.trim(), messageType: "document" };
  if (p?.sticker) return { body: "[sticker]", messageType: "sticker" };
  if (p?.reaction) return { body: `[reação] ${p.reaction.value || ""}`.trim(), messageType: "reaction" };
  if (p?.poll || p?.pollCreation) return { body: "[enquete]", messageType: "poll" };
  if (p?.listResponseMessage || p?.message?.listResponseMessage) {
    return { body: String(p.listResponseMessage?.singleSelectReply?.selectedRowId || "[resposta de lista]"), messageType: "list_response" };
  }
  if (p?.buttonsResponseMessage || p?.message?.buttonsResponseMessage) {
    return { body: String(p.buttonsResponseMessage?.selectedDisplayText || "[resposta de botão]"), messageType: "button_response" };
  }
  if (p?.location) return { body: `[localização] ${p.location.latitude},${p.location.longitude}`, messageType: "location" };
  if (p?.contact || p?.contacts || p?.contactsArrayMessage) {
    return { body: `[contato] ${p.contact?.displayName || ""}`.trim(), messageType: "contact" };
  }
  return { body: "[mensagem não reconhecida]", messageType: "other" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: rows, error } = await admin
      .from("whatsapp_messages")
      .select("id, raw_payload, message_type, body")
      .or("message_type.eq.other,body.eq.[mensagem não reconhecida]")
      .not("raw_payload", "is", null)
      .limit(2000);

    if (error) return jr({ error: error.message }, 500);

    let updated = 0;
    let stillUnknown = 0;
    const errors: string[] = [];

    for (const row of rows || []) {
      const { body, messageType } = extractBodyAndType(row.raw_payload);
      if (messageType === "other") {
        stillUnknown++;
        continue;
      }
      const { error: upErr } = await admin
        .from("whatsapp_messages")
        .update({ body: body.slice(0, 4000), message_type: messageType })
        .eq("id", row.id);
      if (upErr) errors.push(upErr.message);
      else updated++;
    }

    return jr({
      ok: true,
      total_scanned: rows?.length || 0,
      updated,
      still_unknown: stillUnknown,
      errors: errors.slice(0, 5),
    });
  } catch (err: any) {
    console.error("reprocess error", err);
    return jr({ error: err?.message || "internal error" }, 500);
  }
});

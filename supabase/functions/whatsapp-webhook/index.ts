// Edge Function: whatsapp-webhook
// Versão: 5.1 (Blindada & Limpa)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, client-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizePhone(raw: string | null | undefined): string {
  if (!raw) return "";
  const clean = String(raw).split("@")[0];
  const digits = clean.replace(/\D/g, "");
  if (!digits) return "";
  if (digits.length >= 14) return digits; 
  if (digits.length === 10 || digits.length === 11) return `55${digits}`;
  return digits;
}

function extractBodyAndType(p: any): { body: string; messageType: string; mediaUrl: string | null } {
  let mediaUrl: null | string = null;
  const text = p?.text?.message || p?.text || p?.message?.conversation || p?.message?.extendedTextMessage?.text || p?.body || p?.caption || "";
  if (p?.image) return { body: p.image.caption || "[imagem]", messageType: "image", mediaUrl: p.image.imageUrl || p.image.url || null };
  if (p?.audio) return { body: "[áudio]", messageType: "audio", mediaUrl: p.audio.audioUrl || p.audio.url || null };
  if (p?.video) return { body: p.video.caption || "[vídeo]", messageType: "video", mediaUrl: p.video.videoUrl || p.video.url || null };
  if (p?.document) return { body: p.document.caption || `[documento] ${p.document.fileName || ""}`.trim(), messageType: "document", mediaUrl: p.document.documentUrl || p.document.url || null };
  return { body: String(text).trim() || "[conteúdo vazio]", messageType: "text", mediaUrl: null };
}

async function notifyAssignedReminder(admin: any, phone: string, senderName: string | null, preview: string, zapiCreds: { id: string; token: string; client: string | null }) {
  try {
    if (!zapiCreds.id || !zapiCreds.token) return;
    const { data: settings } = await admin.from("app_settings").select("key, value").in("key", ["whatsapp_reminder_enabled", "whatsapp_reminder_recipients"]);
    const sMap = Object.fromEntries((settings || []).map(s => [s.key, s.value]));
    if (String(sMap.whatsapp_reminder_enabled).toLowerCase() !== "true" && sMap.whatsapp_reminder_enabled !== "1") return;
    if (phone.length > 15) return;
    let recipients: string[] = String(sMap.whatsapp_reminder_recipients || "").split(/[,\s]+/).map(p => p.replace(/\D/g, "")).filter(p => p.length >= 10);
    const who = senderName ? `${senderName} (+${phone})` : `+${phone}`;
    const message = `🆕 *Novo lead WhatsApp*\n\n${who}\n"${preview.slice(0, 160)}"\n\nResponda no painel hbrmarine.online`;
    const base = `https://api.z-api.io/instances/${zapiCreds.id}/token/${zapiCreds.token}`;
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (zapiCreds.client) headers["Client-Token"] = zapiCreds.client;
    await Promise.all(recipients.map(to => fetch(`${base}/send-text`, { method: "POST", headers, body: JSON.stringify({ phone: to, message }) }).catch(() => null)));
  } catch (e) { console.error("notifyAssignedReminder failed", e); }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });

  // --- MODO FAXINA E BLINDAGEM (GET) ---
  if (req.method === "GET") {
    try {
      console.log("[Cleanup] Iniciando limpeza de leads fantasmas...");
      const { data: leads } = await admin.from("whatsapp_leads").select("id, phone_number");
      if (!leads) return new Response("Nenhum lead encontrado.", { headers: corsHeaders });

      let count = 0;
      for (const l of leads) {
        const phone = l.phone_number || "";
        const isWeird = phone.length < 10 || !phone.startsWith("55") || phone.length > 15;
        if (isWeird) {
          const { count: msgCount } = await admin.from("whatsapp_messages").select("*", { count: "exact", head: true }).eq("whatsapp_lead_id", l.id);
          if (!msgCount || msgCount === 0) {
            await admin.from("whatsapp_leads").delete().eq("id", l.id);
            count++;
          }
        }
      }
      return new Response(`Faxina Concluída! ${count} leads fantasmas removidos. O sistema agora está blindado contra novos registros inválidos.`, { headers: { ...corsHeaders, "Content-Type": "text/plain; charset=utf-8" } });
    } catch (e) { return new Response("Erro: " + e.message, { status: 500, headers: corsHeaders }); }
  }

  // --- WEBHOOK POST ---
  try {
    const payload = await req.json().catch(() => null);
    if (!payload) return jr({ error: "No payload" }, 400);

    const pAny = payload as any;
    const type = String(pAny.type || pAny.event || "");
    const phoneRaw = pAny.phone || pAny.chatId || pAny.senderLid || "";
    const phone = normalizePhone(phoneRaw);
    const fromMe = !!pAny.fromMe;

    const ignoredTypes = ["PresenceChatCallback", "ChatStateCallback", "PresenceCallback", "ChatPresence", "Presence", "typing", "recording"];
    if (ignoredTypes.includes(type)) return jr({ ok: true, ignored: "system" });
    if (pAny.isGroup === true) return jr({ ok: true, ignored: "group" });

    const { data: settings } = await admin.from("app_settings").select("key, value").in("key", ["zapi_instance_id", "zapi_token", "zapi_client_token"]);
    const sMap = Object.fromEntries((settings || []).map(s => [s.key, s.value]));
    const zapiCreds = { id: sMap.zapi_instance_id, token: sMap.zapi_token, client: sMap.zapi_client_token };

    if (type === "MessageStatusCallback" || type === "MessageStatus") {
      const status = String(pAny.status || "").toLowerCase();
      const zapiId = pAny.messageId || (pAny.ids ? pAny.ids[0] : null);
      if (zapiId && status) await admin.from("whatsapp_messages").update({ delivery_status: status }).eq("zapi_message_id", String(zapiId));
      return jr({ ok: true, type: "status" });
    }

    const { body, messageType, mediaUrl } = extractBodyAndType(pAny);
    const zapiId = pAny.messageId || pAny.id || null;
    if (zapiId) {
      const { data: dup } = await admin.from("whatsapp_messages").select("id").eq("zapi_message_id", String(zapiId)).maybeSingle();
      if (dup) return jr({ ok: true, dedup: true });
    }

    let clientId = null;
    let leadId = null;
    let isNewLead = false;

    const { data: client } = await admin.from("clients").select("id").or(`phone.ilike.%${phone}%,whatsapp.ilike.%${phone}%`).eq("active", true).maybeSingle();
    if (client) {
      clientId = client.id;
    } else {
      const { data: lead } = await admin.from("whatsapp_leads").select("id").eq("phone_normalized", phone).maybeSingle();
      if (lead) {
        leadId = lead.id;
      } else if (!fromMe) {
        const isValidPhone = phone.startsWith("55") && (phone.length === 12 || phone.length === 13);
        if (isValidPhone) {
          const { data: newLead } = await admin.from("whatsapp_leads").insert({
            phone_normalized: phone,
            phone_number: phone,
            display_name: pAny.senderName || pAny.notifyName || null,
            status: "pending"
          }).select("id").single();
          leadId = newLead?.id;
          isNewLead = true;
        }
      }
    }

    const { data: msg, error: insErr } = await admin.from("whatsapp_messages").insert({
      direction: fromMe ? "outbound" : "inbound",
      phone_normalized: phone,
      message_type: messageType,
      body: body.slice(0, 4000),
      media_url: mediaUrl,
      client_id: clientId,
      lead_id: leadId,
      zapi_message_id: zapiId ? String(zapiId) : null,
      delivery_status: fromMe ? "sent" : "received",
      raw_payload: pAny
    }).select("id").single();

    if (insErr) return jr({ error: "db_error", details: insErr.message }, 500);
    if (isNewLead && !fromMe) notifyAssignedReminder(admin, phone, pAny.senderName || null, body, zapiCreds).catch(console.error);
    if (leadId) await admin.from("whatsapp_leads").update({ updated_at: new Date().toISOString() }).eq("id", leadId);
    else if (clientId) await admin.from("clients").update({ updated_at: new Date().toISOString() }).eq("id", clientId);

    return jr({ ok: true, message_id: msg?.id });
  } catch (err: any) { return jr({ error: err.message }, 500); }
});

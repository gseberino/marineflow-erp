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
  // WhatsApp LID (@lid) — internal identifier, not a real phone number
  if (String(raw).includes("@lid")) return "";
  const clean = String(raw).split("@")[0];
  const digits = clean.replace(/\D/g, "");
  if (!digits) return "";
  if (digits.length >= 14) return digits;
  if (digits.length === 10 || digits.length === 11) return `55${digits}`;
  return digits;
}

function extractBodyAndType(p: any): { body: string; messageType: string; mediaUrl: string | null } {
  const text = p?.text?.message || p?.text || p?.message?.conversation || p?.message?.extendedTextMessage?.text || p?.body || p?.caption || "";
  if (p?.image) return { body: p.image.caption || "[imagem]", messageType: "image", mediaUrl: p.image.imageUrl || p.image.url || null };
  if (p?.audio) return { body: "[áudio]", messageType: "audio", mediaUrl: p.audio.audioUrl || p.audio.url || null };
  if (p?.video) return { body: p.video.caption || "[vídeo]", messageType: "video", mediaUrl: p.video.videoUrl || p.video.url || null };
  if (p?.document) return { body: p.document.caption || `[documento] ${p.document.fileName || ""}`.trim(), messageType: "document", mediaUrl: p.document.documentUrl || p.document.url || null };
  if (p?.sticker) return { body: "[figurinha]", messageType: "sticker", mediaUrl: p.sticker.stickerUrl || null };
  if (p?.location) return { body: `[localização] ${p.location.address || p.location.name || ""}`.trim(), messageType: "location", mediaUrl: null };
  if (p?.contact) return { body: `[contato] ${p.contact.displayName || ""}`.trim(), messageType: "contact", mediaUrl: null };
  if (p?.reaction) return { body: `[reação] ${p.reaction.value || ""}`.trim(), messageType: "reaction", mediaUrl: null };
  if (p?.poll) return { body: `[enquete] ${p.poll.question || ""}`.trim(), messageType: "poll", mediaUrl: null };
  if (p?.pollVote) return { body: "[voto em enquete]", messageType: "poll_vote", mediaUrl: null };
  if (p?.buttonsResponseMessage) return { body: p.buttonsResponseMessage.message || "[resposta de botão]", messageType: "button_response", mediaUrl: null };
  if (p?.listResponseMessage) return { body: p.listResponseMessage.message || "[seleção de lista]", messageType: "list_response", mediaUrl: null };
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
    const url = new URL(req.url);

    // Healthcheck — retorna JSON com métricas para o painel de configuração
    if (url.searchParams.get("healthcheck") === "1") {
      try {
        const webhookUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-webhook`;
        const now = new Date();

        const { count: totalInbound } = await admin
          .from("whatsapp_messages")
          .select("*", { count: "exact", head: true })
          .eq("direction", "inbound");

        const since24h = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
        const { count: last24h } = await admin
          .from("whatsapp_messages")
          .select("*", { count: "exact", head: true })
          .eq("direction", "inbound")
          .gte("created_at", since24h);

        const { data: lastMsg } = await admin
          .from("whatsapp_messages")
          .select("created_at, phone_normalized, body")
          .eq("direction", "inbound")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        const { data: recentMsgs } = await admin
          .from("whatsapp_messages")
          .select("created_at, phone_normalized, message_type, body")
          .eq("direction", "inbound")
          .order("created_at", { ascending: false })
          .limit(5);

        const minutesSinceLast = lastMsg
          ? Math.floor((now.getTime() - new Date(lastMsg.created_at).getTime()) / 60000)
          : null;

        const healthStatus =
          !lastMsg ? "never" :
          minutesSinceLast !== null && minutesSinceLast > 60 ? "stale" : "ok";

        return jr({
          webhook_url: webhookUrl,
          health_status: healthStatus,
          total_inbound: totalInbound ?? 0,
          last_24h: last24h ?? 0,
          last_message_at: lastMsg?.created_at ?? null,
          minutes_since_last: minutesSinceLast,
          last_message_preview: lastMsg
            ? { phone: lastMsg.phone_normalized, body: lastMsg.body, is_broadcast: false }
            : null,
          recent_messages: (recentMsgs || []).map((m) => ({
            at: m.created_at,
            phone: m.phone_normalized,
            type: m.message_type,
            body: m.body,
            is_broadcast: false,
          })),
          checked_at: now.toISOString(),
        });
      } catch (e: any) {
        return jr({ error: e.message }, 500);
      }
    }

    try {
      console.log("[Cleanup] Iniciando limpeza de leads fantasmas...");
      const { data: leads } = await admin.from("whatsapp_leads").select("id, phone_normalized");
      if (!leads) return new Response("Nenhum lead encontrado.", { headers: corsHeaders });

      let count = 0;
      for (const l of leads) {
        const phone = l.phone_normalized || "";
        const isWeird = phone.length < 10 || !phone.startsWith("55") || phone.length > 15;
        if (isWeird) {
          const { count: msgCount } = await admin.from("whatsapp_messages").select("*", { count: "exact", head: true }).eq("lead_id", l.id);
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
    const fromMe = !!pAny.fromMe;

    // Para mensagens enviadas por nós (fromMe=true), o destinatário está em pAny.to ou pAny.chatId.
    // Para mensagens recebidas, o remetente está em pAny.phone.
    const phoneRaw = fromMe
      ? (pAny.to || pAny.chatId || pAny.phone || "")
      : (pAny.phone || pAny.chatId || pAny.senderLid || "");
    const phone = normalizePhone(phoneRaw);

    const ignoredTypes = ["PresenceChatCallback", "ChatStateCallback", "PresenceCallback", "ChatPresence", "Presence", "typing", "recording", "ConnectedCallback", "DisconnectedCallback", "AllMessagesReadCallback", "LoginCallback"];
    if (ignoredTypes.includes(type)) return jr({ ok: true, ignored: "system" });
    if (pAny.isGroup === true) return jr({ ok: true, ignored: "group" });

    // Skip fromMe messages where recipient phone couldn't be resolved (e.g. LID-only payloads)
    if (fromMe && !phone) return jr({ ok: true, ignored: "outbound_no_recipient_phone" });
    const ignoredNotifications = ["CALL_VOICE", "CALL_MISSED_VOICE", "CALL_MISSED_VIDEO", "E2E_ENCRYPTED", "CIPHERTEXT", "REVOKE", "GROUP_CREATE", "GROUP_CHANGE_SUBJECT", "GROUP_PARTICIPANT_ADD", "GROUP_PARTICIPANT_REMOVE", "GROUP_PARTICIPANT_LEAVE", "GROUP_PARTICIPANT_PROMOTE", "GROUP_PARTICIPANT_DEMOTE", "MEMBERSHIP_APPROVAL_REQUEST", "REVOKED_MEMBERSHIP_REQUESTS"];
    if (pAny.notification && ignoredNotifications.includes(String(pAny.notification))) return jr({ ok: true, ignored: "notification" });

    const { data: settings } = await admin.from("app_settings").select("key, value").in("key", ["zapi_instance_id", "zapi_token", "zapi_client_token"]);
    const sMap = Object.fromEntries((settings || []).map(s => [s.key, s.value]));
    const zapiCreds = { id: sMap.zapi_instance_id, token: sMap.zapi_token, client: sMap.zapi_client_token };

    if (type === "MessageStatusCallback" || type === "MessageStatus") {
      const zapiStatusMap: Record<string, string> = { SENT: "sent", RECEIVED: "delivered", READ: "read", PLAYED: "played", READ_BY_ME: "read_by_me" };
      const rawStatus = String(pAny.status || "").toUpperCase();
      const mappedStatus = zapiStatusMap[rawStatus] || rawStatus.toLowerCase();
      const ids: string[] = Array.isArray(pAny.ids) ? pAny.ids.map(String) : (pAny.messageId ? [String(pAny.messageId)] : []);
      if (ids.length > 0 && mappedStatus) {
        await Promise.all(ids.map(id => admin.from("whatsapp_messages").update({ delivery_status: mappedStatus }).eq("zapi_message_id", id)));
      }
      return jr({ ok: true, type: "status", status: mappedStatus, updated: ids.length });
    }

    if (type === "DeliveryCallback") {
      const zapiId = pAny.messageId || pAny.zaapId || null;
      if (zapiId) await admin.from("whatsapp_messages").update({ delivery_status: "sent" }).eq("zapi_message_id", String(zapiId));
      return jr({ ok: true, type: "delivery", updated: !!zapiId });
    }

    const { body, messageType, mediaUrl } = extractBodyAndType(pAny);

    // Ignorar eventos outbound sem conteúdo (ex: notificações de sistema do Z-API)
    if (fromMe && (!body || body === "[conteúdo vazio]")) {
      return jr({ ok: true, ignored: "outbound_no_body" });
    }

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
      } else {
        const isValidPhone = phone.startsWith("55") && (phone.length === 12 || phone.length === 13);
        if (isValidPhone) {
          const { data: newLead } = await admin.from("whatsapp_leads").insert({
            phone_normalized: phone,
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

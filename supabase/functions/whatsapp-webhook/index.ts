// Edge Function: whatsapp-webhook
// Recebe TODOS os eventos da Z-API (mensagens recebidas, status de entrega).
// - Detecta listas de transmissão (broadcast) automaticamente
// - Aplica blocklist (whatsapp_blocked_numbers)
// - Match por telefone normalizado contra clients (mesmo já cadastrado registra mensagem)
// - Cria/atualiza lead em whatsapp_leads se não houver match
// - Notifica responsável imediatamente quando chega NOVO lead
// URL para colar na Z-API "On Message Received":
//   https://<project-ref>.supabase.co/functions/v1/whatsapp-webhook
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, client-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizePhone(raw: string | null | undefined, defaultDDI = "55"): string {
  if (!raw) return "";
  let d = String(raw).replace(/\D/g, "");
  if (!d) return "";
  if (d.startsWith("00")) d = d.slice(2);
  if (d.length >= 12) return d;
  if (d.length === 10 || d.length === 11) return `${defaultDDI}${d}`;
  return d;
}

// Detecta indicadores de broadcast / lista de transmissão Z-API
function isBroadcastPayload(p: any): boolean {
  // Z-API marca via campos como `broadcast: true`, `isGroup: false` + `participantPhone` ausente,
  // ou `chatId` terminando em "@broadcast"/"status@broadcast"
  if (p?.broadcast === true || p?.isBroadcast === true) return true;
  const chatId = String(p?.chatId || "");
  if (chatId.endsWith("@broadcast") || chatId.includes("status@broadcast")) return true;
  if (p?.fromBroadcast === true) return true;
  return false;
}

async function notifyAssignedReminder(
  admin: ReturnType<typeof createClient>,
  phone: string,
  senderName: string | null,
  preview: string,
) {
  try {
    const INSTANCE_ID = Deno.env.get("ZAPI_INSTANCE_ID");
    const TOKEN = Deno.env.get("ZAPI_TOKEN");
    const CLIENT_TOKEN = Deno.env.get("ZAPI_CLIENT_TOKEN");
    if (!INSTANCE_ID || !TOKEN) return;

    // Buscar destinatários: app_settings.whatsapp_reminder_recipients OU app_users admin/financial/manager
    const { data: setting } = await admin
      .from("app_settings")
      .select("value")
      .eq("key", "whatsapp_reminder_recipients")
      .maybeSingle();

    let recipients: string[] = String(setting?.value || "")
      .split(/[,\s]+/)
      .map((p) => p.replace(/\D/g, ""))
      .filter((p) => p.length >= 10);

    if (recipients.length === 0) {
      const { data: users } = await admin
        .from("app_users")
        .select("phone")
        .eq("active", true)
        .in("role", ["admin", "financial", "manager"]);
      recipients = (users || [])
        .map((u: any) => (u.phone || "").replace(/\D/g, ""))
        .filter((p: string) => p.length >= 10);
    }
    if (recipients.length === 0) return;

    const who = senderName ? `${senderName} (+${phone})` : `+${phone}`;
    const message = `🆕 *Novo lead WhatsApp*\n\n${who}\n"${preview.slice(0, 160)}"\n\nResponda no painel.`;

    const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (CLIENT_TOKEN) headers["Client-Token"] = CLIENT_TOKEN;

    await Promise.all(
      recipients.map((to) =>
        fetch(`${base}/send-text`, {
          method: "POST",
          headers,
          body: JSON.stringify({ phone: to, message }),
        }).catch(() => null),
      ),
    );
  } catch (e) {
    console.error("notifyAssignedReminder failed", e);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const url = new URL(req.url);

    // ---- Healthcheck (GET) ----
    // Permite validar do app se a Z-API está enviando tráfego para cá.
    // Retorna últimas mensagens recebidas, contagem total e timestamp da última.
    if (req.method === "GET" || url.searchParams.get("healthcheck") === "1") {
      const sinceIso = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

      const [{ count: totalInbound }, { count: last24h }, { data: lastMsg }, { data: recent }] = await Promise.all([
        admin.from("whatsapp_messages").select("*", { count: "exact", head: true }).eq("direction", "inbound"),
        admin.from("whatsapp_messages").select("*", { count: "exact", head: true }).eq("direction", "inbound").gte("created_at", sinceIso),
        admin.from("whatsapp_messages").select("created_at, phone_normalized, body, is_broadcast").eq("direction", "inbound").order("created_at", { ascending: false }).limit(1).maybeSingle(),
        admin.from("whatsapp_messages").select("created_at, phone_normalized, body, message_type, is_broadcast").eq("direction", "inbound").order("created_at", { ascending: false }).limit(5),
      ]);

      const lastAt = lastMsg?.created_at || null;
      const minutesSinceLast = lastAt ? Math.floor((Date.now() - new Date(lastAt).getTime()) / 60000) : null;
      const webhookUrl = `${SUPABASE_URL}/functions/v1/whatsapp-webhook`;

      let healthStatus: "ok" | "stale" | "never" = "never";
      if (lastAt) healthStatus = (minutesSinceLast! < 60) ? "ok" : "stale";

      return jr({
        ok: true,
        type: "healthcheck",
        webhook_url: webhookUrl,
        health_status: healthStatus,
        total_inbound: totalInbound || 0,
        last_24h: last24h || 0,
        last_message_at: lastAt,
        minutes_since_last: minutesSinceLast,
        last_message_preview: lastMsg
          ? { phone: lastMsg.phone_normalized, body: String(lastMsg.body || "").slice(0, 120), is_broadcast: !!lastMsg.is_broadcast }
          : null,
        recent_messages: (recent || []).map((m: any) => ({
          at: m.created_at,
          phone: m.phone_normalized,
          type: m.message_type,
          body: String(m.body || "").slice(0, 80),
          is_broadcast: !!m.is_broadcast,
        })),
        checked_at: new Date().toISOString(),
      });
    }

    const payload = await req.json().catch(() => null);
    if (!payload || typeof payload !== "object") {
      return jr({ error: "Invalid payload" }, 400);
    }

    // Log detalhado para auditoria
    const pAny = payload as any;
    console.log("webhook IN", JSON.stringify({
      type: pAny.type || pAny.event,
      phone: pAny.phone,
      fromMe: pAny.fromMe,
      isGroup: pAny.isGroup,
      messageId: pAny.messageId || pAny.id,
      hasText: !!pAny.text,
      hasImage: !!pAny.image,
      hasAudio: !!pAny.audio,
      keys: Object.keys(pAny).slice(0, 20),
    }));

    // Ignorar mensagens de grupos (a menos que queira tratar depois)
    if (pAny.isGroup === true) {
      console.log("ignored group message", pAny.phone);
      return jr({ ok: true, ignored: "group" });
    }

    const fromMe = !!pAny.fromMe;
    if (fromMe) {
      // Registra como outbound (echo) para manter histórico unificado
      const phoneOut = normalizePhone((payload as any).phone || (payload as any).chatId);
      if (phoneOut) {
        const p = payload as any;
        const body = p.text?.message || p.message || "";
        const zapiId = p.messageId || p.id || null;
        // Dedupe via upsert com unique index em zapi_message_id (parcial)
        if (zapiId) {
          await admin.from("whatsapp_messages").upsert({
            direction: "outbound",
            phone_normalized: phoneOut,
            message_type: "text",
            body: String(body).slice(0, 4000),
            zapi_message_id: String(zapiId),
            delivery_status: "sent",
            raw_payload: payload as any,
          }, { onConflict: "zapi_message_id", ignoreDuplicates: true });
        } else {
          await admin.from("whatsapp_messages").insert({
            direction: "outbound",
            phone_normalized: phoneOut,
            message_type: "text",
            body: String(body).slice(0, 4000),
            zapi_message_id: null,
            delivery_status: "sent",
            raw_payload: payload as any,
          });
        }
      }
      return jr({ ok: true, recorded: "outbound_echo" });
    }

    // ---- Status de entrega ----
    if ((payload as any).status && (payload as any).messageId) {
      const status = String((payload as any).status).toLowerCase();
      const allowed = ["sent", "delivered", "read", "failed"];
      const newStatus = allowed.includes(status) ? status : "sent";
      await admin
        .from("whatsapp_messages")
        .update({ delivery_status: newStatus })
        .eq("zapi_message_id", String((payload as any).messageId));
      return jr({ ok: true, type: "status_update", new_status: newStatus });
    }

    // ---- Mensagem recebida ----
    const phoneRaw =
      (payload as any).phone ||
      (payload as any).from ||
      (payload as any).chatId ||
      "";
    const phone = normalizePhone(phoneRaw);
    if (!phone) return jr({ error: "Telefone ausente" }, 400);

    const isBroadcast = isBroadcastPayload(payload);

    // ---- Blocklist ----
    const { data: blocked } = await admin
      .from("whatsapp_blocked_numbers")
      .select("id")
      .eq("phone_normalized", phone)
      .maybeSingle();
    if (blocked) {
      console.log("ignored blocked phone", phone);
      return jr({ ok: true, ignored: "blocked", phone });
    }

    // Extrai corpo da mensagem
    const p = payload as any;
    let body = "";
    let messageType: string = "text";
    let mediaUrl: string | null = null;

    if (p.text?.message) { body = String(p.text.message); messageType = "text"; }
    else if (typeof p.message === "string") { body = p.message; messageType = "text"; }
    else if (p.image) { body = p.image.caption || "[imagem]"; messageType = "image"; mediaUrl = p.image.imageUrl || p.image.url || null; }
    else if (p.audio) { body = "[áudio]"; messageType = "audio"; mediaUrl = p.audio.audioUrl || p.audio.url || null; }
    else if (p.video) { body = p.video.caption || "[vídeo]"; messageType = "video"; mediaUrl = p.video.videoUrl || p.video.url || null; }
    else if (p.document) { body = p.document.caption || `[documento] ${p.document.fileName || ""}`.trim(); messageType = "document"; mediaUrl = p.document.documentUrl || p.document.url || null; }
    else if (p.location) { body = `[localização] ${p.location.latitude},${p.location.longitude}`; messageType = "location"; }
    else if (p.contact) { body = `[contato] ${p.contact.displayName || ""}`.trim(); messageType = "contact"; }
    else { body = "[mensagem não reconhecida]"; messageType = "other"; }

    const senderName = p.senderName || p.notifyName || p.chatName || null;
    const zapiMessageId = p.messageId || p.id || null;
    const nowIso = new Date().toISOString();

    // ---- Deduplicação: se essa mensagem já foi processada, retorna idempotente ----
    if (zapiMessageId) {
      const { data: dup } = await admin
        .from("whatsapp_messages")
        .select("id, lead_id, client_id")
        .eq("zapi_message_id", String(zapiMessageId))
        .maybeSingle();
      if (dup) {
        console.log("dedup hit zapi_message_id=", zapiMessageId);
        return jr({
          ok: true,
          deduplicated: true,
          message_id: dup.id,
          lead_id: dup.lead_id,
          client_id: dup.client_id,
        });
      }
    }

    // ---- Match em clients (TODA mensagem é registrada, mesmo de cliente cadastrado) ----
    const { data: allClients } = await admin
      .from("clients")
      .select("id, full_name_or_company_name, phone, whatsapp")
      .eq("active", true);

    let matched: { id: string; full_name_or_company_name: string } | null = null;
    for (const c of allClients || []) {
      const wa = normalizePhone(c.whatsapp);
      const ph = normalizePhone(c.phone);
      if ((wa && wa === phone) || (ph && ph === phone)) {
        matched = { id: c.id, full_name_or_company_name: c.full_name_or_company_name };
        break;
      }
    }

    let leadId: string | null = null;
    let isNewLead = false;

    if (!matched) {
      // Lead existente?
      const { data: existing } = await admin
        .from("whatsapp_leads")
        .select("id, message_count, unread_count")
        .eq("phone_normalized", phone)
        .maybeSingle();

      if (existing) {
        leadId = existing.id;
        await admin
          .from("whatsapp_leads")
          .update({
            last_message_at: nowIso,
            last_inbound_at: nowIso,
            message_count: (existing.message_count || 0) + 1,
            unread_count: (existing.unread_count || 0) + 1,
            display_name: senderName || undefined,
            is_broadcast: isBroadcast || undefined,
          })
          .eq("id", existing.id);
      } else {
        const { data: created } = await admin
          .from("whatsapp_leads")
          .insert({
            phone_normalized: phone,
            display_name: senderName,
            first_message: body.slice(0, 500),
            status: isBroadcast ? "discarded" : "pending",
            is_broadcast: isBroadcast,
            unread_count: 1,
            last_inbound_at: nowIso,
          })
          .select("id")
          .single();
        leadId = created?.id || null;
        isNewLead = !isBroadcast;

        await admin.from("audit_log").insert({
          table_name: "whatsapp_leads",
          record_id: leadId || "00000000-0000-0000-0000-000000000000",
          action: isBroadcast ? "lead_broadcast_ignored" : "lead_created",
          changed_by: "z-api:webhook",
          new_value: { phone, sender_name: senderName, first_message: body.slice(0, 200), is_broadcast: isBroadcast },
          reason: isBroadcast ? "Lead vindo de lista de transmissão (auto-descartado)" : "Novo lead via WhatsApp",
        });
      }
    }

    // ---- Insere mensagem no histórico (idempotente via unique zapi_message_id) ----
    const insertPayload = {
      direction: "inbound",
      phone_normalized: phone,
      message_type: messageType,
      body,
      media_url: mediaUrl,
      client_id: matched?.id || null,
      lead_id: leadId,
      zapi_message_id: zapiMessageId ? String(zapiMessageId) : null,
      delivery_status: "received",
      is_broadcast: isBroadcast,
      raw_payload: payload as any,
    };

    // Dedup já feito acima via SELECT em zapi_message_id; insert direto.
    // (índice unique parcial em zapi_message_id existe, mas PostgREST onConflict não suporta índice parcial)
    const insertRes = await admin
      .from("whatsapp_messages")
      .insert(insertPayload)
      .select("id");

    if (insertRes.error) {
      console.error("FAILED to insert whatsapp_messages", {
        error: insertRes.error,
        phone,
        message_type: messageType,
        zapiMessageId,
      });
      return jr({
        ok: false,
        error: "db_insert_failed",
        details: insertRes.error.message,
      }, 500);
    }

    const insertedId = (insertRes.data && insertRes.data[0]?.id) || null;
    console.log("inbound message saved", {
      id: insertedId,
      phone,
      type: messageType,
      lead_id: leadId,
      client_id: matched?.id,
      is_broadcast: isBroadcast,
    });

    // ---- Notificação imediata para LEADS NOVOS (não broadcast) ----
    if (isNewLead && !isBroadcast) {
      notifyAssignedReminder(admin, phone, senderName, body).catch(() => null);
    }

    return jr({
      ok: true,
      type: "message_received",
      message_id: insertedId,
      matched_client_id: matched?.id || null,
      lead_id: leadId,
      is_broadcast: isBroadcast,
      is_new_lead: isNewLead,
    });
  } catch (err: any) {
    console.error("whatsapp-webhook error", err);
    return jr({ error: err?.message || "internal error" }, 500);
  }
});

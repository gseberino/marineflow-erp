// Edge Function: whatsapp-webhook
// Recebe eventos da Z-API (mensagens recebidas, status de entrega).
// Faz match automático por telefone normalizado contra clients.
// - Match → vincula mensagem ao cliente
// - Sem match → cria/atualiza lead em whatsapp_leads (fila de aprovação)
// Configuração na Z-API:
//   On Message Received → URL: https://<project>.supabase.co/functions/v1/whatsapp-webhook
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

// Normaliza telefone para formato somente dígitos com DDI
function normalizePhone(raw: string | null | undefined, defaultDDI = "55"): string {
  if (!raw) return "";
  let d = String(raw).replace(/\D/g, "");
  if (!d) return "";
  if (d.startsWith("00")) d = d.slice(2);
  if (d.length >= 12) return d;
  if (d.length === 10 || d.length === 11) return `${defaultDDI}${d}`;
  return d;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const payload = await req.json().catch(() => null);
    if (!payload || typeof payload !== "object") {
      return jr({ error: "Invalid payload" }, 400);
    }

    // Z-API envia diferentes formatos por tipo de evento. Eventos comuns:
    // - ReceivedCallback (mensagem recebida): { phone, fromMe, text:{message}, image:{...}, ... }
    // - DeliveryCallback / MessageStatusCallback: { messageId, status, phone }
    const event = (payload as any).type || (payload as any).event || "ReceivedCallback";
    const fromMe = !!(payload as any).fromMe;

    // Ignorar mensagens enviadas por nós mesmos (echo)
    if (fromMe) return jr({ ok: true, ignored: "fromMe" });

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

    // Extrai corpo da mensagem (vários formatos possíveis)
    let body = "";
    let messageType: string = "text";
    let mediaUrl: string | null = null;

    const p = payload as any;
    if (p.text?.message) {
      body = String(p.text.message);
      messageType = "text";
    } else if (typeof p.message === "string") {
      body = p.message;
      messageType = "text";
    } else if (p.image) {
      body = p.image.caption || "[imagem]";
      messageType = "image";
      mediaUrl = p.image.imageUrl || p.image.url || null;
    } else if (p.audio) {
      body = "[áudio]";
      messageType = "audio";
      mediaUrl = p.audio.audioUrl || p.audio.url || null;
    } else if (p.video) {
      body = p.video.caption || "[vídeo]";
      messageType = "video";
      mediaUrl = p.video.videoUrl || p.video.url || null;
    } else if (p.document) {
      body = p.document.caption || `[documento] ${p.document.fileName || ""}`.trim();
      messageType = "document";
      mediaUrl = p.document.documentUrl || p.document.url || null;
    } else if (p.location) {
      body = `[localização] ${p.location.latitude},${p.location.longitude}`;
      messageType = "location";
    } else if (p.contact) {
      body = `[contato] ${p.contact.displayName || ""}`.trim();
      messageType = "contact";
    } else {
      body = "[mensagem não reconhecida]";
      messageType = "other";
    }

    const senderName = p.senderName || p.notifyName || p.chatName || null;
    const zapiMessageId = p.messageId || p.id || null;

    // ---- Match automático em clients ----
    // Tenta achar por whatsapp ou phone normalizado
    const { data: allClients } = await admin
      .from("clients")
      .select("id, full_name_or_company_name, phone, whatsapp")
      .eq("active", true);

    let matched: { id: string; full_name_or_company_name: string } | null = null;
    for (const c of allClients || []) {
      const wa = normalizePhone(c.whatsapp);
      const ph = normalizePhone(c.phone);
      if (wa === phone || ph === phone) {
        matched = { id: c.id, full_name_or_company_name: c.full_name_or_company_name };
        break;
      }
    }

    let leadId: string | null = null;
    if (matched) {
      // Vincular mensagem a cliente existente
      await admin.from("audit_log").insert({
        table_name: "clients",
        record_id: matched.id,
        action: "whatsapp_received",
        changed_by: "z-api:webhook",
        new_value: { phone, message_preview: body.slice(0, 200), zapiMessageId },
        reason: "Mensagem WhatsApp vinculada automaticamente ao cliente",
      });
    } else {
      // Upsert lead (incrementa message_count se já existir)
      const { data: existing } = await admin
        .from("whatsapp_leads")
        .select("id, message_count")
        .eq("phone_normalized", phone)
        .maybeSingle();

      if (existing) {
        leadId = existing.id;
        await admin
          .from("whatsapp_leads")
          .update({
            last_message_at: new Date().toISOString(),
            message_count: (existing.message_count || 0) + 1,
            display_name: senderName || undefined,
          })
          .eq("id", existing.id);
      } else {
        const { data: created } = await admin
          .from("whatsapp_leads")
          .insert({
            phone_normalized: phone,
            display_name: senderName,
            first_message: body.slice(0, 500),
            status: "pending",
          })
          .select("id")
          .single();
        leadId = created?.id || null;

        await admin.from("audit_log").insert({
          table_name: "whatsapp_leads",
          record_id: leadId || "00000000-0000-0000-0000-000000000000",
          action: "lead_created",
          changed_by: "z-api:webhook",
          new_value: { phone, sender_name: senderName, first_message: body.slice(0, 200) },
          reason: "Novo lead via WhatsApp aguardando aprovação",
        });
      }
    }

    // ---- Inserir mensagem no histórico ----
    await admin.from("whatsapp_messages").insert({
      direction: "inbound",
      phone_normalized: phone,
      message_type: messageType,
      body,
      media_url: mediaUrl,
      client_id: matched?.id || null,
      lead_id: leadId,
      zapi_message_id: zapiMessageId,
      delivery_status: "received",
      raw_payload: payload as any,
    });

    return jr({
      ok: true,
      type: "message_received",
      matched_client_id: matched?.id || null,
      lead_id: leadId,
    });
  } catch (err: any) {
    console.error("whatsapp-webhook error", err);
    return jr({ error: err?.message || "internal error" }, 500);
  }
});

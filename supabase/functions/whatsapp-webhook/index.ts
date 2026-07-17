// Edge Function: whatsapp-webhook
// Versão: 7.0 (Evolution-ready)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import { EVOLUTION_STATUS_MAP } from "../_shared/whatsapp/evolution-provider.ts";

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

async function notifyAssignedReminder(
  admin: any,
  phone: string,
  senderName: string | null,
  preview: string,
) {
  try {
    const { data: settings } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["whatsapp_reminder_enabled", "whatsapp_reminder_recipients"]);
    const sMap = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));
    if (
      String(sMap.whatsapp_reminder_enabled).toLowerCase() !== "true" &&
      sMap.whatsapp_reminder_enabled !== "1"
    ) return;
    if (phone.length > 15) return;
    const recipients: string[] = String(sMap.whatsapp_reminder_recipients || "")
      .split(/[,\s]+/)
      .map((p: string) => p.replace(/\D/g, ""))
      .filter((p: string) => p.length >= 10);
    if (recipients.length === 0) return;
    const who = senderName ? `${senderName} (+${phone})` : `+${phone}`;
    const message = `🆕 *Novo lead WhatsApp*\n\n${who}\n"${preview.slice(0, 160)}"\n\nResponda no painel hbrmarine.online`;

    const provider = createWhatsAppProvider();
    await Promise.all(
      recipients.map((to) => provider.sendText(to, message).catch(() => null)),
    );
  } catch (e) {
    console.error("notifyAssignedReminder failed", e);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // --- MODO FAXINA E BLINDAGEM (GET) ---
  if (req.method === "GET") {
    const url = new URL(req.url);

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
          const { count: msgCount } = await admin
            .from("whatsapp_messages")
            .select("*", { count: "exact", head: true })
            .eq("lead_id", l.id);
          if (!msgCount || msgCount === 0) {
            await admin.from("whatsapp_leads").delete().eq("id", l.id);
            count++;
          }
        }
      }
      return new Response(
        `Faxina Concluída! ${count} leads fantasmas removidos. O sistema agora está blindado contra novos registros inválidos.`,
        { headers: { ...corsHeaders, "Content-Type": "text/plain; charset=utf-8" } },
      );
    } catch (e: any) {
      return new Response("Erro: " + e.message, { status: 500, headers: corsHeaders });
    }
  }

  // --- WEBHOOK POST ---
  try {
    const payload = await req.json().catch(() => null);
    if (!payload) return jr({ error: "No payload" }, 400);

    const pAny = payload as any;
    const type = String(pAny.type || pAny.event || "");
    const fromMe = !!pAny.fromMe;

    // Evolution delivery status update (messages.update)
    if (type === "messages.update") {
      const updates = Array.isArray(pAny.data) ? pAny.data : [];
      for (const upd of updates as Array<Record<string, unknown>>) {
        const key = upd["key"] as Record<string, unknown> | undefined;
        const msgId = key?.["id"];
        const statusNum = (upd["update"] as Record<string, unknown> | undefined)?.["status"];
        if (msgId && statusNum !== undefined) {
          const status = EVOLUTION_STATUS_MAP[statusNum as number] ?? String(statusNum);
          await admin
            .from("whatsapp_messages")
            .update({ delivery_status: status })
            .eq("wa_message_id", String(msgId));
        }
      }
      return jr({ ok: true, type: "status" });
    }

    // Parse incoming message via active provider
    const provider = createWhatsAppProvider();
    const event = provider.parseIncomingWebhook(payload);

    if (!event) {
      return jr({ ok: true, ignored: "system_or_group" });
    }

    // Outbound messages with no content — ignored
    if (event.fromMe && !event.text && !event.mediaUrl) {
      return jr({ ok: true, ignored: "outbound_no_body" });
    }

    // Dedup by provider message ID
    if (event.messageId) {
      const { data: dup } = await admin
        .from("whatsapp_messages")
        .select("id")
        .eq("wa_message_id", event.messageId)
        .maybeSingle();
      if (dup) return jr({ ok: true, dedup: true });
    }

    const phone = event.from;
    const body = (event.text || (event.messageType !== "text" ? `[${event.messageType}]` : "[conteúdo vazio]")).slice(0, 4000);

    // ---- AI Operator (Fase 4): número é de um funcionário habilitado? ----
    // Checa ANTES de resolver cliente/lead — se for equipe interna com o canal
    // habilitado, a mensagem nunca vira lead, e quem responde é a IA, não um humano
    // pelo painel. Só se aplica a mensagens genuinamente recebidas (não fromMe).
    if (!event.fromMe) {
      const { data: aiUser } = await admin
        .from("app_users")
        .select("id")
        .eq("phone_normalized", phone)
        .eq("ai_whatsapp_enabled", true)
        .eq("active", true)
        .maybeSingle();

      if (aiUser) {
        const { data: msg } = await admin
          .from("whatsapp_messages")
          .insert({
            direction: "inbound",
            phone_normalized: phone,
            message_type: event.messageType,
            body,
            media_url: event.mediaUrl,
            wa_message_id: event.messageId || null,
            delivery_status: "received",
            raw_payload: pAny,
          })
          .select("id")
          .single();

        const dispatchToAgent = async () => {
          try {
            const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/ai-agent`, {
              method: "POST",
              headers: { "Content-Type": "application/json", "x-internal-secret": Deno.env.get("AI_INTERNAL_SECRET") ?? "" },
              body: JSON.stringify({ channel: "whatsapp", phone_normalized: phone, app_user_id: aiUser.id, text: body }),
            });
            if (!res.ok) console.error("[whatsapp-webhook] ai-agent respondeu", res.status, await res.text().catch(() => ""));
          } catch (e) {
            console.error("[whatsapp-webhook] falha ao disparar ai-agent:", e);
          }
        };
        const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil;
        if (typeof waitUntil === "function") waitUntil(dispatchToAgent());
        else dispatchToAgent().catch(() => null); // fire-and-forget sem waitUntil disponível

        return jr({ ok: true, routed: "ai_operator", message_id: msg?.id });
      }
    }

    let clientId = null;
    let leadId = null;
    let isNewLead = false;

    const { data: client } = await admin
      .from("clients")
      .select("id")
      .or(`phone.ilike.%${phone}%,whatsapp.ilike.%${phone}%`)
      .eq("active", true)
      .maybeSingle();

    if (client) {
      clientId = client.id;
    } else {
      const { data: lead } = await admin
        .from("whatsapp_leads")
        .select("id")
        .eq("phone_normalized", phone)
        .maybeSingle();
      if (lead) {
        leadId = lead.id;
      } else if (!event.fromMe) {
        const isValidPhone = phone.startsWith("55") && (phone.length === 12 || phone.length === 13);
        if (isValidPhone) {
          const { data: newLead } = await admin
            .from("whatsapp_leads")
            .insert({
              phone_normalized: phone,
              name: event.senderName || null,
              status: "pending",
            })
            .select("id")
            .single();
          leadId = newLead?.id;
          isNewLead = true;
        }
      }
    }

    const { data: msg, error: insErr } = await admin
      .from("whatsapp_messages")
      .insert({
        direction: event.fromMe ? "outbound" : "inbound",
        phone_normalized: phone,
        message_type: event.messageType,
        body,
        media_url: event.mediaUrl,
        client_id: clientId,
        lead_id: leadId,
        wa_message_id: event.messageId || null,
        delivery_status: event.fromMe ? "sent" : "received",
        raw_payload: pAny,
      })
      .select("id")
      .single();

    if (insErr) return jr({ error: "db_error", details: insErr.message }, 500);

    if (isNewLead && !event.fromMe) {
      notifyAssignedReminder(admin, phone, event.senderName, body).catch(console.error);
    }

    if (leadId) {
      // Mantém o cache de frescor do lead atualizado (antes só gravava updated_at, o que
      // deixava last_inbound_at/last_outbound_at congelados e quebrava a caixa de entrada).
      const nowIso = new Date().toISOString();
      const leadPatch: Record<string, unknown> = { updated_at: nowIso, last_message_at: nowIso };
      if (event.fromMe) leadPatch.last_outbound_at = nowIso;
      else leadPatch.last_inbound_at = nowIso;
      await admin
        .from("whatsapp_leads")
        .update(leadPatch)
        .eq("id", leadId);
    } else if (clientId) {
      await admin
        .from("clients")
        .update({ updated_at: new Date().toISOString() })
        .eq("id", clientId);
    }

    return jr({ ok: true, message_id: msg?.id });
  } catch (err: any) {
    return jr({ error: err.message }, 500);
  }
});

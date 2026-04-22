// Edge Function: whatsapp-unread-reminder
// Roda periodicamente (cron). Detecta conversas WhatsApp com mensagens inbound
// não respondidas há > N minutos e envia lembrete via Z-API para os
// responsáveis configurados.
//
// Configuração via app_settings (key/value):
//   - whatsapp_reminder_minutes          (default 30)   minutos sem resposta para considerar pendente
//   - whatsapp_reminder_cooldown_minutes (default 60)   intervalo mínimo entre lembretes para a mesma conversa
//   - whatsapp_reminder_recipients       (default '')   CSV de telefones (DDI+DDD+numero). Se vazio, usa app_users
//                                                       ativos com role admin/financial e phone preenchido.
//
// Estado: usa app_settings key=`whatsapp_reminder_state_<phone>` com timestamp ISO
//         do último lembrete enviado por conversa (para respeitar cooldown).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function getSetting(
  admin: ReturnType<typeof createClient>,
  key: string,
  fallback: string,
): Promise<string> {
  const { data } = await admin
    .from("app_settings")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  return (data?.value as string) || fallback;
}

async function setSetting(
  admin: ReturnType<typeof createClient>,
  key: string,
  value: string,
): Promise<void> {
  await admin.from("app_settings").upsert(
    { key, value, description: "auto: whatsapp reminder state" },
    { onConflict: "key" },
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const INSTANCE_ID = Deno.env.get("ZAPI_INSTANCE_ID");
    const TOKEN = Deno.env.get("ZAPI_TOKEN");
    const CLIENT_TOKEN = Deno.env.get("ZAPI_CLIENT_TOKEN");

    if (!INSTANCE_ID || !TOKEN) {
      return jr({ error: "Z-API não configurado" }, 500);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    const reminderMin = parseInt(
      await getSetting(admin, "whatsapp_reminder_minutes", "30"),
      10,
    );
    const cooldownMin = parseInt(
      await getSetting(admin, "whatsapp_reminder_cooldown_minutes", "60"),
      10,
    );
    const recipientsCsv = await getSetting(
      admin,
      "whatsapp_reminder_recipients",
      "",
    );

    // Resolve destinatários: lista CSV explícita, ou app_users admin/financial com phone
    let recipients: string[] = recipientsCsv
      .split(/[,\s]+/)
      .map((p) => p.replace(/\D/g, ""))
      .filter((p) => p.length >= 10);

    if (recipients.length === 0) {
      const { data: users } = await admin
        .from("app_users")
        .select("phone, role, active")
        .eq("active", true)
        .in("role", ["admin", "financial", "manager"]);
      recipients = (users || [])
        .map((u: any) => (u.phone || "").replace(/\D/g, ""))
        .filter((p: string) => p.length >= 10);
    }

    if (recipients.length === 0) {
      return jr({
        ok: true,
        skipped: "Nenhum destinatário configurado (defina whatsapp_reminder_recipients ou cadastre telefone em app_users admin/financial).",
      });
    }

    const cutoff = new Date(Date.now() - reminderMin * 60_000).toISOString();
    const cooldownCutoff = new Date(Date.now() - cooldownMin * 60_000).toISOString();

    // Buscar últimas mensagens INBOUND mais antigas que cutoff
    const { data: inboundMsgs, error: msgsErr } = await admin
      .from("whatsapp_messages")
      .select("phone_normalized, occurred_at, body")
      .eq("direction", "inbound")
      .lte("occurred_at", cutoff)
      .order("occurred_at", { ascending: false })
      .limit(500);

    if (msgsErr) return jr({ error: msgsErr.message }, 500);

    // Agrupar por phone — pegar a mais recente de cada
    const lastInboundByPhone = new Map<string, { at: string; body: string }>();
    for (const m of inboundMsgs || []) {
      if (!lastInboundByPhone.has(m.phone_normalized)) {
        lastInboundByPhone.set(m.phone_normalized, {
          at: m.occurred_at,
          body: (m.body || "").slice(0, 80),
        });
      }
    }

    // Para cada conversa, verificar se houve outbound DEPOIS da última inbound
    const pending: Array<{
      phone: string;
      since: string;
      preview: string;
      displayName: string | null;
    }> = [];

    for (const [phone, info] of lastInboundByPhone.entries()) {
      const { count } = await admin
        .from("whatsapp_messages")
        .select("id", { count: "exact", head: true })
        .eq("phone_normalized", phone)
        .eq("direction", "outbound")
        .gt("occurred_at", info.at);
      if ((count || 0) > 0) continue; // já respondido

      // checa cooldown via app_settings
      const stateKey = `whatsapp_reminder_state_${phone}`;
      const lastSent = await getSetting(admin, stateKey, "");
      if (lastSent && lastSent > cooldownCutoff) continue;

      // pega display_name
      const { data: lead } = await admin
        .from("whatsapp_leads")
        .select("display_name")
        .eq("phone_normalized", phone)
        .maybeSingle();

      pending.push({
        phone,
        since: info.at,
        preview: info.body,
        displayName: lead?.display_name || null,
      });
    }

    if (pending.length === 0) {
      return jr({ ok: true, pending: 0, recipients: recipients.length });
    }

    // Monta mensagem
    const lines = pending
      .slice(0, 10)
      .map((p, i) => {
        const who = p.displayName ? `${p.displayName} (${p.phone})` : p.phone;
        const ago = Math.round(
          (Date.now() - new Date(p.since).getTime()) / 60_000,
        );
        return `${i + 1}. ${who} — ${ago} min sem resposta\n   "${p.preview}"`;
      })
      .join("\n");
    const more = pending.length > 10 ? `\n…e mais ${pending.length - 10}.` : "";
    const message =
      `🔔 *Lembrete WhatsApp* — ${pending.length} conversa(s) sem resposta há mais de ${reminderMin} min:\n\n${lines}${more}\n\nResponda em: ${SUPABASE_URL.replace(".supabase.co", "")}`;

    // Envia para cada destinatário
    const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;
    const zapiHeaders: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (CLIENT_TOKEN) zapiHeaders["Client-Token"] = CLIENT_TOKEN;

    const sendResults: Array<{ to: string; ok: boolean; error?: string }> = [];
    for (const to of recipients) {
      try {
        const res = await fetch(`${base}/send-text`, {
          method: "POST",
          headers: zapiHeaders,
          body: JSON.stringify({ phone: to, message }),
        });
        const body = await res.json().catch(() => ({}));
        const ok = res.ok && !(body as any).error;
        sendResults.push({
          to,
          ok,
          error: ok ? undefined : (body as any).error || `HTTP ${res.status}`,
        });
      } catch (e) {
        sendResults.push({
          to,
          ok: false,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }

    // Atualiza state de cooldown apenas se houve ao menos um envio com sucesso
    const anySuccess = sendResults.some((r) => r.ok);
    if (anySuccess) {
      const now = new Date().toISOString();
      for (const p of pending) {
        await setSetting(admin, `whatsapp_reminder_state_${p.phone}`, now);
      }
    }

    // Audit
    await admin.from("audit_log").insert({
      table_name: "whatsapp_messages",
      record_id: "00000000-0000-0000-0000-000000000000",
      action: "whatsapp_unread_reminder",
      changed_by: "cron",
      new_value: {
        pending_count: pending.length,
        recipients,
        send_results: sendResults,
        reminder_minutes: reminderMin,
        cooldown_minutes: cooldownMin,
      },
      reason: `Lembrete enviado para ${sendResults.filter((r) => r.ok).length}/${recipients.length} destinatário(s) sobre ${pending.length} conversa(s).`,
    });

    return jr({
      ok: true,
      pending: pending.length,
      recipients: recipients.length,
      send_results: sendResults,
    });
  } catch (err) {
    console.error("whatsapp-unread-reminder error", err);
    return jr(
      { error: err instanceof Error ? err.message : "Unknown error" },
      500,
    );
  }
});

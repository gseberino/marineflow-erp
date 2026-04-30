// Edge Function: whatsapp-webhook
// Recebe TODOS os eventos da Z-API (mensagens recebidas, status de entrega).
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

/**
 * Normalização de Telefone MarineFlow v3 (LID-Ready)
 */
function normalizePhone(raw: string | null | undefined): string {
  if (!raw) return "";
  
  // Remove sufixos comuns da Z-API/WhatsApp
  const clean = String(raw).split("@")[0];
  const digits = clean.replace(/\D/g, "");
  
  if (!digits) return "";

  // Se for um LID (identificador interno do WhatsApp Business)
  // LIDs costumam ser longos (14-16 dígitos) e não seguem a regra do DDI 55
  if (digits.length >= 14) {
    return digits; // Retorna o ID puro
  }

  // Se for um número brasileiro padrão (10 ou 11 dígitos), força o 55
  if (digits.length === 10 || digits.length === 11) {
    return `55${digits}`;
  }

  // Se já tem 12 ou 13 dígitos, assumimos que já está com DDI ou é internacional
  return digits;
}

function extractBodyAndType(p: any): { body: string; messageType: string; mediaUrl: string | null } {
  let mediaUrl: null | string = null;
  
  // Captura texto de qualquer variante de payload Z-API
  const text = p?.text?.message || 
               p?.text || 
               p?.message?.conversation || 
               p?.message?.extendedTextMessage?.text || 
               p?.body || 
               p?.caption || 
               "";
  
  if (p?.image) {
    mediaUrl = p.image.imageUrl || p.image.url || null;
    return { body: p.image.caption || "[imagem]", messageType: "image", mediaUrl };
  }
  if (p?.audio) {
    mediaUrl = p.audio.audioUrl || p.audio.url || null;
    return { body: "[áudio]", messageType: "audio", mediaUrl };
  }
  if (p?.video) {
    mediaUrl = p.video.videoUrl || p.video.url || null;
    return { body: p.video.caption || "[vídeo]", messageType: "video", mediaUrl };
  }
  if (p?.document) {
    mediaUrl = p.document.documentUrl || p.document.url || null;
    return { body: p.document.caption || `[documento] ${p.document.fileName || ""}`.trim(), messageType: "document", mediaUrl };
  }
  
  return { body: String(text).trim() || "[conteúdo vazio]", messageType: "text", mediaUrl };
}

async function notifyAssignedReminder(
  admin: any,
  phone: string,
  senderName: string | null,
  preview: string,
  zapiCreds: { id: string; token: string; client: string | null }
) {
  try {
    if (!zapiCreds.id || !zapiCreds.token) return;
    
    // 1. Verificar se notificações estão ativadas
    const { data: settings } = await admin.from("app_settings").select("key, value").in("key", ["whatsapp_reminder_enabled", "whatsapp_reminder_recipients"]);
    const sMap = Object.fromEntries((settings || []).map(s => [s.key, s.value]));
    
    const isEnabled = String(sMap.whatsapp_reminder_enabled).toLowerCase() === "true" || sMap.whatsapp_reminder_enabled === "1";
    if (!isEnabled) {
      console.log("[Notify] Notificação desativada nas configurações.");
      return;
    }

    // 2. Ignorar LIDs (IDs internos do WhatsApp que poluem o celular)
    if (phone.length > 15) {
      console.log("[Notify] Ignorando LID:", phone);
      return;
    }

    let recipients: string[] = String(sMap.whatsapp_reminder_recipients || "")
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
    const message = `🆕 *Novo lead WhatsApp*\n\n${who}\n"${preview.slice(0, 160)}"\n\nResponda no painel hbrmarine.online`;

    const base = `https://api.z-api.io/instances/${zapiCreds.id}/token/${zapiCreds.token}`;
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (zapiCreds.client) headers["Client-Token"] = zapiCreds.client;

    await Promise.all(
      recipients.map((to) =>
        fetch(`${base}/send-text`, {
          method: "POST",
          headers,
          body: JSON.stringify({ phone: to, message }),
        }).catch(() => null)
      )
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
    { auth: { persistSession: false, autoRefreshToken: false } }
  );

  // --- CORREÇÃO FINAL V5.0 (THE FINISHER) ---
  if (req.method === "GET") {
    try {
      console.log("[Fix] Iniciando Reconstrução Final V5.0...");
      const f = "\uFFFD";
      
      const patterns = [
        // Cidades e Endereços
        { from: `Jo${f}o`, to: "João" }, { from: `Palho${f}a`, to: "Palhoça" },
        { from: `Aruj${f}`, to: "Arujá" }, { from: `Mour${f}o`, to: "Mourão" },
        { from: `Bar${f}o`, to: "Barão" }, { from: `Jundia${f}`, to: "Jundiaí" },
        { from: `Tr${f}s`, to: "Três" }, { from: `Maring${f}`, to: "Maringá" },
        { from: `Gusm${f}o`, to: "Gusmão" }, { from: `J${f}nio`, to: "Júnio" },
        
        // Nomes e Termos em MAIÚSCULO
        { from: `L${f}GIA`, to: "LÍGIA" }, { from: `VE${f}CULO`, to: "VEÍCULO" },
        { from: `ARA${f}JO`, to: "ARAÚJO" }, { from: `ALC${f}NTARA`, to: "ALCÂNTARA" },
        { from: `PE${f}AS`, to: "PEÇAS" }, { from: `IND${f}STRIA`, to: "INDÚSTRIA" },
        { from: `COM${f}RCIO`, to: "COMÉRCIO" }, { from: `N${f}UTICA`, to: "NÁUTICA" },
        { from: `N${f}UTICOS`, to: "NÁUTICOS" }, { from: `CORPORA${f}${f}O`, to: "CORPORAÇÃO" },
        
        // Nomes Próprios e Termos Técnicos
        { from: `Lu${f}s`, to: "Luís" }, { from: `Imobili${f}rios`, to: "Imobiliários" },
        { from: `Ep${f}xi`, to: "Epóxi" }, { from: `Gusm${f}o`, to: "Gusmão" },
        { from: `Galvaniza${f}${f}o`, to: "Galvanização" }
      ];

      let count = 0;
      const tables = [
        { name: "clients", cols: ["full_name_or_company_name", "city", "neighborhood", "address"] },
        { name: "marinas", cols: ["name", "city"] },
        { name: "vessels", cols: ["boat_name", "home_port"] }
      ];

      for (const table of tables) {
        const { data: rows } = await admin.from(table.name).select("*");
        if (!rows) continue;

        for (const row of rows) {
          let updateObj: any = {};
          let changed = false;

          for (const col of table.cols) {
            let val = row[col] || "";
            let oldVal = val;
            if (val.includes(f) || val.includes("?")) {
              for (const p of patterns) {
                const regex = new RegExp(p.from.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
                if (regex.test(val)) { val = val.replace(regex, p.to); changed = true; }
              }
            }
            if (oldVal !== val) updateObj[col] = val;
          }

          if (changed) {
            await admin.from(table.name).update(updateObj).eq("id", row.id);
            count++;
          }
        }
      }

      return new Response(`Limpeza Final Concluída! ${count} registros restaurados.`, { headers: { ...corsHeaders, "Content-Type": "text/plain; charset=utf-8" } });
    } catch (e) {
      return new Response("Erro: " + e.message, { status: 500, headers: corsHeaders });
    }
  }
  // --- FIM DA FERRAMENTA ---

  try {
    const url = new URL(req.url);
    
    // ---- Healthcheck (GET) ----
    if (req.method === "GET" || url.searchParams.get("healthcheck") === "1") {
      const { count: totalInbound } = await admin.from("whatsapp_messages").select("*", { count: "exact", head: true }).eq("direction", "inbound");
      const { data: recent } = await admin.from("whatsapp_messages").select("*").eq("direction", "inbound").order("created_at", { ascending: false }).limit(5);
      
      return jr({
        ok: true,
        type: "healthcheck",
        total_inbound: totalInbound || 0,
        recent_messages: (recent || []).map(m => ({ at: m.created_at, phone: m.phone_normalized, body: m.body })),
        checked_at: new Date().toISOString(),
      });
    }

    const payload = await req.json().catch(() => null);
    
    // LOG DE DEPURAÇÃO (Tenta salvar, mas não trava se falhar)
    try {
      await admin.from("app_settings").upsert({ 
        key: "debug_last_webhook", 
        value: JSON.stringify({
          received_at: new Date().toISOString(),
          method: req.method,
          payload: payload
        })
      }, { onConflict: 'key' });
    } catch (dbErr) {
      console.error("[Webhook Debug Log Error]:", dbErr);
    }

    if (!payload) {
      console.error("[Webhook] Payload vazio");
      return jr({ error: "No payload" }, 400);
    }

    const pAny = payload as any;
    const type = String(pAny.type || pAny.event || "");
    const phoneRaw = pAny.phone || pAny.chatId || pAny.senderLid || "";
    const phone = normalizePhone(phoneRaw);
    const fromMe = !!pAny.fromMe;

    console.log(`[Webhook Audit] Type: ${type} | FromMe: ${fromMe} | Raw: ${phoneRaw} | Normalized: ${phone}`);

    // 1. Ignorar o que não é mensagem ou status
    const ignoredTypes = [
      "PresenceChatCallback", 
      "ChatStateCallback", 
      "PresenceCallback", 
      "ChatPresence", 
      "Presence",
      "typing",
      "recording"
    ];
    if (ignoredTypes.includes(type) || ignoredTypes.includes(pAny.event)) {
      return jr({ ok: true, ignored: "system_callback" });
    }

    if (pAny.isGroup === true || String(pAny.chatId || "").includes("-")) {
      return jr({ ok: true, ignored: "group" });
    }

    // 2. Buscar Credenciais Z-API
    const { data: settings } = await admin.from("app_settings").select("key, value").in("key", ["zapi_instance_id", "zapi_token", "zapi_client_token"]);
    const sMap = Object.fromEntries((settings || []).map(s => [s.key, s.value]));
    const zapiCreds = {
      id: sMap.zapi_instance_id || "",
      token: sMap.zapi_token || "",
      client: sMap.zapi_client_token || null
    };

    // 3. Status de Entrega (Apenas se não for uma mensagem nova)
    const isStatusUpdate = type === "MessageStatusCallback" || type === "MessageStatus";
    
    if (isStatusUpdate) {
      const status = String(pAny.status || "").toLowerCase();
      const zapiId = pAny.messageId || (Array.isArray(pAny.ids) ? pAny.ids[0] : null);
      if (zapiId && status) {
        console.log(`[Status] Atualizando ${zapiId} para ${status}`);
        await admin.from("whatsapp_messages").update({ delivery_status: status }).eq("zapi_message_id", String(zapiId));
      }
      return jr({ ok: true, type: "status_update" });
    }

    // 4. Salvar Mensagem
    const { body, messageType, mediaUrl } = extractBodyAndType(pAny);
    const zapiId = pAny.messageId || pAny.id || null;

    if (zapiId) {
      const { data: dup } = await admin.from("whatsapp_messages").select("id").eq("zapi_message_id", String(zapiId)).maybeSingle();
      if (dup) return jr({ ok: true, dedup: true });
    }

    let clientId = null;
    let leadId = null;
    let isNewLead = false;

    // Busca cliente
    const { data: client } = await admin.from("clients").select("id").or(`phone.ilike.%${phone}%,whatsapp.ilike.%${phone}%`).eq("active", true).maybeSingle();
    
    if (client) {
      clientId = client.id;
    } else {
      const { data: lead } = await admin.from("whatsapp_leads").select("id").eq("phone_normalized", phone).maybeSingle();
      if (lead) {
        leadId = lead.id;
      } else if (!fromMe) {
        const { data: newLead } = await admin.from("whatsapp_leads").insert({
          phone_normalized: phone,
          display_name: pAny.senderName || pAny.notifyName || null,
          status: "pending"
        }).select("id").single();
        leadId = newLead?.id;
        isNewLead = true;
      }
    }

    const direction = fromMe ? "outbound" : "inbound";
    const { data: msg, error: insErr } = await admin.from("whatsapp_messages").insert({
      direction,
      phone_normalized: phone,
      message_type: messageType,
      body: body.slice(0, 4000),
      media_url: mediaUrl,
      client_id: clientId,
      lead_id: leadId,
      zapi_message_id: zapiId ? String(zapiId) : null,
      delivery_status: direction === "inbound" ? "received" : "sent",
      raw_payload: pAny
    }).select("id").single();

    if (insErr) {
      console.error("[Webhook] Erro no insert:", insErr);
      return jr({ error: "db_error", details: insErr.message }, 500);
    }

    if (isNewLead && direction === "inbound") {
      notifyAssignedReminder(admin, phone, pAny.senderName || null, body, zapiCreds).catch(console.error);
    }

    // 6. Atualizar timestamp do Lead/Cliente para o Inbox ordenar em Realtime
    if (leadId) {
      await admin.from("whatsapp_leads").update({ updated_at: new Date().toISOString() }).eq("id", leadId);
    } else if (clientId) {
      await admin.from("clients").update({ updated_at: new Date().toISOString() }).eq("id", clientId);
    }

    return jr({ ok: true, message_id: msg?.id });

  } catch (err: any) {
    console.error("[Webhook Fatal Error]:", err);
    return jr({ error: err.message }, 500);
  }
});

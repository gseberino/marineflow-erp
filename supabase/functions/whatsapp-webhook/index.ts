// Edge Function: whatsapp-webhook
// Versão: 7.0 (Evolution-ready)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import { EVOLUTION_STATUS_MAP } from "../_shared/whatsapp/evolution-provider.ts";
import { classificarResposta } from "../_shared/ai/comms/reply-router.ts";

// Manejo automático da resposta (Camada de Inteligência de Comunicação, módulo G):
// fecha o loop no ai_comms_log (marca respondido + intenção) e HONRA OPT-OUT sozinho.
// Serve cliente E fornecedor. Best-effort: nunca derruba o webhook.
async function manejarRespostaAutomatica(admin: any, tabela: "clients" | "suppliers", entityId: string, texto: string): Promise<void> {
  try {
    if (!entityId || !texto?.trim()) return;
    const r = classificarResposta(texto);
    // Fecha o loop: marca o último envio a esta entidade como respondido.
    const { data: log } = await admin
      .from("ai_comms_log")
      .select("id")
      .eq("entity_id", entityId)
      .is("responded_at", null)
      .order("created_at", { ascending: false })
      .limit(1);
    const logId = (log as any[])?.[0]?.id;
    if (logId) await admin.from("ai_comms_log").update({ responded_at: new Date().toISOString(), reply_intent: r.intencao }).eq("id", logId);
    // Opt-out é ação segura e clara: honra na hora (bloqueia envios futuros).
    if (r.intencao === "opt_out") {
      await admin.from(tabela).update({ opt_out_whatsapp: true }).eq("id", entityId);
    }
  } catch (_e) {
    // best-effort — silencioso
  }
}

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

// Comparação em tempo constante para não vazar o segredo por timing.
// (mesma implementação já usada em pluggy-webhook)
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

/**
 * Segredo compartilhado com a Evolution API. Chega SEM Authorization
 * (verify_jwt=false), então o segredo é a ÚNICA autenticação desta função.
 *
 * Aceito por query string (?token=...) OU pelo cabeçalho x-webhook-token: a
 * Evolution registra a URL do webhook, e nem toda versão permite cabeçalho
 * customizado — a query string garante que dá para configurar em qualquer uma.
 *
 * Fail-closed em tudo: sem secret nos env vars, rejeita; sem token na
 * requisição, rejeita. Antes desta checagem NÃO pode haver nenhum I/O — é o
 * que garante que uma requisição anônima não alcance o banco.
 *
 * Devolve a Response de recusa, ou null quando a requisição está autorizada.
 */
export function verificarSegredo(req: Request): Response | null {
  const expected = Deno.env.get("EVOLUTION_WEBHOOK_TOKEN");
  if (!expected) {
    console.error("[whatsapp-webhook] EVOLUTION_WEBHOOK_TOKEN ausente nos secrets — rejeitando tudo.");
    return jr({ error: "not_configured" }, 500);
  }
  const url = new URL(req.url);
  const apresentado = url.searchParams.get("token") ?? req.headers.get("x-webhook-token") ?? "";
  if (!timingSafeEqual(apresentado, expected)) {
    console.warn(`[whatsapp-webhook] 401 — segredo ausente ou incorreto (${req.method}).`);
    return jr({ error: "unauthorized" }, 401);
  }
  return null;
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

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Autenticação ANTES de qualquer I/O: requisição sem segredo não toca no banco.
  const recusa = verificarSegredo(req);
  if (recusa) return recusa;

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // --- DIAGNÓSTICO (GET) ---
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

        // Só o que o diagnóstico devolve: nem telefone nem corpo são buscados,
        // para não existirem em memória nem em log de erro desta rota.
        const { data: lastMsg } = await admin
          .from("whatsapp_messages")
          .select("created_at")
          .eq("direction", "inbound")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        const { data: recentMsgs } = await admin
          .from("whatsapp_messages")
          .select("created_at, message_type")
          .eq("direction", "inbound")
          .order("created_at", { ascending: false })
          .limit(5);

        const minutesSinceLast = lastMsg
          ? Math.floor((now.getTime() - new Date(lastMsg.created_at).getTime()) / 60000)
          : null;

        const healthStatus =
          !lastMsg ? "never" :
          minutesSinceLast !== null && minutesSinceLast > 60 ? "stale" : "ok";

        // O diagnóstico responde "o webhook está recebendo?" — e só isso.
        // Telefone e corpo da mensagem NÃO saem daqui: quem precisa ler conversa
        // usa o painel, que tem RLS. Mesmo com o segredo correto, esta rota não
        // é um leitor de mensagens (defesa em profundidade: se o token vazar,
        // vaza um contador, não a conversa do cliente).
        return jr({
          webhook_url: webhookUrl,
          health_status: healthStatus,
          total_inbound: totalInbound ?? 0,
          last_24h: last24h ?? 0,
          last_message_at: lastMsg?.created_at ?? null,
          minutes_since_last: minutesSinceLast,
          recent_messages: (recentMsgs || []).map((m) => ({
            at: m.created_at,
            type: m.message_type,
          })),
          checked_at: now.toISOString(),
        });
      } catch (e: any) {
        return jr({ error: e.message }, 500);
      }
    }

    // A "faxina de leads fantasmas" foi REMOVIDA daqui (MF-AUD-053).
    // Era um DELETE em whatsapp_leads disparado por um GET sem parâmetro — uma
    // operação destrutiva na rota mais exposta do sistema, e sem confirmação.
    // É manutenção pontual, não rota de webhook: se precisar de novo, faz-se por
    // SQL, com o resultado revisado antes de apagar.
    return jr({ error: "method_not_allowed", hint: "Use ?healthcheck=1" }, 405);
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
            // Áudio-comando do dono: transcreve o áudio ANTES de despachar, para o agente
            // agir sobre o que foi FALADO (e não sobre "[audio]"). Roda no fundo (waitUntil),
            // então o webhook responde rápido. Se falhar, cai em "[audio]" e o agente pede
            // para repetir/digitar.
            let dispatchText = body;
            if (event.messageType === "audio" && msg?.id) {
              try {
                const tr = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-transcribe-audio`, {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json",
                    Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
                  },
                  body: JSON.stringify({ message_id: msg.id }),
                });
                const trBody = await tr.json().catch(() => ({}));
                if (trBody?.ok && trBody?.text) dispatchText = String(trBody.text);
              } catch (_e) { /* mantém "[audio]" */ }
            }
            const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/ai-agent`, {
              method: "POST",
              headers: { "Content-Type": "application/json", "x-internal-secret": Deno.env.get("AI_INTERNAL_SECRET") ?? "" },
              body: JSON.stringify({ channel: "whatsapp", phone_normalized: phone, app_user_id: aiUser.id, text: dispatchText }),
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

    // Módulo G (inbound): resposta de contato conhecido → fecha o loop de comunicação
    // (marca respondido + intenção) e honra opt-out automaticamente. Best-effort, assíncrono.
    // Cliente tem prioridade; se não for cliente, tenta fornecedor (respostas de cotação).
    if (!event.fromMe && body) {
      if (clientId) {
        manejarRespostaAutomatica(admin, "clients", clientId, body).catch(() => {});
      } else {
        (async () => {
          try {
            const { data: sup } = await admin.from("suppliers").select("id").ilike("phone", `%${phone}%`).eq("active", true).limit(1).maybeSingle();
            if (sup?.id) await manejarRespostaAutomatica(admin, "suppliers", sup.id, body);
          } catch { /* best-effort */ }
        })();
      }
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

    // Áudio inbound → transcreve via Groq Whisper (fire-and-forget; não atrasa o webhook).
    // Se GROQ_API_KEY não estiver setada, a função sai sem efeito (a mensagem segue "[audio]").
    if (!event.fromMe && event.messageType === "audio" && msg?.id) {
      const transcribe = async () => {
        try {
          await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-transcribe-audio`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
            },
            body: JSON.stringify({ message_id: msg.id }),
          });
        } catch (_e) { /* graceful — a mensagem segue como "[audio]" */ }
      };
      const waitUntil = (globalThis as any).EdgeRuntime?.waitUntil;
      if (typeof waitUntil === "function") waitUntil(transcribe());
      else transcribe().catch(() => null);
    }

    return jr({ ok: true, message_id: msg?.id });
  } catch (err: any) {
    return jr({ error: err.message }, 500);
  }
}

Deno.serve(handler);

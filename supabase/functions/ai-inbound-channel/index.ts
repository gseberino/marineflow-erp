// Edge Function: ai-inbound-channel
// Autonomous processor for inbound WhatsApp messages.
// Called by the existing Z-API webhook handler (or inbox processor) with:
//   { phone: "5547999999999", message: "text", message_id?: "id" }
// Auth: x-api-key header with value from app_settings.inbound_channel_secret
//       OR x-cron-secret (same as other workers) for testing.
//
// What it does:
//   1. Identify the client by phone number.
//   2. Load their recent OS history and session context.
//   3. Call Gemini to classify intent + generate response.
//   4. Send the response back via Z-API directly.
//   5. For actionable intents: create ai_agent_tasks for operator review.
//   6. Update the inbound session with the new message.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai";
const MODEL = Deno.env.get("GEMINI_MODEL_FAST") || "gemini-2.5-flash";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-api-key, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

function brl(v: unknown): string {
  return Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // ── Auth ───────────────────────────────────────────────────────────────────
    const apiKey = req.headers.get("x-api-key") ?? "";
    const cronSecret = req.headers.get("x-cron-secret") ?? "";

    const { data: cronRow } = await admin.from("app_settings").select("value")
      .eq("key", "cron_worker_secret").single();
    const masterSecret = String(cronRow?.value || "");

    let authed = cronSecret === masterSecret && masterSecret !== "";
    if (!authed) {
      const { data: keyRow } = await admin.from("app_settings").select("value")
        .eq("key", "inbound_channel_secret").single();
      authed = apiKey !== "" && apiKey === String(keyRow?.value || "");
    }
    if (!authed) return resp({ error: "Unauthorized" }, 401);

    // ── Parse body ─────────────────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const rawPhone = String(body.phone || "").replace(/\D/g, "");
    const messageText = String(body.message || "").trim();
    const messageId = String(body.message_id || "");

    if (!rawPhone || !messageText) {
      return resp({ error: "phone and message are required" }, 400);
    }

    // ── Load app settings ──────────────────────────────────────────────────────
    const { data: settingsRows } = await admin.from("app_settings").select("key, value");
    const settings: Record<string, string> = {};
    (settingsRows || []).forEach((r: any) => { if (r.key) settings[r.key] = String(r.value ?? ""); });
    const company = settings.company_name || "HBR Marine Solutions";
    const zapiInstanceId = settings.zapi_instance_id || Deno.env.get("ZAPI_INSTANCE_ID") || "";
    const zapiToken = settings.zapi_token || Deno.env.get("ZAPI_TOKEN") || "";
    const zapiClientToken = settings.zapi_client_token || Deno.env.get("ZAPI_CLIENT_TOKEN") || "";

    // ── Identify client ────────────────────────────────────────────────────────
    const { data: client } = await admin
      .from("clients")
      .select("id, full_name_or_company_name, type")
      .or(`phone.eq.${rawPhone},whatsapp.eq.${rawPhone}`)
      .eq("active", true)
      .maybeSingle();

    const clientName: string | null = client?.full_name_or_company_name || null;
    const clientId: string | null = client?.id || null;

    // ── Load recent OSs for context ───────────────────────────────────────────
    const contextLines: string[] = [];
    if (clientId) {
      const { data: recentOS } = await admin
        .from("service_orders")
        .select("service_order_number, status, grand_total, updated_at, vessels(boat_name)")
        .eq("client_id", clientId)
        .not("status", "eq", "cancelled")
        .order("updated_at", { ascending: false })
        .limit(3);

      for (const so of recentOS ?? []) {
        const vessel = (so.vessels as any)?.boat_name || "";
        const statusPt: Record<string, string> = {
          draft: "Rascunho", open: "Aberta", scheduled: "Agendada",
          in_progress: "Em andamento", awaiting_parts: "Aguardando peças",
          awaiting_client: "Aguardando aprovação", approved: "Aprovada",
          completed: "Concluída", invoiced: "Faturada", cancelled: "Cancelada",
        };
        contextLines.push(
          `- OS ${so.service_order_number}${vessel ? ` (${vessel})` : ""}: ${statusPt[so.status] || so.status}${so.grand_total ? ` — R$ ${brl(so.grand_total)}` : ""}`
        );
      }
    }

    // ── Load or create session ─────────────────────────────────────────────────
    const { data: session } = await admin
      .from("ai_inbound_sessions")
      .select("id, messages, last_intent, session_data")
      .eq("phone", rawPhone)
      .maybeSingle();

    const sessionMessages: Array<{ role: string; content: string; ts: string }> =
      Array.isArray(session?.messages) ? (session!.messages as any[]).slice(-6) : [];

    // ── Build conversation for AI ──────────────────────────────────────────────
    const now = new Date();
    const nowBRT = new Date(now.getTime() - 3 * 3600 * 1000);

    const systemPrompt = `Você é o assistente autônomo de atendimento da ${company}.
Responda sempre em português, de forma amigável, profissional e concisa (máximo 3 parágrafos curtos — adequado para WhatsApp).
NUNCA mencione que é uma IA. Apresente-se como "atendimento ${company}".
NUNCA compartilhe preços detalhados de produtos ou negocie descontos — direcione ao time.
NUNCA crie OS ou registros — apenas informe sobre as existentes.

Data/hora atual: ${nowBRT.toLocaleDateString("pt-BR")} ${nowBRT.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })} (BRT)

CLIENTE: ${clientName ? `${clientName} (cadastrado)` : "Não identificado no sistema"}
${clientId ? `HISTÓRICO RECENTE:\n${contextLines.length > 0 ? contextLines.join("\n") : "Nenhuma OS recente."}` : ""}

INSTRUÇÕES POR INTENÇÃO DETECTADA:
1. status_inquiry (perguntas sobre OS, orçamento, status): responda com as informações do histórico acima.
2. new_quote (pedido de novo orçamento/serviço): diga que nossa equipe entrará em contato em breve e que registrou a solicitação.
3. complaint (reclamação, insatisfação): peça desculpas, diga que encaminhará urgentemente à equipe.
4. payment_question (dúvida sobre pagamento, boleto, PIX): redirecione ao time financeiro.
5. general (saudação, dúvida geral, outros): responda cordialmente e ofereça ajuda.
6. escalate (situação urgente, pedido específico fora do escopo): diga que nossa equipe especializada responderá.

Ao final da resposta, na última linha coloque APENAS o código de intenção:
INTENT:status_inquiry | INTENT:new_quote | INTENT:complaint | INTENT:payment_question | INTENT:general | INTENT:escalate`;

    const chatHistory = sessionMessages.map((m) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    }));
    const aiMessages = [
      { role: "system", content: systemPrompt },
      ...chatHistory,
      { role: "user", content: messageText },
    ];

    // ── Call AI ────────────────────────────────────────────────────────────────
    let aiReply = "";
    let detectedIntent = "general";

    try {
      const r = await fetch(`${GEMINI_BASE_URL}/chat/completions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${GEMINI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ model: MODEL, messages: aiMessages }),
      });
      if (r.ok) {
        const data = await r.json();
        const fullReply: string = data.choices?.[0]?.message?.content || "";
        const intentMatch = fullReply.match(/INTENT:(\w+)/);
        if (intentMatch) detectedIntent = intentMatch[1];
        aiReply = fullReply.replace(/\nINTENT:\w+.*$/m, "").trim();
      } else {
        const errBody = await r.text().catch(() => "");
        console.error("[ai-inbound-channel] AI error:", r.status, errBody.slice(0, 200));
        aiReply = `Olá${clientName ? ` ${clientName}` : ""}! Recebemos sua mensagem. Nossa equipe da ${company} entrará em contato em breve.`;
      }
    } catch (e) {
      console.error("[ai-inbound-channel] AI fetch error:", e);
      aiReply = `Olá${clientName ? ` ${clientName}` : ""}! Recebemos sua mensagem e nossa equipe responderá em breve.`;
    }

    // ── Send WhatsApp reply via Z-API directly ─────────────────────────────────
    let replySent = false;
    if (aiReply && zapiInstanceId && zapiToken) {
      try {
        const zapiBase = `https://api.z-api.io/instances/${zapiInstanceId}/token/${zapiToken}`;
        const zapiHeaders: Record<string, string> = { "Content-Type": "application/json" };
        if (zapiClientToken) zapiHeaders["Client-Token"] = zapiClientToken;

        const r = await fetch(`${zapiBase}/send-text`, {
          method: "POST",
          headers: zapiHeaders,
          body: JSON.stringify({ phone: rawPhone, message: aiReply }),
        });
        replySent = r.ok;
        if (!r.ok) {
          const errBody = await r.text().catch(() => "");
          console.error("[ai-inbound-channel] Z-API send failed:", r.status, errBody.slice(0, 200));
        }
      } catch (e) {
        console.error("[ai-inbound-channel] Z-API send error:", e);
      }
    } else if (!zapiInstanceId || !zapiToken) {
      console.warn("[ai-inbound-channel] Z-API not configured, skipping WhatsApp send");
    }

    // ── Create agent task for operator (for actionable intents) ───────────────
    const ESCALATE_INTENTS = new Set(["new_quote", "complaint", "escalate"]);
    if (ESCALATE_INTENTS.has(detectedIntent)) {
      const intentLabel: Record<string, string> = {
        new_quote: "Novo pedido de orçamento via WhatsApp",
        complaint: "Reclamação via WhatsApp",
        escalate: "Situação urgente via WhatsApp",
      };
      const { error: taskErr } = await admin.from("ai_agent_tasks").insert({
        task_type: "follow_up",
        title: `${intentLabel[detectedIntent] || "Inbound WhatsApp"}: ${clientName || rawPhone}`,
        description: `Mensagem recebida: "${messageText.slice(0, 200)}${messageText.length > 200 ? "..." : ""}"`,
        due_at: new Date(now.getTime() + 2 * 3600_000).toISOString(),
        entity_type: clientId ? "client" : null,
        entity_id: clientId || null,
        priority: detectedIntent === "complaint" ? "high" : "normal",
        metadata: { phone: rawPhone, client_name: clientName, intent: detectedIntent, message: messageText },
        created_by_agent: true,
      });
      if (taskErr) console.warn("[ai-inbound-channel] task insert error:", taskErr.message);
    }

    // ── Update session ─────────────────────────────────────────────────────────
    const updatedMessages = [
      ...sessionMessages,
      { role: "user", content: messageText, ts: now.toISOString() },
      { role: "assistant", content: aiReply, ts: now.toISOString() },
    ].slice(-10);

    const { error: sessionErr } = await admin.from("ai_inbound_sessions").upsert(
      {
        phone: rawPhone,
        client_id: clientId,
        messages: updatedMessages,
        last_intent: detectedIntent,
        session_data: { last_message_id: messageId, client_name: clientName },
      },
      { onConflict: "phone" }
    );
    if (sessionErr) console.warn("[ai-inbound-channel] session upsert error:", sessionErr.message);

    // ── Log to ai_agent_memory if linked to client ─────────────────────────────
    if (clientId) {
      const { error: memErr } = await admin.from("ai_agent_memory").insert({
        scope: "client",
        entity_id: clientId,
        entity_name: clientName,
        memory_key: "ultimo_contato_whatsapp",
        memory_value: `Último contato via WhatsApp em ${now.toLocaleDateString("pt-BR")}: "${messageText.slice(0, 100)}". Intenção detectada: ${detectedIntent}.`,
        confidence: "medium",
        source: "ai_inbound_channel",
      });
      if (memErr) console.warn("[ai-inbound-channel] memory insert error:", memErr.message);
    }

    console.log(`[ai-inbound-channel] phone=${rawPhone}, intent=${detectedIntent}, sent=${replySent}, client=${clientId || "unknown"}`);
    return resp({
      ok: true,
      intent: detectedIntent,
      reply_sent: replySent,
      client_identified: !!clientId,
      task_created: ESCALATE_INTENTS.has(detectedIntent),
    });

  } catch (e: any) {
    console.error("[ai-inbound-channel] FATAL:", e?.message || e, e?.stack || "");
    return resp({ error: "internal error", detail: e?.message || String(e) }, 500);
  }
});

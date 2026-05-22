// Edge Function: ai-operator-channel-intake
// MarineFlow AI Operator — adapter de canal (provider-agnostic).
//
// Objetivo: receber eventos brutos de canal (WhatsApp/Z-API hoje;
// Evolution/n8n no futuro) e enfileirá-los em ai_operator_channel_events
// para processamento assíncrono pelo núcleo do operador.
//
// ⚠️ Segurança:
//   * Esta função SOMENTE enfileira. NUNCA responde ao cliente.
//   * O envio de respostas reais continua sendo gated pelo
//     ai-operator-core via pending_actions (aprovação humana).
//   * Não altera o webhook existente whatsapp-webhook — pode ser chamada
//     manualmente, por sincronizadores, ou disparada em uma 2ª fase
//     pelo próprio webhook após ele já ter persistido a mensagem.
//
// Provider-agnostic: aceita um envelope normalizado para que Z-API,
// Evolution API ou n8n possam alimentar o operador sem reescrever lógica.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { validateIntakeAuth } from "./auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-internal-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// FAIL-CLOSED: a função SOMENTE atende requisições se a secret estiver definida
// no ambiente. Sem secret → 503. Token incorreto → 403. Não há fallback aberto.
const INTERNAL_TOKEN = (Deno.env.get("AI_OPERATOR_INTAKE_TOKEN") || "").trim();

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

type IntakeBody = {
  channel: "whatsapp" | "web" | "system";
  provider: "zapi" | "evolution" | "n8n" | "web" | "system";
  external_event_id?: string | null;
  external_thread_key?: string | null; // ex: telefone normalizado
  direction?: "inbound" | "outbound";
  payload: Record<string, unknown>;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    // FAIL-CLOSED. Sem secret no ambiente → 503. Token inválido → 403.
    const authCheck = validateIntakeAuth(INTERNAL_TOKEN, req.headers.get("x-internal-token"));
    if (!authCheck.ok) return jr({ error: authCheck.error }, authCheck.status);

    const body = (await req.json().catch(() => null)) as IntakeBody | null;
    if (!body || !body.channel || !body.provider) return jr({ error: "envelope inválido" }, 400);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Dedupe por (provider, external_event_id)
    if (body.external_event_id) {
      const { data: dup } = await admin
        .from("ai_operator_channel_events")
        .select("id, status")
        .eq("provider", body.provider)
        .eq("external_event_id", body.external_event_id)
        .maybeSingle();
      if (dup) return jr({ ok: true, dedup: true, id: dup.id, status: dup.status });
    }

    const { data: inserted, error } = await admin
      .from("ai_operator_channel_events")
      .insert({
        channel: body.channel,
        provider: body.provider,
        external_event_id: body.external_event_id || null,
        external_thread_key: body.external_thread_key || null,
        direction: body.direction || "inbound",
        payload: body.payload || {},
        status: "queued",
      })
      .select("id, status")
      .single();

    if (error) return jr({ error: "falha ao enfileirar", details: error.message }, 500);

    // Auditoria
    await admin.from("ai_operator_audit").insert({
      actor_kind: "channel",
      event_type: "channel_event_received",
      event_category: "channel",
      payload: {
        channel: body.channel,
        provider: body.provider,
        external_event_id: body.external_event_id,
        thread: body.external_thread_key,
      },
    });

    return jr({ ok: true, id: inserted.id, status: inserted.status });
  } catch (e: any) {
    console.error("[ai-operator-channel-intake] error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

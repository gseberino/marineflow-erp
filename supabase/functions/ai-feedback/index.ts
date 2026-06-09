// Edge Function: ai-feedback
// Called by the frontend when the operator gives thumbs-up/thumbs-down on an AI proposal.
// Stores the feedback in ai_correction_patterns for the agent to learn from.
//
// POST body:
//   feedback_type: "accepted" | "rejected" | "corrected"
//   correction_type?: string  (for rejected/corrected)
//   context: string           (what was proposed)
//   original_value?: string
//   corrected_value?: string
//   lesson_learned?: string
//   client_id?: string
//   entity_type?: string
//   entity_id?: string
//   entity_number?: string
//   scope?: "global" | "client" | "operator"

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) {
    return new Response(JSON.stringify({ error: "Não autenticado" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const sb = createClient(SUPABASE_URL, ANON, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
  if (userErr || !userData?.user?.id) {
    return new Response(JSON.stringify({ error: "Não autenticado" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const userId = userData.user.id;

  const body = await req.json().catch(() => ({}));
  const {
    feedback_type,
    correction_type,
    context,
    original_value,
    corrected_value,
    lesson_learned,
    client_id,
    entity_type,
    entity_id,
    entity_number,
    scope,
  } = body;

  if (!context) {
    return new Response(JSON.stringify({ error: "context é obrigatório" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Only store for rejected/corrected feedback — accepted is implicit positive
  if (feedback_type === "accepted") {
    return new Response(JSON.stringify({ ok: true, stored: false, reason: "Feedback positivo registrado mas não armazenado como padrão de correção." }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const effectiveCorrectionType = correction_type || (feedback_type === "rejected" ? "other" : "other");
  const effectiveLesson = lesson_learned || (
    corrected_value
      ? `Proposta "${original_value || context}" foi corrigida para "${corrected_value}".`
      : `Proposta "${context}" foi rejeitada pelo operador.`
  );

  const { data, error } = await sb
    .from("ai_correction_patterns")
    .insert({
      correction_type: effectiveCorrectionType,
      context: String(context).slice(0, 500),
      original_value: original_value ? String(original_value).slice(0, 500) : null,
      corrected_value: corrected_value ? String(corrected_value).slice(0, 500) : null,
      lesson_learned: effectiveLesson.slice(0, 1000),
      client_id: client_id || null,
      operator_user_id: userId,
      scope: scope || (client_id ? "client" : "global"),
      entity_type: entity_type || null,
      entity_id: entity_id || null,
      entity_number: entity_number || null,
      metadata: { feedback_type, source: "frontend" },
    })
    .select()
    .single();

  if (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ ok: true, id: data.id }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

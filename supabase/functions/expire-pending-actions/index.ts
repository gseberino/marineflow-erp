// Edge Function: expire-pending-actions
// Marca como 'expired' as pendências (ai_operator_pending_actions) que passaram do
// prazo (expires_at) sem decisão. Idempotente por natureza: só afeta linhas ainda
// status='pending', então rodar de novo no mesmo dia não tem efeito colateral — não
// precisa de log de dedupe como os outros lembretes da Fase 5.
//
// Agendamento (pg_cron) fica pra Fase 5, junto com os outros crons — esta function já
// fica pronta e pode ser invocada manualmente com o header x-cron-secret enquanto isso.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret) {
    const incoming = req.headers.get("x-cron-secret");
    if (incoming !== cronSecret) return jr({ error: "Unauthorized" }, 401);
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    const { data, error } = await admin
      .from("ai_operator_pending_actions")
      .update({ status: "expired" })
      .eq("status", "pending")
      .lt("expires_at", new Date().toISOString())
      .select("id");

    if (error) throw error;

    return jr({ ok: true, expired_count: data?.length ?? 0 });
  } catch (e: any) {
    console.error("expire-pending-actions error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

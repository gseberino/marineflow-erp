// Edge Function: expire-pending-actions
// Marca como 'expired' as pendências (ai_operator_pending_actions) que passaram do
// prazo (expires_at) sem decisão. Idempotente por natureza: só afeta linhas ainda
// status='pending', então rodar de novo no mesmo dia não tem efeito colateral — não
// precisa de log de dedupe como os outros lembretes da Fase 5.
//
// Agendamento (pg_cron) fica pra Fase 5, junto com os outros crons — esta function já
// fica pronta e pode ser invocada manualmente com o header x-cron-secret enquanto isso.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { conversaOndeOModeloLe, textoDoVencimento, vencidasPorConversa } from "../_shared/ai/vencimento.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Era fail-OPEN (`if (cronSecret) { ... }`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "expire-pending-actions");
  if (recusa) return recusa;

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    const { data, error } = await admin
      .from("ai_operator_pending_actions")
      .update({ status: "expired" })
      .eq("status", "pending")
      .lt("expires_at", new Date().toISOString())
      .select("id, session_id, title, created_at");

    if (error) throw error;

    // Aprovação em lote (29/10/2026): uma linha na conversa de cada pendência vencida — o modelo lê na próxima vez, e o
    // dono não ouve mais "ainda espera o seu sim" sobre o que já venceu. Só registra (source 'system'): o aviso no
    // WhatsApp é da Fase 5. No WhatsApp, a conversa que o modelo lê agora (conversaOndeOModeloLe). Uma linha por
    // conversa; falha numa não impede as outras.
    const destino = new Map<string, string>();
    for (const sid of new Set((data ?? []).map((v) => v.session_id).filter((s): s is string => typeof s === "string" && !!s))) {
      destino.set(sid, await conversaOndeOModeloLe(admin, sid));
    }
    const ondeLer = (data ?? []).map((v) => ({ ...v, session_id: v.session_id ? destino.get(v.session_id) ?? v.session_id : null }));
    let avisos = 0;
    for (const [sessionId, itens] of vencidasPorConversa(ondeLer)) {
      const content = textoDoVencimento(itens);
      if (!content) continue;
      try {
        const { error: erroDaLinha } = await admin
          .from("ai_operator_messages")
          .insert({ session_id: sessionId, role: "assistant", content, source: "system" });
        if (erroDaLinha) console.error("expire-pending-actions: linha na conversa não gravada", sessionId, erroDaLinha.message);
        else avisos++;
      } catch (e: any) {
        console.error("expire-pending-actions: linha na conversa não gravada", sessionId, e?.message || e);
      }
    }

    return jr({ ok: true, expired_count: data?.length ?? 0, avisos_na_conversa: avisos });
  } catch (e: any) {
    console.error("expire-pending-actions error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

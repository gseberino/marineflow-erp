// Edge Function: evolution-configure-webhook
//
// Utilitário administrativo: aponta o webhook da instância Evolution para o
// `whatsapp-webhook` deste projeto (POST) ou confere para onde ele aponta hoje
// (GET ou ?action=test). Só admin/manager ativo passa.
//
// Histórico: publicada em 06/2026 no cutover Z-API → Evolution e nunca versionada
// (viveu só em produção por 3 meses). Trazida para o repositório em 15/09/2026, sem
// mudar comportamento, para o repo voltar a descrever o que está no ar. O runbook de
// recuperação do WhatsApp continua valendo (ele fala direto com a Evolution via
// PowerShell); esta função é o mesmo gesto pela API do ERP, com auth.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const EVENTOS = ["MESSAGES_UPSERT", "MESSAGES_UPDATE", "MESSAGES_DELETE", "SEND_MESSAGE", "CONNECTION_UPDATE"];

servirComCors(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Não autenticado" }, 401);
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return jr({ error: "Não autenticado" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: appUser } = await admin
      .from("app_users").select("role, active").eq("id", user.id).maybeSingle();
    if (!appUser?.active || !["admin", "manager"].includes(String(appUser.role))) {
      return jr({ error: "Permissão negada" }, 403);
    }

    const EVOLUTION_API_URL = (Deno.env.get("EVOLUTION_API_URL") ?? "").replace(/\/$/, "");
    const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
    const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";
    if (!EVOLUTION_API_URL || !EVOLUTION_API_KEY || !EVOLUTION_INSTANCE) {
      return jr({
        error: "Credenciais Evolution não configuradas.",
        hint: "Configure via: supabase secrets set EVOLUTION_API_URL=... EVOLUTION_API_KEY=... EVOLUTION_INSTANCE=...",
        missing: {
          EVOLUTION_API_URL: !EVOLUTION_API_URL,
          EVOLUTION_API_KEY: !EVOLUTION_API_KEY,
          EVOLUTION_INSTANCE: !EVOLUTION_INSTANCE,
        },
      }, 400);
    }

    const evoHeaders = { "Content-Type": "application/json", "apikey": EVOLUTION_API_KEY };
    const webhookUrl = `${SUPABASE_URL}/functions/v1/whatsapp-webhook`;
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || (req.method === "GET" ? "test" : "configure");

    if (action === "test") {
      const res = await fetch(`${EVOLUTION_API_URL}/webhook/find/${EVOLUTION_INSTANCE}`, {
        method: "GET", headers: evoHeaders,
      });
      const body = await res.json().catch(() => ({})) as { url?: string };
      const atual = String(body?.url ?? "");
      const configured = atual === webhookUrl || atual.includes("/whatsapp-webhook");
      return jr({
        ok: true,
        configured,
        current_webhook_url: body?.url ?? null,
        target_webhook_url: webhookUrl,
        instance: EVOLUTION_INSTANCE,
        api_url: EVOLUTION_API_URL,
        raw_response: body,
        message: configured
          ? "✅ Webhook Evolution já está apontando para o sistema."
          : "⚠️ Webhook não está configurado. Faça POST para configurar.",
      });
    }

    const res = await fetch(`${EVOLUTION_API_URL}/webhook/set/${EVOLUTION_INSTANCE}`, {
      method: "POST",
      headers: evoHeaders,
      body: JSON.stringify({
        url: webhookUrl, webhook_by_events: false, webhook_base64: false, events: EVENTOS,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      return jr({ ok: false, error: `Evolution API retornou HTTP ${res.status}`, raw_response: body }, 502);
    }
    return jr({
      ok: true,
      webhook_url: webhookUrl,
      instance: EVOLUTION_INSTANCE,
      api_url: EVOLUTION_API_URL,
      response: body,
      message: "✅ Webhook Evolution configurado. Teste enviando uma mensagem WhatsApp.",
    });
  } catch (err) {
    console.error("evolution-configure-webhook error", err);
    return jr({ error: (err as Error)?.message || "internal error" }, 500);
  }
});

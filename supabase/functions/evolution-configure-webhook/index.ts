// Edge Function: evolution-configure-webhook
// Configura o webhook da instância Evolution API apontando para o sistema.
// Utilitário administrativo — equivalente ao zapi-configure-webhook para Evolution.
//
// POST  → configura o webhook via POST /webhook/set/{instance}
// GET?action=test → consulta a configuração atual via GET /webhook/find/{instance}
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Require authenticated admin/manager
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Não autenticado" }, 401);

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return jr({ error: "Não autenticado" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: appUser } = await admin
      .from("app_users")
      .select("role, active")
      .eq("id", user.id)
      .maybeSingle();
    if (!appUser?.active || !["admin", "manager"].includes(String(appUser.role))) {
      return jr({ error: "Permissão negada" }, 403);
    }

    // Read Evolution credentials from env (set via supabase secrets set)
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

    const evoHeaders = {
      "Content-Type": "application/json",
      "apikey": EVOLUTION_API_KEY,
    };

    const webhookUrl = `${SUPABASE_URL}/functions/v1/whatsapp-webhook`;
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || (req.method === "GET" ? "test" : "configure");

    // ---- Test: GET /webhook/find/{instance} ----
    if (action === "test") {
      const res = await fetch(
        `${EVOLUTION_API_URL}/webhook/find/${EVOLUTION_INSTANCE}`,
        { method: "GET", headers: evoHeaders },
      );
      const body = await res.json().catch(() => ({}));
      const configured = (body as any)?.url === webhookUrl ||
        String((body as any)?.url ?? "").includes("/whatsapp-webhook");
      return jr({
        ok: true,
        configured,
        current_webhook_url: (body as any)?.url ?? null,
        target_webhook_url: webhookUrl,
        instance: EVOLUTION_INSTANCE,
        api_url: EVOLUTION_API_URL,
        raw_response: body,
        message: configured
          ? "✅ Webhook Evolution já está apontando para o sistema."
          : "⚠️ Webhook não está configurado. Faça POST para configurar.",
      });
    }

    // ---- Configure: POST /webhook/set/{instance} ----
    const res = await fetch(
      `${EVOLUTION_API_URL}/webhook/set/${EVOLUTION_INSTANCE}`,
      {
        method: "POST",
        headers: evoHeaders,
        body: JSON.stringify({
          url: webhookUrl,
          webhook_by_events: false,
          webhook_base64: false,
          events: [
            "MESSAGES_UPSERT",
            "MESSAGES_UPDATE",
            "MESSAGES_DELETE",
            "SEND_MESSAGE",
            "CONNECTION_UPDATE",
          ],
        }),
      },
    );
    const body = await res.json().catch(() => ({}));

    if (!res.ok) {
      return jr({
        ok: false,
        error: `Evolution API retornou HTTP ${res.status}`,
        raw_response: body,
      }, 502);
    }

    return jr({
      ok: true,
      webhook_url: webhookUrl,
      instance: EVOLUTION_INSTANCE,
      api_url: EVOLUTION_API_URL,
      response: body,
      message: "✅ Webhook Evolution configurado. Teste enviando uma mensagem WhatsApp.",
    });

  } catch (err: any) {
    console.error("evolution-configure-webhook error", err);
    return jr({ error: err?.message || "internal error" }, 500);
  }
});

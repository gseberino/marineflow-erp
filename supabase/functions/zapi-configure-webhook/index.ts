// Edge Function: zapi-configure-webhook
// Configura automaticamente o webhook "On Message Received" na Z-API
// apontando para nossa função whatsapp-webhook.
// Também permite consultar o status atual e configurar os outros webhooks
// (status de entrega, mensagem enviada por mim, presença).
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
    const INSTANCE_ID = Deno.env.get("ZAPI_INSTANCE_ID");
    const TOKEN = Deno.env.get("ZAPI_TOKEN");
    const CLIENT_TOKEN = Deno.env.get("ZAPI_CLIENT_TOKEN");

    if (!INSTANCE_ID || !TOKEN) {
      return jr({ error: "ZAPI_INSTANCE_ID ou ZAPI_TOKEN não configurados" }, 400);
    }

    // Validar usuário autenticado (admin)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Não autenticado" }, 401);

    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return jr({ error: "Não autenticado" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: appUser } = await admin.from("app_users").select("role, active").eq("id", user.id).maybeSingle();
    if (!appUser?.active || !["admin", "manager"].includes(String(appUser.role))) {
      return jr({ error: "Permissão negada" }, 403);
    }

    const webhookUrl = `${SUPABASE_URL}/functions/v1/whatsapp-webhook?apikey=${Deno.env.get("SUPABASE_ANON_KEY")}`;
    const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (CLIENT_TOKEN) headers["Client-Token"] = CLIENT_TOKEN;

    // Endpoints da Z-API para cada tipo de webhook
    const endpoints = {
      received: "update-webhook-received",         // Mensagem recebida
      delivery: "update-webhook-delivery",         // Status de entrega
      messageStatus: "update-webhook-message-status", // Status alternativo
      received_by_me: "update-webhook-receive-by-me", // Mensagens que ENVIO via celular
      disconnected: "update-webhook-disconnected", // Desconexão
    };

    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "configure_all";

    // ---- Status: consulta os webhooks atuais configurados na Z-API ----
    if (action === "status") {
      const statusRes = await fetch(`${base}/webhooks`, { method: "GET", headers });
      const statusData = await statusRes.json().catch(() => null);
      return jr({
        ok: statusRes.ok,
        target_webhook_url: webhookUrl,
        zapi_response: statusData,
        zapi_status_code: statusRes.status,
      });
    }

    // ---- Test each: consulta o valor atual de CADA endpoint individualmente ----
    if (action === "test_each") {
      const startedAt = Date.now();
      const tests: Record<string, any> = {};
      
      try {
        // Z-API centralized webhooks status
        const res = await fetch(`${base}/webhooks`, { method: "GET", headers });
        const webhooks = await res.json().catch(() => ({}));
        
        // Mapping Z-API response keys to our internal names
        // Note: keys vary by Z-API version, we try common ones.
        const zapiMapping: Record<string, string[]> = {
          received: ["onMessageReceived", "value", "received"],
          delivery: ["onMessageDelivery", "delivery"],
          messageStatus: ["onMessageStatus", "messageStatus"],
          received_by_me: ["onMessageReceivedByMe", "receivedByMe"],
          disconnected: ["onDisconnected", "disconnected"],
        };

        for (const [name, endpoint] of Object.entries(endpoints)) {
          const possibleKeys = zapiMapping[name] || [];
          let currentValue = null;
          
          for (const k of possibleKeys) {
            if (webhooks[k]) {
              currentValue = webhooks[k];
              break;
            }
          }

          tests[name] = {
            endpoint,
            url: `${base}/${endpoint}`,
            method: "GET (via /webhooks)",
            http_status: res.status,
            ok: res.ok,
            current_value: currentValue,
            matches_target: currentValue ? String(currentValue).startsWith(webhookUrl) : false,
            response: webhooks,
            duration_ms: Date.now() - startedAt,
          };
        }
      } catch (e: any) {
        return jr({ error: "Falha ao consultar lista de webhooks: " + e.message }, 500);
      }

      const allMatch = Object.values(tests).every((t: any) => t.matches_target);
      return jr({
        ok: true,
        all_match_target: allMatch,
        target_webhook_url: webhookUrl,
        tests,
      });
    }

    // ---- Configura todos os webhooks relevantes ----
    // Z-API atualmente aceita POST nesses endpoints. Algumas instâncias antigas só aceitam PUT,
    // por isso aplicamos fallback automático em caso de 405.
    const results: Record<string, any> = {};
    for (const [name, endpoint] of Object.entries(endpoints)) {
      try {
        let res = await fetch(`${base}/${endpoint}`, {
          method: "POST",
          headers,
          body: JSON.stringify({ value: webhookUrl }),
        });
        let methodUsed = "POST";
        if (res.status === 405) {
          res = await fetch(`${base}/${endpoint}`, {
            method: "PUT",
            headers,
            body: JSON.stringify({ value: webhookUrl }),
          });
          methodUsed = "PUT";
        }
        const data = await res.json().catch(() => ({}));
        results[name] = {
          status: res.status,
          ok: res.ok,
          method_used: methodUsed,
          response: data,
        };
      } catch (e: any) {
        results[name] = { ok: false, error: e?.message || String(e) };
      }
    }

    const allOk = Object.values(results).every((r: any) => r.ok);
    return jr({
      ok: allOk,
      webhook_url: webhookUrl,
      configured: results,
      message: allOk
        ? "Todos os webhooks da Z-API foram apontados para o sistema."
        : "Alguns webhooks falharam. Verifique os detalhes em 'configured'.",
    });
  } catch (err: any) {
    console.error("zapi-configure-webhook error", err);
    return jr({ error: err?.message || "internal error" }, 500);
  }
});

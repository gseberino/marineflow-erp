// Edge Function: zapi-configure-webhook
// Configura automaticamente os webhooks na Z-API.
// Lê credenciais do app_settings (DB) com fallback para variáveis de ambiente.
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

    // Validar usuário autenticado
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Não autenticado" }, 401);

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return jr({ error: "Não autenticado" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: appUser } = await admin.from("app_users").select("role, active").eq("id", user.id).maybeSingle();
    if (!appUser?.active || !["admin", "manager"].includes(String(appUser.role))) {
      return jr({ error: "Permissão negada" }, 403);
    }

    // ---- Carregar credenciais do banco (app_settings) com fallback para env ----
    const { data: settings } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["zapi_instance_id", "zapi_token", "zapi_client_token"]);

    const settingsMap: Record<string, string> = {};
    for (const s of settings || []) {
      settingsMap[s.key] = String(s.value || "");
    }

    const INSTANCE_ID = settingsMap["zapi_instance_id"] || Deno.env.get("ZAPI_INSTANCE_ID") || "";
    const TOKEN = settingsMap["zapi_token"] || Deno.env.get("ZAPI_TOKEN") || "";
    const CLIENT_TOKEN = settingsMap["zapi_client_token"] || Deno.env.get("ZAPI_CLIENT_TOKEN") || "";

    if (!INSTANCE_ID || !TOKEN) {
      return jr({
        error: "Credenciais Z-API não configuradas.",
        hint: "Vá em Configurações → WhatsApp → Credenciais Z-API e salve o Instance ID e Token.",
        from_db: { instance_id: !!settingsMap["zapi_instance_id"], token: !!settingsMap["zapi_token"] },
        from_env: { instance_id: !!Deno.env.get("ZAPI_INSTANCE_ID"), token: !!Deno.env.get("ZAPI_TOKEN") },
      }, 400);
    }

    const webhookUrl = `${SUPABASE_URL}/functions/v1/whatsapp-webhook?apikey=${ANON_KEY}`;
    const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;
    const zapiHeaders: Record<string, string> = { "Content-Type": "application/json" };
    if (CLIENT_TOKEN) zapiHeaders["Client-Token"] = CLIENT_TOKEN;

    // Endpoints da Z-API
    const endpoints: Record<string, string> = {
      received: "update-webhook-received",
      delivery: "update-webhook-delivery",
      messageStatus: "update-webhook-message-status",
      received_by_me: "update-webhook-receive-by-me",
      disconnected: "update-webhook-disconnected",
    };

    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "configure_all";

    // ---- Test each: consulta o estado atual via GET /webhooks ----
    if (action === "test_each") {
      const startedAt = Date.now();

      const res = await fetch(`${base}/webhooks`, { method: "GET", headers: zapiHeaders });
      const rawWebhooks = await res.json().catch(() => ({}));

      console.log("Z-API /webhooks raw response:", JSON.stringify(rawWebhooks));

      // Z-API retorna um objeto; tentamos mapear todos os campos possíveis
      const tests: Record<string, any> = {};
      for (const [name, endpoint] of Object.entries(endpoints)) {
        // Busca o valor em qualquer chave do objeto que contenha "http"
        let currentValue: string | null = null;

        // Tentativa por chaves conhecidas
        const knownKeys = [
          "onMessageReceived", "deliveryWebhook", "onMessageStatus",
          "onMessageReceivedByMe", "onDisconnect",
          "received", "delivery", "messageStatus", "receivedByMe", "disconnected",
          "value", "url", "webhook",
        ];

        // Também tenta buscar por string parcial do endpoint
        const endpointPart = endpoint.replace("update-webhook-", "");

        for (const [k, v] of Object.entries(rawWebhooks)) {
          if (typeof v === "string" && v.startsWith("http")) {
            const keyLower = k.toLowerCase();
            if (
              knownKeys.includes(k) ||
              keyLower.includes(endpointPart.replace("-", "")) ||
              keyLower.includes("webhook")
            ) {
              currentValue = v;
              break;
            }
          }
        }

        tests[name] = {
          endpoint,
          http_status: res.status,
          ok: res.ok,
          current_value: currentValue,
          matches_target: currentValue
            ? currentValue.includes("/whatsapp-webhook")
            : false,
          raw_zapi_response: rawWebhooks,
          duration_ms: Date.now() - startedAt,
        };
      }

      const allMatch = Object.values(tests).every((t: any) => t.matches_target);
      return jr({
        ok: true,
        all_match_target: allMatch,
        target_webhook_url: webhookUrl,
        instance_id: INSTANCE_ID,
        credential_source: settingsMap["zapi_instance_id"] ? "database" : "environment",
        tests,
        raw_zapi_webhooks: rawWebhooks,
      });
    }

    // ---- Configura todos os webhooks (configure_all) ----
    const results: Record<string, any> = {};
    for (const [name, endpoint] of Object.entries(endpoints)) {
      try {
        // Tenta POST primeiro, fallback para PATCH e depois PUT
        let res = await fetch(`${base}/${endpoint}`, {
          method: "POST",
          headers: zapiHeaders,
          body: JSON.stringify({ value: webhookUrl }),
        });
        let methodUsed = "POST";

        if (res.status === 405) {
          res = await fetch(`${base}/${endpoint}`, {
            method: "PATCH",
            headers: zapiHeaders,
            body: JSON.stringify({ value: webhookUrl }),
          });
          methodUsed = "PATCH";
        }
        if (res.status === 405) {
          res = await fetch(`${base}/${endpoint}`, {
            method: "PUT",
            headers: zapiHeaders,
            body: JSON.stringify({ value: webhookUrl }),
          });
          methodUsed = "PUT";
        }

        const responseText = await res.text();
        let responseData: any;
        try { responseData = JSON.parse(responseText); } catch { responseData = responseText; }

        results[name] = {
          status: res.status,
          ok: res.ok,
          method_used: methodUsed,
          response: responseData,
        };
      } catch (e: any) {
        results[name] = { ok: false, error: e?.message || String(e) };
      }
    }

    const allOk = Object.values(results).every((r: any) => r.ok);
    return jr({
      ok: allOk,
      webhook_url: webhookUrl,
      instance_id: INSTANCE_ID,
      credential_source: settingsMap["zapi_instance_id"] ? "database" : "environment",
      configured: results,
      message: allOk
        ? "Todos os webhooks da Z-API foram apontados para o sistema."
        : "Alguns webhooks falharam. Veja detalhes em 'configured'.",
    });

  } catch (err: any) {
    console.error("zapi-configure-webhook error", err);
    return jr({ error: err?.message || "internal error" }, 500);
  }
});

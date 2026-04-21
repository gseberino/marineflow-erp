// Edge Function: whatsapp-send
// Envia mensagens via Z-API (https://z-api.io)
// Suporta texto simples e (futuramente) outros tipos de mensagem.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { z } from "https://esm.sh/zod@3.23.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const BodySchema = z.object({
  phone: z.string().min(8).max(20), // E.164 sem '+', ex: 5521999998888
  message: z.string().min(1).max(4096),
  service_order_id: z.string().uuid().optional(),
  context: z.string().max(64).optional(), // ex: 'service_order', 'quote', 'billing'
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const INSTANCE_ID = Deno.env.get("ZAPI_INSTANCE_ID");
    const TOKEN = Deno.env.get("ZAPI_TOKEN");
    const CLIENT_TOKEN = Deno.env.get("ZAPI_CLIENT_TOKEN");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!INSTANCE_ID || !TOKEN) {
      return new Response(
        JSON.stringify({ error: "Z-API credentials not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Auth: exige usuário logado
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseAuth = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await supabaseAuth.auth.getUser();
    if (userErr || !userData.user) {
      return new Response(JSON.stringify({ error: "Invalid session" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const json = await req.json().catch(() => null);
    const parsed = BodySchema.safeParse(json);
    if (!parsed.success) {
      return new Response(
        JSON.stringify({ error: parsed.error.flatten().fieldErrors }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const { phone, message, service_order_id, context } = parsed.data;

    // Normaliza: somente dígitos
    const phoneClean = phone.replace(/\D/g, "");
    if (phoneClean.length < 10) {
      return new Response(
        JSON.stringify({ error: "Telefone inválido (precisa incluir DDI+DDD)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Chama Z-API send-text
    const zapiUrl = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}/send-text`;
    const zapiHeaders: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (CLIENT_TOKEN) zapiHeaders["Client-Token"] = CLIENT_TOKEN;

    const zapiRes = await fetch(zapiUrl, {
      method: "POST",
      headers: zapiHeaders,
      body: JSON.stringify({ phone: phoneClean, message }),
    });

    const zapiBody = await zapiRes.json().catch(() => ({}));
    const success = zapiRes.ok && !zapiBody.error;

    // Log de auditoria (best-effort)
    const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE);
    await supabaseAdmin.from("audit_log").insert({
      table_name: "service_orders",
      record_id: service_order_id || "00000000-0000-0000-0000-000000000000",
      action: "whatsapp_send_api",
      changed_by: userData.user.email || userData.user.id,
      new_value: {
        provider: "z-api",
        context: context || null,
        phone: phoneClean,
        message_preview: message.slice(0, 200),
        zapi_response: zapiBody,
        http_status: zapiRes.status,
      },
      reason: success
        ? "Mensagem enviada via Z-API"
        : `Falha no envio Z-API: ${zapiBody.error || zapiRes.status}`,
    });

    if (!success) {
      return new Response(
        JSON.stringify({
          error: zapiBody.error || `Z-API HTTP ${zapiRes.status}`,
          details: zapiBody,
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        messageId: zapiBody.messageId || zapiBody.id || null,
        zapi: zapiBody,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("whatsapp-send error", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

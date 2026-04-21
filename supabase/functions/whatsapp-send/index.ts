// Edge Function: whatsapp-send
// Envia mensagens via Z-API (https://z-api.io)
// Suporta:
//   kind=text     → /send-text                 { phone, message }
//   kind=link     → /send-link                 { phone, message, image, linkUrl, title, linkDescription }
//   kind=document → /send-document/pdf         { phone, document(URL), fileName, caption? }
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { z } from "https://esm.sh/zod@3.23.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const BodySchema = z.object({
  phone: z.string().min(8).max(20),
  kind: z.enum(["text", "link", "document"]).default("text"),
  message: z.string().max(4096).optional(),
  // link
  link_url: z.string().url().optional(),
  link_title: z.string().max(200).optional(),
  link_description: z.string().max(500).optional(),
  link_image: z.string().url().optional(),
  // document
  document_url: z.string().url().optional(),
  document_filename: z.string().max(120).optional(),
  document_caption: z.string().max(1024).optional(),
  // contexto / log
  service_order_id: z.string().uuid().optional(),
  receivable_id: z.string().uuid().optional(),
  context: z.string().max(64).optional(),
});

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const INSTANCE_ID = Deno.env.get("ZAPI_INSTANCE_ID");
    const TOKEN = Deno.env.get("ZAPI_TOKEN");
    const CLIENT_TOKEN = Deno.env.get("ZAPI_CLIENT_TOKEN");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!INSTANCE_ID || !TOKEN) {
      return jr({ error: "Z-API credentials not configured" }, 500);
    }

    // Auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Unauthorized" }, 401);
    const supabaseAuth = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await supabaseAuth.auth.getUser();
    if (userErr || !userData.user) return jr({ error: "Invalid session" }, 401);

    const json = await req.json().catch(() => null);
    const parsed = BodySchema.safeParse(json);
    if (!parsed.success) return jr({ error: parsed.error.flatten().fieldErrors }, 400);
    const body = parsed.data;

    const phoneClean = body.phone.replace(/\D/g, "");
    if (phoneClean.length < 10) {
      return jr({ error: "Telefone inválido (precisa incluir DDI+DDD)" }, 400);
    }

    // Monta endpoint + payload por tipo
    const base = `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}`;
    let zapiUrl = "";
    let zapiPayload: Record<string, unknown> = {};
    let messagePreview = "";

    if (body.kind === "text") {
      if (!body.message) return jr({ error: "message é obrigatório para kind=text" }, 400);
      zapiUrl = `${base}/send-text`;
      zapiPayload = { phone: phoneClean, message: body.message };
      messagePreview = body.message.slice(0, 200);
    } else if (body.kind === "link") {
      if (!body.link_url || !body.message) {
        return jr({ error: "link_url e message são obrigatórios para kind=link" }, 400);
      }
      zapiUrl = `${base}/send-link`;
      zapiPayload = {
        phone: phoneClean,
        message: body.message,
        image: body.link_image || "",
        linkUrl: body.link_url,
        title: body.link_title || "",
        linkDescription: body.link_description || "",
      };
      messagePreview = `[link] ${body.link_url} — ${body.message.slice(0, 160)}`;
    } else if (body.kind === "document") {
      if (!body.document_url) return jr({ error: "document_url é obrigatório para kind=document" }, 400);
      zapiUrl = `${base}/send-document/pdf`;
      zapiPayload = {
        phone: phoneClean,
        document: body.document_url,
        fileName: body.document_filename || "documento.pdf",
        caption: body.document_caption || body.message || "",
      };
      messagePreview = `[pdf] ${body.document_filename || "documento.pdf"}`;
    }

    const zapiHeaders: Record<string, string> = { "Content-Type": "application/json" };
    if (CLIENT_TOKEN) zapiHeaders["Client-Token"] = CLIENT_TOKEN;

    const zapiRes = await fetch(zapiUrl, {
      method: "POST",
      headers: zapiHeaders,
      body: JSON.stringify(zapiPayload),
    });
    const zapiBody = await zapiRes.json().catch(() => ({}));
    const success = zapiRes.ok && !(zapiBody as any).error;

    // Log de auditoria
    const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const auditTable = body.receivable_id ? "receivables" : "service_orders";
    const auditId = body.receivable_id || body.service_order_id || "00000000-0000-0000-0000-000000000000";

    await supabaseAdmin.from("audit_log").insert({
      table_name: auditTable,
      record_id: auditId,
      action: "whatsapp_send_api",
      changed_by: userData.user.email || userData.user.id,
      new_value: {
        provider: "z-api",
        kind: body.kind,
        context: body.context || null,
        phone: phoneClean,
        message_preview: messagePreview,
        link_url: body.link_url || null,
        document_url: body.document_url || null,
        document_filename: body.document_filename || null,
        zapi_response: zapiBody,
        http_status: zapiRes.status,
      },
      reason: success
        ? `Envio Z-API (${body.kind}) realizado com sucesso`
        : `Falha no envio Z-API (${body.kind}): ${(zapiBody as any).error || zapiRes.status}`,
    });

    if (!success) {
      return jr(
        { error: (zapiBody as any).error || `Z-API HTTP ${zapiRes.status}`, details: zapiBody },
        502,
      );
    }

    return jr({
      success: true,
      kind: body.kind,
      messageId: (zapiBody as any).messageId || (zapiBody as any).id || null,
      zapi: zapiBody,
    });
  } catch (err) {
    console.error("whatsapp-send error", err);
    return jr({ error: err instanceof Error ? err.message : "Unknown error" }, 500);
  }
});

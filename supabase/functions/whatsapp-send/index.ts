// Edge Function: whatsapp-send
// Envia mensagens via WhatsApp (provider configurado por WHATSAPP_PROVIDER).
// Suporta:
//   kind=text     → sendText
//   kind=link     → sendLink
//   kind=document → sendDocument
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { z } from "https://esm.sh/zod@3.23.8";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import { normalizePhoneNumber } from "../_shared/whatsapp/normalize.ts";

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
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Unauthorized" }, 401);
    const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE);

    const token = authHeader.replace(/^Bearer\s+/i, "");
    const isServiceRoleCall = token === SERVICE_ROLE;
    let callerIdentity = "system";

    if (!isServiceRoleCall) {
      const supabaseAuth = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: userData, error: userErr } = await supabaseAuth.auth.getUser();
      if (userErr || !userData.user) return jr({ error: "Invalid session" }, 401);
      callerIdentity = userData.user.email || userData.user.id;
    }

    // Load app settings for test mode
    const { data: settings } = await supabaseAdmin.from("app_settings").select("key, value");
    const settingsMap = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));

    if (!Deno.env.get("EVOLUTION_API_URL") || !Deno.env.get("EVOLUTION_API_KEY") || !Deno.env.get("EVOLUTION_INSTANCE")) {
      return jr({ error: "Evolution API credentials not configured (EVOLUTION_API_URL, EVOLUTION_API_KEY, EVOLUTION_INSTANCE)." }, 500);
    }

    const json = await req.json().catch(() => null);
    const parsed = BodySchema.safeParse(json);
    if (!parsed.success) return jr({ error: parsed.error.flatten().fieldErrors }, 400);
    const body = parsed.data;

    const testMode = settingsMap["zapi_test_mode"] === "true";
    const testNumber = settingsMap["zapi_test_number"]?.replace(/\D/g, "");

    let phoneClean = normalizePhoneNumber(body.phone);

    if (testMode && testNumber) {
      console.log(`WhatsApp: Test Mode Active. Redirecting from ${phoneClean} to ${testNumber}`);
      phoneClean = testNumber;
    }

    if (phoneClean.length < 10) {
      return jr({ error: "Telefone inválido (precisa incluir DDI+DDD)" }, 400);
    }

    const provider = createWhatsAppProvider();

    let sendResult;
    let messagePreview = "";

    if (body.kind === "text") {
      if (!body.message) return jr({ error: "message é obrigatório para kind=text" }, 400);
      sendResult = await provider.sendText(phoneClean, body.message);
      messagePreview = body.message.slice(0, 200);
    } else if (body.kind === "link") {
      if (!body.link_url || !body.message) {
        return jr({ error: "link_url e message são obrigatórios para kind=link" }, 400);
      }
      sendResult = await provider.sendLink(
        phoneClean,
        body.message,
        body.link_url,
        body.link_title,
        body.link_description,
        body.link_image && body.link_image.trim() !== "" ? body.link_image : undefined,
      );
      messagePreview = `[link] ${body.link_url} — ${body.message.slice(0, 160)}`;
    } else {
      // kind === "document"
      if (!body.document_url) return jr({ error: "document_url é obrigatório para kind=document" }, 400);
      sendResult = await provider.sendDocument(
        phoneClean,
        body.document_url,
        body.document_filename || "documento.pdf",
        body.document_caption || body.message,
      );
      messagePreview = `[pdf] ${body.document_filename || "documento.pdf"}`;
    }

    const success = sendResult.ok;

    // Audit log — structure preserved from original; provider field updated.
    const auditTable = body.receivable_id ? "receivables" : "service_orders";
    const auditId = body.receivable_id || body.service_order_id || "00000000-0000-0000-0000-000000000000";

    await supabaseAdmin.from("audit_log").insert({
      table_name: auditTable,
      record_id: auditId,
      action: "whatsapp_send_api",
      changed_by: callerIdentity,
      new_value: {
        provider: Deno.env.get("WHATSAPP_PROVIDER") ?? "evolution",
        kind: body.kind,
        context: body.context || null,
        phone: phoneClean,
        message_preview: messagePreview,
        link_url: body.link_url || null,
        document_url: body.document_url || null,
        document_filename: body.document_filename || null,
        provider_result: sendResult,
      },
      reason: success
        ? `Envio WhatsApp (${body.kind}) realizado com sucesso${testMode ? " [TEST MODE ACTIVE]" : ""}`
        : `Falha no envio WhatsApp (${body.kind}): ${!sendResult.ok ? sendResult.error : ""}`,
    });

    if (!success) {
      return jr(
        { error: !sendResult.ok ? sendResult.error : "send failed" },
        502,
      );
    }

    return jr({
      success: true,
      kind: body.kind,
      messageId: sendResult.providerMessageId || null,
    });
  } catch (err) {
    console.error("whatsapp-send error", err);
    return jr({ error: err instanceof Error ? err.message : "Unknown error" }, 500);
  }
});

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
import { concluirEnvio, liberarEnvio, reservarEnvio } from "../_shared/whatsapp/idempotencia.ts";
import { decidirMarcarEnviado, urlDeDocumentoPermitida } from "../_shared/whatsapp/marcar-enviado.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
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
  // Idempotência: quem chama manda uma chave estável para "esta mensagem, para este
  // destinatário, nesta ocasião". Chave já usada = já enviada = responde sem reenviar.
  dedupe_key: z.string().min(4).max(200).optional(),
});

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

servirComCors(async (req) => {
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

    // A Evolution baixa esta URL de dentro da rede da empresa: só do nosso Storage.
    if (body.kind === "document" && body.document_url && !urlDeDocumentoPermitida(body.document_url, SUPABASE_URL)) {
      return jr({ error: "document_url precisa ser um arquivo do Storage deste projeto." }, 400);
    }

    const testMode = (settingsMap["wa_test_mode"] ?? settingsMap["zapi_test_mode"]) === "true";
    const testNumber = settingsMap["wa_test_number"] ?? settingsMap["zapi_test_number"]?.replace(/\D/g, "");
    const desviadoPorTeste = !!(testMode && testNumber);

    let phoneClean = normalizePhoneNumber(body.phone);

    if (desviadoPorTeste) {
      console.log(`WhatsApp: Test Mode Active. Redirecting from ${phoneClean} to ${testNumber}`);
      phoneClean = testNumber;
    }

    if (phoneClean.length < 10) {
      return jr({ error: "Telefone inválido (precisa incluir DDI+DDD)" }, 400);
    }

    // Reserva a chave ANTES de chamar o provedor. Repetida: já foi; não envia de novo.
    // Banco indisponível para a reserva: segue e envia (duplicado raro < cobrança que não sai).
    const chave = body.dedupe_key || null;
    if (chave) {
      const reserva = await reservarEnvio(supabaseAdmin, chave, { phone: phoneClean, contexto: body.context });
      if (reserva === "repetida") {
        console.info(`[whatsapp-send] chave repetida, não reenviado: ${chave}`);
        return jr({ success: true, deduplicated: true, kind: body.kind, messageId: null });
      }
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
    if (chave) {
      if (success) await concluirEnvio(supabaseAdmin, chave, sendResult.providerMessageId || null);
      else await liberarEnvio(supabaseAdmin, chave);
    }

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

    // Marca o orçamento como ENVIADO AO CLIENTE só quando ele foi mesmo ao cliente
    // (regra e motivo em _shared/whatsapp/marcar-enviado.ts). Antes marcava qualquer envio com
    // context='quote' — inclusive o dono mandando para si e o modo de teste —, e o "enviado"
    // falso levou a rotina quote-reminders a rejeitar orçamentos vivos.
    if (body.context === "quote" && body.service_order_id) {
      try {
        const { data: ordem } = await supabaseAdmin
          .from("service_orders")
          .select("status, quote_status, converted_to_os_at, clients(whatsapp, phone)")
          .eq("id", body.service_order_id)
          .maybeSingle();
        const cliente = (ordem as any)?.clients ?? null;
        const decisao = decidirMarcarEnviado({
          context: body.context,
          serviceOrderId: body.service_order_id,
          desviadoPorTeste,
          telefoneDestino: phoneClean,
          telefonesDoCliente: [cliente?.whatsapp, cliente?.phone],
          ordem: ordem as any,
        });
        if (decisao.marcar) {
          // Os mesmos filtros no próprio UPDATE: se outra pessoa mexeu no funil entre a leitura
          // e aqui, não sobrescreve.
          const { data: mudou } = await supabaseAdmin
            .from("service_orders")
            .update({ quote_status: "sent" } as any)
            .eq("id", body.service_order_id)
            .eq("status", "draft")
            .in("quote_status" as any, ["draft", "awaiting_approval"])
            .is("converted_to_os_at" as any, null)
            .select("id");
          if ((mudou ?? []).length > 0) {
            await supabaseAdmin.from("audit_log").insert({
              table_name: "service_orders",
              record_id: body.service_order_id,
              action: "update",
              changed_by: callerIdentity,
              previous_value: { quote_status: (ordem as any).quote_status },
              new_value: { quote_status: "sent" },
              reason: `Marcado como enviado: ${decisao.motivo} (${body.kind}).`,
            });
          }
        } else {
          console.info(`[whatsapp-send] orçamento não marcado como enviado: ${decisao.motivo}`);
        }
      } catch (_e) {
        // Não bloqueia — o envio já aconteceu.
        console.warn("quote_status update skipped:", _e);
      }
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

// Edge Function: fiscal-webhook
// Recebe callbacks de status do provedor fiscal (Contora). Chega SEM
// Authorization (só headers X-Fiscal-*) — verify_jwt=false no config.toml.
// A autenticação é a verificação de assinatura HMAC-SHA256 feita internamente
// pelo provider (timing-safe), não o gateway.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider } from "../_shared/fiscal/factory.ts";
import { applyStatusUpdate } from "../_shared/fiscal/apply-status.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-fiscal-signature, x-fiscal-timestamp, x-fiscal-event, x-fiscal-idempotency-key, x-fiscal-delivery-id, x-fiscal-attempt",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Precisa do corpo cru (não parseado) para validar o HMAC — a assinatura é
  // calculada sobre `${timestamp}.${rawBody}` exatamente como recebido.
  const rawBody = await req.text();
  const headers: Record<string, string> = {};
  req.headers.forEach((v, k) => {
    headers[k] = v;
  });

  const provider = createFiscalProvider();
  const event = await provider.parseWebhook(headers, rawBody);
  if (!event) {
    console.warn("[fiscal-webhook] assinatura inválida ou payload malformado");
    return jr({ error: "invalid_signature" }, 401);
  }

  if (!event.providerDocumentId) {
    return jr({ ok: true, ignored: "no_document_id" });
  }

  const { data: doc } = await admin
    .from("issued_fiscal_documents")
    .select("id, document_type, provider_document_id, environment, status, xml_storage_path, pdf_storage_path, provider_status")
    .eq("provider_document_id", event.providerDocumentId)
    .maybeSingle();

  if (!doc) {
    // Documento não rastreado por este ERP (ex.: manipulado direto no console
    // da Contora) — responde 200 para não gerar retries infinitos do provedor.
    return jr({ ok: true, ignored: "unknown_document" });
  }

  // Dedup por entrega: evita reprocessar o mesmo delivery em caso de retry do
  // provedor após um 200 que se perdeu na rede antes de chegar ao cliente dele.
  const lastDeliveryId = (doc.provider_status as Record<string, unknown> | null)
    ?.__last_delivery_id;
  if (event.deliveryId && lastDeliveryId && lastDeliveryId === event.deliveryId) {
    return jr({ ok: true, dedup: true });
  }

  // Sempre reconsulta o status oficial (grátis, não consome cota) em vez de
  // confiar só no nome do evento — alguns eventos são inconclusivos por design
  // (ex.: document.created não indica se autorizou ou rejeitou).
  const statusInfo = await provider.getStatus(doc.document_type, event.providerDocumentId);
  if (!statusInfo.ok) {
    console.error("[fiscal-webhook] falha ao consultar status:", statusInfo.error);
    // 200 mesmo assim: fiscal-reconcile (cron) cobre esse documento depois.
    return jr({ ok: true, warning: "status_fetch_failed" });
  }

  await applyStatusUpdate(admin, provider, doc, statusInfo.data, {
    __last_delivery_id: event.deliveryId,
  });

  return jr({ ok: true, event: event.event });
});

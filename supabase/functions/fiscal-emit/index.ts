// Edge Function: fiscal-emit
// Emissão de documentos fiscais via provedor ativo (Contora). Piloto: só NF-e.
// Admin-only (checado aqui além do JWT exigido pelo gateway — verify_jwt=true).
// Ações: action="create" (default) | "cancel" | "correction".
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider, readFiscalEnvironment } from "../_shared/fiscal/factory.ts";
import { resolveIbgeCityCode } from "../_shared/fiscal/ibge.ts";
import {
  buildNfeDraftPayload,
  validateNfeDraftInput,
  type BuildNfePayloadInput,
} from "../_shared/fiscal/payload-builder.ts";

// SEFAZ exige justificativa com pelo menos 15 caracteres tanto no cancelamento
// quanto na Carta de Correção Eletrônica.
const MIN_JUSTIFICATION_LENGTH = 15;
const ACTIVE_STATUSES = ["draft", "queued", "processing", "authorized"];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
async function requireAdmin(admin: any, req: Request): Promise<{ id: string } | null> {
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data: userData, error } = await admin.auth.getUser(jwt);
  if (error || !userData?.user) return null;
  const { data: profile } = await admin
    .from("app_users")
    .select("id, role, active")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (!profile || profile.role !== "admin" || profile.active === false) return null;
  return { id: profile.id };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const caller = await requireAdmin(admin, req);
  if (!caller) return jr({ error: "unauthorized" }, 401);

  // deno-lint-ignore no-explicit-any
  const body = (await req.json().catch(() => null)) as any;
  if (!body) return jr({ error: "invalid_json" }, 400);

  try {
    if (body.action === "cancel") return await handleCancel(admin, body);
    if (body.action === "correction") return await handleCorrection(admin, body);
    return await handleCreate(admin, body);
  } catch (err) {
    console.error("[fiscal-emit] erro:", err);
    const message = err instanceof Error ? err.message : String(err);
    return jr({ error: message }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function findActiveDocument(admin: any, documentType: string, originType: string, originId: string | null, idempotencyKey: string | null) {
  let query = admin
    .from("issued_fiscal_documents")
    .select("*")
    .eq("document_type", documentType)
    .in("status", ACTIVE_STATUSES);
  query = originId
    ? query.eq("origin_type", originType).eq("origin_id", originId)
    : query.eq("idempotency_key", idempotencyKey);
  return await query.maybeSingle();
}

// deno-lint-ignore no-explicit-any
async function handleCreate(admin: any, body: any): Promise<Response> {
  const documentType = "nfe"; // piloto: só NF-e por ora (NFS-e fica para a Fase 3)
  const environment = readFiscalEnvironment();
  const originType: string = body.origin_type ?? "manual";
  const originId: string | null = body.origin_id ?? null;
  // Chave de idempotência: o front gera uma vez por abertura do diálogo de
  // emissão e reenvia a mesma em caso de duplo clique/retry de rede — sem
  // isso, o fluxo manual (único exposto na UI, sempre sem origin_id) não
  // tinha NENHUMA proteção contra emitir duas NF-e reais para a mesma venda.
  const clientIdempotencyKey: string | null = body.idempotency_key || null;

  if (originId || clientIdempotencyKey) {
    const { data: existing, error: existingErr } = await findActiveDocument(
      admin, documentType, originType, originId, clientIdempotencyKey,
    );
    if (existingErr) {
      return jr({ error: "Falha ao checar duplicidade: " + existingErr.message }, 500);
    }
    if (existing) return jr({ ok: true, data: existing, reused: true });
  }

  const { data: company, error: companyErr } = await admin
    .from("company_fiscal_settings")
    .select("*")
    .limit(1)
    .maybeSingle();
  if (companyErr) {
    return jr({ error: "Falha ao consultar empresa emissora: " + companyErr.message }, 500);
  }
  if (!company) {
    return jr(
      { error: "Empresa emissora não configurada. Preencha os dados fiscais da empresa antes de emitir." },
      422,
    );
  }

  const addr = body.recipient?.address ?? {};
  let cityCode: string | null = addr.city_code || null;
  if (!cityCode && addr.state_code && addr.city_name) {
    cityCode = await resolveIbgeCityCode(addr.state_code, addr.city_name);
  }

  const input: BuildNfePayloadInput = {
    natureOperation: body.nature_operation || undefined,
    recipient: {
      name: body.recipient?.name,
      document: body.recipient?.document,
      email: body.recipient?.email,
      address: {
        street: addr.street,
        number: addr.number,
        complement: addr.complement,
        district: addr.district,
        cityName: addr.city_name,
        cityCode: cityCode || "",
        stateCode: addr.state_code,
        postalCode: addr.postal_code,
      },
    },
    items: (body.items ?? []).map((it: Record<string, unknown>) => ({
      code: String(it.code ?? it.sku ?? "ITEM"),
      name: String(it.name ?? ""),
      ncm: String(it.ncm ?? ""),
      cfop: it.cfop ? String(it.cfop) : undefined,
      unit: it.unit ? String(it.unit) : undefined,
      quantity: Number(it.quantity),
      unitPrice: Number(it.unit_price),
    })),
    paymentMethod: body.payment_method || "01",
  };

  const errors = validateNfeDraftInput(input);
  if (errors.length) return jr({ error: errors.join(" ") }, 422);

  const payload = buildNfeDraftPayload(input);

  // Numeração atômica. Séries distintas por ambiente evitam colisão de
  // numeração quando homologação e produção passarem a coexistir.
  const series = environment === "producao" ? 1 : 900;
  const { data: number, error: seqErr } = await admin.rpc("next_fiscal_number", {
    p_document_type: documentType,
    p_series: series,
    p_environment: environment,
  });
  if (seqErr) {
    return jr({ error: "Falha ao reservar numeração: " + seqErr.message }, 500);
  }

  // Grava o rascunho ANTES de chamar o provedor — garante rastro mesmo se a
  // chamada externa falhar, e serve de guarda contra corrida (índices únicos
  // uq_ifd_active_per_origin / uq_ifd_idempotency_key travam uma segunda
  // emissão concorrente para a mesma origem ou o mesmo envio do front).
  const idempotencyKey = clientIdempotencyKey || crypto.randomUUID();
  const { data: draftRow, error: insErr } = await admin
    .from("issued_fiscal_documents")
    .insert({
      document_type: documentType,
      origin_type: originType,
      origin_id: originId,
      client_id: body.client_id ?? null,
      provider: "contora",
      environment,
      series,
      number,
      status: "draft",
      idempotency_key: idempotencyKey,
      request_payload: payload,
    })
    .select()
    .single();

  if (insErr) {
    if (String(insErr.code) === "23505") {
      const { data: existing } = await findActiveDocument(
        admin, documentType, originType, originId, idempotencyKey,
      );
      if (existing) return jr({ ok: true, data: existing, reused: true });
    }
    return jr({ error: "Falha ao registrar documento: " + insErr.message }, 500);
  }

  const provider = createFiscalProvider();
  const created = await provider.createDraft({
    documentType,
    environment,
    series,
    number,
    payload,
  });

  if (!created.ok) {
    await markFailed(admin, draftRow.id, created.error, created.errorType, created.details);
    return jr({ error: created.error, details: created.details }, 422);
  }
  if (!created.data.providerDocumentId) {
    const msg = "Resposta inesperada do provedor: documento criado sem identificador.";
    await markFailed(admin, draftRow.id, msg);
    return jr({ error: msg }, 502);
  }

  await admin.from("issued_fiscal_documents").update({
    provider_document_id: created.data.providerDocumentId,
    status: created.data.status,
    updated_at: new Date().toISOString(),
  }).eq("id", draftRow.id);

  // Build é opcional segundo a documentação da Contora ("execute o build
  // assinado se quiser revisar XML antes do envio"), mas chamamos mesmo
  // assim: não consome cota (não conta como evento fiscal) e remove qualquer
  // ambiguidade sobre a sequência exigida antes de autorizar.
  const built = await provider.build(documentType, created.data.providerDocumentId, true);
  if (!built.ok) {
    await markFailed(admin, draftRow.id, built.error, built.errorType, built.details);
    return jr({ error: built.error, details: built.details }, 422);
  }

  const dispatched = await provider.dispatch(
    documentType,
    created.data.providerDocumentId,
    "authorize",
  );

  if (!dispatched.ok) {
    await markFailed(admin, draftRow.id, dispatched.error, dispatched.errorType, dispatched.details);
    return jr({ error: dispatched.error, details: dispatched.details }, 422);
  }

  await admin.from("issued_fiscal_documents").update({
    status: "queued",
    updated_at: new Date().toISOString(),
  }).eq("id", draftRow.id);

  return jr({ ok: true, data: { id: draftRow.id, status: "queued", environment } });
}

// deno-lint-ignore no-explicit-any
async function markFailed(
  admin: any,
  documentId: string,
  error: string,
  errorType?: string,
  details?: unknown,
): Promise<void> {
  await admin.from("issued_fiscal_documents").update({
    status: "failed",
    status_message: error,
    provider_status: { error, error_type: errorType, details },
    updated_at: new Date().toISOString(),
  }).eq("id", documentId);
}

// deno-lint-ignore no-explicit-any
async function handleCancel(admin: any, body: any): Promise<Response> {
  const documentId: string | undefined = body.document_id;
  const reason: string | undefined = body.reason;
  if (!documentId || !reason?.trim()) {
    return jr({ error: "document_id e reason são obrigatórios" }, 422);
  }
  if (reason.trim().length < MIN_JUSTIFICATION_LENGTH) {
    return jr({ error: `O motivo do cancelamento precisa ter pelo menos ${MIN_JUSTIFICATION_LENGTH} caracteres.` }, 422);
  }

  const { data: doc, error: docErr } = await admin
    .from("issued_fiscal_documents")
    .select("*")
    .eq("id", documentId)
    .maybeSingle();
  if (docErr) return jr({ error: "Falha ao consultar documento: " + docErr.message }, 500);
  if (!doc) return jr({ error: "Documento não encontrado" }, 404);
  if (!doc.provider_document_id) {
    return jr({ error: "Documento ainda não foi enviado ao provedor" }, 422);
  }
  if (doc.status !== "authorized") {
    return jr({ error: `Só é possível cancelar um documento autorizado (status atual: ${doc.status}).` }, 422);
  }

  const provider = createFiscalProvider();
  const result = await provider.cancel(doc.document_type, doc.provider_document_id, reason.trim());
  if (!result.ok) return jr({ error: result.error, details: result.details }, 422);

  // Cancelamento também é assíncrono — webhook/reconcile confirmam o status final.
  await admin.from("issued_fiscal_documents").update({
    status: "processing",
    updated_at: new Date().toISOString(),
  }).eq("id", documentId);

  return jr({ ok: true });
}

// deno-lint-ignore no-explicit-any
async function handleCorrection(admin: any, body: any): Promise<Response> {
  const documentId: string | undefined = body.document_id;
  const text: string | undefined = body.text;
  if (!documentId || !text?.trim()) {
    return jr({ error: "document_id e text são obrigatórios" }, 422);
  }
  if (text.trim().length < MIN_JUSTIFICATION_LENGTH) {
    return jr({ error: `O texto da carta de correção precisa ter pelo menos ${MIN_JUSTIFICATION_LENGTH} caracteres.` }, 422);
  }

  const { data: doc, error: docErr } = await admin
    .from("issued_fiscal_documents")
    .select("*")
    .eq("id", documentId)
    .maybeSingle();
  if (docErr) return jr({ error: "Falha ao consultar documento: " + docErr.message }, 500);
  if (!doc) return jr({ error: "Documento não encontrado" }, 404);
  if (!doc.provider_document_id) {
    return jr({ error: "Documento ainda não foi enviado ao provedor" }, 422);
  }
  if (doc.status !== "authorized") {
    return jr({ error: `Só é possível corrigir um documento autorizado (status atual: ${doc.status}).` }, 422);
  }

  const provider = createFiscalProvider();
  const result = await provider.correct(doc.document_type, doc.provider_document_id, text.trim());
  if (!result.ok) return jr({ error: result.error, details: result.details }, 422);

  return jr({ ok: true });
}

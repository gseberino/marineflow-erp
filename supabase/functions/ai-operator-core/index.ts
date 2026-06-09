// Edge Function: ai-operator-core
// MarineFlow AI Operator — núcleo seguro com gate determinístico de aprovação.
//
// Mudanças desta versão (continuação do Macro Ciclo 1):
//   * Ownership de sessão validado antes de qualquer leitura/gravação.
//   * Endpoints approve_action / reject_action validam matriz de
//     autorização role × action via SQL helper `ai_op_can_approve`.
//   * Tentativas negadas são auditadas (event_category='security').
//   * Memória técnica criada pela IA nasce sempre `verification_status='candidate'`;
//     promoção/rejeição vai por endpoints dedicados que checam papel.
//   * Modelo configurável por env (`AI_OPERATOR_MODEL`) com fallback seguro.
//   * Sem mudanças nos fluxos sensíveis (continuam bloqueados pelo gate).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  fetchAIWithRetry,
  resolveOverloadUserMessage,
  resolveRateLimitUserMessage,
} from "../_shared/ai-error.ts";
import { classifyAction } from "./risk.ts";
import { OPERATOR_TOOLS } from "./tools.ts";
import { buildSystemPrompt } from "./prompt.ts";
import { validateAllReferences } from "./entity-validation.ts";
import { resolveProposalDraftId } from "./proposal.ts";
import {
  evaluateActionProposalGovernance,
  findOpenEquivalentPendingAction,
  isInformationalActionRequest,
} from "./action-governance.ts";
import {
  buildDraftGroundingSnapshotNote,
  buildExternalQuoteFormalizationProposal,
  buildGroundedInformationalResponse,
  evaluateExternalQuoteFormalization,
  mapDraftItemsToExternalQuoteRows,
  type DraftItemForExternalQuote,
} from "./formal-quote.ts";
import { interpretPendingUpdate, interpretMemoryUpdate } from "./transitions.ts";
import { resolveCoreChannel } from "./channel-source.ts";
import { preAuthorizeApprove } from "./approve-guard.ts";
import {
  buildBootstrapDraft,
  classifyMessage,
  detectOperationalIntent,
} from "./operational-intent.ts";
import { buildDraftContextNote, redactUuidTokens, toModelConversationHistory } from "./session-history.ts";
import {
  buildDraftUpdatePatch,
  draftProtectedAuditEventForOperation,
  evaluateCancelDraft,
  evaluateDraftMutationPolicy,
  isSanitizedInternalReference,
  resolveEntityLinkByHumanTerms,
  resolveCreateDraftLinks,
  resolveCreateDraftStatus,
  resolveExplicitDraftEntitySelection,
  resolveLinkProposal,
  resolveMemoryCandidateLinks,
  sanitizeToolEventsForFrontend,
  type UnexpectedEntityAttempt,
} from "./entity-linking.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") || "";
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai";
// Modelo configurável. O legacy `ai-agent` foi atualizado para
// `gemini-2.5-flash` (default real em uso no projeto) — alinhamos aqui para
// que o operador interno não rode com modelo diferente por acidente.
// Override por env: `AI_OPERATOR_MODEL`.
// Recomendação documentada (docs/ai-operator/macro-cycle-1-security-hardening.md):
// para a homologação do cenário Raymarine, configure `AI_OPERATOR_MODEL` para
// um modelo Gemini com forte fidelidade a instrução (ex: gemini-2.5-flash —
// mesmo modelo já validado no agente atual).
const MODEL = (Deno.env.get("AI_OPERATOR_MODEL") || "gemini-2.5-flash").trim();
const MODEL_FAST_FALLBACK = (Deno.env.get("GEMINI_MODEL_FAST") || "gemini-2.5-flash").trim();
const MAX_ITERATIONS = 6;

// Always returns HTTP 200 so Supabase invoke() never throws FunctionsHttpError.
// The real status is forwarded via X-Actual-Status for client-side inspection.
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json", "X-Actual-Status": String(status) },
  });
}

// --------------------------------------------------------------------------
// Audit helper
// --------------------------------------------------------------------------
async function audit(
  admin: any,
  params: {
    session_id?: string | null;
    draft_id?: string | null;
    pending_action_id?: string | null;
    actor_user_id?: string | null;
    actor_kind: "user" | "ai_model" | "system" | "channel";
    event_type: string;
    event_category?: "info" | "security" | "data" | "channel" | "error";
    payload?: Record<string, unknown>;
  }
) {
  try {
    await admin.from("ai_operator_audit").insert({
      session_id: params.session_id ?? null,
      draft_id: params.draft_id ?? null,
      pending_action_id: params.pending_action_id ?? null,
      actor_user_id: params.actor_user_id ?? null,
      actor_kind: params.actor_kind,
      event_type: params.event_type,
      event_category: params.event_category ?? "info",
      payload: params.payload ?? {},
    });
  } catch (e) {
    console.error("[ai-operator-core] audit failed", e);
  }
}

// --------------------------------------------------------------------------
// Authorization helpers
// --------------------------------------------------------------------------
async function sessionBelongsTo(admin: any, sessionId: string, userId: string, isAdmin: boolean) {
  if (isAdmin) {
    const { data: s } = await admin
      .from("ai_operator_sessions")
      .select("id, owner_user_id")
      .eq("id", sessionId)
      .maybeSingle();
    return !!s;
  }
  const { data: s } = await admin
    .from("ai_operator_sessions")
    .select("id")
    .eq("id", sessionId)
    .eq("owner_user_id", userId)
    .maybeSingle();
  return !!s;
}

async function canApprove(admin: any, userId: string, actionName: string): Promise<boolean> {
  const { data, error } = await admin.rpc("ai_op_can_approve", { _user_id: userId, _action: actionName });
  if (error) {
    console.error("[ai-operator-core] ai_op_can_approve rpc failed", error);
    return false;
  }
  return !!data;
}

async function canReject(admin: any, userId: string, pendingActionId: string): Promise<boolean> {
  const { data, error } = await admin.rpc("ai_op_can_reject", {
    _user_id: userId,
    _pending_action_id: pendingActionId,
  });
  if (error) {
    console.error("[ai-operator-core] ai_op_can_reject rpc failed", error);
    return false;
  }
  return !!data;
}

async function getSessionRow(admin: any, sessionId: string) {
  const { data } = await admin
    .from("ai_operator_sessions")
    .select("id, client_id, vessel_id, service_order_id, metadata, created_at, last_activity_at")
    .eq("id", sessionId)
    .maybeSingle();
  return data ?? null;
}

async function mergeSessionMetadata(admin: any, sessionId: string, patch: Record<string, unknown>) {
  const current = await getSessionRow(admin, sessionId);
  const metadata = current?.metadata && typeof current.metadata === "object" ? current.metadata : {};
  await admin
    .from("ai_operator_sessions")
    .update({ metadata: { ...metadata, ...patch } })
    .eq("id", sessionId);
}

async function getDraftRow(admin: any, draftId: string) {
  const { data } = await admin
    .from("ai_operator_drafts")
    .select(
      "id, session_id, kind, title, status, summary, metadata, pending_questions, next_steps, hypotheses, client_id, vessel_id, service_order_id, converted_service_order_id, interpreted_category, estimated_labor_hours, estimated_labor_value, estimated_parts_value, estimated_travel_value, estimated_total, created_at, updated_at, clients(full_name_or_company_name), vessels(boat_name)"
    )
    .eq("id", draftId)
    .maybeSingle();
  return data ?? null;
}

async function findActiveDraft(admin: any, sessionId: string, requestedDraftId?: string | null) {
  if (requestedDraftId) {
    const requested = await getDraftRow(admin, requestedDraftId);
    if (requested && requested.session_id === sessionId) return requested;
  }

  const session = await getSessionRow(admin, sessionId);
  const sessionActiveDraftId =
    session?.metadata && typeof session.metadata === "object"
      ? (session.metadata as Record<string, unknown>).active_draft_id
      : null;
  if (typeof sessionActiveDraftId === "string") {
    const fromSession = await getDraftRow(admin, sessionActiveDraftId);
    if (fromSession && fromSession.session_id === sessionId) return fromSession;
  }

  const { data } = await admin
    .from("ai_operator_drafts")
    .select(
      "id, session_id, kind, title, status, summary, pending_questions, next_steps, hypotheses, client_id, vessel_id, service_order_id, converted_service_order_id, interpreted_category, estimated_labor_hours, estimated_labor_value, estimated_parts_value, estimated_travel_value, estimated_total, created_at, updated_at, clients(full_name_or_company_name), vessels(boat_name)"
    )
    .eq("session_id", sessionId)
    .order("updated_at", { ascending: false })
    .limit(1);
  return data?.[0] ?? null;
}

export type DraftCandidateForSelection = {
  id: string;
  title: string | null;
  kind: string;
  status: string;
  summary: string | null;
  client_name: string | null;
  vessel_name: string | null;
  updated_at: string;
};

// Lista os drafts mais recentes visíveis ao usuário autenticado para fluxos
// em que ele referenciou um rascunho existente sem ter passado draft_id.
// Usa o cliente `sb` (JWT do usuário) — RLS impõe a visibilidade. Filtra
// estados terminais e cancelados.
async function findDraftCandidatesForSelection(
  sb: any,
  opts: { limit?: number } = {}
): Promise<DraftCandidateForSelection[]> {
  const limit = Math.min(Math.max(opts.limit ?? 5, 1), 10);
  const { data, error } = await sb
    .from("ai_operator_drafts")
    .select(
      "id, title, kind, status, summary, updated_at, clients(full_name_or_company_name), vessels(boat_name)"
    )
    .in("status", ["draft", "awaiting_info", "awaiting_approval"])
    .order("updated_at", { ascending: false })
    .limit(limit);
  if (error) return [];
  return (data || []).map((row: any) => ({
    id: row.id,
    title: row.title,
    kind: row.kind,
    status: row.status,
    summary: row.summary,
    client_name: row.clients?.full_name_or_company_name ?? null,
    vessel_name: row.vessels?.boat_name ?? null,
    updated_at: row.updated_at,
  }));
}

async function buildActiveDraftContext(admin: any, draftId: string) {
  const [draft, itemsResult, formalQuote, openActions] = await Promise.all([
    getDraftRow(admin, draftId),
    admin.from("ai_operator_draft_items").select("item_kind, description").eq("draft_id", draftId).order("position"),
    getFormalQuoteForDraft(admin, draftId),
    countOpenPendingActionsForDraft(admin, draftId),
  ]);
  if (!draft) return null;

  const officialServiceOrder = await getOfficialServiceOrderForDraft(admin, draft);
  const pendingQuestions = Array.isArray(draft.pending_questions) ? draft.pending_questions : [];

  const legacyContext = buildDraftContextNote({
    title: draft.title ?? null,
    status: draft.status ?? null,
    summary: draft.summary ?? null,
    clientName: draft.clients?.full_name_or_company_name ?? null,
    vesselName: draft.vessels?.boat_name ?? null,
    pendingQuestions,
    nextSteps: Array.isArray(draft.next_steps) ? draft.next_steps : [],
    hypotheses: Array.isArray(draft.hypotheses) ? draft.hypotheses : [],
    items: (itemsResult.data || []).map((item: any) => ({
      item_kind: item.item_kind,
      description: item.description,
    })),
  });
  const snapshot = buildDraftGroundingSnapshotNote({
    draft: draftForExternalQuote(draft, formalQuote?.id ?? null),
    itemCount: itemsResult.data?.length ?? 0,
    pendingQuestionCount: pendingQuestions.length,
    openActionCount: openActions,
    formalQuote,
    officialServiceOrder,
  });

  return `${snapshot}\n\n${legacyContext}`;
}

function draftForExternalQuote(draft: any, externalQuoteId: string | null = null) {
  return {
    id: draft.id,
    title: draft.title ?? null,
    kind: draft.kind ?? null,
    status: draft.status ?? null,
    summary: draft.summary ?? null,
    client_id: draft.client_id ?? null,
    vessel_id: draft.vessel_id ?? null,
    client_name: draft.clients?.full_name_or_company_name ?? null,
    vessel_name: draft.vessels?.boat_name ?? null,
    converted_service_order_id: draft.converted_service_order_id ?? null,
    service_order_id: draft.service_order_id ?? null,
    external_quote_id: externalQuoteId,
    pending_questions: Array.isArray(draft.pending_questions) ? draft.pending_questions : [],
    next_steps: Array.isArray(draft.next_steps) ? draft.next_steps : [],
    hypotheses: Array.isArray(draft.hypotheses) ? draft.hypotheses : [],
  };
}

async function getFormalQuoteForDraft(admin: any, draftId: string) {
  const { data } = await admin
    .from("external_quotes")
    .select("id, quote_number, status")
    .eq("ai_operator_draft_id", draftId)
    .maybeSingle();
  return data ?? null;
}

async function getOfficialServiceOrderForDraft(admin: any, draft: any) {
  const serviceOrderId = draft?.converted_service_order_id ?? draft?.service_order_id ?? null;
  if (!serviceOrderId) return null;
  const { data } = await admin
    .from("service_orders")
    .select("id, service_order_number, status")
    .eq("id", serviceOrderId)
    .maybeSingle();
  return data ?? null;
}

async function countOpenPendingActionsForDraft(admin: any, draftId: string) {
  const { count } = await admin
    .from("ai_operator_pending_actions")
    .select("id", { count: "exact", head: true })
    .eq("draft_id", draftId)
    .in("status", ["pending", "approved"])
    .is("executed_at", null);
  return count ?? 0;
}

async function getDraftItemsForExternalQuote(admin: any, draftId: string): Promise<DraftItemForExternalQuote[]> {
  const { data, error } = await admin
    .from("ai_operator_draft_items")
    .select("id, item_kind, service_id, product_id, description, notes, quantity, unit, unit_price, estimated_total, position")
    .eq("draft_id", draftId)
    .order("position");
  if (error) throw error;
  return (data || []) as DraftItemForExternalQuote[];
}

function buildFormalQuoteInternalNotes(input: {
  draft: any;
  nonBillableNotes: string[];
  pendingQuestionCount: number;
}) {
  const pendingQuestions = Array.isArray(input.draft.pending_questions) ? input.draft.pending_questions : [];
  const nextSteps = Array.isArray(input.draft.next_steps) ? input.draft.next_steps : [];
  const hypotheses = Array.isArray(input.draft.hypotheses) ? input.draft.hypotheses : [];
  const blocks = [
    "Origem: MarineFlow AI Operator.",
    input.pendingQuestionCount > 0
      ? `Perguntas pendentes (${input.pendingQuestionCount}):\n${pendingQuestions.map((q: string) => `- ${q}`).join("\n")}`
      : null,
    nextSteps.length > 0 ? `Proximos passos sugeridos:\n${nextSteps.map((step: string) => `- ${step}`).join("\n")}` : null,
    hypotheses.length > 0 ? `Hipoteses tecnicas:\n${hypotheses.map((h: string) => `- ${h}`).join("\n")}` : null,
    input.nonBillableNotes.length > 0
      ? `Observacoes nao cobradas:\n${input.nonBillableNotes.map((note) => `- ${note}`).join("\n")}`
      : null,
  ].filter(Boolean);
  return blocks.join("\n\n");
}

function minimizedExternalQuotePayload(row: any) {
  return {
    id: row.id,
    quote_number: row.quote_number ?? null,
    status: row.status ?? null,
    path: `/external-quotes/${row.id}`,
  };
}

function safeLimit(value: unknown, fallback = 10, max = 25) {
  const n = Number(value) || fallback;
  return Math.min(Math.max(n, 1), max);
}

function formatClientForModel(row: any) {
  return {
    name: row?.full_name_or_company_name ?? null,
    type: row?.type ?? null,
  };
}

function formatVesselForModel(row: any) {
  return {
    name: row?.boat_name ?? null,
    manufacturer: row?.manufacturer ?? null,
    model: row?.model ?? null,
    year: row?.year ?? null,
    asset_type: row?.asset_type ?? null,
  };
}

async function searchClientRowsForLink(sb: any, queryText: string) {
  const q = String(queryText || "").trim();
  if (!q || isSanitizedInternalReference(q)) return [];
  const { data, error } = await sb
    .from("clients")
    .select("id, full_name_or_company_name, type")
    .or(`full_name_or_company_name.ilike.%${q}%`)
    .eq("active", true)
    .limit(5);
  if (error) throw error;
  return (data || []).map((row: any) => ({
    id: row.id,
    name: row.full_name_or_company_name ?? null,
    type: row.type ?? null,
  }));
}

async function searchVesselRowsForLink(sb: any, queryText: string) {
  const q = String(queryText || "").trim();
  if (!q || isSanitizedInternalReference(q)) return [];
  const { data, error } = await sb
    .from("vessels")
    .select("id, boat_name, manufacturer, model, year, client_id")
    .eq("active", true)
    .or(`boat_name.ilike.%${q}%,model.ilike.%${q}%,manufacturer.ilike.%${q}%`)
    .limit(5);
  if (error) throw error;
  return (data || []).map((row: any) => ({
    id: row.id,
    name: row.boat_name ?? null,
    manufacturer: row.manufacturer ?? null,
    model: row.model ?? null,
    year: row.year ?? null,
    client_id: row.client_id ?? null,
  }));
}

function resolveActiveDraftTarget(args: any, activeDraftId?: string | null) {
  if (activeDraftId) return activeDraftId;
  const legacy = typeof args?.draft_id === "string" ? args.draft_id.trim() : "";
  if (!legacy || isSanitizedInternalReference(legacy)) return null;
  return legacy;
}

async function auditUnexpectedEntityAttempts(
  admin: any,
  params: {
    sessionId: string;
    userId: string;
    tool: string;
    attempts: UnexpectedEntityAttempt[];
    draftId?: string | null;
  }
) {
  for (const attempt of params.attempts) {
    await audit(admin, {
      session_id: params.sessionId,
      draft_id: params.draftId ?? null,
      actor_user_id: params.userId,
      actor_kind: "ai_model",
      event_type: "model_entity_link_ignored",
      event_category: "security",
      payload: {
        tool: params.tool,
        field: attempt.field,
        attempted: true,
      },
    });
  }
}

// --------------------------------------------------------------------------
// Safe-tool executors
// --------------------------------------------------------------------------
async function execSafeTool(
  name: string,
  args: any,
  ctx: { sb: any; admin: any; userId: string; sessionId: string; activeDraftId?: string | null }
): Promise<{ result: any; draftId?: string | null }> {
  const { sb, admin, userId, sessionId, activeDraftId } = ctx;

  switch (name) {
    case "search_clients": {
      const q = String(args.query || "").trim();
      const limit = safeLimit(args.limit, 10, 25);
      const { data, error } = await sb
        .from("clients")
        .select("id, full_name_or_company_name, type, phone, whatsapp, email, cpf_cnpj")
        .or(
          `full_name_or_company_name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%,whatsapp.ilike.%${q}%,cpf_cnpj.ilike.%${q}%`
        )
        .eq("active", true)
        .limit(limit);
      if (error) throw error;
      return { result: { results: (data || []).map(formatClientForModel), result_count: data?.length ?? 0 } };
    }
    case "search_vessels": {
      const q = String(args.query || "").trim();
      const { data, error } = await sb
        .from("vessels")
        .select("id, boat_name, manufacturer, model, year, client_id, asset_type, marina_id")
        .eq("active", true)
        .or(`boat_name.ilike.%${q}%,model.ilike.%${q}%,manufacturer.ilike.%${q}%`)
        .limit(15);
      if (error) throw error;
      if (args.client_id) {
        await audit(admin, {
          session_id: sessionId,
          actor_user_id: userId,
          actor_kind: "ai_model",
          event_type: "model_client_filter_ignored",
          event_category: "security",
          payload: { tool: "search_vessels", attempted: true },
        });
      }
      return { result: { results: (data || []).map(formatVesselForModel), result_count: data?.length ?? 0 } };
    }
    case "search_products": {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("products")
        .select("id, product_name, sku, brand, sale_price, stock_quantity, unit")
        .eq("active", true)
        .or(`product_name.ilike.%${q}%,sku.ilike.%${q}%,brand.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { result: { results: data } };
    }
    case "search_services": {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("services")
        .select("id, service_name, description, billing_unit, default_price")
        .eq("active", true)
        .or(`service_name.ilike.%${q}%,description.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { result: { results: data } };
    }
    case "get_vessel_history": {
      const vesselQuery = typeof args.vessel_query === "string" ? args.vessel_query.trim() : "";
      if (!vesselQuery || isSanitizedInternalReference(vesselQuery)) {
        return { result: { error: "Informe o nome da embarcacao para consultar historico." } };
      }
      const vesselCandidates = await searchVesselRowsForLink(sb, vesselQuery);
      if (vesselCandidates.length === 0) return { result: { error: "Embarcacao nao localizada." } };
      if (vesselCandidates.length > 1) {
        return {
          result: {
            error: "Mais de uma embarcacao localizada. Especifique melhor o nome/modelo antes de consultar o historico.",
            candidates: vesselCandidates.map((vessel: any) => formatVesselForModel({ boat_name: vessel.name, ...vessel })),
          },
        };
      }
      const { data, error } = await sb
        .from("service_orders")
        .select(
          "id, service_order_number, status, scheduled_start_at, grand_total, created_at, problem_description, clients(full_name_or_company_name)"
        )
        .eq("vessel_id", vesselCandidates[0].id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return {
        result: {
          history: (data || []).map((row: any) => ({
            service_order_number: row.service_order_number,
            status: row.status,
            scheduled_start_at: row.scheduled_start_at,
            grand_total: row.grand_total,
            created_at: row.created_at,
            problem_description: row.problem_description,
            client_name: row.clients?.full_name_or_company_name ?? null,
          })),
        },
      };
    }
    case "list_technicians": {
      const { data, error } = await sb
        .from("app_users")
        .select("id, full_name, role")
        .in("role", ["technician", "admin"])
        .eq("active", true)
        .order("full_name");
      if (error) throw error;
      return { result: { results: data } };
    }
    case "create_draft": {
      // Validar referências de cliente/embarcação com o JWT do usuário
      // (respeita RLS real do ERP). Referências não visíveis NÃO são
      // persistidas; o rascunho ainda pode ser criado sem o link, e a
      // tentativa é auditada.
      const session = await getSessionRow(admin, sessionId);
      const linkPolicy = resolveCreateDraftLinks(args, session);
      const pendingQuestions = Array.isArray(args.pending_questions) ? args.pending_questions : [];
      const draftStatus = resolveCreateDraftStatus(args.status, pendingQuestions.length > 0);
      await auditUnexpectedEntityAttempts(admin, {
        sessionId: sessionId,
        userId,
        tool: "create_draft",
        attempts: linkPolicy.unexpected,
      });
      if (draftStatus.blockedStatus) {
        await audit(admin, {
          session_id: sessionId,
          actor_user_id: userId,
          actor_kind: "ai_model",
          event_type: "model_draft_status_blocked",
          event_category: "security",
          payload: { tool: "create_draft", attempted_status: draftStatus.blockedStatus },
        });
      }
      const { data: draft, error } = await admin
        .from("ai_operator_drafts")
        .insert({
          session_id: sessionId,
          created_by: userId,
          kind: args.kind,
          status: draftStatus.status,
          title: args.title || null,
          summary: args.summary || null,
          client_id: linkPolicy.links.client_id,
          vessel_id: linkPolicy.links.vessel_id,
          interpreted_intent: args.interpreted_intent || null,
          interpreted_category: args.interpreted_category || null,
          estimated_labor_hours: args.estimated_labor_hours ?? null,
          estimated_labor_value: args.estimated_labor_value ?? null,
          estimated_parts_value: args.estimated_parts_value ?? null,
          estimated_travel_value: args.estimated_travel_value ?? null,
          estimated_total: args.estimated_total ?? null,
          pending_questions: pendingQuestions,
          next_steps: Array.isArray(args.next_steps) ? args.next_steps : [],
          hypotheses: Array.isArray(args.hypotheses) ? args.hypotheses : [],
        })
        .select()
        .single();
      if (error) throw error;
      await audit(admin, {
        session_id: sessionId,
        draft_id: draft.id,
        actor_user_id: userId,
        actor_kind: "ai_model",
        event_type: "draft_created",
        event_category: "data",
        payload: { kind: args.kind, title: args.title },
      });
      await admin
        .from("ai_operator_sessions")
        .update({
          client_id: linkPolicy.links.client_id,
          vessel_id: linkPolicy.links.vessel_id,
        })
        .eq("id", sessionId);
      await mergeSessionMetadata(admin, sessionId, { active_draft_id: draft.id });
      return { result: { ok: true, draft_id: draft.id, draft }, draftId: draft.id };
    }
    case "update_draft": {
      const targetDraftId = resolveActiveDraftTarget(args, activeDraftId);
      if (!targetDraftId) return { result: { error: "Nao ha rascunho ativo para atualizar." } };
      const { data: draftOwner } = await admin
        .from("ai_operator_drafts")
        .select("id, session_id, client_id, vessel_id, status")
        .eq("id", targetDraftId)
        .maybeSingle();
      if (!draftOwner || draftOwner.session_id !== sessionId) {
        return { result: { error: "Rascunho nao pertence a sessao atual." } };
      }
      const updatePolicy = buildDraftUpdatePatch(args, draftOwner);
      await auditUnexpectedEntityAttempts(admin, {
        sessionId: sessionId,
        userId,
        tool: "update_draft",
        attempts: updatePolicy.unexpected,
        draftId: targetDraftId,
      });
      if (updatePolicy.blockedStatus) {
        await audit(admin, {
          session_id: sessionId,
          draft_id: targetDraftId,
          actor_user_id: userId,
          actor_kind: "ai_model",
          event_type: "model_draft_status_blocked",
          event_category: "security",
          payload: { tool: "update_draft", attempted_status: updatePolicy.blockedStatus },
        });
      }
      if (updatePolicy.blockedCurrentStatus) {
        await audit(admin, {
          session_id: sessionId,
          draft_id: targetDraftId,
          actor_user_id: userId,
          actor_kind: "ai_model",
          event_type: draftProtectedAuditEventForOperation("model_update_draft"),
          event_category: "security",
          payload: {
            tool: "update_draft",
            current_status: updatePolicy.blockedCurrentStatus,
            attempted_status: updatePolicy.blockedStatus,
          },
        });
        return {
          result: {
            ok: false,
            blocked: true,
            reason: "draft_current_status_protected",
            message:
              "Este rascunho esta em estado protegido e exige um fluxo humano especifico de revisao ou reabertura antes de qualquer alteracao.",
            current_status: updatePolicy.blockedCurrentStatus,
          },
        };
      }
      if (Object.keys(updatePolicy.patch).length === 0) {
        return {
          result: {
            ok: false,
            blocked: !!updatePolicy.blockedStatus,
            reason: updatePolicy.blockedStatus ? "draft_status_governance_protected" : "no_safe_fields",
            message: updatePolicy.blockedStatus
              ? "Status de governanca do draft nao pode ser alterado pelo modelo."
              : "Nenhum campo seguro informado para atualizar o rascunho.",
          },
        };
      }
      const { data: updated, error } = await admin
        .from("ai_operator_drafts")
        .update(updatePolicy.patch)
        .eq("id", targetDraftId)
        .select()
        .single();
      if (error) throw error;
      await admin
        .from("ai_operator_sessions")
        .update({
          client_id: updatePolicy.links.client_id,
          vessel_id: updatePolicy.links.vessel_id,
        })
        .eq("id", sessionId);
      await mergeSessionMetadata(admin, sessionId, { active_draft_id: targetDraftId });
      await audit(admin, {
        session_id: sessionId,
        draft_id: targetDraftId,
        actor_user_id: userId,
        actor_kind: "ai_model",
        event_type: "draft_updated",
        event_category: "data",
        payload: { fields: Object.keys(updatePolicy.patch) },
      });
      return { result: { ok: true, draft_id: targetDraftId, draft: updated }, draftId: targetDraftId };
    }
    case "add_draft_item": {
      // Garante que o draft pertence à sessão atual (anti-injection cross-session)
      const targetDraftId = resolveActiveDraftTarget(args, activeDraftId);
      if (!targetDraftId) return { result: { error: "Nao ha rascunho ativo para adicionar item." } };
      const { data: draftOwner } = await admin
        .from("ai_operator_drafts")
        .select("id, session_id, status")
        .eq("id", targetDraftId)
        .maybeSingle();
      if (!draftOwner || draftOwner.session_id !== sessionId) {
        return { result: { error: "Rascunho não pertence à sessão atual." } };
      }
      const mutationPolicy = evaluateDraftMutationPolicy({
        draftStatus: draftOwner.status,
        operation: "model_add_draft_item",
      });
      if (!mutationPolicy.ok) {
        await audit(admin, {
          session_id: sessionId,
          draft_id: targetDraftId,
          actor_user_id: userId,
          actor_kind: "ai_model",
          event_type: draftProtectedAuditEventForOperation("model_add_draft_item"),
          event_category: "security",
          payload: {
            tool: "add_draft_item",
            current_status: mutationPolicy.currentStatus,
            reason: mutationPolicy.reason,
          },
        });
        return {
          result: {
            ok: false,
            blocked: true,
            reason: mutationPolicy.reason,
            message: mutationPolicy.message,
            current_status: mutationPolicy.currentStatus,
          },
        };
      }
      // Validar referências de produto/serviço com RLS do usuário.
      const itemRefs = await validateAllReferences(sb, {
        product: args.product_id,
        service: args.service_id,
      });
      const safeProduct = itemRefs.product?.ok ? args.product_id : null;
      const safeService = itemRefs.service?.ok ? args.service_id : null;
      for (const [k, r] of Object.entries(itemRefs)) {
        if (r && !r.ok) {
          await audit(admin, {
            session_id: sessionId,
            draft_id: targetDraftId,
            actor_user_id: userId,
            actor_kind: "system",
            event_type: "entity_reference_blocked",
            event_category: "security",
            payload: { tool: "add_draft_item", kind: k, reason: r.reason },
          });
        }
      }
      const { data: existing } = await admin
        .from("ai_operator_draft_items")
        .select("id")
        .eq("draft_id", targetDraftId);
      const position = (existing?.length ?? 0) + 1;
      const { data: item, error } = await admin
        .from("ai_operator_draft_items")
        .insert({
          draft_id: targetDraftId,
          item_kind: args.item_kind,
          service_id: safeService,
          product_id: safeProduct,
          description: args.description,
          notes: args.notes || null,
          quantity: args.quantity ?? 1,
          unit: args.unit || "unit",
          unit_price: args.unit_price ?? null,
          estimated_total: args.estimated_total ?? null,
          confidence: args.confidence || "medium",
          position,
        })
        .select()
        .single();
      if (error) throw error;
      return { result: { ok: true, item } };
    }
    case "ask_pending_question": {
      const targetDraftId = resolveActiveDraftTarget(args, activeDraftId);
      if (!targetDraftId) return { result: { error: "Nao ha rascunho ativo para registrar pergunta." } };
      const { data: draftOwner } = await admin
        .from("ai_operator_drafts")
        .select("id, session_id, status, pending_questions")
        .eq("id", targetDraftId)
        .maybeSingle();
      if (!draftOwner || draftOwner.session_id !== sessionId) {
        return { result: { error: "Rascunho não pertence à sessão atual." } };
      }
      const mutationPolicy = evaluateDraftMutationPolicy({
        draftStatus: draftOwner.status,
        operation: "model_ask_pending_question",
      });
      if (!mutationPolicy.ok) {
        await audit(admin, {
          session_id: sessionId,
          draft_id: targetDraftId,
          actor_user_id: userId,
          actor_kind: "ai_model",
          event_type: draftProtectedAuditEventForOperation("model_ask_pending_question"),
          event_category: "security",
          payload: {
            tool: "ask_pending_question",
            current_status: mutationPolicy.currentStatus,
            reason: mutationPolicy.reason,
          },
        });
        return {
          result: {
            ok: false,
            blocked: true,
            reason: mutationPolicy.reason,
            message: mutationPolicy.message,
            current_status: mutationPolicy.currentStatus,
          },
        };
      }
      const list = Array.isArray(draftOwner.pending_questions) ? draftOwner.pending_questions : [];
      list.push(args.question);
      const { error: uErr } = await admin
        .from("ai_operator_drafts")
        .update({ pending_questions: list })
        .eq("id", targetDraftId);
      if (uErr) throw uErr;
      return { result: { ok: true, count: list.length } };
    }
    case "register_memory_note":  // alias retrocompatível
    case "register_memory_candidate": {
      // Nasce SEMPRE como candidate. Promoção a 'verified' exige endpoint
      // dedicado com role admin/technician (verify_memory_note).
      // Validar referências de cliente/embarcação com RLS do usuário.
      const [session, activeDraft] = await Promise.all([
        getSessionRow(admin, sessionId),
        findActiveDraft(admin, sessionId, null),
      ]);
      const memoryPolicy = resolveMemoryCandidateLinks(args, {
        draft: activeDraft,
        session,
      });
      await auditUnexpectedEntityAttempts(admin, {
        sessionId: sessionId,
        userId,
        tool: name,
        attempts: memoryPolicy.unexpected,
        draftId: activeDraft?.id ?? null,
      });
      const { data: note, error } = await admin
        .from("ai_operator_memory_notes")
        .insert({
          client_id: memoryPolicy.client_id,
          vessel_id: memoryPolicy.vessel_id,
          scope: memoryPolicy.scope,
          topic: args.topic,
          title: args.title,
          body: args.body,
          confidence: args.confidence || "low",  // candidate → confiança baixa por default
          source: "ai",
          verification_status: "candidate",
          created_by: userId,
        })
        .select()
        .single();
      if (error) throw error;
      await audit(admin, {
        session_id: sessionId,
        actor_user_id: userId,
        actor_kind: "ai_model",
        event_type: "memory_candidate_created",
        event_category: "data",
        payload: { topic: args.topic, title: args.title },
      });
      return { result: { ok: true, note_id: note.id, verification_status: "candidate" } };
    }
    default:
      return { result: { error: `Tool segura desconhecida: ${name}` } };
  }
}

async function recordMessage(
  admin: any,
  sessionId: string,
  msg: {
    role: "user" | "assistant" | "tool" | "system";
    content?: string | null;
    tool_calls?: any;
    tool_call_id?: string;
    tool_name?: string;
    source?: string;
  }
) {
  try {
    await admin.from("ai_operator_messages").insert({
      session_id: sessionId,
      role: msg.role,
      content: msg.content ?? null,
      tool_calls: msg.tool_calls ?? null,
      tool_call_id: msg.tool_call_id ?? null,
      tool_name: msg.tool_name ?? null,
      source: msg.source ?? "web",
    });
    await admin
      .from("ai_operator_sessions")
      .update({ last_activity_at: new Date().toISOString() })
      .eq("id", sessionId);
  } catch (e) {
    console.error("[ai-operator-core] recordMessage failed", e);
  }
}

// --------------------------------------------------------------------------
// HTTP handler
// --------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (!GEMINI_API_KEY) return jr({ error: "GEMINI_API_KEY não configurada" }, 500);

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return jr({ error: "Não autenticado" }, 401);

    const sb = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user?.id) return jr({ error: "Não autenticado" }, 401);
    const userId = userData.user.id;
    const { data: profile } = await sb
      .from("app_users")
      .select("id, role, full_name, active")
      .eq("id", userId)
      .maybeSingle();
    if (!profile || profile.active === false) return jr({ error: "Usuário inativo ou não cadastrado" }, 403);
    const isAdmin = profile.role === "admin";

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "chat");

    // --------------------------------------------------------------
    // approve_action / reject_action — autorização ANTES de revelar estado
    // --------------------------------------------------------------
    // Princípio: usuários não autorizados não devem distinguir entre
    //   (a) ação inexistente,
    //   (b) ação alheia que existe e ainda está pending,
    //   (c) ação alheia já resolvida.
    // Estratégia:
    //   * approve  → admin pode aprovar qualquer pending; technician pode
    //                aprovar verify/reject de memória. Qualquer outro papel
    //                recebe 403 GENÉRICO antes de consultar a ação.
    //   * reject   → admin pode rejeitar qualquer pending; technician pode
    //                rejeitar verify/reject de memória; o solicitante pode
    //                rejeitar sua própria ação (não-memória). Usamos o
    //                helper SQL `ai_op_can_reject` que devolve false para
    //                ação inexistente, indistinguindo isso de não-autorização.
    // Em ambos os casos, a resposta de bloqueio é a MESMA mensagem 403; o
    // motivo real fica em audit (event_category='security') para forense.
    const GENERIC_RESOLVE_DENIED = "Você não pode resolver esta ação.";
    if (action === "approve_action" || action === "reject_action") {
      const pendingId = String(body.pending_action_id || "");
      if (!pendingId) return jr({ error: "pending_action_id obrigatório" }, 400);

      let pending: any = null;
      let authorized = false;

      if (action === "approve_action") {
        // Pre-authorization (atalho de papel) extraído para helper testável.
        const pre = preAuthorizeApprove(profile.role);
        if (!pre.allowedToRead) {
          await audit(admin, {
            actor_user_id: userId,
            actor_kind: "user",
            event_type: "action_approve_denied",
            event_category: "security",
            payload: { pending_action_id: pendingId, role: profile.role, reason: pre.reason },
          });
          return jr({ error: GENERIC_RESOLVE_DENIED }, 403);
        }
        // Buscar a ação só para admin/technician. Mesmo aqui, NÃO retornamos
        // 404 distintamente — qualquer falha vira o mesmo 403 genérico.
        const { data: p } = await admin
          .from("ai_operator_pending_actions")
          .select("*")
          .eq("id", pendingId)
          .maybeSingle();
        pending = p ?? null;
        if (!pending) {
          await audit(admin, {
            actor_user_id: userId,
            actor_kind: "user",
            event_type: "action_approve_denied",
            event_category: "security",
            payload: { pending_action_id: pendingId, role: profile.role, reason: "not_found" },
          });
          return jr({ error: GENERIC_RESOLVE_DENIED }, 403);
        }
        const okApprove = await canApprove(admin, userId, pending.action_name);
        authorized = okApprove;
        if (!authorized) {
          await audit(admin, {
            session_id: pending.session_id,
            pending_action_id: pendingId,
            actor_user_id: userId,
            actor_kind: "user",
            event_type: "action_approve_denied",
            event_category: "security",
            payload: { action: pending.action_name, role: profile.role, reason: "scope" },
          });
          return jr({ error: GENERIC_RESOLVE_DENIED }, 403);
        }
      } else {
        // reject_action — autorização determinística no DB. Helper retorna
        // false tanto para "ação inexistente" quanto para "não autorizado",
        // o que dá uma resposta uniforme ao chamador.
        const okReject = await canReject(admin, userId, pendingId);
        if (!okReject) {
          await audit(admin, {
            actor_user_id: userId,
            actor_kind: "user",
            event_type: "action_reject_denied",
            event_category: "security",
            payload: { pending_action_id: pendingId, role: profile.role, reason: "not_found_or_unauthorized" },
          });
          return jr({ error: GENERIC_RESOLVE_DENIED }, 403);
        }
        // Só agora (autorizado) lemos o restante para checar conflito de
        // estado e emitir audit com detalhes.
        const { data: p } = await admin
          .from("ai_operator_pending_actions")
          .select("*")
          .eq("id", pendingId)
          .maybeSingle();
        pending = p ?? null;
        // O helper garante existência, mas se houve corrida entre helper e
        // leitura (delete por exemplo), tratamos como denied genérico.
        if (!pending) {
          await audit(admin, {
            actor_user_id: userId,
            actor_kind: "user",
            event_type: "action_reject_denied",
            event_category: "security",
            payload: { pending_action_id: pendingId, role: profile.role, reason: "vanished" },
          });
          return jr({ error: GENERIC_RESOLVE_DENIED }, 403);
        }
        authorized = true;
      }

      // Conflito de estado só é revelado A USUÁRIOS AUTORIZADOS.
      if (pending.status !== "pending") {
        return jr({ error: `Ação já está no estado ${pending.status}` }, 409);
      }

      const now = new Date().toISOString();
      // UPDATE com retorno: protege contra corrida entre a leitura e o update.
      // Se nada foi atualizado mesmo autorizado → 409 conflict.
      if (action === "approve_action") {
        const { data: updated, error: upErr } = await admin
          .from("ai_operator_pending_actions")
          .update({ status: "approved", approved_by_user_id: userId, approved_at: now })
          .eq("id", pendingId)
          .eq("status", "pending")
          .select("id, status")
          .maybeSingle();
        if (upErr) return jr({ error: "Falha ao aprovar", details: upErr.message }, 500);
        const out = interpretPendingUpdate(updated);
        if (!out.ok) {
          await audit(admin, {
            session_id: pending.session_id,
            pending_action_id: pendingId,
            actor_user_id: userId,
            actor_kind: "user",
            event_type: "action_approve_conflict",
            event_category: "security",
            payload: { action: pending.action_name, role: profile.role },
          });
          return jr({ error: "Ação já não está em estado pending." }, out.status);
        }
        await audit(admin, {
          session_id: pending.session_id,
          pending_action_id: pendingId,
          actor_user_id: userId,
          actor_kind: "user",
          event_type: "action_approved",
          event_category: "security",
          payload: { action: pending.action_name, risk: pending.risk_level, role: profile.role },
        });
        return jr({ ok: true, status: "approved", pending_action_id: pendingId });
      } else {
        const { data: updated, error: upErr } = await admin
          .from("ai_operator_pending_actions")
          .update({ status: "rejected", rejected_by_user_id: userId, rejected_at: now })
          .eq("id", pendingId)
          .eq("status", "pending")
          .select("id, status")
          .maybeSingle();
        if (upErr) return jr({ error: "Falha ao rejeitar", details: upErr.message }, 500);
        const out = interpretPendingUpdate(updated);
        if (!out.ok) {
          await audit(admin, {
            session_id: pending.session_id,
            pending_action_id: pendingId,
            actor_user_id: userId,
            actor_kind: "user",
            event_type: "action_reject_conflict",
            event_category: "security",
            payload: { action: pending.action_name, role: profile.role },
          });
          return jr({ error: "Ação já não está em estado pending." }, out.status);
        }
        await audit(admin, {
          session_id: pending.session_id,
          pending_action_id: pendingId,
          actor_user_id: userId,
          actor_kind: "user",
          event_type: "action_rejected",
          event_category: "security",
          payload: { action: pending.action_name, risk: pending.risk_level, role: profile.role },
        });
        return jr({ ok: true, status: "rejected" });
      }
    }

    if (action === "link_draft_entities") {
      const draftId = String(body.draft_id || "");
      if (!draftId) return jr({ error: "draft_id obrigatorio" }, 400);

      const draft = await getDraftRow(admin, draftId);
      if (!draft || !draft.session_id) return jr({ error: "Rascunho nao encontrado." }, 404);
      const ownsSession = await sessionBelongsTo(admin, draft.session_id, userId, isAdmin);
      if (!ownsSession) return jr({ error: "Rascunho nao pertence ao usuario." }, 403);

      const mutationPolicy = evaluateDraftMutationPolicy({
        draftStatus: draft.status,
        operation: "ui_link_entities",
      });
      if (!mutationPolicy.ok) {
        await audit(admin, {
          session_id: draft.session_id,
          draft_id: draftId,
          actor_user_id: userId,
          actor_kind: "user",
          event_type: draftProtectedAuditEventForOperation("ui_link_entities"),
          event_category: "security",
          payload: {
            current_status: mutationPolicy.currentStatus,
            reason: mutationPolicy.reason,
          },
        });
        return jr(
          {
            error: mutationPolicy.message,
            blocked: true,
            reason: mutationPolicy.reason,
            current_status: mutationPolicy.currentStatus,
          },
          mutationPolicy.status
        );
      }

      const requestedClientId = body.client_id ? String(body.client_id) : null;
      const requestedVesselId = body.vessel_id ? String(body.vessel_id) : null;
      const refs = await validateAllReferences(sb, {
        client: requestedClientId,
        vessel: requestedVesselId,
      });
      let vesselClientId: string | null = null;
      if (requestedClientId && requestedVesselId) {
        const { data: vesselRow } = await sb
          .from("vessels")
          .select("id, client_id")
          .eq("id", requestedVesselId)
          .maybeSingle();
        vesselClientId = vesselRow?.client_id ?? null;
      }

      const selection = resolveExplicitDraftEntitySelection({
        requestedClientId,
        requestedVesselId,
        clientVisible: !requestedClientId || !!refs.client?.ok,
        vesselVisible: !requestedVesselId || !!refs.vessel?.ok,
        vesselClientId,
      });
      if (!selection.ok) {
        return jr({ error: selection.error }, selection.status);
      }

      await admin
        .from("ai_operator_drafts")
        .update({ client_id: selection.client_id, vessel_id: selection.vessel_id })
        .eq("id", draftId);
      await admin
        .from("ai_operator_sessions")
        .update({ client_id: selection.client_id, vessel_id: selection.vessel_id })
        .eq("id", draft.session_id);
      await mergeSessionMetadata(admin, draft.session_id, { active_draft_id: draftId });
      await audit(admin, {
        session_id: draft.session_id,
        draft_id: draftId,
        actor_user_id: userId,
        actor_kind: "user",
        event_type: "draft_entities_linked",
        event_category: "data",
        payload: {
          client_linked: !!selection.client_id,
          vessel_linked: !!selection.vessel_id,
        },
      });
      return jr({
        ok: true,
        draft_id: draftId,
        client_id: selection.client_id,
        vessel_id: selection.vessel_id,
      });
    }

    if (action === "create_external_quote_from_draft") {
      const draftId = String(body.draft_id || "");
      if (!draftId) return jr({ error: "draft_id obrigatorio" }, 400);

      const draft = await getDraftRow(admin, draftId);
      if (!draft || !draft.session_id) return jr({ error: "Rascunho nao encontrado." }, 404);
      const ownsSession = await sessionBelongsTo(admin, draft.session_id, userId, isAdmin);
      if (!ownsSession) return jr({ error: "Rascunho nao pertence ao usuario." }, 403);

      const existingQuote = await getFormalQuoteForDraft(admin, draftId);
      const items = await getDraftItemsForExternalQuote(admin, draftId);
      const eligibility = evaluateExternalQuoteFormalization({
        draft: draftForExternalQuote(draft, existingQuote?.id ?? null),
        itemCount: items.length,
        existingExternalQuoteId: existingQuote?.id ?? null,
        latestUserMessage: "Formalize este rascunho como orcamento no ERP.",
      });

      if (!eligibility.ok) {
        if (eligibility.reason === "already_formalized" && existingQuote) {
          await audit(admin, {
            session_id: draft.session_id,
            draft_id: draftId,
            actor_user_id: userId,
            actor_kind: "system",
            event_type: "external_quote_formalization_duplicate_suppressed",
            event_category: "data",
            payload: { existing_quote: true },
          });
          return jr({
            ok: true,
            created: false,
            existing: true,
            external_quote: minimizedExternalQuotePayload(existingQuote),
          });
        }

        await audit(admin, {
          session_id: draft.session_id,
          draft_id: draftId,
          actor_user_id: userId,
          actor_kind: "system",
          event_type: "external_quote_formalization_blocked",
          event_category: "security",
          payload: { reason: eligibility.reason },
        });
        return jr({ error: eligibility.message, blocked: true, reason: eligibility.reason }, 409);
      }

      const proposal = buildExternalQuoteFormalizationProposal({
        draft: draftForExternalQuote(draft, null),
        items,
      });
      const mapped = mapDraftItemsToExternalQuoteRows(items);
      const pendingQuestionCount = Array.isArray(draft.pending_questions) ? draft.pending_questions.length : 0;
      const knownServiceTotal = mapped.services.reduce((sum, row: any) => sum + Number(row.line_total || 0), 0);
      const knownPartTotal = mapped.parts.reduce((sum, row: any) => sum + Number(row.line_total_sale || 0), 0);
      let createdQuote: any = null;

      try {
        const { data: quote, error: quoteErr } = await admin
          .from("external_quotes")
          .insert({
            ai_operator_draft_id: draftId,
            created_by: userId,
            client_id: draft.client_id,
            vessel_id: draft.vessel_id,
            status: proposal.initial_status,
            service_type: draft.interpreted_category || draft.kind || "quote",
            problem_description: draft.title || "Orcamento formal gerado a partir de rascunho do AI Operator",
            initial_findings: draft.summary || null,
            customer_visible_report: draft.summary || null,
            internal_notes: buildFormalQuoteInternalNotes({
              draft,
              nonBillableNotes: mapped.nonBillableNotes,
              pendingQuestionCount,
            }),
            estimated_hours: draft.estimated_labor_hours ?? null,
            labor_cost_total: knownServiceTotal,
            parts_cost_total: knownPartTotal,
            travel_cost_total: 0,
            grand_total: mapped.knownGrandTotal,
            currency: "BRL",
          })
          .select("id, quote_number, status")
          .single();
        if (quoteErr) {
          if (String(quoteErr.code || "") === "23505") {
            const already = await getFormalQuoteForDraft(admin, draftId);
            if (already) {
              return jr({
                ok: true,
                created: false,
                existing: true,
                external_quote: minimizedExternalQuotePayload(already),
              });
            }
          }
          throw quoteErr;
        }
        createdQuote = quote;

        if (mapped.parts.length > 0) {
          const { error: partsErr } = await admin
            .from("external_quote_parts")
            .insert(mapped.parts.map((part) => ({ ...part, external_quote_id: quote.id })));
          if (partsErr) throw partsErr;
        }

        if (mapped.services.length > 0) {
          const { error: servicesErr } = await admin
            .from("external_quote_services")
            .insert(mapped.services.map((service) => ({ ...service, external_quote_id: quote.id })));
          if (servicesErr) throw servicesErr;
        }

        await audit(admin, {
          session_id: draft.session_id,
          draft_id: draftId,
          actor_user_id: userId,
          actor_kind: "user",
          event_type: "external_quote_formalization_created",
          event_category: "data",
          payload: {
            initial_status: proposal.initial_status,
            part_count: mapped.parts.length,
            service_count: mapped.services.length,
            pending_item_count: mapped.pendingItemCount,
            no_service_order_created: true,
          },
        });

        return jr({
          ok: true,
          created: true,
          external_quote: minimizedExternalQuotePayload(quote),
          counts: {
            parts: mapped.parts.length,
            services: mapped.services.length,
            pending_items: mapped.pendingItemCount,
            pending_questions: pendingQuestionCount,
          },
          effects: proposal.effects,
        });
      } catch (e: any) {
        if (createdQuote?.id) {
          await admin.from("external_quote_services").delete().eq("external_quote_id", createdQuote.id);
          await admin.from("external_quote_parts").delete().eq("external_quote_id", createdQuote.id);
          await admin.from("external_quotes").delete().eq("id", createdQuote.id);
        }
        await audit(admin, {
          session_id: draft.session_id,
          draft_id: draftId,
          actor_user_id: userId,
          actor_kind: "system",
          event_type: "external_quote_formalization_failed",
          event_category: "error",
          payload: { error: e?.message || "unknown", rolled_back: !!createdQuote?.id },
        });
        return jr({ error: "Falha ao criar orcamento formal", details: e?.message || "erro desconhecido" }, 500);
      }
    }

    // --------------------------------------------------------------
    // cancel_draft — fluxo seguro para rascunhos criados incorretamente.
    // Permite cancelar apenas drafts em estados compativeis com erro
    // operacional (draft, awaiting_info) e sem pending_actions em status
    // pending. Estados de governanca/conversao (approved/rejected/converted/
    // awaiting_approval) NUNCA podem ser cancelados silenciosamente.
    // --------------------------------------------------------------
    if (action === "cancel_draft") {
      const draftId = String(body.draft_id || "");
      if (!draftId) return jr({ error: "draft_id obrigatorio" }, 400);

      const draft = await getDraftRow(admin, draftId);
      if (!draft) return jr({ error: "Rascunho nao encontrado." }, 404);
      if (!draft.session_id) return jr({ error: "Rascunho sem sessao associada." }, 409);
      const ownsSession = await sessionBelongsTo(admin, draft.session_id, userId, isAdmin);
      if (!ownsSession) return jr({ error: "Rascunho nao pertence ao usuario." }, 403);

      const { count: pendingCount } = await admin
        .from("ai_operator_pending_actions")
        .select("id", { count: "exact", head: true })
        .eq("draft_id", draftId)
        .eq("status", "pending");

      const check = evaluateCancelDraft({
        draftStatus: draft.status,
        pendingOpenCount: pendingCount ?? 0,
      });
      if (!check.ok) {
        await audit(admin, {
          session_id: draft.session_id,
          draft_id: draftId,
          actor_user_id: userId,
          actor_kind: "user",
          event_type: "draft_cancel_denied",
          event_category: "security",
          payload: { reason: check.reason },
        });
        const message =
          check.reason === "invalid_status"
            ? `Rascunho em status '${check.currentStatus}' nao pode ser cancelado nesta fase.`
            : check.reason === "pending_actions_open"
              ? `Rascunho possui ${check.openCount} acao(oes) pendente(s). Resolva ou rejeite antes de cancelar.`
              : "Rascunho nao encontrado.";
        return jr({ error: message, reason: check.reason }, check.status);
      }

      const reason = typeof body.reason === "string" ? body.reason.trim().slice(0, 500) : "";
      const draftMetadata =
        draft.metadata && typeof draft.metadata === "object" ? (draft.metadata as Record<string, unknown>) : {};
      const cancelMetadata = {
        ...draftMetadata,
        cancelled_at: new Date().toISOString(),
        cancelled_by: userId,
        cancellation_reason: reason || null,
      };
      const { error: cancelErr } = await admin
        .from("ai_operator_drafts")
        .update({ status: "cancelled", metadata: cancelMetadata })
        .eq("id", draftId);
      if (cancelErr) {
        return jr({ error: "Falha ao cancelar rascunho", details: cancelErr.message }, 500);
      }
      await audit(admin, {
        session_id: draft.session_id,
        draft_id: draftId,
        actor_user_id: userId,
        actor_kind: "user",
        event_type: "draft_cancelled",
        event_category: "data",
        payload: { reason: reason || null, previous_status: draft.status },
      });
      return jr({ ok: true, draft_id: draftId, status: "cancelled" });
    }

    // --------------------------------------------------------------
    // resume_draft — retoma a sessão original de um draft existente selecionado
    // exclusivamente pela UI (seleção humana). O modelo nunca escolhe draft_id
    // nem session_id: eles chegam da seleção explícita na interface.
    // Dupla validação: RLS via JWT (visibilidade) + sessionBelongsTo admin
    // (ownership). Devolve o session_id original autorizado para o frontend
    // substituir o session_id atual do widget pelo correto.
    // --------------------------------------------------------------
    if (action === "resume_draft") {
      const draftId = String(body.draft_id || "");
      if (!draftId) return jr({ error: "draft_id obrigatorio" }, 400);

      // Visibilidade via JWT do usuário (RLS real do ERP). Não revela diferença
      // entre "não existe" e "não visível" — ambos resultam em 404 genérico.
      const { data: draftVisible } = await sb
        .from("ai_operator_drafts")
        .select("id, session_id, title, status")
        .eq("id", draftId)
        .maybeSingle();
      if (!draftVisible || !draftVisible.session_id) {
        return jr({ error: "Rascunho nao encontrado ou nao visivel." }, 404);
      }

      // Ownership da sessão via admin (bypass RLS para verificação direta).
      const ownsSession = await sessionBelongsTo(admin, draftVisible.session_id, userId, isAdmin);
      if (!ownsSession) {
        await audit(admin, {
          draft_id: draftId,
          actor_user_id: userId,
          actor_kind: "user",
          event_type: "draft_resume_denied",
          event_category: "security",
          payload: { session_id: draftVisible.session_id, role: profile.role },
        });
        return jr({ error: "Rascunho nao pertence ao usuario." }, 403);
      }

      // Garante que a sessão original aponta para este draft como ativo.
      await mergeSessionMetadata(admin, draftVisible.session_id, { active_draft_id: draftId });
      await audit(admin, {
        session_id: draftVisible.session_id,
        draft_id: draftId,
        actor_user_id: userId,
        actor_kind: "user",
        event_type: "draft_resumed",
        event_category: "info",
        payload: { draft_title: draftVisible.title ?? null, draft_status: draftVisible.status ?? null },
      });

      return jr({
        ok: true,
        session_id: draftVisible.session_id,
        draft_id: draftId,
        draft_title: draftVisible.title ?? null,
      });
    }

    // --------------------------------------------------------------
    // Memory governance — verify_memory_note / reject_memory_note
    // --------------------------------------------------------------
    if (action === "verify_memory_note" || action === "reject_memory_note") {
      const noteId = String(body.memory_note_id || "");
      if (!noteId) return jr({ error: "memory_note_id obrigatório" }, 400);
      const ok = await canApprove(admin, userId, action);
      if (!ok) {
        await audit(admin, {
          actor_user_id: userId,
          actor_kind: "user",
          event_type: action === "verify_memory_note" ? "memory_verify_denied" : "memory_reject_denied",
          event_category: "security",
          payload: { role: profile.role, memory_note_id: noteId },
        });
        return jr({ error: "Seu papel não pode promover/rejeitar memória técnica." }, 403);
      }
      const now = new Date().toISOString();
      const newStatus = action === "verify_memory_note" ? "verified" : "rejected";
      const updatePayload =
        action === "verify_memory_note"
          ? { verification_status: "verified", verified_by: userId, verified_at: now }
          : { verification_status: "rejected", rejected_by: userId, rejected_at: now };

      const { data: updatedNote, error: upErr } = await admin
        .from("ai_operator_memory_notes")
        .update(updatePayload)
        .eq("id", noteId)
        .eq("verification_status", "candidate")
        .select("id, verification_status")
        .maybeSingle();
      if (upErr) {
        return jr({ error: `Falha ao ${newStatus} nota`, details: upErr.message }, 500);
      }
      {
        // Confirmação determinística via helper testável. Se não atualizou,
        // checamos se a nota existe (404) ou está em outro estado (409).
        let existing: { verification_status: string } | null = null;
        if (!updatedNote) {
          const { data: existingRow } = await admin
            .from("ai_operator_memory_notes")
            .select("id, verification_status")
            .eq("id", noteId)
            .maybeSingle();
          existing = existingRow ?? null;
        }
        const out = interpretMemoryUpdate(updatedNote, existing);
        if (!out.ok) {
          const event =
            action === "verify_memory_note" ? "memory_verify_conflict" : "memory_reject_conflict";
          await audit(admin, {
            actor_user_id: userId,
            actor_kind: "user",
            event_type: event,
            event_category: "security",
            payload: {
              memory_note_id: noteId,
              role: profile.role,
              existing_status: existing?.verification_status ?? null,
            },
          });
          if (out.reason === "not_found") return jr({ error: "Nota de memória não encontrada." }, 404);
          return jr({ error: `Nota já está em estado ${out.existingStatus}.` }, out.status);
        }
      }
      await audit(admin, {
        actor_user_id: userId,
        actor_kind: "user",
        event_type: action === "verify_memory_note" ? "memory_verified" : "memory_rejected",
        event_category: "security",
        payload: { memory_note_id: noteId, role: profile.role },
      });
      return jr({ ok: true, status: newStatus });
    }

    // --------------------------------------------------------------
    // chat (default)
    // --------------------------------------------------------------
    const incoming = Array.isArray(body.messages) ? body.messages : [];
    const latestMessageText =
      typeof body.message === "string"
        ? body.message
        : String([...incoming].reverse().find((m: any) => m.role === "user")?.content || "");
    const clientCtx = body.context || {};

    // Procedência de canal FIXADA via helper testável (ver channel-source.ts).
    // Esta Edge Function é o único endpoint autenticado por JWT do operator
    // nesta fase, acionado pela interface web. Canais futuros (WhatsApp etc.)
    // entrarão por endpoints dedicados — não por este corpo.
    const channelInfo = resolveCoreChannel(body.channel);
    const channel = channelInfo.enforced; // "web"
    const channelSpoofAttempt = channelInfo.spoofAttempt;
    const declaredChannel = channelInfo.declared;

    let sessionId: string | null = body.session_id || null;

    const { data: settingsRows } = await admin.from("app_settings").select("key, value");
    const settings: Record<string, string> = {};
    (settingsRows || []).forEach((r: any) => {
      if (r.key) settings[r.key] = String(r.value ?? "");
    });

    // Cria/recupera sessão com validação de ownership
    if (sessionId) {
      const ok = await sessionBelongsTo(admin, sessionId, userId, isAdmin);
      if (!ok) {
        await audit(admin, {
          actor_user_id: userId,
          actor_kind: "user",
          event_type: "session_access_denied",
          event_category: "security",
          payload: { session_id: sessionId, role: profile.role },
        });
        return jr({ error: "Sessão não pertence ao usuário." }, 403);
      }
      if (channelSpoofAttempt) {
        await audit(admin, {
          session_id: sessionId,
          actor_user_id: userId,
          actor_kind: "system",
          event_type: "channel_spoof_attempted",
          event_category: "security",
          payload: { declared: declaredChannel, enforced: "web" },
        });
      }
    } else {
      // Valida referências contextuais (client/vessel/service_order) com RLS
      // real do usuário. Refs invisíveis são DESCARTADAS e auditadas — a
      // sessão é criada sem vínculo (não vaza diferença entre inexistente
      // e oculto por RLS).
      const ctxRefs: Partial<Record<"client" | "vessel" | "service_order", string>> = {};
      if (clientCtx.entityType === "client" && clientCtx.entityId) ctxRefs.client = clientCtx.entityId;
      if (clientCtx.entityType === "vessel" && clientCtx.entityId) ctxRefs.vessel = clientCtx.entityId;
      if (clientCtx.entityType === "service_order" && clientCtx.entityId)
        ctxRefs.service_order = clientCtx.entityId;
      const ctxResults = await validateAllReferences(sb, ctxRefs);
      const safeCtxClient = ctxResults.client?.ok ? ctxRefs.client : null;
      const safeCtxVessel = ctxResults.vessel?.ok ? ctxRefs.vessel : null;
      const safeCtxSO = ctxResults.service_order?.ok ? ctxRefs.service_order : null;

      const { data: created, error: sErr } = await admin
        .from("ai_operator_sessions")
        .insert({
          // Sempre 'web' nesta Edge Function — vide bloco "procedência de canal".
          channel: "web",
          channel_provider: "web",
          owner_user_id: userId,
          client_id: safeCtxClient ?? null,
          vessel_id: safeCtxVessel ?? null,
          service_order_id: safeCtxSO ?? null,
          metadata: { route: clientCtx.route || null },
        })
        .select("id")
        .single();
      if (sErr) return jr({ error: "Falha ao abrir sessão", details: sErr.message }, 500);
      sessionId = created.id;
      await audit(admin, {
        session_id: sessionId,
        actor_user_id: userId,
        actor_kind: "user",
        event_type: "session_opened",
        payload: { channel: "web", route: clientCtx.route || null },
      });
      if (channelSpoofAttempt) {
        await audit(admin, {
          session_id: sessionId,
          actor_user_id: userId,
          actor_kind: "system",
          event_type: "channel_spoof_attempted",
          event_category: "security",
          payload: { declared: declaredChannel, enforced: "web" },
        });
      }
      for (const [k, r] of Object.entries(ctxResults)) {
        if (r && !r.ok) {
          await audit(admin, {
            session_id: sessionId,
            actor_user_id: userId,
            actor_kind: "system",
            event_type: "entity_reference_blocked",
            event_category: "security",
            payload: { tool: "open_session_context", kind: k, reason: r.reason },
          });
        }
      }
    }

    if (latestMessageText) {
      await recordMessage(admin, sessionId!, {
        role: "user",
        content: latestMessageText,
        source: channel,
      });
    }

    const now = new Date();
    const dateStr = now.toLocaleDateString("pt-BR", {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric",
    });
    const timeStr = now.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
    const entityContext = clientCtx.entityType
      ? `${clientCtx.entityType}${clientCtx.entityId ? ` (id interno presente)` : ""}`
      : "nenhum";
    const currentSession = await getSessionRow(admin, sessionId!);
    let activeDraft = await findActiveDraft(admin, sessionId!, body.draft_id ? String(body.draft_id) : null);
    let draftCandidatesForFrontend: DraftCandidateForSelection[] | null = null;

    if (!activeDraft && latestMessageText) {
      // Classificação determinística: distingue nova demanda de operação sobre
      // draft existente. Bootstrap só dispara em new_demand puro — referências
      // a rascunho existente (vincule/cancele/aquele orcamento/do <Nome>)
      // bloqueiam bootstrap mesmo quando a mensagem cita "orcamento" ou
      // "instalacao".
      const classification = classifyMessage(latestMessageText);

      if (classification.type === "operate_on_existing") {
        const candidates = await findDraftCandidatesForSelection(sb, { limit: 5 });
        await audit(admin, {
          session_id: sessionId,
          actor_user_id: userId,
          actor_kind: "system",
          event_type: "draft_selection_requested",
          event_category: "data",
          payload: {
            reference_kind: classification.reference.kind,
            reference_matched: classification.reference.matched,
            candidate_count: candidates.length,
          },
        });
        await recordMessage(admin, sessionId!, {
          role: "assistant",
          content:
            candidates.length > 0
              ? "Identifiquei que voce quer operar sobre um rascunho existente. Selecione abaixo qual rascunho deseja continuar."
              : "Voce mencionou um rascunho existente, mas nao encontrei rascunhos ativos seus para selecionar.",
          source: channel,
        });
        draftCandidatesForFrontend = candidates;
        return jr({
          ok: true,
          session_id: sessionId,
          message: {
            role: "assistant",
            content:
              candidates.length > 0
                ? "Identifiquei que voce quer operar sobre um rascunho existente. Selecione abaixo qual rascunho deseja continuar."
                : "Voce mencionou um rascunho existente, mas nao encontrei rascunhos ativos seus para selecionar.",
          },
          draft_id: null,
          draft_candidates: draftCandidatesForFrontend,
          reference_kind: classification.reference.kind,
        });
      }

      if (classification.type === "new_demand") {
        const detectedIntent = classification.intent;
        const bootstrap = buildBootstrapDraft(detectedIntent, { message: latestMessageText });
        const { data: createdBootstrap, error: bootstrapError } = await admin
          .from("ai_operator_drafts")
          .insert({
            session_id: sessionId,
            created_by: userId,
            kind: bootstrap.kind,
            status: bootstrap.status,
            title: bootstrap.title,
            summary: bootstrap.summary,
            client_id: currentSession?.client_id ?? null,
            vessel_id: currentSession?.vessel_id ?? null,
            interpreted_intent: bootstrap.interpreted_intent,
            interpreted_category: bootstrap.interpreted_category,
            pending_questions: bootstrap.pending_questions,
            next_steps: bootstrap.next_steps,
            hypotheses: bootstrap.hypotheses,
          })
          .select()
          .single();
        if (bootstrapError) {
          return jr({ error: "Falha ao criar rascunho inicial", details: bootstrapError.message }, 500);
        }
        if (bootstrap.items.length > 0) {
          await admin.from("ai_operator_draft_items").insert(
            bootstrap.items.map((item, index) => ({
              draft_id: createdBootstrap.id,
              item_kind: item.item_kind,
              description: item.description,
              notes: item.notes || null,
              quantity: item.quantity ?? 1,
              unit: item.unit || "unit",
              estimated_total: item.estimated_total ?? null,
              position: index + 1,
              confidence: "medium",
            }))
          );
        }
        await mergeSessionMetadata(admin, sessionId!, { active_draft_id: createdBootstrap.id });
        await audit(admin, {
          session_id: sessionId,
          draft_id: createdBootstrap.id,
          actor_user_id: userId,
          actor_kind: "system",
          event_type: "draft_bootstrap_created",
          event_category: "data",
          payload: { kind: bootstrap.kind, status: bootstrap.status },
        });
        activeDraft = await findActiveDraft(admin, sessionId!, createdBootstrap.id);
      }
    }

    if (activeDraft && latestMessageText && isInformationalActionRequest(latestMessageText)) {
      const [freshDraft, items, formalQuote] = await Promise.all([
        getDraftRow(admin, activeDraft.id),
        getDraftItemsForExternalQuote(admin, activeDraft.id),
        getFormalQuoteForDraft(admin, activeDraft.id),
      ]);
      const officialServiceOrder = freshDraft ? await getOfficialServiceOrderForDraft(admin, freshDraft) : null;
      if (freshDraft) {
        const content = buildGroundedInformationalResponse({
          draft: draftForExternalQuote(freshDraft, formalQuote?.id ?? null),
          itemCount: items.length,
          pendingQuestionCount: Array.isArray(freshDraft.pending_questions) ? freshDraft.pending_questions.length : 0,
          formalQuote,
          officialServiceOrder,
        });
        await recordMessage(admin, sessionId!, { role: "assistant", content, source: channel });
        await audit(admin, {
          session_id: sessionId,
          draft_id: freshDraft.id,
          actor_user_id: userId,
          actor_kind: "system",
          event_type: "grounded_informational_response",
          event_category: "info",
          payload: {
            draft_status: freshDraft.status ?? null,
            formal_quote_exists: !!formalQuote,
            service_order_exists: !!officialServiceOrder,
          },
        });
        return jr({
          ok: true,
          session_id: sessionId,
          message: { role: "assistant", content },
          draft_id: freshDraft.id,
          tool_events: [],
        });
      }
    }

    const systemPrompt = buildSystemPrompt({
      userName: profile.full_name || "Usuário",
      userRole: profile.role || "user",
      dateStr,
      timeStr,
      companyName: settings.company_name || "HBR Marine",
      defaultHourlyRate: settings.default_hourly_rate || "200",
      diagnosticHourlyRate: settings.diagnostic_hourly_rate || "300",
      costPerKm: settings.cost_per_km || "0",
      defaultProfitMargin: settings.default_profit_margin || "30",
      channel,
      routeOrChannel: clientCtx.route || channel,
      entityContext,
    });

    const { data: persistedMessages } = await admin
      .from("ai_operator_messages")
      .select("role, content")
      .eq("session_id", sessionId!)
      .order("created_at");
    const draftContextNote = activeDraft ? await buildActiveDraftContext(admin, activeDraft.id) : null;
    const messages: any[] = [{ role: "system", content: systemPrompt }];
    if (draftContextNote) {
      messages.push({
        role: "system",
        content:
          `${draftContextNote}\n\nUse este rascunho ativo como fonte de continuidade. ` +
          `Se precisar refinar o mesmo atendimento, prefira update_draft e add_draft_item.`,
      });
    }
    messages.push(...toModelConversationHistory((persistedMessages as any[]) || []));
    const toolEvents: any[] = [];
    let createdDraftId: string | null = activeDraft?.id ?? null;
    let pendingActionForFrontend: any = null;
    let linkProposalForFrontend: any = null;
    let quoteProposalForFrontend: any = null;

    for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
      const fetchResult = await fetchAIWithRetry(
        `${GEMINI_BASE_URL}/chat/completions`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${GEMINI_API_KEY}`, "Content-Type": "application/json" },
          body: JSON.stringify({ model: MODEL, messages, tools: OPERATOR_TOOLS, tool_choice: "auto" }),
        },
        { maxRetries: iter === 0 ? 2 : 0, fallbackModel: MODEL_FAST_FALLBACK }
      );
      if (!fetchResult.ok) {
        console.error("[ai-operator-core] gateway error", fetchResult.response.status, fetchResult.rawBody.slice(0, 200));
        if (fetchResult.classification === "provider_overloaded") {
          return jr({ error: resolveOverloadUserMessage(iter) }, 503);
        }
        if (fetchResult.classification === "rate_limit") {
          return jr({ error: resolveRateLimitUserMessage(iter) }, 429);
        }
        if (fetchResult.classification === "billing") {
          return jr({ error: "Créditos da IA esgotados. Verifique as configurações de faturamento." }, 402);
        }
        if (fetchResult.classification === "permission") {
          return jr({ error: "Permissão negada pelo provedor de IA. Verifique as configurações de API key e faturamento." }, 403);
        }
        return jr({ error: `Gateway de IA falhou (${fetchResult.response.status})` }, 500);
      }
      const aiJson = await fetchResult.response.json();
      const choice = aiJson.choices?.[0];
      const aiMsg = choice?.message;
      if (!aiMsg) return jr({ error: "Resposta vazia do modelo" }, 500);
      messages.push(aiMsg);

      const toolCalls = aiMsg.tool_calls || [];
      if (toolCalls.length === 0) {
        const finalContent = redactUuidTokens(aiMsg.content || "");
        await recordMessage(admin, sessionId!, { role: "assistant", content: finalContent, source: channel });
        return jr({
          ok: true,
          session_id: sessionId,
          message: { role: "assistant", content: finalContent },
          draft_id: createdDraftId,
          pending_action: pendingActionForFrontend,
          proposed_link: linkProposalForFrontend,
          quote_proposal: quoteProposalForFrontend,
          tool_events: sanitizeToolEventsForFrontend(toolEvents),
        });
      }

      for (const tc of toolCalls) {
        const fnName = String(tc.function?.name || "");
        let fnArgs: any = {};
        try {
          fnArgs = JSON.parse(tc.function?.arguments || "{}");
        } catch {
          fnArgs = {};
        }

        if (fnName === "propose_external_quote_from_draft") {
          const targetDraftId = createdDraftId;
          if (!targetDraftId) {
            const blocked = {
              blocked: true,
              reason: "no_active_draft",
              message: "Nao ha rascunho ativo para formalizar como orcamento.",
            };
            toolEvents.push({ name: fnName, args: {}, result: blocked, blocked: true });
            messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(blocked) });
            continue;
          }

          const [draft, items, formalQuote] = await Promise.all([
            getDraftRow(admin, targetDraftId),
            getDraftItemsForExternalQuote(admin, targetDraftId),
            getFormalQuoteForDraft(admin, targetDraftId),
          ]);
          const eligibility = evaluateExternalQuoteFormalization({
            draft: draft ? draftForExternalQuote(draft, formalQuote?.id ?? null) : null,
            itemCount: items.length,
            existingExternalQuoteId: formalQuote?.id ?? null,
            latestUserMessage: latestMessageText,
          });

          if (!eligibility.ok) {
            await audit(admin, {
              session_id: sessionId,
              draft_id: targetDraftId,
              actor_user_id: userId,
              actor_kind: "system",
              event_type: "external_quote_formalization_proposal_blocked",
              event_category: eligibility.reason === "informational_request" ? "info" : "security",
              payload: { reason: eligibility.reason },
            });
            const blocked = {
              blocked: true,
              reason: eligibility.reason,
              message: eligibility.message,
              existing_external_quote_id: eligibility.existingExternalQuoteId ?? null,
            };
            toolEvents.push({ name: fnName, args: {}, result: blocked, blocked: true });
            messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(blocked) });
            continue;
          }

          quoteProposalForFrontend = buildExternalQuoteFormalizationProposal({
            draft: draftForExternalQuote(draft, null),
            items,
          });
          const toolResult = {
            ok: true,
            proposed: true,
            persisted: false,
            requires_user_confirmation: true,
            initial_status: quoteProposalForFrontend.initial_status,
            item_count: quoteProposalForFrontend.item_count,
            part_count: quoteProposalForFrontend.part_count,
            service_count: quoteProposalForFrontend.service_count,
            pending_item_count: quoteProposalForFrontend.pending_item_count,
            pending_questions_count: quoteProposalForFrontend.pending_questions_count,
            creates_service_order: false,
          };
          toolEvents.push({ name: fnName, args: {}, result: toolResult });
          messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(toolResult) });
          await audit(admin, {
            session_id: sessionId,
            draft_id: targetDraftId,
            actor_user_id: userId,
            actor_kind: "ai_model",
            event_type: "external_quote_formalization_proposed",
            event_category: "data",
            payload: {
              initial_status: quoteProposalForFrontend.initial_status,
              part_count: quoteProposalForFrontend.part_count,
              service_count: quoteProposalForFrontend.service_count,
              pending_item_count: quoteProposalForFrontend.pending_item_count,
            },
          });
          continue;
        }

        if (fnName === "propose_action") {
          const proposedAction = String(fnArgs.action || "unknown");
          const proposedRisk = classifyAction(proposedAction);

          // Validar draft_id em propose_action via helper testável.
          const draftRes = await resolveProposalDraftId({
            requestedDraftId: createdDraftId ? null : (fnArgs.draft_id ?? null),
            createdDraftIdThisRun: createdDraftId,
            currentSessionId: sessionId!,
            lookup: async (id) => {
              const { data } = await admin
                .from("ai_operator_drafts")
                .select("id, session_id")
                .eq("id", id)
                .maybeSingle();
              return data ?? null;
            },
          });
          if (!draftRes.ok) {
            await audit(admin, {
              session_id: sessionId,
              actor_user_id: userId,
              actor_kind: "system",
              event_type: "propose_action_blocked_foreign_draft",
              event_category: "security",
              payload: { proposed_action: proposedAction, requested_draft_id: draftRes.requestedDraftId },
            });
            const blocked = {
              blocked: true,
              reason: "draft_id referenciado não pertence à sessão atual; proposta recusada.",
            };
            toolEvents.push({ name: fnName, args: fnArgs, result: blocked, blocked: true });
            messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(blocked) });
            continue;
          }
          const proposalDraftId = draftRes.draftId;
          const { data: proposalDraft } = proposalDraftId
            ? await admin
                .from("ai_operator_drafts")
                .select("id, session_id, kind, status")
                .eq("id", proposalDraftId)
                .maybeSingle()
            : { data: null };
          const { data: duplicateRows } = proposalDraftId
            ? await admin
                .from("ai_operator_pending_actions")
                .select("id, draft_id, action_name, status, executed_at")
                .eq("draft_id", proposalDraftId)
                .eq("action_name", proposedAction)
                .in("status", ["pending", "approved"])
                .is("executed_at", null)
                .limit(5)
            : { data: [] };
          const duplicateAction = findOpenEquivalentPendingAction(
            (duplicateRows || []) as any[],
            proposalDraftId,
            proposedAction
          );
          const actionGate = evaluateActionProposalGovernance({
            latestUserMessage: latestMessageText,
            actionName: proposedAction,
            draft: proposalDraft
              ? { id: proposalDraft.id, kind: proposalDraft.kind ?? null }
              : proposalDraftId
                ? { id: proposalDraftId, kind: null }
                : null,
            duplicate: duplicateAction,
          });
          if (!actionGate.ok) {
            await audit(admin, {
              session_id: sessionId,
              draft_id: proposalDraftId,
              pending_action_id: actionGate.existingActionId ?? null,
              actor_user_id: userId,
              actor_kind: "system",
              event_type: actionGate.auditEvent,
              event_category: "security",
              payload: { action: proposedAction, reason: actionGate.reason },
            });
            const blocked = {
              blocked: true,
              reason: actionGate.reason,
              message: actionGate.message,
              existing_action_id: actionGate.existingActionId ?? null,
            };
            toolEvents.push({ name: fnName, args: fnArgs, result: blocked, blocked: true });
            messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(blocked) });
            continue;
          }

          const { data: pending, error: pErr } = await admin
            .from("ai_operator_pending_actions")
            .insert({
              session_id: sessionId,
              draft_id: proposalDraftId,
              requested_by_user_id: userId,
              action_name: proposedAction,
              risk_level: proposedRisk.level,
              risk_reason: proposedRisk.reason,
              title: fnArgs.title || proposedAction,
              summary: fnArgs.summary_markdown || null,
              payload: fnArgs.payload || {},
              status: "pending",
            })
            .select()
            .single();
          if (pErr) {
            await audit(admin, {
              session_id: sessionId,
              actor_user_id: userId,
              actor_kind: "system",
              event_type: "pending_action_insert_failed",
              event_category: "error",
              payload: { error: pErr.message, action: proposedAction },
            });
            return jr({ error: "Falha ao registrar ação pendente", details: pErr.message }, 500);
          }
          await audit(admin, {
            session_id: sessionId,
            pending_action_id: pending.id,
            actor_user_id: userId,
            actor_kind: "ai_model",
            event_type: "action_proposed",
            event_category: "security",
            payload: { action: proposedAction, risk: proposedRisk.level },
          });
          pendingActionForFrontend = {
            id: pending.id,
            action: proposedAction,
            risk_level: proposedRisk.level,
            risk_reason: proposedRisk.reason,
            title: pending.title,
            summary_markdown: fnArgs.summary_markdown || "",
            payload: fnArgs.payload || {},
          };
          await recordMessage(admin, sessionId!, {
            role: "assistant",
            content: redactUuidTokens(aiMsg.content || ""),
            tool_calls: aiMsg.tool_calls,
            source: channel,
          });
          await recordMessage(admin, sessionId!, {
            role: "tool",
            tool_call_id: tc.id,
            tool_name: fnName,
            content: JSON.stringify({ ok: true, pending_action_id: pending.id }),
            source: channel,
          });
          return jr({
            ok: true,
            session_id: sessionId,
            message: { role: "assistant", content: redactUuidTokens(aiMsg.content || "") },
            draft_id: createdDraftId,
            pending_action: pendingActionForFrontend,
            proposed_link: linkProposalForFrontend,
            quote_proposal: quoteProposalForFrontend,
            tool_events: sanitizeToolEventsForFrontend(toolEvents),
          });
        }

        if (fnName === "propose_entity_link") {
          const targetDraftIdV2 = createdDraftId;
          const clientQuery = typeof fnArgs.client_query === "string" ? fnArgs.client_query.trim() : null;
          const vesselQuery = typeof fnArgs.vessel_query === "string" ? fnArgs.vessel_query.trim() : null;
          const safeToolArgs = { has_client_query: !!clientQuery, has_vessel_query: !!vesselQuery };

          if (!targetDraftIdV2) {
            const blocked = {
              blocked: true,
              reason:
                "Nao ha rascunho ativo na sessao. Peca ao usuario para selecionar um rascunho existente antes de propor vinculo.",
            };
            toolEvents.push({ name: fnName, args: safeToolArgs, result: blocked, blocked: true });
            messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(blocked) });
            await audit(admin, {
              session_id: sessionId,
              actor_user_id: userId,
              actor_kind: "system",
              event_type: "link_proposal_blocked_no_draft",
              event_category: "security",
              payload: safeToolArgs,
            });
            continue;
          }

          const [draftRowV2, clientCandidates, vesselCandidates] = await Promise.all([
            getDraftRow(admin, targetDraftIdV2),
            clientQuery ? searchClientRowsForLink(sb, clientQuery) : Promise.resolve([]),
            vesselQuery ? searchVesselRowsForLink(sb, vesselQuery) : Promise.resolve([]),
          ]);
          const resolution = resolveEntityLinkByHumanTerms({
            draftId: targetDraftIdV2,
            draftTitle: draftRowV2?.title ?? null,
            clientQuery,
            vesselQuery,
            clientCandidates,
            vesselCandidates,
            rationale: typeof fnArgs.rationale === "string" ? fnArgs.rationale : null,
          });

          if (!resolution.ok) {
            const blocked = { blocked: true, reason: resolution.message, code: resolution.reason };
            if (resolution.reason === "client_ambiguous" || resolution.reason === "vessel_ambiguous") {
              linkProposalForFrontend = {
                draft_id: targetDraftIdV2,
                draft_title: draftRowV2?.title ?? null,
                client: null,
                vessel: null,
                client_candidates: resolution.clientCandidates ?? [],
                vessel_candidates: resolution.vesselCandidates ?? [],
                compatibility: {
                  status: "needs_selection",
                  message: resolution.message,
                },
                rationale: typeof fnArgs.rationale === "string" ? fnArgs.rationale : null,
              };
            }
            toolEvents.push({ name: fnName, args: safeToolArgs, result: blocked, blocked: true });
            messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(blocked) });
            await audit(admin, {
              session_id: sessionId,
              draft_id: targetDraftIdV2,
              actor_user_id: userId,
              actor_kind: "system",
              event_type: "link_proposal_blocked",
              event_category: "security",
              payload: { reason: resolution.reason },
            });
            continue;
          }

          linkProposalForFrontend = resolution.proposal;
          const toolResult = {
            ok: true,
            proposed: true,
            persisted: false,
            requires_user_confirmation: true,
            draft_title: resolution.proposal.draft_title,
            client_name: resolution.proposal.client?.name ?? null,
            vessel_name: resolution.proposal.vessel?.name ?? null,
            compatibility: resolution.proposal.compatibility.message,
          };
          toolEvents.push({ name: fnName, args: safeToolArgs, result: toolResult });
          messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(toolResult) });
          await audit(admin, {
            session_id: sessionId,
            draft_id: targetDraftIdV2,
            actor_user_id: userId,
            actor_kind: "ai_model",
            event_type: "link_proposal_presented",
            event_category: "data",
            payload: {
              client_proposed: !!resolution.proposal.client,
              vessel_proposed: !!resolution.proposal.vessel,
              compatibility: resolution.proposal.compatibility.status,
            },
          });
          continue;
        }

        const risk = classifyAction(fnName);
        if (risk.requires_approval) {
          await audit(admin, {
            session_id: sessionId,
            actor_user_id: userId,
            actor_kind: "system",
            event_type: "tool_call_blocked",
            event_category: "security",
            payload: { action: fnName, risk: risk.level, reason: risk.reason },
          });
          const blocked = {
            blocked: true,
            reason: `A ação "${fnName}" é sensível (${risk.level}). Use propose_action.`,
          };
          toolEvents.push({ name: fnName, args: fnArgs, result: blocked, blocked: true });
          messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(blocked) });
          continue;
        }

        let toolResult: any;
        try {
          const exec = await execSafeTool(fnName, fnArgs, { sb, admin, userId, sessionId: sessionId!, activeDraftId: createdDraftId });
          toolResult = exec.result;
          if (exec.draftId && !createdDraftId) createdDraftId = exec.draftId;
        } catch (e: any) {
          toolResult = { error: e?.message || "Falha na execução da tool segura" };
          await audit(admin, {
            session_id: sessionId,
            actor_user_id: userId,
            actor_kind: "system",
            event_type: "safe_tool_failed",
            event_category: "error",
            payload: { action: fnName, error: toolResult.error },
          });
        }
        toolEvents.push({ name: fnName, args: fnArgs, result: toolResult });
        messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(toolResult) });
        await audit(admin, {
          session_id: sessionId,
          draft_id: createdDraftId,
          actor_user_id: userId,
          actor_kind: "ai_model",
          event_type: "safe_tool_executed",
          event_category: "data",
          payload: { action: fnName, args_keys: Object.keys(fnArgs) },
        });
      }
    }

    return jr({ error: "Limite de iterações atingido" }, 500);
  } catch (e: any) {
    console.error("[ai-operator-core] error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

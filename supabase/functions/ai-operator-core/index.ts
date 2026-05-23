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
import { classifyAction } from "./risk.ts";
import { OPERATOR_TOOLS } from "./tools.ts";
import { buildSystemPrompt } from "./prompt.ts";
import { validateAllReferences } from "./entity-validation.ts";
import { resolveProposalDraftId } from "./proposal.ts";
import { interpretPendingUpdate, interpretMemoryUpdate } from "./transitions.ts";
import { resolveCoreChannel } from "./channel-source.ts";
import { preAuthorizeApprove } from "./approve-guard.ts";

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
const MAX_ITERATIONS = 6;

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
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

// --------------------------------------------------------------------------
// Safe-tool executors
// --------------------------------------------------------------------------
async function execSafeTool(
  name: string,
  args: any,
  ctx: { sb: any; admin: any; userId: string; sessionId: string }
): Promise<{ result: any; draftId?: string | null }> {
  const { sb, admin, userId, sessionId } = ctx;

  switch (name) {
    case "search_clients": {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("clients")
        .select("id, full_name_or_company_name, type, phone, whatsapp, email, cpf_cnpj")
        .or(
          `full_name_or_company_name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%,whatsapp.ilike.%${q}%,cpf_cnpj.ilike.%${q}%`
        )
        .eq("active", true)
        .limit(limit);
      if (error) throw error;
      return { result: { results: data } };
    }
    case "search_vessels": {
      const q = String(args.query || "").trim();
      let query = sb
        .from("vessels")
        .select("id, boat_name, manufacturer, model, year, client_id, asset_type, marina_id")
        .eq("active", true)
        .or(`boat_name.ilike.%${q}%,model.ilike.%${q}%,manufacturer.ilike.%${q}%`)
        .limit(15);
      if (args.client_id) query = query.eq("client_id", args.client_id);
      const { data, error } = await query;
      if (error) throw error;
      return { result: { results: data } };
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
      const { data, error } = await sb
        .from("service_orders")
        .select(
          "id, service_order_number, status, scheduled_start_at, grand_total, created_at, problem_description, clients(full_name_or_company_name)"
        )
        .eq("vessel_id", args.vessel_id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return { result: { history: data } };
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
      const refs = await validateAllReferences(sb, {
        client: args.client_id,
        vessel: args.vessel_id,
      });
      const safeClient = refs.client?.ok ? args.client_id : null;
      const safeVessel = refs.vessel?.ok ? args.vessel_id : null;
      for (const [k, r] of Object.entries(refs)) {
        if (r && !r.ok) {
          await audit(admin, {
            session_id: sessionId,
            actor_user_id: userId,
            actor_kind: "system",
            event_type: "entity_reference_blocked",
            event_category: "security",
            payload: { tool: "create_draft", kind: k, reason: r.reason },
          });
        }
      }
      const { data: draft, error } = await admin
        .from("ai_operator_drafts")
        .insert({
          session_id: sessionId,
          created_by: userId,
          kind: args.kind,
          title: args.title || null,
          summary: args.summary || null,
          client_id: safeClient,
          vessel_id: safeVessel,
          interpreted_intent: args.interpreted_intent || null,
          interpreted_category: args.interpreted_category || null,
          estimated_labor_hours: args.estimated_labor_hours ?? null,
          estimated_labor_value: args.estimated_labor_value ?? null,
          estimated_parts_value: args.estimated_parts_value ?? null,
          estimated_travel_value: args.estimated_travel_value ?? null,
          estimated_total: args.estimated_total ?? null,
          pending_questions: Array.isArray(args.pending_questions) ? args.pending_questions : [],
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
      return { result: { ok: true, draft_id: draft.id, draft }, draftId: draft.id };
    }
    case "add_draft_item": {
      // Garante que o draft pertence à sessão atual (anti-injection cross-session)
      const { data: draftOwner } = await admin
        .from("ai_operator_drafts")
        .select("id, session_id")
        .eq("id", args.draft_id)
        .maybeSingle();
      if (!draftOwner || draftOwner.session_id !== sessionId) {
        return { result: { error: "Rascunho não pertence à sessão atual." } };
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
            draft_id: args.draft_id,
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
        .eq("draft_id", args.draft_id);
      const position = (existing?.length ?? 0) + 1;
      const { data: item, error } = await admin
        .from("ai_operator_draft_items")
        .insert({
          draft_id: args.draft_id,
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
      const { data: draftOwner } = await admin
        .from("ai_operator_drafts")
        .select("id, session_id, pending_questions")
        .eq("id", args.draft_id)
        .maybeSingle();
      if (!draftOwner || draftOwner.session_id !== sessionId) {
        return { result: { error: "Rascunho não pertence à sessão atual." } };
      }
      const list = Array.isArray(draftOwner.pending_questions) ? draftOwner.pending_questions : [];
      list.push(args.question);
      const { error: uErr } = await admin
        .from("ai_operator_drafts")
        .update({ pending_questions: list })
        .eq("id", args.draft_id);
      if (uErr) throw uErr;
      return { result: { ok: true, count: list.length } };
    }
    case "register_memory_note":  // alias retrocompatível
    case "register_memory_candidate": {
      // Nasce SEMPRE como candidate. Promoção a 'verified' exige endpoint
      // dedicado com role admin/technician (verify_memory_note).
      // Validar referências de cliente/embarcação com RLS do usuário.
      const memRefs = await validateAllReferences(sb, {
        client: args.client_id,
        vessel: args.vessel_id,
      });
      const safeMemClient = memRefs.client?.ok ? args.client_id : null;
      const safeMemVessel = memRefs.vessel?.ok ? args.vessel_id : null;
      for (const [k, r] of Object.entries(memRefs)) {
        if (r && !r.ok) {
          await audit(admin, {
            session_id: sessionId,
            actor_user_id: userId,
            actor_kind: "system",
            event_type: "entity_reference_blocked",
            event_category: "security",
            payload: { tool: "register_memory_candidate", kind: k, reason: r.reason },
          });
        }
      }
      const scope = safeMemVessel ? "vessel" : safeMemClient ? "client" : "global";
      const { data: note, error } = await admin
        .from("ai_operator_memory_notes")
        .insert({
          client_id: safeMemClient,
          vessel_id: safeMemVessel,
          scope,
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

    const lastUser = [...incoming].reverse().find((m: any) => m.role === "user");
    if (lastUser) {
      await recordMessage(admin, sessionId!, {
        role: "user",
        content: String(lastUser.content || ""),
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

    const messages: any[] = [{ role: "system", content: systemPrompt }, ...incoming];
    const toolEvents: any[] = [];
    let createdDraftId: string | null = null;
    let pendingActionForFrontend: any = null;

    for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
      const aiRes = await fetch(`${GEMINI_BASE_URL}/chat/completions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${GEMINI_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model: MODEL, messages, tools: OPERATOR_TOOLS, tool_choice: "auto" }),
      });
      if (aiRes.status === 429) return jr({ error: "Limite de requisições do modelo atingido." }, 429);
      if (!aiRes.ok) {
        const txt = await aiRes.text();
        console.error("[ai-operator-core] gateway error", aiRes.status, txt);
        return jr({ error: `Gateway de IA falhou (${aiRes.status})` }, 500);
      }
      const aiJson = await aiRes.json();
      const choice = aiJson.choices?.[0];
      const aiMsg = choice?.message;
      if (!aiMsg) return jr({ error: "Resposta vazia do modelo" }, 500);
      messages.push(aiMsg);

      const toolCalls = aiMsg.tool_calls || [];
      if (toolCalls.length === 0) {
        const finalContent = aiMsg.content || "";
        await recordMessage(admin, sessionId!, { role: "assistant", content: finalContent, source: channel });
        return jr({
          ok: true,
          session_id: sessionId,
          message: { role: "assistant", content: finalContent },
          draft_id: createdDraftId,
          pending_action: pendingActionForFrontend,
          tool_events: toolEvents,
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

        if (fnName === "propose_action") {
          const proposedAction = String(fnArgs.action || "unknown");
          const proposedRisk = classifyAction(proposedAction);

          // Validar draft_id em propose_action via helper testável.
          const draftRes = await resolveProposalDraftId({
            requestedDraftId: fnArgs.draft_id ?? null,
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
            content: aiMsg.content || "",
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
            message: { role: "assistant", content: aiMsg.content || "" },
            draft_id: createdDraftId,
            pending_action: pendingActionForFrontend,
            tool_events: toolEvents,
          });
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
          const exec = await execSafeTool(fnName, fnArgs, { sb, admin, userId, sessionId: sessionId! });
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

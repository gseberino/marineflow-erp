// Edge Function: ai-agent
// Adaptador HTTP para o AI Operator (Claude/Anthropic). Toda a lógica de tool-calling
// vive em _shared/ai/ (agnóstica de canal). Este arquivo cuida de CORS/auth, tradução
// entre o formato de mensagens legado do frontend (OpenAI-shape, ChatMessage[]) e o
// formato nativo da Anthropic, e serialização da resposta no contrato existente do
// widget — que não muda nesta fase.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { runAgentLoop, type Proposal } from "../_shared/ai/agent.ts";
import { buildSystemBlocks } from "../_shared/ai/prompt.ts";
import { callClaude, ClaudeApiError, type ClaudeContentBlock, type ClaudeMessage } from "../_shared/ai/anthropic.ts";
import { MODEL_AGENT, MODEL_LITE } from "../_shared/ai/models.ts";
import { allTools, toolsByName, type Role } from "../_shared/ai/tools/index.ts";
import {
  checkWhatsAppRateLimit,
  formatOptionsAsNumberedText,
  parseConfirmationReply,
  parseOptionReply,
  queueWhatsAppReply,
  resolveOptionAsUserText,
  resolveOrCreateWhatsAppSession,
} from "../_shared/ai/whatsapp-channel.ts";
import { verifyPin } from "../_shared/ai/whatsapp-pin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jr = (b: unknown, s = 200) => {
  console.log(`[AI-AGENT] Returning status ${s}:`, JSON.stringify(b).slice(0, 200));
  return new Response(JSON.stringify(b), {
    status: 200, // Always return 200 to avoid Supabase generic non-2xx error handling
    headers: { ...corsHeaders, "Content-Type": "application/json", "X-Actual-Status": s.toString() },
  });
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

// ---------------- Contrato legado com o frontend (não muda nesta fase) ----------------
type ChatMessage =
  | { role: "user"; content: string }
  | { role: "assistant"; content: string; tool_calls?: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }> }
  | { role: "tool"; tool_call_id: string; content: string };

/** Traduz o histórico OpenAI-shape (vindo do frontend) para o formato nativo Anthropic. */
function toAnthropicMessages(openaiMessages: ChatMessage[]): ClaudeMessage[] {
  const result: ClaudeMessage[] = [];
  for (const m of openaiMessages) {
    if (m.role === "user") {
      result.push({ role: "user", content: [{ type: "text", text: m.content }] });
    } else if (m.role === "assistant") {
      const blocks: ClaudeContentBlock[] = [];
      if (m.content) blocks.push({ type: "text", text: m.content });
      for (const tc of m.tool_calls || []) {
        let input: Record<string, unknown> = {};
        try {
          input = JSON.parse(tc.function?.arguments || "{}");
        } catch {
          input = {};
        }
        blocks.push({ type: "tool_use", id: tc.id, name: tc.function?.name, input });
      }
      result.push({ role: "assistant", content: blocks });
    } else if (m.role === "tool") {
      const block: ClaudeContentBlock = { type: "tool_result", tool_use_id: m.tool_call_id, content: m.content };
      const last = result[result.length - 1];
      if (last && last.role === "user" && last.content.length > 0 && last.content.every((b) => b.type === "tool_result")) {
        last.content.push(block);
      } else {
        result.push({ role: "user", content: [block] });
      }
    }
  }
  return result;
}

/** Traduz o histórico nativo Anthropic de volta para OpenAI-shape (updated_messages do frontend). */
function fromAnthropicMessages(claudeMessages: ClaudeMessage[]): ChatMessage[] {
  const result: ChatMessage[] = [];
  for (const m of claudeMessages) {
    if (m.role === "user") {
      const toolResults = m.content.filter((b) => b.type === "tool_result");
      if (toolResults.length > 0) {
        for (const tr of toolResults) {
          if (tr.type === "tool_result") result.push({ role: "tool", tool_call_id: tr.tool_use_id, content: tr.content });
        }
      } else {
        const text = m.content.filter((b) => b.type === "text").map((b) => (b.type === "text" ? b.text : "")).join("");
        result.push({ role: "user", content: text });
      }
    } else if (m.role === "assistant") {
      const text = m.content.filter((b) => b.type === "text").map((b) => (b.type === "text" ? b.text : "")).join("");
      const toolCalls = m.content
        .filter((b) => b.type === "tool_use")
        .map((b) => (b.type === "tool_use" ? { id: b.id, type: "function" as const, function: { name: b.name, arguments: JSON.stringify(b.input) } } : null))
        .filter((x): x is NonNullable<typeof x> => x !== null);
      result.push({ role: "assistant", content: text, ...(toolCalls.length ? { tool_calls: toolCalls } : {}) });
    }
  }
  return result;
}

// ---------------- Persistência (Fase 2) — supabase/migrations/20260703140000_ai_operator_tables.sql ----------------

type MessageRow = {
  role: "user" | "assistant" | "tool" | "system";
  content: string | null;
  tool_calls: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }> | null;
  tool_call_id: string | null;
};

/** Linha de ai_operator_messages -> ChatMessage (OpenAI-shape), inverso de buildMessageRows. */
function rowToChatMessage(row: MessageRow): ChatMessage {
  if (row.role === "tool") return { role: "tool", tool_call_id: row.tool_call_id || "", content: row.content || "" };
  if (row.role === "assistant") {
    const toolCalls = Array.isArray(row.tool_calls) && row.tool_calls.length > 0 ? row.tool_calls : undefined;
    return { role: "assistant", content: row.content || "", ...(toolCalls ? { tool_calls: toolCalls } : {}) };
  }
  return { role: "user", content: row.content || "" };
}

/**
 * Monta as linhas novas de ai_operator_messages para um turno. `usageLog` tem uma
 * entrada por chamada ao Claude nesse turno, na MESMA ordem em que agent.ts empilha as
 * mensagens assistant — por isso o índice avança só quando encontra role:"assistant".
 */
function buildMessageRows(
  sessionId: string,
  newMessages: ChatMessage[],
  usageLog: Array<{ inputTokens: number; outputTokens: number; cacheReadInputTokens: number }>,
  model: string,
  source: "web" | "whatsapp" = "web",
) {
  let usageIdx = 0;
  return newMessages.map((m) => {
    if (m.role === "tool") {
      return { session_id: sessionId, role: "tool", content: m.content, tool_call_id: m.tool_call_id, source };
    }
    if (m.role === "assistant") {
      const usage = usageLog[usageIdx++];
      return {
        session_id: sessionId,
        role: "assistant",
        content: m.content || null,
        tool_calls: m.tool_calls && m.tool_calls.length > 0 ? m.tool_calls : null,
        source,
        tokens_in: usage?.inputTokens ?? null,
        tokens_out: usage?.outputTokens ?? null,
        cache_read_tokens: usage?.cacheReadInputTokens ?? null,
        model,
      };
    }
    return { session_id: sessionId, role: "user", content: m.content, source };
  });
}

// Prompt do modo "sales copy" (usado por AIConsultantDashboard/ProspectingPage) — reaproveitado
// quase literal do original. Chamada única a MODEL_LITE, sem tools, sem prompt caching (turno
// isolado, sem ganho de cache).
const SALES_COPY_PROMPT = `Você é um Copywriter de Vendas Náuticas especialista do MarineFlow, atuando para um prestador de serviços de elétrica e eletrônica embarcada de alto padrão.

OBJETIVO:
- Gerar mensagens de WhatsApp persuasivas, humanas e diretas para prospecção e relacionamento com proprietários de embarcações, marinas e estaleiros.

ESTILO:
- Tom profissional, próximo, sem ser bajulador. Cordial, confiante e consultivo.
- Português brasileiro natural, evite anglicismos desnecessários.
- Frases curtas. Quebra de linha entre ideias. Use 1 ou 2 emojis no máximo, com bom gosto (⚓ ⚡ 🛥️).
- Nunca soe genérico ou robótico. Personalize quando houver contexto (nome, embarcação, marina, problema).
- Foque em benefício concreto (segurança elétrica, autonomia, evitar pane no mar, valorização do barco).
- CTA claro no final (responder, agendar visita, enviar foto do painel, etc.).

REGRAS:
- Nunca invente dados que não foram fornecidos.
- Nunca inclua links suspeitos ou promessas mirabolantes.
- Não use markdown pesado — WhatsApp aceita *negrito* simples e quebras de linha.
- Tamanho ideal: 4 a 8 linhas. Nunca ultrapasse 12 linhas.
- Não inclua assinatura institucional a menos que solicitado.

Responda APENAS com o texto da mensagem pronta para envio, sem explicações ou comentários adicionais.`;

// ---------------- Canal WhatsApp interno (Fase 4) ----------------
// Autenticado só por x-internal-secret (chamado pelo whatsapp-webhook, não por um
// usuário logado) — não existe JWT de usuário aqui, então toolCtx.sb === toolCtx.admin
// (service-role faz o papel de RLS pra este canal; a role do app_user já filtra as
// tools e é revalidada em cada execute() restrito).

/** Executa a decisão (aprovar/rejeitar) de uma pendência vinda de "sim"/"não" no WhatsApp. */
async function resolveWhatsAppConfirmation(
  admin: any,
  metadata: Record<string, any>,
  appUser: { id: string; role: string; full_name: string | null; ai_whatsapp_pin_hash: string | null },
  toolCtx: { sb: any; admin: any; userId: string; userRole: Role; jwt: string; appOrigin: string; settings: Record<string, string> },
  confirmation: { decision: "approve"; pin?: string } | { decision: "reject" },
): Promise<{ message: string; metadata: Record<string, any> }> {
  const pendingActionId = metadata.pending_confirm_action_id as string;
  const { data: pending } = await admin.from("ai_operator_pending_actions").select("*").eq("id", pendingActionId).maybeSingle();
  const clearedMetadata = { ...metadata, pending_confirm_action_id: null, pin_attempts: 0 };

  if (!pending || pending.status !== "pending") {
    return { message: "Essa pendência não existe mais ou já foi decidida.", metadata: clearedMetadata };
  }

  if (confirmation.decision === "reject") {
    await admin
      .from("ai_operator_pending_actions")
      .update({ status: "rejected", rejected_by_user_id: appUser.id, rejected_at: new Date().toISOString() })
      .eq("id", pendingActionId);
    await admin.from("ai_operator_audit").insert({
      session_id: pending.session_id,
      pending_action_id: pendingActionId,
      actor_user_id: appUser.id,
      actor_kind: "user",
      event_type: `reject:${pending.action_name}`,
      event_category: "security",
      payload: { channel: "whatsapp", args: pending.payload },
    });
    return { message: `❌ Ação rejeitada: ${pending.title}.`, metadata: clearedMetadata };
  }

  // approve — ações high exigem PIN (telefone sozinho é autenticação fraca)
  if (pending.risk_level === "high") {
    if (!confirmation.pin) {
      return { message: "Ação de alto risco — para confirmar, responda: *sim <SEU PIN>*.", metadata };
    }
    const pinOk = await verifyPin(confirmation.pin, appUser.ai_whatsapp_pin_hash);
    if (!pinOk) {
      const attempts = (metadata.pin_attempts || 0) + 1;
      if (attempts >= 3) {
        await admin
          .from("ai_operator_pending_actions")
          .update({ status: "rejected", rejected_by_user_id: appUser.id, rejected_at: new Date().toISOString() })
          .eq("id", pendingActionId);
        await admin.from("ai_operator_audit").insert({
          session_id: pending.session_id,
          pending_action_id: pendingActionId,
          actor_user_id: appUser.id,
          actor_kind: "user",
          event_type: `pin_failed_reject:${pending.action_name}`,
          event_category: "security",
          payload: { channel: "whatsapp", attempts },
        });
        await notifyAdminsPinFailure(admin, pending);
        return { message: "❌ PIN incorreto 3 vezes — ação rejeitada por segurança.", metadata: clearedMetadata };
      }
      return { message: `PIN incorreto. Tente de novo: *sim <SEU PIN>* (tentativa ${attempts}/3).`, metadata: { ...metadata, pin_attempts: attempts } };
    }
  }

  const toolDef = toolsByName[pending.action_name];
  let execResult: unknown;
  try {
    execResult = toolDef ? await toolDef.execute(pending.payload, toolCtx) : { error: `Tool desconhecida: ${pending.action_name}` };
  } catch (e: any) {
    execResult = { error: e?.message || "Falha na execução da tool" };
  }
  const executedAt = new Date().toISOString();
  await admin
    .from("ai_operator_pending_actions")
    .update({ status: "executed", approved_by_user_id: appUser.id, approved_at: executedAt, executed_at: executedAt, result: execResult })
    .eq("id", pendingActionId);
  await admin.from("ai_operator_audit").insert({
    session_id: pending.session_id,
    pending_action_id: pendingActionId,
    actor_user_id: appUser.id,
    actor_kind: "user",
    event_type: `approve_execute:${pending.action_name}`,
    event_category: "data",
    payload: { channel: "whatsapp", args: pending.payload, risk: pending.risk_level, result_summary: JSON.stringify(execResult ?? null).slice(0, 500) },
  });
  const execError = (execResult as any)?.error;
  const message = execError ? `⚠️ ${pending.title} — falhou: ${execError}` : `✅ ${pending.title} — executado.`;
  return { message, metadata: clearedMetadata };
}

/** 3 tentativas de PIN erradas: avisa todo admin com telefone cadastrado. */
async function notifyAdminsPinFailure(admin: any, pending: { title: string }): Promise<void> {
  try {
    const { data: admins } = await admin
      .from("app_users")
      .select("phone_normalized")
      .eq("role", "admin")
      .eq("active", true)
      .not("phone_normalized", "is", null);
    const alertMsg = `⚠️ Alerta de segurança: 3 tentativas de PIN incorretas ao tentar aprovar "${pending.title}" via WhatsApp. A ação foi rejeitada automaticamente.`;
    for (const a of admins || []) {
      if (a.phone_normalized) await queueWhatsAppReply(admin, a.phone_normalized, alertMsg);
    }
  } catch (e) {
    console.error("[ai-agent][whatsapp] falha ao notificar admins:", e);
  }
}

async function handleWhatsAppTurn(req: Request, internalSecret: string): Promise<Response> {
  const expectedSecret = Deno.env.get("AI_INTERNAL_SECRET");
  if (!expectedSecret || internalSecret !== expectedSecret) return jr({ error: "Não autorizado" }, 401);

  const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const body = await req.json().catch(() => ({}));
  const phoneNormalized: string | undefined = body.phone_normalized;
  const appUserId: string | undefined = body.app_user_id;
  const text = String(body.text || "").trim();
  if (!phoneNormalized || !appUserId || !text) {
    return jr({ error: "phone_normalized, app_user_id e text são obrigatórios" }, 400);
  }

  // Rate limit — custo $0, nem chega a resolver sessão/usuário.
  const withinLimit = await checkWhatsAppRateLimit(admin, phoneNormalized);
  if (!withinLimit) return jr({ ok: true, skipped: "rate_limited" });

  const { data: appUser } = await admin
    .from("app_users")
    .select("id, role, full_name, ai_whatsapp_pin_hash")
    .eq("id", appUserId)
    .eq("ai_whatsapp_enabled", true)
    .eq("active", true)
    .maybeSingle();
  if (!appUser) return jr({ error: "Usuário não autorizado para o canal WhatsApp" }, 403);

  const sessionId = await resolveOrCreateWhatsAppSession(admin, phoneNormalized, appUserId);
  const { data: sessionRow } = await admin.from("ai_operator_sessions").select("metadata").eq("id", sessionId).maybeSingle();
  const metadata: Record<string, any> = (sessionRow?.metadata as any) || {};

  const { data: settingsRows } = await admin.from("app_settings").select("key, value");
  const settings: Record<string, string> = {};
  (settingsRows || []).forEach((r: any) => {
    if (r.key) settings[r.key] = String(r.value ?? "");
  });

  // Sem JWT de usuário neste canal — sb e admin são o mesmo client service-role.
  const toolCtx = { sb: admin, admin, userId: appUserId, userRole: (appUser.role as Role) || "unknown", jwt: "", appOrigin: settings.app_public_url || "", settings };

  // ---- Camada determinística (custo $0): confirmação de pendência ----
  if (metadata.pending_confirm_action_id) {
    const confirmation = parseConfirmationReply(text);
    if (confirmation) {
      const resolved = await resolveWhatsAppConfirmation(admin, metadata, appUser, toolCtx, confirmation);
      await admin.from("ai_operator_sessions").update({ metadata: resolved.metadata, last_activity_at: new Date().toISOString() }).eq("id", sessionId);
      await queueWhatsAppReply(admin, phoneNormalized, resolved.message);
      return jr({ ok: true });
    }
    // Não pareceu confirmação — segue pro LLM (usuário pode ter mudado de assunto).
  }

  // ---- Camada determinística (custo $0): número de uma lista de opções pendente ----
  let effectiveText = text;
  const pendingOptions = metadata.pending_options as Array<{ label: string; value: string }> | undefined;
  if (pendingOptions && pendingOptions.length > 0) {
    const idx = parseOptionReply(text, pendingOptions.length);
    if (idx !== null) {
      effectiveText = resolveOptionAsUserText(pendingOptions[idx - 1]);
      metadata.pending_options = null;
    }
  }

  // ---- Turno normal do LLM ----
  const { data: rows } = await admin
    .from("ai_operator_messages")
    .select("role, content, tool_calls, tool_call_id")
    .eq("session_id", sessionId)
    .order("created_at", { ascending: true })
    .limit(30);
  const seedMessages = (rows || []).map(rowToChatMessage);
  const alreadyPersistedCount = toAnthropicMessages(seedMessages).length;
  const historyMessages: ChatMessage[] = [...seedMessages, { role: "user", content: effectiveText }];

  const { data: memoryRows } = await admin
    .from("ai_operator_memory_notes")
    .select("title, body")
    .eq("scope", "global")
    .eq("verification_status", "verified")
    .order("created_at", { ascending: false })
    .limit(10);
  const memoryNotes = (memoryRows || []).map((r: any) => `${r.title}: ${r.body}`);

  const system = buildSystemBlocks(settings, {
    userName: appUser.full_name || "Usuário",
    userRole: appUser.role || "unknown",
    memoryNotes,
    channel: "whatsapp",
  });

  const toolsForRole = allTools.filter((t) => !t.roles || t.roles.includes((appUser.role as Role) || ("unknown" as Role)));

  const result = await runAgentLoop({
    system,
    messages: toAnthropicMessages(historyMessages),
    tools: toolsForRole,
    toolCtx,
    sessionId,
    channel: "whatsapp",
  });

  try {
    const newNativeSlice = result.messages.slice(alreadyPersistedCount);
    const newRows = fromAnthropicMessages(newNativeSlice);
    if (newRows.length > 0) {
      const rowsToInsert = buildMessageRows(sessionId, newRows, result.usage, MODEL_AGENT, "whatsapp");
      await admin.from("ai_operator_messages").insert(rowsToInsert);
    }
  } catch (persistErr) {
    console.error("[ai-agent][whatsapp] falha ao persistir mensagens:", persistErr);
  }

  let replyText: string;
  const newMetadata: Record<string, any> = { ...metadata };

  if (result.error) {
    replyText = `⚠️ ${result.error}`;
    newMetadata.pending_confirm_action_id = null;
  } else if (result.options) {
    replyText = formatOptionsAsNumberedText(result.options.question, result.options.options);
    newMetadata.pending_options = result.options.options;
    newMetadata.pending_confirm_action_id = null;
  } else if (result.proposal) {
    const proposal = result.proposal as Proposal;
    const pinNote =
      proposal.risk_level === "high"
        ? "\n\nPara aprovar, responda: *sim <SEU PIN>*. Para rejeitar: *não*."
        : "\n\nResponda *sim* para aprovar ou *não* para rejeitar.";
    replyText = `⚠️ ${proposal.title}\n${proposal.summary_markdown}${pinNote}`;
    newMetadata.pending_confirm_action_id = proposal.pending_action_id;
    newMetadata.pin_attempts = 0;
    newMetadata.pending_options = null;
  } else {
    replyText = result.message.content || "Ok.";
    newMetadata.pending_confirm_action_id = null;
  }

  await admin.from("ai_operator_sessions").update({ metadata: newMetadata, last_activity_at: new Date().toISOString() }).eq("id", sessionId);
  await queueWhatsAppReply(admin, phoneNormalized, replyText);

  return jr({ ok: true, session_id: sessionId });
}

// ---------------- HANDLER ----------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (!Deno.env.get("OPENROUTER_API_KEY")) return jr({ error: "OPENROUTER_API_KEY não configurada no Supabase" }, 500);

    const internalSecret = req.headers.get("x-internal-secret");
    if (internalSecret) return await handleWhatsAppTurn(req, internalSecret);

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return jr({ error: "Não autenticado" }, 401);

    const sb = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user?.id) return jr({ error: "Não autenticado" }, 401);
    const userId = userData.user.id;

    const { data: userProfile } = await sb.from("app_users").select("role, full_name").eq("id", userId).maybeSingle();
    const userRole = userProfile?.role || "unknown";
    const userName = userProfile?.full_name || "Usuário";

    const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // ---- Carrega TODAS as configuracoes do sistema uma unica vez ----
    const { data: settingsRows } = await admin.from("app_settings").select("key, value");
    const settings: Record<string, string> = {};
    (settingsRows || []).forEach((r: any) => {
      if (r.key) settings[r.key] = String(r.value ?? "");
    });

    const body = await req.json().catch(() => ({}));
    const incoming: ChatMessage[] = Array.isArray(body.messages) ? body.messages : [];
    const context = body.context || {};
    const isSalesCopy = body.is_sales_copy === true;
    const requestedSessionId: string | undefined = typeof body.session_id === "string" ? body.session_id : undefined;

    // ---------- Carregar histórico (Fase 2) — usado pelo widget ao reabrir, sem chamar o LLM ----------
    if (body.type === "load_history") {
      if (!requestedSessionId) return jr({ error: "session_id obrigatório" }, 400);
      const { data: sess } = await admin.from("ai_operator_sessions").select("id, owner_user_id").eq("id", requestedSessionId).maybeSingle();
      if (!sess || (sess.owner_user_id && sess.owner_user_id !== userId && userRole !== "admin")) {
        return jr({ session_id: null, messages: [] });
      }
      const { data: rows } = await admin
        .from("ai_operator_messages")
        .select("role, content, tool_calls, tool_call_id")
        .eq("session_id", requestedSessionId)
        .order("created_at", { ascending: true })
        .limit(30);
      return jr({ session_id: requestedSessionId, messages: (rows || []).map(rowToChatMessage) });
    }

    // ---------- Confirmação determinística de pendência (Fase 3) — SEM chamada de LLM ----------
    if (body.type === "confirm_action") {
      const pendingActionId: string | undefined = body.pending_action_id;
      const decision: string | undefined = body.decision;
      if (!pendingActionId || (decision !== "approve" && decision !== "reject")) {
        return jr({ error: "pending_action_id e decision ('approve'|'reject') são obrigatórios" }, 400);
      }

      const { data: pending, error: pendingErr } = await admin
        .from("ai_operator_pending_actions")
        .select("*")
        .eq("id", pendingActionId)
        .maybeSingle();
      if (pendingErr || !pending) return jr({ error: "Pendência não encontrada" }, 404);
      if (pending.status !== "pending") {
        return jr({ error: `Esta pendência já foi ${pending.status === "approved" || pending.status === "executed" ? "processada" : pending.status}.` }, 409);
      }
      const isOwner = pending.requested_by_user_id === userId;
      if (!isOwner && userRole !== "admin") return jr({ error: "Sem permissão para decidir esta pendência." }, 403);

      const appOriginConfirm = req.headers.get("origin") || req.headers.get("referer")?.replace(/\/$/, "") || "";

      if (decision === "reject") {
        await admin
          .from("ai_operator_pending_actions")
          .update({ status: "rejected", rejected_by_user_id: userId, rejected_at: new Date().toISOString() })
          .eq("id", pendingActionId);
        await admin.from("ai_operator_audit").insert({
          session_id: pending.session_id,
          pending_action_id: pendingActionId,
          actor_user_id: userId,
          actor_kind: "user",
          event_type: `reject:${pending.action_name}`,
          event_category: "security",
          payload: { args: pending.payload },
        });
        const rejectMsg = `❌ Ação rejeitada: ${pending.title}.`;
        if (pending.session_id) {
          await admin.from("ai_operator_messages").insert({ session_id: pending.session_id, role: "assistant", content: rejectMsg, source: "web" });
          await admin.from("ai_operator_sessions").update({ last_activity_at: new Date().toISOString() }).eq("id", pending.session_id);
        }
        return jr({ message: { role: "assistant", content: rejectMsg }, tool_events: [], session_id: pending.session_id });
      }

      // decision === "approve": executa o payload GRAVADO, sem passar pelo LLM de novo.
      const toolDef = toolsByName[pending.action_name];
      if (!toolDef) return jr({ error: `Tool desconhecida: ${pending.action_name}` }, 500);

      let execResult: unknown;
      try {
        execResult = await toolDef.execute(pending.payload, { sb, admin, userId, userRole: userRole as Role, jwt, appOrigin: appOriginConfirm, settings });
      } catch (e: any) {
        execResult = { error: e?.message || "Falha na execução da tool" };
      }

      const executedAt = new Date().toISOString();
      await admin
        .from("ai_operator_pending_actions")
        .update({ status: "executed", approved_by_user_id: userId, approved_at: executedAt, executed_at: executedAt, result: execResult })
        .eq("id", pendingActionId);

      await admin.from("ai_operator_audit").insert({
        session_id: pending.session_id,
        pending_action_id: pendingActionId,
        actor_user_id: userId,
        actor_kind: "user",
        event_type: `approve_execute:${pending.action_name}`,
        event_category: "data",
        payload: { args: pending.payload, risk: pending.risk_level, result_summary: JSON.stringify(execResult ?? null).slice(0, 500) },
      });

      const execError = (execResult as any)?.error;
      const execMsg = execError ? `⚠️ ${pending.title} — falhou: ${execError}` : `✅ ${pending.title} — executado.`;
      // Continuidade: injeta uma mensagem assistant simples no histórico (não um tool_result
      // sintético — o tool_result do momento da interceptação já foi persistido no turno
      // original; inventar outro sem um tool_use pareado quebraria a reconstrução do
      // histórico nativo da Anthropic no próximo turno).
      if (pending.session_id) {
        await admin.from("ai_operator_messages").insert({ session_id: pending.session_id, role: "assistant", content: execMsg, source: "web" });
        await admin.from("ai_operator_sessions").update({ last_activity_at: executedAt }).eq("id", pending.session_id);
      }

      return jr({
        message: { role: "assistant", content: execMsg },
        tool_events: [{ name: pending.action_name, args: pending.payload, result: execResult }],
        session_id: pending.session_id,
      });
    }

    // ---------- MODO SALES COPY (sem tools, foco em copy persuasiva para WhatsApp) ----------
    if (isSalesCopy) {
      try {
        const result = await callClaude({
          model: MODEL_LITE,
          system: [{ type: "text", text: SALES_COPY_PROMPT }],
          messages: toAnthropicMessages(incoming),
          maxTokens: 1024,
        });
        const content = result.content
          .filter((b): b is { type: "text"; text: string } => b.type === "text")
          .map((b) => b.text)
          .join("");
        return jr({ message: { role: "assistant", content }, tool_events: [] });
      } catch (e: any) {
        const status = e instanceof ClaudeApiError ? e.status : 500;
        console.error("AI gateway sales error:", e);
        return jr({ error: e?.message || "Erro no gateway de IA" }, status);
      }
    }

    const appOrigin = req.headers.get("origin") || req.headers.get("referer")?.replace(/\/$/, "") || "";

    // ---- Resolve a sessão (Fase 2): cria uma nova se ausente/inválida/de outro usuário ----
    let sessionId = requestedSessionId;
    let seedMessages: ChatMessage[] = [];
    let alreadyPersistedCount = 0; // em "unidades nativas" Anthropic (após toAnthropicMessages)

    if (sessionId) {
      const { data: sess } = await admin.from("ai_operator_sessions").select("id, owner_user_id").eq("id", sessionId).maybeSingle();
      if (!sess || (sess.owner_user_id && sess.owner_user_id !== userId && userRole !== "admin")) {
        sessionId = undefined; // sessão inválida ou de outro usuário -> cria uma nova abaixo
      }
    }

    if (!sessionId) {
      const { data: newSession, error: sessErr } = await admin
        .from("ai_operator_sessions")
        .insert({ channel: "web", owner_user_id: userId, status: "open" })
        .select("id")
        .single();
      if (sessErr || !newSession) return jr({ error: `Falha ao criar sessão: ${sessErr?.message || "erro desconhecido"}` }, 500);
      sessionId = newSession.id;
    } else {
      const { data: rows } = await admin
        .from("ai_operator_messages")
        .select("role, content, tool_calls, tool_call_id")
        .eq("session_id", sessionId)
        .order("created_at", { ascending: true })
        .limit(30);
      seedMessages = (rows || []).map(rowToChatMessage);
      alreadyPersistedCount = toAnthropicMessages(seedMessages).length;
    }
    // Neste ponto sessionId sempre está definido (criado ou validado acima).
    const resolvedSessionId: string = sessionId!;

    // Sessão já tinha histórico no banco -> banco é autoritativo, só a última mensagem
    // de usuário do payload é o input novo deste turno. Sessão nova (ou sem linhas
    // persistidas ainda) -> usa o array inteiro que o frontend mandou, como na Fase 1.
    const newUserMsg = alreadyPersistedCount > 0 ? [...incoming].reverse().find((m) => m.role === "user") : undefined;
    const historyMessages: ChatMessage[] = alreadyPersistedCount > 0 ? (newUserMsg ? [...seedMessages, newUserMsg] : seedMessages) : incoming;

    // ---- Notas de memória ativas (Fase 2) — só as globais já verificadas ----
    const { data: memoryRows } = await admin
      .from("ai_operator_memory_notes")
      .select("title, body")
      .eq("scope", "global")
      .eq("verification_status", "verified")
      .order("created_at", { ascending: false })
      .limit(10);
    const memoryNotes = (memoryRows || []).map((r: any) => `${r.title}: ${r.body}`);

    const system = buildSystemBlocks(settings, {
      userName,
      userRole,
      route: context.route,
      entityType: context.entityType,
      entityId: context.entityId,
      memoryNotes,
    });

    // Filtra a lista de tools pelo cargo ANTES do modelo ver — technician não recebe
    // tools financeiras/compras/preço. Defesa em profundidade real fica em cada
    // execute() (blockTechnician), necessária pro canal WhatsApp futuro.
    const toolsForRole = allTools.filter((t) => !t.roles || t.roles.includes(userRole as Role));

    const result = await runAgentLoop({
      system,
      messages: toAnthropicMessages(historyMessages),
      tools: toolsForRole,
      toolCtx: { sb, admin, userId, userRole: userRole as Role, jwt, appOrigin, settings },
      sessionId: resolvedSessionId,
      channel: "panel",
    });

    // ---- Persiste as mensagens novas deste turno (best-effort — não derruba a resposta) ----
    try {
      const newNativeSlice = result.messages.slice(alreadyPersistedCount);
      const newRows = fromAnthropicMessages(newNativeSlice);
      if (newRows.length > 0) {
        const rowsToInsert = buildMessageRows(resolvedSessionId, newRows, result.usage, MODEL_AGENT);
        await admin.from("ai_operator_messages").insert(rowsToInsert);
      }
      await admin.from("ai_operator_sessions").update({ last_activity_at: new Date().toISOString() }).eq("id", resolvedSessionId);
    } catch (persistErr) {
      console.error("[ai-agent] falha ao persistir mensagens/sessão:", persistErr);
    }

    if (result.error) {
      return jr({ error: result.error, session_id: resolvedSessionId }, result.errorStatus ?? 500);
    }

    if (result.options) {
      return jr({
        message: result.message,
        options: result.options,
        tool_events: result.toolEvents,
        updated_messages: fromAnthropicMessages(result.messages),
        session_id: resolvedSessionId,
      });
    }

    if (result.proposal) {
      return jr({
        message: result.message,
        proposal: result.proposal,
        tool_events: result.toolEvents,
        updated_messages: fromAnthropicMessages(result.messages),
        session_id: resolvedSessionId,
      });
    }

    // Resposta final sem tool calls no último giro — igual ao comportamento original,
    // não inclui updated_messages (o frontend só acrescenta esta mensagem ao seu estado local).
    return jr({ message: result.message, tool_events: result.toolEvents, session_id: resolvedSessionId });
  } catch (e: any) {
    console.error("ai-agent error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

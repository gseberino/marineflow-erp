// Edge Function: ai-agent
// Adaptador HTTP para o AI Operator (Claude/Anthropic). Toda a lógica de tool-calling
// vive em _shared/ai/ (agnóstica de canal). Este arquivo cuida de CORS/auth, tradução
// entre o formato de mensagens legado do frontend (OpenAI-shape, ChatMessage[]) e o
// formato nativo da Anthropic, e serialização da resposta no contrato existente do
// widget — que não muda nesta fase.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { runAgentLoop } from "../_shared/ai/agent.ts";
import { buildSystemBlocks } from "../_shared/ai/prompt.ts";
import { callClaude, ClaudeApiError, type ClaudeContentBlock, type ClaudeMessage } from "../_shared/ai/anthropic.ts";
import { MODEL_AGENT, MODEL_LITE } from "../_shared/ai/models.ts";

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
function buildMessageRows(sessionId: string, newMessages: ChatMessage[], usageLog: Array<{ inputTokens: number; outputTokens: number; cacheReadInputTokens: number }>, model: string) {
  let usageIdx = 0;
  return newMessages.map((m) => {
    if (m.role === "tool") {
      return { session_id: sessionId, role: "tool", content: m.content, tool_call_id: m.tool_call_id, source: "web" };
    }
    if (m.role === "assistant") {
      const usage = usageLog[usageIdx++];
      return {
        session_id: sessionId,
        role: "assistant",
        content: m.content || null,
        tool_calls: m.tool_calls && m.tool_calls.length > 0 ? m.tool_calls : null,
        source: "web",
        tokens_in: usage?.inputTokens ?? null,
        tokens_out: usage?.outputTokens ?? null,
        cache_read_tokens: usage?.cacheReadInputTokens ?? null,
        model,
      };
    }
    return { session_id: sessionId, role: "user", content: m.content, source: "web" };
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

// ---------------- HANDLER ----------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (!Deno.env.get("OPENROUTER_API_KEY")) return jr({ error: "OPENROUTER_API_KEY não configurada no Supabase" }, 500);

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

    const result = await runAgentLoop({
      system,
      messages: toAnthropicMessages(historyMessages),
      toolCtx: { sb, admin, userId, jwt, appOrigin, settings },
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

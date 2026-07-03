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
import { MODEL_LITE } from "../_shared/ai/models.ts";

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

    const system = buildSystemBlocks(settings, {
      userName,
      userRole,
      route: context.route,
      entityType: context.entityType,
      entityId: context.entityId,
    });

    const result = await runAgentLoop({
      system,
      messages: toAnthropicMessages(incoming),
      toolCtx: { sb, admin, userId, jwt, appOrigin, settings },
      channel: "panel",
    });

    if (result.error) {
      return jr({ error: result.error }, result.errorStatus ?? 500);
    }

    if (result.options) {
      return jr({
        message: result.message,
        options: result.options,
        tool_events: result.toolEvents,
        updated_messages: fromAnthropicMessages(result.messages),
      });
    }

    if (result.proposal) {
      return jr({
        message: result.message,
        proposal: result.proposal,
        tool_events: result.toolEvents,
        updated_messages: fromAnthropicMessages(result.messages),
      });
    }

    // Resposta final sem tool calls no último giro — igual ao comportamento original,
    // não inclui updated_messages (o frontend só acrescenta esta mensagem ao seu estado local).
    return jr({ message: result.message, tool_events: result.toolEvents });
  } catch (e: any) {
    console.error("ai-agent error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});

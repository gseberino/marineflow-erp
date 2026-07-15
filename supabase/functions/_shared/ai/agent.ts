import {
  callClaude,
  ClaudeApiError,
  type ClaudeContentBlock,
  type ClaudeMessage,
  type ClaudeTextBlock,
  type ClaudeToolResultBlock,
  type ClaudeToolUseBlock,
  type ClaudeUsage,
} from "./anthropic.ts";
import { allTools, type ToolCtx, type ToolDef } from "./tools/index.ts";
import { DEFAULT_MAX_TOKENS, MAX_ITERATIONS as DEFAULT_MAX_ITERATIONS, MODEL_AGENT } from "./models.ts";

export interface Proposal {
  pending_action_id: string;
  title: string;
  summary_markdown: string;
  risk_level: "medium" | "high";
}

export interface OptionItem {
  label: string;
  value: string;
}

export interface OptionsData {
  question: string;
  options: OptionItem[];
}

export interface ToolEvent {
  name: string;
  args: unknown;
  result: unknown;
}

export interface AgentTurnResult {
  message: { role: "assistant"; content: string };
  toolEvents: ToolEvent[];
  proposal?: Proposal;
  options?: OptionsData;
  /** Histórico completo atualizado (formato nativo Anthropic, sem o system). */
  messages: ClaudeMessage[];
  /** Uma entrada de usage por chamada à API feita neste turno. */
  usage: ClaudeUsage[];
  error?: string;
  errorStatus?: number;
}

export interface RunAgentLoopParams {
  system: ClaudeTextBlock[];
  messages: ClaudeMessage[];
  tools?: ToolDef[];
  toolCtx: ToolCtx;
  /** Sessão (ai_operator_sessions) — usada pra registrar pending_actions e audit. */
  sessionId: string;
  model?: string;
  maxIterations?: number;
  /** Guardado no payload de auditoria — o loop em si é agnóstico de canal. */
  channel?: "panel" | "whatsapp" | "system";
}

type AutoDisambigConfig = {
  question: (query: string, total: number) => string;
  label: (item: any) => string;
  value: (item: any) => string;
};

// Desambiguação automática HARDCODED (só estas 4 tools) — porte fiel do comportamento
// original: quando a busca volta >1 resultado, o LOOP monta as opções direto, sem
// depender do modelo decidir chamar present_options.
const AUTO_DISAMBIG: Record<string, AutoDisambigConfig> = {
  search_clients: {
    question: (q, n) => (n > 5 ? `Encontrei ${n} clientes para "${q}". Escolha ou refine:` : `Qual cliente chamado "${q}"?`),
    label: (c) => {
      const parts = [c.name];
      const contact = c.whatsapp || c.phone || c.email || c.cpf_cnpj || c.city;
      if (contact) parts.push(contact);
      return parts.join(" — ");
    },
    value: (c) => c.id,
  },
  search_vessels: {
    question: (q, n) => (n > 5 ? `Encontrei ${n} embarcações para "${q}". Escolha ou refine:` : `Qual embarcação chamada "${q}"?`),
    label: (v) => [v.name, v.model, v.year].filter(Boolean).join(" · "),
    value: (v) => v.id,
  },
  search_products: {
    question: (q, n) => (n > 5 ? `Encontrei ${n} produtos para "${q}". Escolha ou refine:` : `Qual produto para "${q}"?`),
    label: (p) => `${p.name}${p.sale_price ? ` — R$ ${Number(p.sale_price).toFixed(2)}` : ""}`,
    value: (p) => p.id,
  },
  list_service_orders: {
    question: (_q, n) => (n > 5 ? `Encontrei ${n} ordens de serviço. Escolha ou refine:` : "Qual ordem de serviço?"),
    label: (so) => `${so.numero} — R$ ${Number(so.valor_total || 0).toFixed(2)} — ${so.status}${so.embarcacao && so.embarcacao !== "—" ? ` · ${so.embarcacao}` : ""}`,
    value: (so) => so.id,
  },
};

function humanizeToolName(name: string): string {
  return name.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function buildPendingSummary(toolDef: ToolDef, args: Record<string, unknown>): string {
  const lines = [toolDef.description, "", "**Parâmetros:**"];
  for (const [k, v] of Object.entries(args || {})) {
    lines.push(`- ${k}: ${typeof v === "object" ? JSON.stringify(v) : String(v)}`);
  }
  return lines.join("\n");
}

function summarizeForAudit(result: unknown): string {
  const text = JSON.stringify(result ?? null);
  return text.length > 500 ? `${text.slice(0, 500)}…` : text;
}

/** Auditoria best-effort — nunca derruba o turno se falhar. */
async function writeAudit(
  toolCtx: ToolCtx,
  sessionId: string,
  channel: string | undefined,
  entry: { eventType: string; risk: string; args: unknown; result: unknown }
): Promise<void> {
  try {
    await toolCtx.admin.from("ai_operator_audit").insert({
      session_id: sessionId,
      actor_user_id: toolCtx.userId,
      actor_kind: "ai_model",
      event_type: entry.eventType,
      event_category: "data",
      payload: { channel: channel ?? "panel", risk: entry.risk, args: entry.args, result_summary: summarizeForAudit(entry.result) },
    });
  } catch (e) {
    console.error("[agent] falha ao gravar auditoria:", e);
  }
}

function textFromContent(content: ClaudeContentBlock[]): string {
  return content
    .filter((b): b is ClaudeTextBlock => b.type === "text")
    .map((b) => b.text)
    .join("");
}

/**
 * Clona `messages` e marca cache_control no último bloco de conteúdo da última
 * mensagem — segundo breakpoint de cache. Como cada iteração reenvia o histórico
 * inteiro do turno, isso permite cache hit no prefixo que cresce a cada rodada.
 * Não muta o array canônico (o `messages` guardado para a próxima iteração/turno
 * fica limpo, sem marcador).
 */
function withTrailingCacheMark(messages: ClaudeMessage[]): ClaudeMessage[] {
  if (messages.length === 0) return messages;
  const cloned = messages.map((m) => ({ role: m.role, content: m.content.map((b) => ({ ...b })) }));
  const lastMsg = cloned[cloned.length - 1];
  if (lastMsg.content.length > 0) {
    (lastMsg.content[lastMsg.content.length - 1] as any).cache_control = { type: "ephemeral" };
  }
  return cloned;
}

/**
 * Loop de tool-calling agnóstico de canal. Recebe o histórico em formato nativo
 * Anthropic e devolve o resultado do turno (mensagem final, ou proposal/options
 * para a UI aguardar o usuário). Quem chama decide como renderizar cada canal.
 */
export async function runAgentLoop(params: RunAgentLoopParams): Promise<AgentTurnResult> {
  const tools = params.tools ?? allTools;
  const model = params.model ?? MODEL_AGENT;
  const maxIterations = params.maxIterations ?? DEFAULT_MAX_ITERATIONS;
  const messages: ClaudeMessage[] = params.messages.map((m) => ({ role: m.role, content: [...m.content] }));
  const toolEvents: ToolEvent[] = [];
  const usageLog: ClaudeUsage[] = [];

  const toolSchemas = tools.map((t) => ({ name: t.name, description: t.description, input_schema: t.input_schema }));
  const toolsByName: Record<string, ToolDef> = Object.fromEntries(tools.map((t) => [t.name, t]));

  for (let iter = 0; iter < maxIterations; iter++) {
    let result;
    try {
      result = await callClaude({
        model,
        system: params.system,
        messages: withTrailingCacheMark(messages),
        tools: toolSchemas,
        maxTokens: DEFAULT_MAX_TOKENS,
        // "medium" deixava cada volta do loop (cada tool-call) lenta o bastante para
        // somar 38-66s em pedidos com várias etapas — "low" é suficiente para um
        // assistente de CRUD/consulta de negócio (não é pesquisa complexa) e reduz a
        // latência por chamada sem desligar o raciocínio de vez.
        effort: model === MODEL_AGENT ? "low" : undefined,
      });
    } catch (e: any) {
      return {
        message: { role: "assistant", content: "" },
        toolEvents,
        messages,
        usage: usageLog,
        error: e?.message || "Falha ao chamar a Anthropic API",
        errorStatus: e instanceof ClaudeApiError ? e.status : undefined,
      };
    }

    usageLog.push(result.usage);

    if (result.stopReason === "max_tokens") {
      return {
        message: { role: "assistant", content: textFromContent(result.content) },
        toolEvents,
        messages,
        usage: usageLog,
        error: "Resposta truncada por limite de tokens. Tente uma pergunta mais objetiva.",
      };
    }

    messages.push({ role: "assistant", content: result.content });

    const toolUses = result.content.filter((b): b is ClaudeToolUseBlock => b.type === "tool_use");

    if (toolUses.length === 0) {
      return {
        message: { role: "assistant", content: textFromContent(result.content) },
        toolEvents,
        messages,
        usage: usageLog,
      };
    }

    // Executa TODAS as tool_use do turno e monta UM tool_result por chamada antes
    // de decidir encerrar cedo — a API exige tool_result para toda tool_use da
    // mensagem anterior antes de qualquer novo conteúdo na próxima.
    const toolResults: ClaudeToolResultBlock[] = [];
    let shortCircuit: { proposal?: Proposal; options?: OptionsData } | null = null;

    for (const tc of toolUses) {
      const toolDef = toolsByName[tc.name];
      let toolResult: unknown;
      let createdPendingProposal: Proposal | undefined;

      const effectiveRisk = toolDef ? (toolDef.computeRisk ? toolDef.computeRisk(tc.input) : toolDef.risk) : "low";

      if (!toolDef) {
        toolResult = { error: `Tool desconhecida: ${tc.name}` };
      } else if (effectiveRisk !== "low") {
        // Interceptação por risco (Fase 3): não executa — grava a pendência e devolve
        // um tool_result sintético. A tool real só roda via confirm_action, sem LLM.
        const { data: pending, error: pendingErr } = await params.toolCtx.admin
          .from("ai_operator_pending_actions")
          .insert({
            session_id: params.sessionId,
            requested_by_user_id: params.toolCtx.userId,
            action_name: tc.name,
            risk_level: effectiveRisk,
            title: humanizeToolName(tc.name),
            summary: buildPendingSummary(toolDef, tc.input as Record<string, unknown>),
            payload: tc.input,
            status: "pending",
            expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          })
          .select("id, title, summary, risk_level")
          .single();

        if (pendingErr || !pending) {
          toolResult = { error: `Falha ao registrar pendência: ${pendingErr?.message || "erro desconhecido"}` };
        } else {
          toolResult = { pending: true, pending_action_id: pending.id, instruction: "Ação registrada para aprovação. Aguardando decisão do usuário — não repita a chamada." };
          createdPendingProposal = { pending_action_id: pending.id, title: pending.title, summary_markdown: pending.summary, risk_level: pending.risk_level };
        }
        await writeAudit(params.toolCtx, params.sessionId, params.channel, { eventType: `pending_action:${tc.name}`, risk: effectiveRisk, args: tc.input, result: toolResult });
      } else {
        try {
          toolResult = await toolDef.execute(tc.input, params.toolCtx);
        } catch (e: any) {
          toolResult = { error: e?.message || "Falha na execução da tool" };
        }
        await writeAudit(params.toolCtx, params.sessionId, params.channel, { eventType: `tool:${tc.name}`, risk: toolDef.risk, args: tc.input, result: toolResult });
      }

      toolEvents.push({ name: tc.name, args: tc.input, result: toolResult });
      toolResults.push({ type: "tool_result", tool_use_id: tc.id, content: JSON.stringify(toolResult) });

      if (!shortCircuit) {
        const disambig = AUTO_DISAMBIG[tc.name];
        const items: any[] = (toolResult as any)?.results ?? [];
        if (disambig && items.length > 1) {
          const searchQuery = (tc.input as any)?.query || (tc.input as any)?.client_id || "";
          const top5 = items.slice(0, 5);
          const options: OptionItem[] = top5.map((item) => ({ label: disambig.label(item).slice(0, 60), value: disambig.value(item) }));
          if (items.length > 5) options.push({ label: "🔍 Refinar busca — digitar mais detalhes", value: "__refine__" });
          shortCircuit = { options: { question: disambig.question(searchQuery, items.length), options } };
        } else if (createdPendingProposal) {
          shortCircuit = { proposal: createdPendingProposal };
        } else if (tc.name === "present_options") {
          const input = tc.input as any;
          shortCircuit = { options: { question: input.question, options: input.options } };
        }
      }
    }

    messages.push({ role: "user", content: toolResults });

    if (shortCircuit) {
      return {
        message: { role: "assistant", content: textFromContent(result.content) },
        toolEvents,
        messages,
        usage: usageLog,
        ...shortCircuit,
      };
    }
    // Sem short-circuit — segue pro próximo giro do loop.
  }

  return {
    message: { role: "assistant", content: "" },
    toolEvents,
    messages,
    usage: usageLog,
    error: "Limite de iterações de tool-calling atingido",
  };
}

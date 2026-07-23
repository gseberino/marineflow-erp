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
import { isAutonomyGranted } from "./autonomy-policy.ts";
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
  /** Teto de tempo do turno em ms. Protege contra o limite de parede da Edge Function
   * (~150s): estourar devolve 546 e joga fora TODO o trabalho já pago. Padrão 100s. */
  timeBudgetMs?: number;
  /** Guardado no payload de auditoria — o loop em si é agnóstico de canal. */
  channel?: "panel" | "whatsapp" | "system";
  /** Esforço de raciocínio do modelo agente. Painel e WhatsApp usam o MESMO cérebro
   * (este runAgentLoop), mas podem pedir esforços diferentes: painel faz trabalho
   * complexo de ERP (montar orçamento com vários itens) e tolera mais latência →
   * "medium"; WhatsApp é conversa rápida → "low". Padrão "low" se omitido. */
  effort?: "low" | "medium" | "high";
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
  // list_service_orders foi REMOVIDO daqui de propósito: é uma tool de LISTAGEM, não de
  // escolha. Forçar "qual ordem de serviço?" quebrava pedidos legítimos de consulta
  // ("pesquise os preços já usados nas OS anteriores") — o usuário não queria escolher uma.
  // Quando realmente for preciso escolher, o modelo chama present_options.
};

function humanizeToolName(name: string): string {
  return name.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}


// Rótulos em pt-BR para as ações que passam por aprovação — mesmo mapeamento usado no
// sino de aprovações do painel (src/components/ai/PendingActionsBell.tsx), pra o título
// ficar igual nos dois canais. Ferramenta gated nova sem entrada aqui cai no fallback
// (nome técnico humanizado) em vez de quebrar.
const TOOL_LABELS_PT: Record<string, string> = {
  register_payment: "Registrar pagamento",
  register_deposit_and_convert: "Registrar sinal e converter em OS",
  receive_purchase_order: "Receber ordem de compra",
  cancel_service_order: "Cancelar OS",
  reopen_service_order: "Reabrir OS",
  send_whatsapp_message: "Enviar WhatsApp a cliente",
  send_collection_reminder: "Enviar lembrete de cobrança",
  send_service_order_link: "Enviar link da OS ao cliente",
  schedule_whatsapp_message: "Agendar WhatsApp a cliente",
};

function humanizeToolNamePt(name: string): string {
  return TOOL_LABELS_PT[name] || humanizeToolName(name);
}

// Nomes técnicos de parâmetro -> rótulo pt-BR. Cobre os campos usados pelas tools gated
// (financial.ts, purchasing.ts, service-orders.ts, whatsapp.ts).
const FIELD_LABELS_PT: Record<string, string> = {
  receivable_id: "Recebível",
  payable_id: "Conta a pagar",
  service_order_id: "OS/Orçamento",
  po_id: "Pedido de compra",
  client_id: "Cliente",
  amount: "Valor",
  payment_date: "Data do pagamento",
  payment_method: "Forma de pagamento",
  installments: "Parcelas",
  card_fee_percent: "Taxa de cartão (%)",
  notes: "Observações",
  reason: "Motivo",
  to_phone: "Telefone",
  message: "Mensagem",
  custom_message: "Mensagem personalizada",
  scheduled_at: "Agendado para",
  recurrence_type: "Recorrência",
  collection_id: "Cobrança",
  due_days: "Prazo (dias)",
};

const CURRENCY_FIELDS = new Set(["amount", "card_fee_percent"]);
const DATE_FIELDS = new Set(["payment_date", "scheduled_at"]);
const fmtBRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

function formatFieldValue(key: string, v: unknown): string {
  if (v === null || v === undefined) return "—";
  if (key === "amount" && typeof v === "number") return fmtBRL.format(v);
  if (CURRENCY_FIELDS.has(key) && key !== "amount" && typeof v === "number") return `${v}%`;
  if (DATE_FIELDS.has(key) && typeof v === "string") {
    const d = new Date(v);
    if (!isNaN(d.getTime())) return d.toLocaleDateString("pt-BR");
  }
  return typeof v === "object" ? JSON.stringify(v) : String(v);
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Troca um UUID cru pelo identificador que a pessoa reconhece (nº da OS, descrição da
 * cobrança etc.) — best-effort: qualquer falha de consulta mantém o UUID como fallback. */
async function resolveIdLabel(admin: any, key: string, id: string): Promise<string> {
  try {
    if (key === "receivable_id" || key === "payable_id") {
      const table = key === "receivable_id" ? "receivables" : "payables";
      const { data } = await admin.from(table).select("description").eq("id", id).maybeSingle();
      if (data?.description) return data.description;
    } else if (key === "service_order_id") {
      const { data } = await admin.from("service_orders").select("service_order_number").eq("id", id).maybeSingle();
      if (data?.service_order_number) return data.service_order_number;
    } else if (key === "po_id") {
      const { data } = await admin.from("purchase_orders").select("po_number").eq("id", id).maybeSingle();
      if (data?.po_number) return data.po_number;
    } else if (key === "client_id") {
      const { data } = await admin.from("clients").select("name").eq("id", id).maybeSingle();
      if (data?.name) return data.name;
      // A IA às vezes passa o id de um app_user (a própria pessoa) como client_id —
      // resolve o nome mesmo assim, pra nunca mostrar UUID cru pro usuário.
      const { data: u } = await admin.from("app_users").select("full_name").eq("id", id).maybeSingle();
      if (u?.full_name) return u.full_name;
    } else if (key === "collection_id") {
      const { data } = await admin.from("collections").select("description").eq("id", id).maybeSingle();
      if (data?.description) return data.description;
    }
  } catch {
    // best-effort — cai no UUID original
  }
  return id;
}

/**
 * Resumo da ação pendente mostrado ao usuário (painel e WhatsApp) — mesmo texto nos dois
 * canais. Usa asterisco simples (padrão WhatsApp; o painel exibe este campo como texto
 * puro, então não há perda de negrito lá). Não expõe a descrição técnica da tool (escrita
 * para o modelo, não para o usuário) nem UUIDs crus quando dá pra resolver o nome real.
 */
async function buildPendingSummary(admin: any, toolName: string, args: Record<string, unknown>): Promise<string> {
  // Macros de fluxo: a confirmação PRECISA mostrar o que vai acontecer de verdade (a lista
  // do lote, os passos da aprovação) — os args crus não bastam. Resolve o conteúdo real.
  if (toolName === "send_bulk_collection_reminders") {
    const ids: string[] = Array.isArray(args?.collection_ids) ? (args.collection_ids as string[]) : [];
    if (ids.length === 0) return "Nenhuma cobrança selecionada.";
    let rows: any[] = [];
    try {
      const { data } = await admin.from("collections").select("contact_name, amount, due_date").in("id", ids);
      rows = (data as any[]) || [];
    } catch { /* best-effort */ }
    if (rows.length === 0) return `Enviar cobrança para ${ids.length} cliente(s) selecionado(s).`;
    const hoje = Date.now();
    const linhas = rows.map((r) => {
      const dias = r.due_date ? Math.floor((hoje - new Date(`${r.due_date}T00:00:00`).getTime()) / 86400000) : 0;
      const atraso = dias > 0 ? ` · ${dias}d de atraso` : "";
      return `- ${r.contact_name || "cliente"}: ${fmtBRL.format(Number(r.amount) || 0)}${atraso}`;
    });
    const total = rows.reduce((a, r) => a + (Number(r.amount) || 0), 0);
    return `Enviar cobrança por WhatsApp para *${rows.length}* cliente(s):\n${linhas.join("\n")}\nTotal: *${fmtBRL.format(total)}*`;
  }
  if (toolName === "approve_quote_full") {
    const osLabel = args?.service_order_id ? await resolveIdLabel(admin, "service_order_id", String(args.service_order_id)) : "orçamento";
    const dep = typeof args?.deposit_amount === "number" ? fmtBRL.format(args.deposit_amount) : String(args?.deposit_amount ?? "—");
    const partes = [`Aprovar *${osLabel}*: registrar sinal de *${dep}* (${args?.payment_method || "forma não informada"}) e converter em OS`];
    if (Number(args?.follow_up_in_days) > 0) partes.push(`agendar follow-up em ${args.follow_up_in_days} dia(s)`);
    if (args?.scheduled_start_at) {
      const d = new Date(String(args.scheduled_start_at));
      partes.push(`agendar a OS para ${isNaN(d.getTime()) ? args.scheduled_start_at : d.toLocaleString("pt-BR")}`);
    }
    return partes.map((p) => `- ${p}`).join("\n");
  }

  const lines: string[] = [];
  for (const [k, v] of Object.entries(args || {})) {
    const label = FIELD_LABELS_PT[k] || humanizeToolName(k);
    let value = formatFieldValue(k, v);
    if (typeof v === "string" && UUID_RE.test(v)) value = await resolveIdLabel(admin, k, v);
    lines.push(`- ${label}: ${value}`);
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
  entry: { eventType: string; risk: string; args: unknown; result: unknown; autonomous?: boolean }
): Promise<void> {
  try {
    await toolCtx.admin.from("ai_operator_audit").insert({
      session_id: sessionId,
      actor_user_id: toolCtx.userId,
      actor_kind: "ai_model",
      event_type: entry.eventType,
      // Ação sensível executada SEM confirmação (autonomia concedida) entra como 'security'
      // para ficar fácil de auditar depois "o que o agente fez sozinho".
      event_category: entry.autonomous ? "security" : "data",
      payload: {
        channel: channel ?? "panel",
        risk: entry.risk,
        args: entry.args,
        result_summary: summarizeForAudit(entry.result),
        ...(entry.autonomous ? { autonomous: true } : {}),
      },
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

  // ORÇAMENTO DE TEMPO — o que realmente protege o turno.
  // A Edge Function do Supabase tem teto de parede de ~150s: estourar devolve HTTP 546 e o
  // turno INTEIRO é descartado — o usuário paga todas as chamadas do LLM e não recebe nada.
  // Foi o que aconteceu ao subir maxIterations de 8 para 24: contar iterações não protege,
  // porque cada chamada leva de 5 a 35 segundos. Aqui paramos ANTES do limite e devolvemos o
  // que já foi feito (as mensagens são persistidas por quem chama, então "continue" retoma).
  const inicioDoTurno = Date.now();
  const orcamentoMs = params.timeBudgetMs ?? 100_000; // margem confortável sob os 150s
  let pausadoPorTempo = false;

  for (let iter = 0; iter < maxIterations; iter++) {
    if (Date.now() - inicioDoTurno > orcamentoMs) {
      pausadoPorTempo = true;
      break;
    }
    let result;
    try {
      result = await callClaude({
        model,
        system: params.system,
        messages: withTrailingCacheMark(messages),
        tools: toolSchemas,
        maxTokens: DEFAULT_MAX_TOKENS,
        // Esforço configurável por canal (ver RunAgentLoopParams.effort): painel usa
        // "medium" (trabalho complexo), WhatsApp "low" (conversa rápida). Só o modelo
        // agente raciocina; o lite (Haiku) não recebe effort.
        effort: model === MODEL_AGENT ? (params.effort ?? "low") : undefined,
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

      // Autonomia concedida pelo dono para ESTA ação (Onda 2). Ações de dinheiro/destrutivas
      // nunca entram aqui — ver NEVER_AUTONOMOUS.
      const autonomo = toolDef ? isAutonomyGranted(tc.name, effectiveRisk, params.toolCtx.settings) : false;

      if (!toolDef) {
        toolResult = { error: `Tool desconhecida: ${tc.name}` };
      } else if (effectiveRisk !== "low" && !autonomo) {
        // Interceptação por risco (Fase 3): não executa — grava a pendência e devolve
        // um tool_result sintético. A tool real só roda via confirm_action, sem LLM.
        const { data: pending, error: pendingErr } = await params.toolCtx.admin
          .from("ai_operator_pending_actions")
          .insert({
            session_id: params.sessionId,
            requested_by_user_id: params.toolCtx.userId,
            action_name: tc.name,
            risk_level: effectiveRisk,
            title: humanizeToolNamePt(tc.name),
            summary: await buildPendingSummary(params.toolCtx.admin, tc.name, tc.input as Record<string, unknown>),
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
        await writeAudit(params.toolCtx, params.sessionId, params.channel, {
          eventType: `tool:${tc.name}`,
          risk: toolDef.risk,
          args: tc.input,
          result: toolResult,
          autonomous: effectiveRisk !== "low", // sensível que rodou direto = autonomia concedida
        });
      }

      toolEvents.push({ name: tc.name, args: tc.input, result: toolResult });
      toolResults.push({ type: "tool_result", tool_use_id: tc.id, content: JSON.stringify(toolResult) });

      if (!shortCircuit) {
        const disambig = AUTO_DISAMBIG[tc.name];
        const items: any[] = (toolResult as any)?.results ?? [];
        // Em TRABALHO COMPOSTO (o modelo disparou várias buscas no mesmo turno, ex.: montar um
        // orçamento com 20 itens), interromper a cada busca ambígua inviabiliza a tarefa: vira
        // uma pergunta por item. Nesse caso devolvemos a lista ao modelo, que escolhe e informa
        // o que escolheu — ou chama present_options por conta própria se estiver realmente em
        // dúvida. A desambiguação forçada continua valendo quando a busca é o assunto do turno.
        const trabalhoComposto = toolUses.length > 1;
        if (disambig && items.length > 1 && !trabalhoComposto) {
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

  // Saída por tempo é DIFERENTE de erro: o trabalho até aqui é válido e está salvo.
  if (pausadoPorTempo) {
    return {
      message: {
        role: "assistant",
        content:
          "Cheguei ao limite de tempo desta rodada, mas **o que já fiz está salvo**. " +
          "Me diga *continue* que eu retomo exatamente de onde parei.",
      },
      toolEvents,
      messages,
      usage: usageLog,
    };
  }

  return {
    message: {
      role: "assistant",
      content:
        "Fiz várias etapas nesta rodada e cheguei ao limite de passos. **O que já fiz está salvo** — " +
        "me diga *continue* para eu seguir de onde parei.",
    },
    toolEvents,
    messages,
    usage: usageLog,
  };
}

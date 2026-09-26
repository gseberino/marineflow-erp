import { resumirPedido } from "./tools/caixa.ts";
import { resumirEnvioAoCliente } from "./tools/whatsapp.ts";
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
import { CHAVE_DO_SOLICITANTE, type Solicitante } from "./tools/registry.ts";
import { isAutonomyGranted } from "./autonomy-policy.ts";
import { DEFAULT_MAX_TOKENS, MAX_ITERATIONS as DEFAULT_MAX_ITERATIONS, MODEL_AGENT } from "./models.ts";
import { PERFIL_OPERACAO, rodaDiretoPelaRede, SO_PELA_REDE } from "./perfil-operacao.ts";

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
  // Desde 26/09/2026 o padrão é o PDF anexado; o formato vai no resumo da confirmação.
  send_service_order_link: "Enviar orçamento/OS ao cliente (WhatsApp)",
  schedule_whatsapp_message: "Agendar WhatsApp a cliente",
  followup_send_touch: "Enviar toque de acompanhamento (IA acompanha)",
  criar_missao_acompanhamento: "Deixar a IA acompanhar",
  cancelar_missao_acompanhamento: "Encerrar acompanhamento da IA",
  update_service_order_notes: "Editar observações do orçamento/OS",
  update_payable: "Corrigir conta a pagar",
  update_receivable: "Corrigir conta a receber",
  desfazer_aprovacao_de_lancamento: "Desfazer aprovação de lançamento",
  cancelar_lancamento: "Cancelar lançamento",
  casar_lancamento_com_extrato: "Casar lançamento com o extrato",
  cadastrar_contraparte_do_extrato: "Cadastrar a partir do extrato",
  fechar_mes: "Fechar o mês",
  lancar_no_caixa: "Lançar no Caixa (dinheiro)",
  ajustar_saldo_do_caixa: "Acertar o Caixa pela contagem",
  anotar_transacao_do_banco: "Anotar transação que o banco vai trazer",
  configurar_lancamento_automatico: "Ligar/desligar o lançar sozinho",
  // As que pedem confirmação quando chegam pela rede de segurança (perfil-operacao.ts,
  // SO_PELA_REDE): sem rótulo, o dono aprovava um nome técnico em inglês às cegas.
  review_entity_note: "Aprovar ou rejeitar anotação da memória",
  convert_external_quote_to_so: "Converter orçamento externo em OS",
  remove_service_order_step: "Remover passo do roteiro",
  reopen_service_order_step: "Reabrir passo do roteiro",
  reorder_service_order_step: "Reordenar passos do roteiro",
  review_ai_step: "Revisar passo sugerido pela IA",
  remove_service_order_expense: "Remover gasto da OS",
  create_composed_product: "Criar produto composto/kit",
  criar_categoria_de_despesa: "Criar categoria de despesa",
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
  // Correção de lançamento (update_payable/update_receivable e lancamentos.ts)
  supplier_id: "Fornecedor",
  payee_id: "Favorecido",
  linked_service_order_id: "OS",
  expense_category: "Categoria",
  category: "Categoria",
  description: "Descrição",
  issue_date: "Data",
  due_date: "Vencimento",
  cost_center_id: "Centro de custo",
  limpar: "Deixar vazio",
  motivo: "Motivo",
  bank_transaction_id: "Linha do extrato",
  proposta_id: "Linha do Extrato",
  tipo_de_favorecido: "Tipo de favorecido",
  vinculos: "Casar com",
  mes: "Mês",
  ano: "Ano",
  ligado: "Ligado",
  conta: "Conta",
  sentido: "Tipo",
  valor: "Valor",
  descricao: "O que foi",
  quem: "Quem",
  os: "OS",
  pago_por: "Pago por",
  socio: "Sócio",
  saldo_contado: "Saldo contado",
  documento: "Documento",
};

const CURRENCY_FIELDS = new Set(["amount", "card_fee_percent"]);
const DATE_FIELDS = new Set(["payment_date", "scheduled_at", "issue_date", "due_date"]);
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
    } else if (key === "supplier_id") {
      const { data } = await admin.from("suppliers").select("name").eq("id", id).maybeSingle();
      if (data?.name) return data.name;
    } else if (key === "payee_id") {
      const { data } = await admin.from("payees").select("name").eq("id", id).maybeSingle();
      if (data?.name) return data.name;
    } else if (key === "linked_service_order_id") {
      const { data } = await admin.from("service_orders").select("service_order_number").eq("id", id).maybeSingle();
      if (data?.service_order_number) return data.service_order_number;
    } else if (key === "cost_center_id") {
      const { data } = await admin.from("cost_centers").select("name").eq("id", id).maybeSingle();
      if (data?.name) return data.name;
    } else if (key === "proposta_id") {
      const { data } = await admin.from("finance_review_queue").select("title, suggested_amount").eq("id", id).maybeSingle();
      if (data?.title) return `${data.title} · ${fmtBRL.format(Number(data.suggested_amount) || 0)}`;
    } else if (key === "bank_transaction_id") {
      // A linha do extrato como o dono a reconhece: data, quem e quanto.
      const { data } = await admin.from("bank_transactions")
        .select("transaction_date, counterparty_name, description, amount").eq("id", id).maybeSingle();
      if (data) {
        const quando = String(data.transaction_date ?? "").split("-").reverse().join("/");
        return `${quando} · ${data.counterparty_name || data.description || "sem descrição"} · ${fmtBRL.format(Number(data.amount) || 0)}`;
      }
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
  // Dinheiro vivo e anotação: a confirmação mostra o pedido JÁ RESOLVIDO (categoria, quem,
  // Caixa ou bolso do sócio) — o "sim" tem de ser sobre o que vai acontecer de fato.
  if (toolName === "lancar_no_caixa" || toolName === "anotar_transacao_do_banco") {
    try {
      const r = await resumirPedido({ admin } as unknown as ToolCtx, toolName, args);
      if (r) return r;
    } catch { /* cai no resumo genérico */ }
  }
  // Envio ao cliente: o "sim <PIN>" tem de ser sobre QUEM recebe, em que número, qual
  // documento, quanto e em que formato (o padrão é o PDF com preço e PIX). O resumo mora ao
  // lado da tool (tools/whatsapp.ts), que lê o destino do mesmo cadastro.
  if (toolName === "send_service_order_link") {
    try {
      const r = await resumirEnvioAoCliente(admin, args);
      if (r) return r;
    } catch { /* cai no resumo genérico */ }
  }
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
  if (toolName === "send_supplier_quote_request") {
    const partes: string[] = [];
    // Código COT-XXXXX, nunca o UUID da cotação.
    if (args?.quote_request_id) {
      try {
        const { data } = await admin.from("quote_requests").select("code").eq("id", String(args.quote_request_id)).maybeSingle();
        if (data?.code) partes.push(`Cotação: *${data.code}*`);
      } catch { /* best-effort */ }
    }
    // Fornecedores: NOME + TELEFONE (o dono confirma por aí, não por UUID). Avisa quem está sem telefone.
    const ids: string[] = Array.isArray(args?.supplier_ids) ? (args.supplier_ids as string[]) : [];
    if (ids.length) {
      let linhas: string[] = [`Enviar para ${ids.length} fornecedor(es):`];
      try {
        const { data } = await admin.from("suppliers").select("id, name, trade_name, phone, opt_out_whatsapp").in("id", ids);
        const byId: Record<string, any> = Object.fromEntries(((data as any[]) || []).map((s) => [s.id, s]));
        linhas = linhas.concat(ids.map((id) => {
          const s = byId[id];
          if (!s) return `- (fornecedor não encontrado: ${id})`;
          const nome = s.trade_name || s.name || "sem nome";
          const tel = s.phone ? ` — ${s.phone}` : " — ⚠️ sem telefone cadastrado";
          return `- ${nome}${tel}${s.opt_out_whatsapp ? " · 🚫 opt-out" : ""}`;
        }));
      } catch { /* best-effort */ }
      partes.push(linhas.join("\n"));
    }
    return partes.length ? partes.join("\n") : "Enviar pedido de cotação.";
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

const ROTULO_DO_CARGO: Record<string, string> = {
  admin: "Administrador",
  technician: "Técnico",
  financial: "Financeiro",
  seller: "Vendedor",
  external_seller: "Vendedor Externo",
};

/**
 * Quem está pedindo, para gravar na pendência (ToolDef.gravarSolicitante). O cargo é o do ctx
 * — o autenticado neste turno, nunca um argumento do modelo. O nome é só para o resumo:
 * best-effort, falhar a leitura não impede a pendência.
 */
async function quemPede(ctx: ToolCtx): Promise<Solicitante> {
  let nome: string | null = null;
  try {
    const { data } = await ctx.admin.from("app_users").select("full_name").eq("id", ctx.userId).maybeSingle();
    if (typeof data?.full_name === "string" && data.full_name.trim()) nome = data.full_name.trim();
  } catch { /* sem nome: o cargo é o que a execução revalida */ }
  return { user_id: ctx.userId, nome, cargo: ctx.userRole };
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
  entry: { eventType: string; risk: string; args: unknown; result: unknown; autonomous?: boolean; detalhe?: Record<string, unknown> }
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
        ...(entry.detalhe ?? {}),
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
 * D18 (decisão do dono, 17/09/2026) — perfil enxuto de tools.
 *
 * As 194 tools custavam ~35 mil tokens por chamada e 138 delas nunca tinham sido usadas.
 * Com `app_settings.ai_tool_profile = 'operacao'`, só entram no turno as tools de
 * PERFIL_OPERACAO (perfil-operacao.ts — a lista mora no código desde 26/09/2026; o banco
 * guarda só o liga/desliga), as de risco alto (ações que o dono aprova no sino — e que o
 * `confirm_action` precisa encontrar) e qualquer tool cujo nome apareça no pedido do usuário
 * ("use a list_low_stock"). Qualquer outro valor no setting, ou erro de leitura, devolve a
 * lista completa: o corte de custo nunca pode virar um agente sem mãos.
 */
const PERFIL_DE_TOOLS = { validoAte: 0, ativo: false };

// Nome antigo mantido: o SEMPRE_NO_PERFIL daqui foi unificado com a lista que morava no banco
// em PERFIL_OPERACAO (26/09/2026). Testes e outras frentes ainda importam por este nome.
// Ferramenta nova que o dono quer usar conversando entra em perfil-operacao.ts, não aqui.
export { PERFIL_OPERACAO as SEMPRE_NO_PERFIL };

function textoDoUltimoPedido(messages: ClaudeMessage[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role !== "user") continue;
    return messages[i].content
      .map((b) => ((b as { type?: string; text?: string }).type === "text" ? String((b as { text?: string }).text ?? "") : ""))
      .join(" ");
  }
  return "";
}

async function aplicarPerfilDeTools(todas: ToolDef[], params: RunAgentLoopParams): Promise<ToolDef[]> {
  try {
    if (Date.now() > PERFIL_DE_TOOLS.validoAte) {
      const { data } = await params.toolCtx.admin
        .from("app_settings").select("key, value")
        .in("key", ["ai_tool_profile"]);
      const mapa = Object.fromEntries(((data ?? []) as { key: string; value: string }[]).map((r) => [r.key, r.value]));
      PERFIL_DE_TOOLS.ativo = mapa.ai_tool_profile === "operacao";
      PERFIL_DE_TOOLS.validoAte = Date.now() + 5 * 60_000;
    }
  } catch {
    return todas;
  }
  if (!PERFIL_DE_TOOLS.ativo) return todas;
  const pedido = textoDoUltimoPedido(params.messages).toLowerCase();
  return todas.filter((t) =>
    t.risk === "high" || PERFIL_OPERACAO.has(t.name) ||
    (pedido.length > 0 && pedido.includes(t.name))
  );
}

/**
 * REDE DE SEGURANÇA DO PERFIL (26/09/2026).
 *
 * O perfil esconde ferramentas que o prompt ensina. Quando o modelo obedece o prompt e chama
 * uma delas, antes ele recebia "Tool desconhecida" — foi o que aconteceu em 25/09 com
 * send_document_pdf_to_self. A rede alcança SÓ as de SO_PELA_REDE (perfil-operacao.ts: o que o
 * prompt ensina e fica fora do perfil de propósito), e delas só as que estão em params.tools, a
 * lista JÁ filtrada por cargo e canal (ai-agent/index.ts). Nunca allTools, e nunca qualquer tool
 * fora do perfil: vários `roles` são frouxos (create_purchase_order não tem roles,
 * get_technician_commissions abre para external_seller), e o perfil era a única coisa que as
 * mantinha longe de técnico e vendedor — a rede não pode devolver o que ele escondia.
 *
 * O modelo chamou sem ver o esquema, então o argumento é conferido contra o input_schema (e, se
 * estiver errado, volta o erro COM o esquema para ele acertar na próxima rodada). Passou: roda
 * direto só o que rodaDiretoPelaRede aceita (risco low declarado, e leitura ou escrita de
 * sugestão/análise de ESCRITAS_VERIFICADAS_DA_REDE) e o computeRisk calcula low; todo o resto
 * vira pendência de confirmação, sem autonomia — escrita de risco low inclusive, porque o modelo
 * a chamou sem ter lido a descrição e os limites dela.
 */

/**
 * Confere os argumentos contra o input_schema: obrigatórios presentes, enum válido e nenhuma
 * chave fora de properties. Não confere tipo de propósito — rejeitar demais custa tanto quanto
 * aceitar errado, e a própria tool já recusa valor que não serve. Devolve a lista de problemas
 * em português (vazia = pode seguir).
 */
export function validarArgumentosDaTool(schema: Record<string, unknown>, args: unknown): string[] {
  if (args === null || typeof args !== "object" || Array.isArray(args)) {
    return ["os argumentos precisam ser um objeto JSON com os campos do input_schema"];
  }
  const entrada = args as Record<string, unknown>;
  const props = ((schema?.properties ?? {}) as Record<string, { enum?: unknown[]; items?: { enum?: unknown[] } }>);
  const obrigatorios = Array.isArray(schema?.required) ? (schema.required as string[]) : [];
  const problemas: string[] = [];
  for (const campo of obrigatorios) {
    const v = entrada[campo];
    if (v === undefined || v === null || v === "") problemas.push(`falta o campo obrigatório '${campo}'`);
  }
  for (const [campo, valor] of Object.entries(entrada)) {
    const def = props[campo];
    if (!def) {
      problemas.push(`o campo '${campo}' não existe nesta ferramenta`);
      continue;
    }
    if (valor === undefined || valor === null) continue;
    if (Array.isArray(def.enum) && !def.enum.includes(valor)) {
      problemas.push(`'${campo}' aceita só: ${def.enum.map(String).join(", ")}`);
    }
    if (Array.isArray(def.items?.enum) && Array.isArray(valor)) {
      const fora = valor.filter((x) => !def.items!.enum!.includes(x));
      if (fora.length) problemas.push(`'${campo}' aceita só: ${def.items.enum.map(String).join(", ")}`);
    }
  }
  return problemas;
}

/** O resultado da tool traz `error` preenchido (é o formato de falha das tools e do catch do loop). */
function temErro(resultado: unknown): boolean {
  return resultado !== null && typeof resultado === "object" && Boolean((resultado as { error?: unknown }).error);
}

/**
 * Loop de tool-calling agnóstico de canal. Recebe o histórico em formato nativo
 * Anthropic e devolve o resultado do turno (mensagem final, ou proposal/options
 * para a UI aguardar o usuário). Quem chama decide como renderizar cada canal.
 */
export async function runAgentLoop(params: RunAgentLoopParams): Promise<AgentTurnResult> {
  const tools = await aplicarPerfilDeTools(params.tools ?? allTools, params);
  const model = params.model ?? MODEL_AGENT;
  const maxIterations = params.maxIterations ?? DEFAULT_MAX_ITERATIONS;
  const messages: ClaudeMessage[] = params.messages.map((m) => ({ role: m.role, content: [...m.content] }));
  const toolEvents: ToolEvent[] = [];
  const usageLog: ClaudeUsage[] = [];

  const toolSchemas = tools.map((t) => ({ name: t.name, description: t.description, input_schema: t.input_schema }));
  const toolsByName: Record<string, ToolDef> = Object.fromEntries(tools.map((t) => [t.name, t]));
  // Rede de segurança do perfil: SÓ SO_PELA_REDE, e dela só o que cargo e canal já liberaram
  // (params.tools). Nunca allTools, nunca outra tool fora do perfil (ver o comentário acima).
  const alcancaveisPelaRede: Record<string, ToolDef> = Object.fromEntries(
    (params.tools ?? []).filter((t) => SO_PELA_REDE.has(t.name)).map((t) => [t.name, t]),
  );

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
      // Escondida pelo perfil, em SO_PELA_REDE e liberada por cargo e canal → rede (ver acima).
      const foraDoPerfil = toolsByName[tc.name] ? undefined : alcancaveisPelaRede[tc.name];
      const toolDef = toolsByName[tc.name] ?? foraDoPerfil;
      const argumentosInvalidos = foraDoPerfil ? validarArgumentosDaTool(foraDoPerfil.input_schema, tc.input) : [];
      let toolResult: unknown;
      let createdPendingProposal: Proposal | undefined;
      let executou = false;

      const riscoDaTool = toolDef ? (toolDef.computeRisk ? toolDef.computeRisk(tc.input) : toolDef.risk) : "low";
      // Pela rede, só roda direto o que o computeRisk CALCULA como low e rodaDiretoPelaRede aceita:
      // declarada low E leitura ou escrita de sugestão/análise (ESCRITAS_VERIFICADAS_DA_REDE).
      // Escrita low fora dessa lista, ou declarada acima de low e rebaixada pelo computeRisk, pede
      // confirmação. Só sobe o risco, nunca rebaixa.
      const effectiveRisk = foraDoPerfil && riscoDaTool === "low" && !rodaDiretoPelaRede(foraDoPerfil) ? "medium" : riscoDaTool;

      // Autonomia concedida pelo dono para ESTA ação (Onda 2). Ações de dinheiro/destrutivas
      // nunca entram aqui — ver NEVER_AUTONOMOUS. Pela rede também não: a autonomia foi dada
      // pensando no modelo que VÊ a ferramenta, não no que a chama de memória do prompt. Os
      // argumentos vão junto porque há trava por argumento: o envio do PDF ao cliente nunca roda
      // sozinho (NEVER_AUTONOMOUS_WHEN).
      const autonomo = toolDef && !foraDoPerfil
        ? isAutonomyGranted(tc.name, effectiveRisk, params.toolCtx.settings, tc.input as Record<string, unknown>)
        : false;

      if (!toolDef) {
        toolResult = { error: `Tool desconhecida: ${tc.name}` };
      } else if (argumentosInvalidos.length > 0) {
        // Nada roda: devolve o que está errado JUNTO com o esquema, que o modelo não tinha visto.
        toolResult = {
          error: `Argumentos inválidos para ${tc.name}: ${argumentosInvalidos.join("; ")}.`,
          input_schema: toolDef.input_schema,
          instruction: "Nada foi executado. Corrija os argumentos seguindo o input_schema acima e chame a ferramenta de novo.",
        };
      } else if (effectiveRisk !== "low" && !autonomo) {
        // Recusa barata ANTES de a pendência nascer (ToolDef.preValidar): o dono não vê no
        // sino — nem aprova com PIN — um pedido que a execução vai recusar de qualquer jeito.
        let recusa: ({ error: string } & Record<string, unknown>) | null = null;
        try {
          recusa = toolDef.preValidar?.(tc.input, params.toolCtx) ?? null;
        } catch (e: any) {
          recusa = { error: `Falha ao validar o pedido: ${e?.message || "erro desconhecido"}` };
        }
        if (recusa) {
          toolResult = recusa;
          await writeAudit(params.toolCtx, params.sessionId, params.channel, { eventType: `pre_validacao_recusada:${tc.name}`, risk: effectiveRisk, args: tc.input, result: toolResult });
        } else {
          // Interceptação por risco (Fase 3): não executa — grava a pendência e devolve
          // um tool_result sintético. A tool real só roda via confirm_action, sem LLM.
          //
          // Quem pediu vai junto quando a tool pede (ToolDef.gravarSolicitante): a pendência é
          // executada com o ctx de quem CONFIRMA, e um admin pode aprovar a de outro — a tool
          // revalida com o cargo de quem pediu. Grava POR CIMA de qualquer `_solicitante` que
          // tenha vindo nos argumentos do modelo, e o resumo é montado sem ele.
          const entrada = { ...((tc.input ?? {}) as Record<string, unknown>) };
          const solicitante = toolDef.gravarSolicitante ? await quemPede(params.toolCtx) : null;
          if (solicitante) delete entrada[CHAVE_DO_SOLICITANTE];
          let resumo = await buildPendingSummary(params.toolCtx.admin, tc.name, solicitante ? entrada : tc.input as Record<string, unknown>);
          if (solicitante) {
            resumo += `\nPedido por: *${solicitante.nome || "—"}* (${ROTULO_DO_CARGO[solicitante.cargo] ?? solicitante.cargo})`;
          }
          const { data: pending, error: pendingErr } = await params.toolCtx.admin
            .from("ai_operator_pending_actions")
            .insert({
              session_id: params.sessionId,
              requested_by_user_id: params.toolCtx.userId,
              action_name: tc.name,
              risk_level: effectiveRisk,
              title: humanizeToolNamePt(tc.name),
              summary: resumo,
              payload: solicitante ? { ...entrada, [CHAVE_DO_SOLICITANTE]: solicitante } : tc.input,
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
        }
      } else {
        executou = true;
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

      // Marca própria da rede: 'fora_do_perfil:%' na auditoria mostra quais ferramentas o prompt
      // faz o modelo procurar fora do perfil — a que aparecer com frequência merece entrar nele.
      // Rodou mas devolveu { error } (ou lançou, e o catch acima virou { error }) é falha, não
      // execução: senão a auditoria diz que a rede resolveu quando o modelo recebeu erro.
      if (foraDoPerfil) {
        const desfecho = argumentosInvalidos.length > 0
          ? "argumentos_invalidos"
          : executou
          ? (temErro(toolResult) ? "falha_na_execucao" : "executada")
          : createdPendingProposal ? "pendencia" : "falha_ao_registrar_pendencia";
        await writeAudit(params.toolCtx, params.sessionId, params.channel, {
          eventType: `fora_do_perfil:${tc.name}`,
          risk: effectiveRisk,
          args: tc.input,
          result: toolResult,
          detalhe: { desfecho },
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

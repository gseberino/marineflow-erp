// MarineFlow AI Operator — Risk classification (deterministic gate)
// ----------------------------------------------------------------
// Este módulo é a fonte da verdade sobre QUAIS ações são consideradas
// sensíveis e exigem aprovação explícita do usuário antes de serem
// executadas, independentemente do que o modelo de linguagem diga.
//
// A regra é: o que NÃO estiver listado como SAFE é tratado como sensível.

export type RiskLevel = "low" | "medium" | "high" | "critical";

export type RiskClassification = {
  level: RiskLevel;
  // Se requires_approval = true, o backend NÃO executa a ação automaticamente.
  // Em vez disso, persiste em ai_operator_pending_actions e devolve o id
  // para o frontend mostrar um card de aprovação.
  requires_approval: boolean;
  reason: string;
};

// Ações seguras — leitura, busca, propostas de rascunho interno.
// Estas podem rodar sem aprovação porque NÃO afetam dados oficiais
// nem disparam comunicação com clientes externos.
const SAFE_ACTIONS = new Set<string>([
  // Leitura de domínio
  "search_clients",
  "search_vessels",
  "search_products",
  "search_services",
  "list_agenda",
  "list_service_orders",
  "get_service_order",
  "get_client_history",
  "get_vessel_history",
  "list_technicians",
  "list_marinas",
  // Operações internas do AI Operator (não afetam dados do ERP)
  "open_session",
  "log_audit",
  "create_draft",
  "update_draft",
  "add_draft_item",
  "ask_pending_question",
  "register_memory_candidate",
  "register_memory_note", // alias legado — também tratado como candidate no executor
  "present_options",
  "propose_action",
  "propose_entity_link",
  "list_recent_drafts",
  "summarize_request",
  "estimate_quote",
]);

// Mapeamento explícito de risco por action. Tudo que não estiver aqui e não
// estiver em SAFE_ACTIONS é tratado como HIGH por segurança.
const RISK_MAP: Record<string, RiskClassification> = {
  // ----- ESCRITAS NO ERP (pendentes de aprovação) -----
  create_service_order: {
    level: "high",
    requires_approval: true,
    reason: "Cria registro oficial de OS no ERP.",
  },
  update_service_order_status: {
    level: "high",
    requires_approval: true,
    reason: "Muda o status de uma OS oficial.",
  },
  add_service_order_item: {
    level: "medium",
    requires_approval: true,
    reason: "Adiciona produto a uma OS oficial.",
  },
  add_service_to_order: {
    level: "medium",
    requires_approval: true,
    reason: "Adiciona serviço de mão de obra a uma OS oficial.",
  },
  schedule_service_order: {
    level: "high",
    requires_approval: true,
    reason: "Agenda OS — bloqueia técnico e horário.",
  },
  apply_service_order_discount: {
    level: "high",
    requires_approval: true,
    reason: "Desconto comercial.",
  },
  create_client: {
    level: "medium",
    requires_approval: true,
    reason: "Cria cliente no ERP.",
  },
  create_vessel: {
    level: "medium",
    requires_approval: true,
    reason: "Cria embarcação/motorhome no ERP.",
  },
  create_product: {
    level: "medium",
    requires_approval: true,
    reason: "Cria produto no catálogo.",
  },
  create_purchase_order: {
    level: "high",
    requires_approval: true,
    reason: "Compromisso financeiro com fornecedor.",
  },
  create_agenda_task: {
    level: "medium",
    requires_approval: true,
    reason: "Reserva agenda real de técnico.",
  },
  update_agenda_task: {
    level: "medium",
    requires_approval: true,
    reason: "Altera compromisso real de agenda.",
  },
  // ----- COMUNICAÇÃO EXTERNA (críticas) -----
  send_whatsapp_message: {
    level: "critical",
    requires_approval: true,
    reason: "Envia mensagem real para cliente via WhatsApp.",
  },
  send_collection_reminder: {
    level: "critical",
    requires_approval: true,
    reason: "Envia cobrança real para cliente.",
  },
  send_service_order_link: {
    level: "critical",
    requires_approval: true,
    reason: "Envia link/orçamento real para cliente.",
  },
  schedule_whatsapp_message: {
    level: "high",
    requires_approval: true,
    reason: "Agenda envio futuro para cliente.",
  },
  cancel_scheduled_whatsapp: {
    level: "medium",
    requires_approval: true,
    reason: "Cancela envio agendado.",
  },
  // ----- ESTOQUE / FINANCEIRO -----
  adjust_inventory: {
    level: "high",
    requires_approval: true,
    reason: "Ajuste de estoque é financeiro.",
  },
  // ----- CONVERSÃO DE RASCUNHO -----
  convert_draft_to_service_order: {
    level: "high",
    requires_approval: true,
    reason: "Materializa um rascunho como OS oficial.",
  },
  // ----- GOVERNANÇA DE MEMÓRIA -----
  verify_memory_note: {
    level: "medium",
    requires_approval: true,
    reason: "Promove memória técnica candidata a fato verificado.",
  },
  reject_memory_note: {
    level: "low",
    requires_approval: true,
    reason: "Marca memória candidata como rejeitada.",
  },
};

export function classifyAction(name: string): RiskClassification {
  if (SAFE_ACTIONS.has(name)) {
    return { level: "low", requires_approval: false, reason: "Ação somente leitura ou interna ao AI Operator." };
  }
  if (RISK_MAP[name]) return RISK_MAP[name];
  // Fallback DEFENSIVO: ações desconhecidas são tratadas como HIGH.
  return {
    level: "high",
    requires_approval: true,
    reason: "Ação não classificada — bloqueada por padrão até classificação explícita.",
  };
}

export function isSafeAction(name: string): boolean {
  return SAFE_ACTIONS.has(name);
}

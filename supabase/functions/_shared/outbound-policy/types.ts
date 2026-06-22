// Outbound Policy Engine — tipos
//
// Espinha de segurança do AI Operator. TODA ação que sai para o cliente
// (WhatsApp, cobrança, confirmação, link, documento) passa por aqui — tanto
// as ações manuais do operador quanto os follow-ups autônomos (Camada 2).
//
// Princípio (definido com o usuário): back-office o AI executa direto; só o
// que vai para o cliente passa por este filtro. Auto-envia o que é claramente
// seguro; só interrompe no que exige julgamento.

export type OutboundActionType =
  | "send_whatsapp_message" // mensagem livre ao cliente
  | "send_service_order_link" // link de orçamento/OS
  | "send_document" // PDF (orçamento/OS/recibo)
  | "send_collection_reminder" // lembrete de cobrança
  | "send_charge" // cobrança efetiva (dinheiro)
  | "request_client_confirmation" // pedir confirmação ao cliente
  | "schedule_whatsapp_message"; // agendar envio

export type Channel = "whatsapp" | "email" | "sms";

export type Relationship = "known_client" | "new_lead" | "unknown";

export interface OutboundAction {
  type: OutboundActionType;
  channel: Channel;
  recipient: {
    phone?: string | null;
    /** Se o número já foi validado como existente no WhatsApp. */
    phoneValidated?: boolean;
    clientId?: string | null;
  };
  content: {
    text?: string | null;
    /** true se o texto ainda tem variáveis não resolvidas (ex: "{{cliente}}"). */
    hasUnresolvedPlaceholders?: boolean;
    documentUrl?: string | null;
  };
  money?: {
    amount?: number | null;
    currency?: string | null;
    /** true se a ação cobra dinheiro do cliente. */
    isCharge?: boolean;
  };
  meta?: {
    /** Confiança do modelo na ação (0..1). */
    aiConfidence?: number;
    /** Chave de idempotência para dedupe de envios. */
    idempotencyKey?: string;
  };
}

export interface PolicyContext {
  now: Date;
  relationship: Relationship;
  /** Quantos envios já foram feitos a este destinatário na janela de dedupe. */
  recentSendsToRecipient?: number;
  lastSendAt?: Date | null;
  /** Resultado da verificação de idempotência feita pelo chamador. */
  isDuplicate?: boolean;
}

export interface BusinessHours {
  startHour: number; // 0..23
  endHour: number; // 0..23 (exclusivo)
  /** Dias permitidos: 0=Dom ... 6=Sáb. */
  days: number[];
}

export interface ApprovalManager {
  /**
   * Contato único de WhatsApp (o gestor de aprovações) que recebe TODOS os
   * pedidos de confirmação, lembretes e avisos. Normalmente o dono do negócio.
   * Formato E.164 sem símbolos (ex: "5547999990000"). null = não configurado.
   */
  whatsapp: string | null;
}

export interface PolicyConfig {
  /** Quando true, o chamador NÃO executa nada — só registra a decisão. */
  shadowMode: boolean;
  /** Contato do gestor de aprovações (para onde vão confirmações/avisos). */
  approvalManager: ApprovalManager;
  /**
   * Quando true, QUALQUER envio ao cliente exige confirmação do gestor antes
   * de sair (orçamento incluído) — independente de valor. É o modo conservador
   * de partida: o AI prepara tudo, mas você confirma no WhatsApp. Pode ser
   * afrouxado por tipo conforme a confiança cresce (graduação de autonomia).
   */
  clientSendsRequireManagerConfirmation: boolean;
  /** Auto-envio permitido abaixo deste valor (cliente conhecido). */
  autoSendMaxValue: number;
  /** Limite mais rígido para lead novo/desconhecido. */
  newLeadAutoSendMaxValue: number;
  businessHours: BusinessHours;
  /** Intervalo mínimo (min) entre envios ao mesmo destinatário. */
  minFrequencyGapMinutes: number;
  /** Abaixo desta confiança → exige aprovação. */
  minAiConfidence: number;
  /** Tipos que SEMPRE exigem humano (dinheiro/legal). */
  alwaysHumanTypes: OutboundActionType[];
}

export type Decision = "auto_send" | "needs_approval" | "blocked";

export type ReasonCode =
  | "missing_phone"
  | "phone_not_validated"
  | "duplicate"
  | "empty_content"
  | "unresolved_placeholders"
  | "always_human_type"
  | "is_charge"
  | "value_above_threshold"
  | "low_ai_confidence"
  | "outside_business_hours"
  | "frequency_gap_violation"
  | "new_or_unknown_relationship"
  | "requires_manager_confirmation"
  | "passed_all_rules";

export interface PolicyReason {
  code: ReasonCode;
  /** Severidade que esta razão impõe à decisão. */
  level: Decision;
  message: string;
}

export interface ApprovalRoute {
  /** Para onde o pedido de aprovação/confirmação deve ser enviado. */
  kind: "manager_whatsapp" | "in_app";
  /** Número do gestor quando kind=manager_whatsapp; null se não configurado. */
  to: string | null;
}

export interface PolicyDecision {
  /** Decisão efetiva computada pelas regras. */
  decision: Decision;
  reasons: PolicyReason[];
  /**
   * Se true, o chamador deve apenas REGISTRAR `decision` e NÃO executar.
   * (modo sombra — para ganhar confiança antes de ativar de verdade)
   */
  shadow: boolean;
  /**
   * Quando decision === "needs_approval", indica para onde mandar o pedido de
   * confirmação. Vai para o WhatsApp do gestor se configurado; senão, in-app.
   * undefined quando não há aprovação a rotear (auto_send/blocked).
   */
  approvalRoute?: ApprovalRoute;
}

// Outbound Policy Engine — avaliador de regras (puro, sem efeitos colaterais)
//
// evaluateOutbound() é determinístico e testável. Não envia nada, não toca
// banco — só decide. O chamador (edge function) executa ou enfileira conforme
// a decisão, respeitando o flag `shadow`.
//
// Combinação de severidade (a mais restritiva vence):
//   blocked > needs_approval > auto_send
// Coletamos TODAS as razões para auditoria/transparência.

import type {
  Decision,
  OutboundAction,
  PolicyConfig,
  PolicyContext,
  PolicyDecision,
  PolicyReason,
} from "./types.ts";

const SEVERITY: Record<Decision, number> = {
  auto_send: 0,
  needs_approval: 1,
  blocked: 2,
};

function mostRestrictive(reasons: PolicyReason[]): Decision {
  let worst: Decision = "auto_send";
  for (const r of reasons) {
    if (SEVERITY[r.level] > SEVERITY[worst]) worst = r.level;
  }
  return worst;
}

function isWithinBusinessHours(now: Date, cfg: PolicyConfig): boolean {
  const day = now.getDay();
  const hour = now.getHours();
  return (
    cfg.businessHours.days.includes(day) &&
    hour >= cfg.businessHours.startHour &&
    hour < cfg.businessHours.endHour
  );
}

export function evaluateOutbound(
  action: OutboundAction,
  ctx: PolicyContext,
  cfg: PolicyConfig,
): PolicyDecision {
  const reasons: PolicyReason[] = [];

  // ---- BLOQUEIOS (hard stops) ----
  if (action.channel === "whatsapp" || action.channel === "sms") {
    if (!action.recipient.phone) {
      reasons.push({
        code: "missing_phone",
        level: "blocked",
        message: "Destinatário sem telefone.",
      });
    } else if (action.recipient.phoneValidated === false) {
      reasons.push({
        code: "phone_not_validated",
        level: "blocked",
        message: "Número não validado no WhatsApp.",
      });
    }
  }

  if (ctx.isDuplicate) {
    reasons.push({
      code: "duplicate",
      level: "blocked",
      message: "Envio duplicado (idempotência).",
    });
  }

  if (action.content.hasUnresolvedPlaceholders) {
    reasons.push({
      code: "unresolved_placeholders",
      level: "blocked",
      message: "Conteúdo tem variáveis não resolvidas.",
    });
  }

  const needsText =
    action.type === "send_whatsapp_message" ||
    action.type === "schedule_whatsapp_message";
  if (needsText && !(action.content.text && action.content.text.trim())) {
    reasons.push({
      code: "empty_content",
      level: "blocked",
      message: "Mensagem vazia.",
    });
  }

  // ---- SEMPRE HUMANO (dinheiro/legal) ----
  if (cfg.alwaysHumanTypes.includes(action.type)) {
    reasons.push({
      code: "always_human_type",
      level: "needs_approval",
      message: `Ação "${action.type}" sempre exige aprovação humana.`,
    });
  }
  if (action.money?.isCharge) {
    reasons.push({
      code: "is_charge",
      level: "needs_approval",
      message: "Cobrança de dinheiro exige aprovação humana.",
    });
  }

  // ---- VALOR x RELACIONAMENTO ----
  const amount = action.money?.amount ?? 0;
  const threshold =
    ctx.relationship === "known_client"
      ? cfg.autoSendMaxValue
      : cfg.newLeadAutoSendMaxValue;
  if (amount > threshold) {
    reasons.push({
      code: "value_above_threshold",
      level: "needs_approval",
      message: `Valor ${amount} acima do limite de auto-envio (${threshold}).`,
    });
  }
  if (
    (ctx.relationship === "new_lead" || ctx.relationship === "unknown") &&
    amount > 0
  ) {
    reasons.push({
      code: "new_or_unknown_relationship",
      level: "needs_approval",
      message: "Lead novo/desconhecido com valor — exige aprovação.",
    });
  }

  // ---- CONFIANÇA DO MODELO ----
  const conf = action.meta?.aiConfidence;
  if (typeof conf === "number" && conf < cfg.minAiConfidence) {
    reasons.push({
      code: "low_ai_confidence",
      level: "needs_approval",
      message: `Confiança ${conf} abaixo do mínimo (${cfg.minAiConfidence}).`,
    });
  }

  // ---- HORÁRIO COMERCIAL ----
  if (!isWithinBusinessHours(ctx.now, cfg)) {
    reasons.push({
      code: "outside_business_hours",
      level: "needs_approval",
      message: "Fora do horário comercial.",
    });
  }

  // ---- FREQUÊNCIA ----
  if (ctx.lastSendAt) {
    const gapMin = (ctx.now.getTime() - ctx.lastSendAt.getTime()) / 60000;
    if (gapMin < cfg.minFrequencyGapMinutes) {
      reasons.push({
        code: "frequency_gap_violation",
        level: "needs_approval",
        message: `Último envio há ${Math.round(gapMin)}min (< ${cfg.minFrequencyGapMinutes}min).`,
      });
    }
  }

  // ---- DECISÃO ----
  if (reasons.length === 0) {
    reasons.push({
      code: "passed_all_rules",
      level: "auto_send",
      message: "Passou em todas as regras.",
    });
  }

  return {
    decision: mostRestrictive(reasons),
    reasons,
    shadow: cfg.shadowMode,
  };
}

import { describe, it, expect } from "vitest";
import {
  evaluateOutbound,
  type OutboundAction,
  type PolicyConfig,
  type PolicyContext,
} from "../../supabase/functions/_shared/outbound-policy/index.ts";

// Config de teste determinística (shadow desligado p/ assertar decisão real;
// horário comercial cobrindo todos os dias/horas, exceto onde sobrescrito).
function cfg(over: Partial<PolicyConfig> = {}): PolicyConfig {
  return {
    shadowMode: false,
    approvalManager: { whatsapp: null },
    // desligado no baseline para validar os caminhos de auto_send;
    // ligado nos testes dedicados ao Canal do Gestor.
    clientSendsRequireManagerConfirmation: false,
    autoSendMaxValue: 1500,
    newLeadAutoSendMaxValue: 0,
    businessHours: { startHour: 0, endHour: 24, days: [0, 1, 2, 3, 4, 5, 6] },
    minFrequencyGapMinutes: 360,
    minAiConfidence: 0.8,
    alwaysHumanTypes: [
      "send_charge",
      "send_collection_reminder",
      "request_client_confirmation",
    ],
    ...over,
  };
}

function action(over: Partial<OutboundAction> = {}): OutboundAction {
  return {
    type: "send_service_order_link",
    channel: "whatsapp",
    recipient: { phone: "5547999990000", phoneValidated: true, clientId: "c1" },
    content: { text: "Olá, segue seu orçamento." },
    money: { amount: 500, currency: "BRL" },
    meta: { aiConfidence: 0.95 },
    ...over,
  };
}

function ctx(over: Partial<PolicyContext> = {}): PolicyContext {
  return {
    now: new Date("2026-06-15T10:00:00"),
    relationship: "known_client",
    lastSendAt: null,
    isDuplicate: false,
    ...over,
  };
}

describe("outbound policy — caminho feliz", () => {
  it("cliente conhecido, valor baixo, dentro de tudo → auto_send", () => {
    const d = evaluateOutbound(action(), ctx(), cfg());
    expect(d.decision).toBe("auto_send");
    expect(d.shadow).toBe(false);
  });

  it("shadow flag reflete o config", () => {
    const d = evaluateOutbound(action(), ctx(), cfg({ shadowMode: true }));
    expect(d.shadow).toBe(true);
    // mesmo em sombra, a decisão computada continua sendo a real
    expect(d.decision).toBe("auto_send");
  });
});

describe("outbound policy — bloqueios (hard stops)", () => {
  it("sem telefone → blocked", () => {
    const d = evaluateOutbound(
      action({ recipient: { phone: null, phoneValidated: true } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("blocked");
    expect(d.reasons.map((r) => r.code)).toContain("missing_phone");
  });

  it("telefone não validado → blocked", () => {
    const d = evaluateOutbound(
      action({ recipient: { phone: "5547999990000", phoneValidated: false } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("blocked");
    expect(d.reasons.map((r) => r.code)).toContain("phone_not_validated");
  });

  it("duplicado → blocked", () => {
    const d = evaluateOutbound(action(), ctx({ isDuplicate: true }), cfg());
    expect(d.decision).toBe("blocked");
  });

  it("placeholder não resolvido → blocked", () => {
    const d = evaluateOutbound(
      action({ content: { text: "Olá {{cliente}}", hasUnresolvedPlaceholders: true } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("blocked");
  });

  it("mensagem vazia (whatsapp livre) → blocked", () => {
    const d = evaluateOutbound(
      action({ type: "send_whatsapp_message", content: { text: "   " } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("blocked");
  });
});

describe("outbound policy — sempre humano (dinheiro/legal)", () => {
  it("cobrança efetiva → needs_approval", () => {
    const d = evaluateOutbound(
      action({ type: "send_charge", money: { amount: 100, isCharge: true } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.reasons.map((r) => r.code)).toContain("always_human_type");
  });

  it("lembrete de cobrança → needs_approval", () => {
    const d = evaluateOutbound(
      action({ type: "send_collection_reminder", money: { amount: 0 } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("needs_approval");
  });

  it("pedido de confirmação ao cliente → needs_approval", () => {
    const d = evaluateOutbound(
      action({ type: "request_client_confirmation", money: { amount: 0 } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("needs_approval");
  });
});

describe("outbound policy — julgamento (needs_approval)", () => {
  it("valor acima do limite (cliente conhecido) → needs_approval", () => {
    const d = evaluateOutbound(
      action({ money: { amount: 5000 } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.reasons.map((r) => r.code)).toContain("value_above_threshold");
  });

  it("lead novo com valor → needs_approval", () => {
    const d = evaluateOutbound(
      action({ money: { amount: 300 } }),
      ctx({ relationship: "new_lead" }),
      cfg(),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.reasons.map((r) => r.code)).toContain("new_or_unknown_relationship");
  });

  it("confiança baixa do modelo → needs_approval", () => {
    const d = evaluateOutbound(
      action({ meta: { aiConfidence: 0.4 } }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.reasons.map((r) => r.code)).toContain("low_ai_confidence");
  });

  it("fora do horário comercial → needs_approval", () => {
    const d = evaluateOutbound(
      action(),
      ctx(),
      cfg({ businessHours: { startHour: 8, endHour: 18, days: [] } }),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.reasons.map((r) => r.code)).toContain("outside_business_hours");
  });

  it("envio recente demais (frequência) → needs_approval", () => {
    const now = new Date("2026-06-15T10:00:00");
    const d = evaluateOutbound(
      action(),
      ctx({ now, lastSendAt: new Date("2026-06-15T09:00:00") }), // 60min < 360min
      cfg(),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.reasons.map((r) => r.code)).toContain("frequency_gap_violation");
  });
});

describe("outbound policy — canal do gestor de aprovações", () => {
  it("com confirmação do gestor ligada, orçamento de cliente conhecido → needs_approval", () => {
    const d = evaluateOutbound(
      action(),
      ctx(),
      cfg({ clientSendsRequireManagerConfirmation: true }),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.reasons.map((r) => r.code)).toContain("requires_manager_confirmation");
  });

  it("rota de aprovação vai para o WhatsApp do gestor quando configurado", () => {
    const d = evaluateOutbound(
      action(),
      ctx(),
      cfg({
        clientSendsRequireManagerConfirmation: true,
        approvalManager: { whatsapp: "5547999991111" },
      }),
    );
    expect(d.decision).toBe("needs_approval");
    expect(d.approvalRoute).toEqual({
      kind: "manager_whatsapp",
      to: "5547999991111",
    });
  });

  it("sem gestor configurado, aprovação cai no card in-app", () => {
    const d = evaluateOutbound(
      action(),
      ctx(),
      cfg({ clientSendsRequireManagerConfirmation: true }),
    );
    expect(d.approvalRoute).toEqual({ kind: "in_app", to: null });
  });

  it("auto_send não tem rota de aprovação", () => {
    const d = evaluateOutbound(action(), ctx(), cfg());
    expect(d.decision).toBe("auto_send");
    expect(d.approvalRoute).toBeUndefined();
  });
});

describe("outbound policy — combinação de severidade", () => {
  it("blocked vence needs_approval", () => {
    const d = evaluateOutbound(
      action({
        type: "send_charge", // needs_approval
        recipient: { phone: null }, // blocked
        money: { amount: 9999, isCharge: true },
      }),
      ctx(),
      cfg(),
    );
    expect(d.decision).toBe("blocked");
    // ainda registra TODAS as razões para auditoria
    const codes = d.reasons.map((r) => r.code);
    expect(codes).toContain("missing_phone");
    expect(codes).toContain("always_human_type");
  });
});

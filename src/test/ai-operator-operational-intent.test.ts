import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  detectOperationalIntent,
  buildBootstrapDraft,
} from "../../supabase/functions/ai-operator-core/operational-intent.ts";

describe("AI Operator - operational intent bootstrap", () => {
  it("detects quote intent for a clear Raymarine installation request", () => {
    const result = detectOperationalIntent(
      "Tenho um cliente que precisa de um orçamento para instalação de uma nova tela da Raymarine no fly."
    );

    expect(result).toMatchObject({
      kind: "quote",
      category: "marine_electronics",
      shouldBootstrapDraft: true,
      status: "awaiting_info",
    });
  });

  it("detects diagnosis intent for a technical failure report", () => {
    const result = detectOperationalIntent(
      "Preciso de um diagnóstico para uma passarela Besenzoni com falha intermitente."
    );

    expect(result).toMatchObject({
      kind: "diagnosis",
      shouldBootstrapDraft: true,
      status: "awaiting_info",
    });
  });

  it("does not bootstrap a casual greeting without operational intent", () => {
    const result = detectOperationalIntent("Bom dia, tudo bem?");

    expect(result).toBeNull();
  });

  it("builds an awaiting_info Raymarine bootstrap draft with pending questions and preliminary items", () => {
    const intent = detectOperationalIntent(
      "Tenho um cliente que precisa de um orçamento para instalação de uma nova tela da Raymarine no fly. Considere mão de obra, rede de comunicação auxiliar, cabos necessários, alimentação de energia, deslocamento e verifique se existem equipamentos antigos ou incompatíveis com a nova tela."
    );

    expect(intent).not.toBeNull();
    const draft = buildBootstrapDraft(intent!, {
      message:
        "Tenho um cliente que precisa de um orçamento para instalação de uma nova tela da Raymarine no fly. Considere mão de obra, rede de comunicação auxiliar, cabos necessários, alimentação de energia, deslocamento e verifique se existem equipamentos antigos ou incompatíveis com a nova tela.",
    });

    expect(draft.kind).toBe("quote");
    expect(draft.status).toBe("awaiting_info");
    expect(draft.title).toMatch(/Raymarine/i);
    expect(draft.pending_questions.length).toBeGreaterThan(0);
    expect(draft.items.map((item) => item.item_kind)).toEqual(
      expect.arrayContaining(["service", "displacement", "engineering", "risk"])
    );
  });
});

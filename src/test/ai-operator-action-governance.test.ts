import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  evaluateActionProposalGovernance,
  findOpenEquivalentPendingAction,
  isInformationalActionRequest,
} from "../../supabase/functions/ai-operator-core/action-governance.ts";

describe("AI Operator - action proposal governance", () => {
  it("classifies explanatory OS questions as informational, not execution intent", () => {
    for (const message of [
      "Qual o procedimento para transformarmos este rascunho em OS?",
      "Como este orçamento vira OS?",
      "O que acontece se eu converter?",
      "É possível gerar uma OS?",
      "Quais os próximos passos?",
    ]) {
      expect(isInformationalActionRequest(message)).toBe(true);
    }
  });

  it("does not classify explicit proposal commands as informational", () => {
    for (const message of [
      "Proponha a formalização deste rascunho como orçamento.",
      "Prepare a ação para criar a OS de diagnóstico.",
      "Registre a intenção de converter este orçamento formal aprovado em OS.",
    ]) {
      expect(isInformationalActionRequest(message)).toBe(false);
    }
  });

  it("blocks pending action creation for informational requests", () => {
    const result = evaluateActionProposalGovernance({
      latestUserMessage: "Qual o procedimento para transformarmos este rascunho em OS?",
      actionName: "create_service_order",
      draft: { id: "draft-diagnosis", kind: "diagnosis" },
      duplicate: null,
    });

    expect(result).toMatchObject({
      ok: false,
      reason: "informational_request",
      auditEvent: "action_proposal_blocked_informational_request",
    });
  });

  it("blocks create_service_order for quote drafts before creating a pending action", () => {
    const result = evaluateActionProposalGovernance({
      latestUserMessage: "Prepare a ação para criar a OS deste orçamento.",
      actionName: "create_service_order",
      draft: { id: "draft-quote", kind: "quote" },
      duplicate: { id: "existing-action", status: "approved", executed_at: null },
    });

    expect(result).toMatchObject({
      ok: false,
      reason: "quote_requires_formalization",
      auditEvent: "service_order_proposal_blocked_quote_requires_formalization",
    });
    expect(result.message).toMatch(/orcamento formal/i);
  });

  it("suppresses duplicate pending actions for the same draft/action", () => {
    const result = evaluateActionProposalGovernance({
      latestUserMessage: "Prepare a ação para criar a OS de diagnóstico.",
      actionName: "create_service_order",
      draft: { id: "draft-diagnosis", kind: "diagnosis" },
      duplicate: { id: "existing-action", status: "pending", executed_at: null },
    });

    expect(result).toMatchObject({
      ok: false,
      reason: "duplicate_open_action",
      auditEvent: "duplicate_pending_action_suppressed",
      existingActionId: "existing-action",
    });
  });

  it("allows explicit service-order proposal for diagnosis drafts without executing anything", () => {
    const result = evaluateActionProposalGovernance({
      latestUserMessage: "Prepare a ação para criar a OS de diagnóstico.",
      actionName: "create_service_order",
      draft: { id: "draft-diagnosis", kind: "diagnosis" },
      duplicate: null,
    });

    expect(result).toEqual({ ok: true });
  });

  it("finds only pending or approved non-executed equivalent actions as duplicates", () => {
    const rows = [
      { id: "rejected-action", draft_id: "draft-1", action_name: "create_service_order", status: "rejected", executed_at: null },
      { id: "executed-action", draft_id: "draft-1", action_name: "create_service_order", status: "approved", executed_at: "2026-05-23T17:00:00Z" },
      { id: "open-action", draft_id: "draft-1", action_name: "create_service_order", status: "approved", executed_at: null },
    ];

    expect(findOpenEquivalentPendingAction(rows, "draft-1", "create_service_order")).toMatchObject({
      id: "open-action",
    });
    expect(findOpenEquivalentPendingAction(rows, "draft-1", "send_whatsapp_message")).toBeNull();
  });
});

export type DraftForActionGovernance = {
  id: string | null;
  kind: string | null;
};

export type PendingActionForGovernance = {
  id: string;
  draft_id?: string | null;
  action_name?: string | null;
  status: string | null;
  executed_at: string | null;
};

export type ActionProposalGovernanceResult =
  | { ok: true }
  | {
      ok: false;
      reason: "informational_request" | "quote_requires_formalization" | "duplicate_open_action";
      message: string;
      auditEvent:
        | "action_proposal_blocked_informational_request"
        | "service_order_proposal_blocked_quote_requires_formalization"
        | "duplicate_pending_action_suppressed";
      existingActionId?: string;
    };

const OPEN_PENDING_ACTION_STATUSES = new Set(["pending", "approved"]);

function normalizeText(text: string) {
  return text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

export function isInformationalActionRequest(message: string | null | undefined): boolean {
  const normalized = normalizeText(String(message || ""));
  if (!normalized) return false;

  const explicitProposal =
    /\b(proponha|prepare|registre|formalize|crie a acao|registre a intencao|pode registrar|vamos converter|converta)\b/.test(
      normalized
    );
  if (explicitProposal) return false;

  const asksAboutProcedure =
    /\b(qual|quais|como|o que|e possivel|eh possivel|pode|procedimento|proximos passos|acontece se)\b/.test(
      normalized
    );
  const mentionsSensitiveConversion =
    /\b(os|ordem de servico|converter|conversao|transformar|virar|gerar|orcamento|formalizar)\b/.test(
      normalized
    );

  return asksAboutProcedure && (mentionsSensitiveConversion || normalized.includes("?"));
}

export function findOpenEquivalentPendingAction(
  rows: PendingActionForGovernance[],
  draftId: string | null,
  actionName: string
): PendingActionForGovernance | null {
  if (!draftId) return null;
  return (
    rows.find(
      (row) =>
        row.draft_id === draftId &&
        row.action_name === actionName &&
        OPEN_PENDING_ACTION_STATUSES.has(String(row.status || "")) &&
        !row.executed_at
    ) ?? null
  );
}

export function evaluateActionProposalGovernance(input: {
  latestUserMessage: string;
  actionName: string;
  draft: DraftForActionGovernance | null;
  duplicate: PendingActionForGovernance | null;
}): ActionProposalGovernanceResult {
  if (isInformationalActionRequest(input.latestUserMessage)) {
    return {
      ok: false,
      reason: "informational_request",
      auditEvent: "action_proposal_blocked_informational_request",
      message:
        "O usuario pediu orientacao sobre o procedimento, nao uma execucao. Explique o fluxo sem registrar pending action.",
    };
  }

  if (input.actionName === "create_service_order" && input.draft?.kind === "quote") {
    return {
      ok: false,
      reason: "quote_requires_formalization",
      auditEvent: "service_order_proposal_blocked_quote_requires_formalization",
      message:
        "Este e um rascunho interno de orcamento. A etapa correta e formalizar um orcamento formal no ERP antes de qualquer OS; essa formalizacao sera implementada em ciclo posterior. Nenhuma OS foi criada.",
    };
  }

  if (input.duplicate) {
    return {
      ok: false,
      reason: "duplicate_open_action",
      auditEvent: "duplicate_pending_action_suppressed",
      existingActionId: input.duplicate.id,
      message: "Ja existe uma intencao equivalente registrada para este rascunho.",
    };
  }

  return { ok: true };
}

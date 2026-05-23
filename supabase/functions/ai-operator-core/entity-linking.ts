export type ConfirmedEntityLinks = {
  client_id: string | null;
  vessel_id: string | null;
};

export type LinkCarrier = Partial<ConfirmedEntityLinks> | null | undefined;

export type UnexpectedEntityField =
  | "client_id"
  | "vessel_id"
  | "service_order_id"
  | "converted_service_order_id";

export type UnexpectedEntityAttempt = {
  field: UnexpectedEntityField;
  value: string;
};

const ENTITY_LINK_FIELDS: UnexpectedEntityField[] = ["client_id", "vessel_id"];
const ALL_FORBIDDEN_WRITE_FIELDS: UnexpectedEntityField[] = [
  "client_id",
  "vessel_id",
  "service_order_id",
  "converted_service_order_id",
];

const DRAFT_WRITABLE_FIELDS = [
  "title",
  "status",
  "summary",
  "interpreted_intent",
  "interpreted_category",
  "estimated_labor_hours",
  "estimated_labor_value",
  "estimated_parts_value",
  "estimated_travel_value",
  "estimated_total",
] as const;

function normalizeId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function inheritConfirmedLinks(source: LinkCarrier): ConfirmedEntityLinks {
  return {
    client_id: normalizeId(source?.client_id) ?? null,
    vessel_id: normalizeId(source?.vessel_id) ?? null,
  };
}

export function collectUnexpectedEntityAttempts(
  args: Record<string, unknown>,
  fields: UnexpectedEntityField[] = ALL_FORBIDDEN_WRITE_FIELDS
): UnexpectedEntityAttempt[] {
  const attempts: UnexpectedEntityAttempt[] = [];

  for (const field of fields) {
    const value = normalizeId(args[field]);
    if (value) attempts.push({ field, value });
  }

  return attempts;
}

export function resolveCreateDraftLinks(args: Record<string, unknown>, session: LinkCarrier) {
  return {
    links: inheritConfirmedLinks(session),
    unexpected: collectUnexpectedEntityAttempts(args, ENTITY_LINK_FIELDS),
  };
}

export function buildDraftUpdatePatch(args: Record<string, unknown>, current: LinkCarrier) {
  const patch: Record<string, unknown> = {};

  for (const key of DRAFT_WRITABLE_FIELDS) {
    if (typeof args[key] !== "undefined") patch[key] = args[key];
  }
  if (Array.isArray(args.pending_questions)) patch.pending_questions = args.pending_questions;
  if (Array.isArray(args.next_steps)) patch.next_steps = args.next_steps;
  if (Array.isArray(args.hypotheses)) patch.hypotheses = args.hypotheses;

  return {
    patch,
    links: inheritConfirmedLinks(current),
    unexpected: collectUnexpectedEntityAttempts(args),
  };
}

export function resolveMemoryCandidateLinks(
  args: Record<string, unknown>,
  context: { draft?: LinkCarrier; session?: LinkCarrier }
) {
  const draftLinks = inheritConfirmedLinks(context.draft);
  const sessionLinks = inheritConfirmedLinks(context.session);
  const client_id = draftLinks.client_id ?? sessionLinks.client_id;
  const vessel_id = draftLinks.vessel_id ?? sessionLinks.vessel_id;

  return {
    client_id,
    vessel_id,
    scope: vessel_id ? "vessel" : client_id ? "client" : "global",
    unexpected: collectUnexpectedEntityAttempts(args, ENTITY_LINK_FIELDS),
  };
}

export function resolveExplicitDraftEntitySelection(params: {
  requestedClientId: string | null;
  requestedVesselId: string | null;
  clientVisible: boolean;
  vesselVisible: boolean;
  vesselClientId: string | null;
}) {
  if (params.requestedClientId && !params.clientVisible) {
    return {
      ok: false as const,
      status: 403,
      error: "Cliente nao visivel para o usuario.",
    };
  }

  if (params.requestedVesselId && !params.vesselVisible) {
    return {
      ok: false as const,
      status: 403,
      error: "Embarcacao nao visivel para o usuario.",
    };
  }

  if (
    params.requestedClientId &&
    params.requestedVesselId &&
    params.vesselClientId &&
    params.vesselClientId !== params.requestedClientId
  ) {
    return {
      ok: false as const,
      status: 400,
      error: "A embarcacao selecionada nao pertence ao cliente informado.",
    };
  }

  return {
    ok: true as const,
    status: 200,
    client_id: params.requestedClientId,
    vessel_id: params.requestedVesselId,
  };
}

// ---------------------------------------------------------------------------
// PROPOSTA DE VINCULO (não persiste — apenas estrutura para confirmação UI)
// ---------------------------------------------------------------------------
// Macro Ciclo evolução operacional:
//   * Modelo NÃO controla draft_id. O draft alvo é definido pelo backend a
//     partir do contexto estruturado da sessão/UI.
//   * Modelo pode SUGERIR cliente e/ou embarcacao por id (obtidos de
//     search_clients / search_vessels), mas a proposta volta para a UI com
//     NOMES legíveis. Persistência só acontece via link_draft_entities após
//     confirmação humana explícita.

export type LinkProposalInput = {
  clientId: string | null;
  vesselId: string | null;
  clientVisible: boolean;
  vesselVisible: boolean;
  vesselBelongsToClient: boolean | null;
};

export type LinkProposalResult =
  | {
      ok: true;
      proposal: {
        client_id: string | null;
        vessel_id: string | null;
      };
    }
  | { ok: false; reason: "no_candidates" | "client_invisible" | "vessel_invisible" | "vessel_mismatch" };

export function resolveLinkProposal(input: LinkProposalInput): LinkProposalResult {
  if (!input.clientId && !input.vesselId) {
    return { ok: false, reason: "no_candidates" };
  }
  if (input.clientId && !input.clientVisible) {
    return { ok: false, reason: "client_invisible" };
  }
  if (input.vesselId && !input.vesselVisible) {
    return { ok: false, reason: "vessel_invisible" };
  }
  if (
    input.clientId &&
    input.vesselId &&
    input.vesselBelongsToClient === false
  ) {
    return { ok: false, reason: "vessel_mismatch" };
  }
  return {
    ok: true,
    proposal: {
      client_id: input.clientId,
      vessel_id: input.vesselId,
    },
  };
}

// ---------------------------------------------------------------------------
// RESOLUCAO ESTRUTURADA POR TERMOS HUMANOS
// ---------------------------------------------------------------------------
// O modelo informa intencao e nomes. IDs persistiveis ficam restritos ao
// backend/payload estruturado autenticado usado pela UI para confirmacao.

export type LinkResolutionClientCandidate = {
  id: string;
  name: string | null;
  type?: string | null;
};

export type LinkResolutionVesselCandidate = {
  id: string;
  name: string | null;
  manufacturer?: string | null;
  model?: string | null;
  year?: number | string | null;
  client_id?: string | null;
};

export type SafeLinkCandidate = {
  id: string;
  name: string | null;
  subtitle: string | null;
};

export type EntityLinkCompatibility = {
  status: "already_linked_to_client" | "client_only" | "vessel_only";
  message: string;
};

export type StructuredEntityLinkProposal = {
  draft_id: string;
  draft_title: string | null;
  client: SafeLinkCandidate | null;
  vessel: SafeLinkCandidate | null;
  client_candidates?: SafeLinkCandidate[];
  vessel_candidates?: SafeLinkCandidate[];
  compatibility: EntityLinkCompatibility;
  rationale: string | null;
};

export type EntityLinkResolutionResult =
  | { ok: true; persisted: false; proposal: StructuredEntityLinkProposal }
  | {
      ok: false;
      reason:
        | "no_terms"
        | "invalid_reference"
        | "client_not_found"
        | "vessel_not_found"
        | "client_ambiguous"
        | "vessel_ambiguous"
        | "vessel_mismatch";
      message: string;
      clientCandidates?: SafeLinkCandidate[];
      vesselCandidates?: SafeLinkCandidate[];
    };

function cleanHumanTerm(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed;
}

export function isSanitizedInternalReference(value: unknown): boolean {
  return typeof value === "string" && /\[?\s*referencia interna oculta\s*\]?/i.test(value);
}

function clientSubtitle(client: LinkResolutionClientCandidate): string | null {
  if (!client.type) return null;
  if (client.type === "individual") return "Cliente individual";
  if (client.type === "company") return "Cliente empresa";
  return `Cliente ${client.type}`;
}

function vesselSubtitle(vessel: LinkResolutionVesselCandidate): string | null {
  const manufacturer = vessel.manufacturer ? String(vessel.manufacturer) : "";
  const model = vessel.model ? String(vessel.model) : "";
  const parts = model.toLocaleLowerCase().includes(manufacturer.toLocaleLowerCase())
    ? [model]
    : [manufacturer, model].filter(Boolean);
  if (parts.length > 0) return parts.join(" ");
  return vessel.year ? String(vessel.year) : null;
}

export function toSafeClientCandidate(client: LinkResolutionClientCandidate): SafeLinkCandidate {
  return {
    id: client.id,
    name: client.name,
    subtitle: clientSubtitle(client),
  };
}

export function toSafeVesselCandidate(vessel: LinkResolutionVesselCandidate): SafeLinkCandidate {
  return {
    id: vessel.id,
    name: vessel.name,
    subtitle: vesselSubtitle(vessel),
  };
}

export function resolveEntityLinkByHumanTerms(input: {
  draftId: string;
  draftTitle: string | null;
  clientQuery?: string | null;
  vesselQuery?: string | null;
  clientCandidates: LinkResolutionClientCandidate[];
  vesselCandidates: LinkResolutionVesselCandidate[];
  rationale?: string | null;
}): EntityLinkResolutionResult {
  const clientQuery = cleanHumanTerm(input.clientQuery);
  const vesselQuery = cleanHumanTerm(input.vesselQuery);

  if (!clientQuery && !vesselQuery) {
    return {
      ok: false,
      reason: "no_terms",
      message: "Informe o nome do cliente, da embarcacao, ou ambos.",
    };
  }
  if (isSanitizedInternalReference(clientQuery) || isSanitizedInternalReference(vesselQuery)) {
    return {
      ok: false,
      reason: "invalid_reference",
      message: "A referencia interna usada na conversa expirou. Informe o nome do cliente ou da embarcacao.",
    };
  }

  if (clientQuery && input.clientCandidates.length === 0) {
    return { ok: false, reason: "client_not_found", message: "Cliente nao localizado para o termo informado." };
  }
  if (vesselQuery && input.vesselCandidates.length === 0) {
    return {
      ok: false,
      reason: "vessel_not_found",
      message: "Embarcacao nao localizada para o termo informado.",
    };
  }
  if (clientQuery && input.clientCandidates.length > 1) {
    return {
      ok: false,
      reason: "client_ambiguous",
      message: "Encontrei mais de um cliente possivel. Selecione o correto antes de confirmar.",
      clientCandidates: input.clientCandidates.map(toSafeClientCandidate),
    };
  }
  if (vesselQuery && input.vesselCandidates.length > 1) {
    return {
      ok: false,
      reason: "vessel_ambiguous",
      message: "Encontrei mais de uma embarcacao possivel. Selecione a correta antes de confirmar.",
      vesselCandidates: input.vesselCandidates.map(toSafeVesselCandidate),
    };
  }

  const client = clientQuery ? input.clientCandidates[0] : null;
  const vessel = vesselQuery ? input.vesselCandidates[0] : null;
  if (client && vessel && vessel.client_id && vessel.client_id !== client.id) {
    return {
      ok: false,
      reason: "vessel_mismatch",
      message: "A embarcacao localizada nao pertence ao cliente informado.",
    };
  }

  const compatibility: EntityLinkCompatibility =
    client && vessel
      ? {
          status: "already_linked_to_client",
          message: "Esta embarcacao ja esta cadastrada para este cliente.",
        }
      : client
        ? { status: "client_only", message: "A proposta vincula apenas o cliente ao rascunho." }
        : { status: "vessel_only", message: "A proposta vincula apenas a embarcacao ao rascunho." };

  return {
    ok: true,
    persisted: false,
    proposal: {
      draft_id: input.draftId,
      draft_title: input.draftTitle,
      client: client ? toSafeClientCandidate(client) : null,
      vessel: vessel ? toSafeVesselCandidate(vessel) : null,
      compatibility,
      rationale: cleanHumanTerm(input.rationale),
    },
  };
}

export function sanitizeToolEventsForFrontend(events: any[]) {
  return (Array.isArray(events) ? events : []).map((event) => {
    const result = event?.result && typeof event.result === "object" ? event.result : {};
    const results = Array.isArray(result.results) ? result.results : null;
    const history = Array.isArray(result.history) ? result.history : null;
    return {
      name: String(event?.name || "unknown"),
      blocked: !!event?.blocked,
      result_summary: {
        ...(results ? { result_count: results.length } : {}),
        ...(history ? { history_count: history.length } : {}),
        ...(typeof result.ok === "boolean" ? { ok: result.ok } : {}),
        ...(typeof result.proposed === "boolean" ? { proposed: result.proposed } : {}),
        ...(typeof result.persisted === "boolean" ? { persisted: result.persisted } : {}),
      },
    };
  });
}

// ---------------------------------------------------------------------------
// CANCELAMENTO SEGURO DE DRAFT
// ---------------------------------------------------------------------------
// Cancelamento só é permitido em estados compatíveis com erro operacional
// (draft, awaiting_info). Estados de governança/conversão (approved,
// rejected, awaiting_approval, converted) NÃO podem ser cancelados
// silenciosamente nesta fase. Drafts com pending_actions em status `pending`
// também não podem ser cancelados — o usuário precisa resolver ou rejeitar
// a ação pendente antes.

export type CancelDraftCheck =
  | { ok: true }
  | { ok: false; status: 409; reason: "invalid_status"; currentStatus: string }
  | { ok: false; status: 409; reason: "pending_actions_open"; openCount: number }
  | { ok: false; status: 404; reason: "not_found" };

const CANCELLABLE_STATUSES = new Set<string>(["draft", "awaiting_info"]);

export function evaluateCancelDraft(params: {
  draftStatus: string | null;
  pendingOpenCount: number;
}): CancelDraftCheck {
  if (!params.draftStatus) return { ok: false, status: 404, reason: "not_found" };
  if (!CANCELLABLE_STATUSES.has(params.draftStatus)) {
    return {
      ok: false,
      status: 409,
      reason: "invalid_status",
      currentStatus: params.draftStatus,
    };
  }
  if (params.pendingOpenCount > 0) {
    return {
      ok: false,
      status: 409,
      reason: "pending_actions_open",
      openCount: params.pendingOpenCount,
    };
  }
  return { ok: true };
}

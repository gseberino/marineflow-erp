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

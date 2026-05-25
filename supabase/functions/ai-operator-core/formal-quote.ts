import { isInformationalActionRequest } from "./action-governance.ts";
import { isDraftStatusOperationallyMutable } from "./entity-linking.ts";

export type DraftForExternalQuoteFormalization = {
  id: string;
  title: string | null;
  kind: string | null;
  status: string | null;
  summary?: string | null;
  client_id: string | null;
  vessel_id: string | null;
  client_name?: string | null;
  vessel_name?: string | null;
  converted_service_order_id?: string | null;
  external_quote_id?: string | null;
  service_order_id?: string | null;
  pending_questions?: string[] | null;
  next_steps?: string[] | null;
  hypotheses?: string[] | null;
};

export type FormalQuoteSummary = {
  id: string;
  quote_number?: string | null;
  status?: string | null;
} | null;

export type OfficialServiceOrderSummary = {
  id: string;
  service_order_number?: string | null;
  status?: string | null;
} | null;

export type DraftItemForExternalQuote = {
  id?: string | null;
  item_kind: string | null;
  service_id?: string | null;
  product_id?: string | null;
  description: string | null;
  notes?: string | null;
  quantity?: number | null;
  unit?: string | null;
  unit_price?: number | null;
  estimated_total?: number | null;
  position?: number | null;
};

export type ExternalQuoteFormalizationProposal = {
  draft_id: string;
  draft_title: string | null;
  client_name: string | null;
  vessel_name: string | null;
  item_count: number;
  service_count: number;
  part_count: number;
  pending_item_count: number;
  pending_questions_count: number;
  known_total: number;
  initial_status: "draft" | "pending_product";
  effects: {
    creates_external_quote: true;
    creates_service_order: false;
    sends_whatsapp: false;
    changes_stock: false;
    changes_financials: false;
    changes_schedule: false;
  };
};

export type ExternalQuoteFormalizationEligibility =
  | { ok: true }
  | {
      ok: false;
      reason:
        | "informational_request"
        | "draft_not_found"
        | "not_quote_draft"
        | "draft_status_not_operational"
        | "missing_entity_link"
        | "no_items"
        | "already_formalized";
      message: string;
      existingExternalQuoteId?: string | null;
    };

const BILLABLE_SERVICE_KINDS = new Set(["service", "engineering", "displacement"]);
const BILLABLE_PART_KINDS = new Set(["product", "product_to_quote"]);

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : [];
}

function toNumber(value: unknown, fallback = 0): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function positiveOrNull(value: unknown): number | null {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

function knownLineTotal(item: DraftItemForExternalQuote): number {
  const explicit = positiveOrNull(item.estimated_total);
  if (explicit != null) return explicit;
  const unit = positiveOrNull(item.unit_price);
  if (unit == null) return 0;
  return toNumber(item.quantity, 1) * unit;
}

export function determineExternalQuoteInitialStatus(input: {
  pendingItemCount: number;
  pendingQuestionCount: number;
}): "draft" | "pending_product" {
  return input.pendingItemCount > 0 || input.pendingQuestionCount > 0 ? "pending_product" : "draft";
}

export function mapDraftItemsToExternalQuoteRows(items: DraftItemForExternalQuote[]) {
  const parts: Array<Record<string, unknown>> = [];
  const services: Array<Record<string, unknown>> = [];
  const nonBillableNotes: string[] = [];
  let knownGrandTotal = 0;
  let pendingItemCount = 0;

  for (const item of items) {
    const kind = String(item.item_kind || "");
    const description = String(item.description || "").trim();
    if (!description) continue;

    if (BILLABLE_PART_KINDS.has(kind)) {
      const lineTotal = knownLineTotal(item);
      const unitSale = positiveOrNull(item.unit_price) ?? 0;
      const isPending = kind === "product_to_quote" || unitSale === 0 || lineTotal === 0;
      if (isPending) pendingItemCount += 1;
      knownGrandTotal += lineTotal;
      const notes = [
        item.notes || null,
        isPending ? "Pendente de cotacao: preco nao informado pelo rascunho interno." : null,
      ]
        .filter(Boolean)
        .join("\n");
      parts.push({
        product_id: item.product_id ?? null,
        product_name_snapshot: description,
        quantity: toNumber(item.quantity, 1),
        unit_cost_snapshot: 0,
        unit_sale_snapshot: unitSale,
        currency_snapshot: "BRL",
        line_total_cost: 0,
        line_total_sale: lineTotal,
        warranty_days: 0,
        notes: notes || null,
      });
      continue;
    }

    if (BILLABLE_SERVICE_KINDS.has(kind)) {
      const lineTotal = knownLineTotal(item);
      const unitPrice = positiveOrNull(item.unit_price) ?? (lineTotal > 0 ? lineTotal / Math.max(toNumber(item.quantity, 1), 1) : 0);
      const isPending = unitPrice === 0 || lineTotal === 0;
      if (isPending) pendingItemCount += 1;
      knownGrandTotal += lineTotal;
      services.push({
        service_id: item.service_id ?? null,
        service_name_snapshot: description,
        description_snapshot: item.notes ?? null,
        billing_unit_snapshot: item.unit || "unit",
        quantity: toNumber(item.quantity, 1),
        unit_price_snapshot: unitPrice,
        line_total: lineTotal,
        warranty_days: 0,
        notes: isPending
          ? [item.notes || null, "Pendente de precificacao: valor nao informado pelo rascunho interno."]
              .filter(Boolean)
              .join("\n")
          : item.notes ?? null,
      });
      continue;
    }

    nonBillableNotes.push(`${kind || "note"}: ${description}${item.notes ? ` - ${item.notes}` : ""}`);
  }

  return {
    parts,
    services,
    nonBillableNotes,
    knownGrandTotal,
    pendingItemCount,
  };
}

export function buildExternalQuoteFormalizationProposal(input: {
  draft: DraftForExternalQuoteFormalization;
  items: DraftItemForExternalQuote[];
}): ExternalQuoteFormalizationProposal {
  const mapped = mapDraftItemsToExternalQuoteRows(input.items);
  const pendingQuestions = asStringArray(input.draft.pending_questions);
  return {
    draft_id: input.draft.id,
    draft_title: input.draft.title ?? null,
    client_name: input.draft.client_name ?? null,
    vessel_name: input.draft.vessel_name ?? null,
    item_count: input.items.length,
    service_count: mapped.services.length,
    part_count: mapped.parts.length,
    pending_item_count: mapped.pendingItemCount,
    pending_questions_count: pendingQuestions.length,
    known_total: mapped.knownGrandTotal,
    initial_status: determineExternalQuoteInitialStatus({
      pendingItemCount: mapped.pendingItemCount,
      pendingQuestionCount: pendingQuestions.length,
    }),
    effects: {
      creates_external_quote: true,
      creates_service_order: false,
      sends_whatsapp: false,
      changes_stock: false,
      changes_financials: false,
      changes_schedule: false,
    },
  };
}

export function evaluateExternalQuoteFormalization(input: {
  draft: DraftForExternalQuoteFormalization | null;
  itemCount: number;
  existingExternalQuoteId: string | null;
  latestUserMessage: string | null;
}): ExternalQuoteFormalizationEligibility {
  if (isInformationalActionRequest(input.latestUserMessage)) {
    return {
      ok: false,
      reason: "informational_request",
      message:
        "O usuario pediu orientacao sobre o procedimento, nao a criacao do orcamento formal. Explique o fluxo sem criar external_quote.",
    };
  }

  if (!input.draft) {
    return { ok: false, reason: "draft_not_found", message: "Rascunho ativo nao encontrado." };
  }

  const existingExternalQuoteId = input.existingExternalQuoteId ?? input.draft.external_quote_id ?? null;
  if (existingExternalQuoteId) {
    return {
      ok: false,
      reason: "already_formalized",
      existingExternalQuoteId,
      message: "Este rascunho ja possui um orcamento formal no ERP.",
    };
  }

  if (input.draft.kind !== "quote") {
    return {
      ok: false,
      reason: "not_quote_draft",
      message: "Apenas rascunhos internos do tipo orcamento podem ser formalizados como external_quote.",
    };
  }

  if (!isDraftStatusOperationallyMutable(input.draft.status)) {
    return {
      ok: false,
      reason: "draft_status_not_operational",
      message: "Este rascunho esta em estado protegido e precisa de fluxo humano antes da formalizacao.",
    };
  }

  if (!input.draft.client_id || !input.draft.vessel_id) {
    return {
      ok: false,
      reason: "missing_entity_link",
      message: "Vincule cliente e embarcacao antes de formalizar o orcamento.",
    };
  }

  if (input.itemCount <= 0) {
    return {
      ok: false,
      reason: "no_items",
      message: "O rascunho nao possui itens para formalizar como orcamento.",
    };
  }

  return { ok: true };
}

export function buildDraftGroundingSnapshotNote(input: {
  draft: DraftForExternalQuoteFormalization;
  itemCount: number;
  pendingQuestionCount: number;
  openActionCount: number;
  formalQuote: FormalQuoteSummary;
  officialServiceOrder: OfficialServiceOrderSummary;
}): string {
  const lines = [
    "SNAPSHOT PERSISTIDO ATUAL DO RASCUNHO (fonte de verdade):",
    "Use este snapshot como estado atual. Mensagens historicas incompatíveis foram supersedidas pelo banco.",
    `- Tipo do draft: ${input.draft.kind || "desconhecido"}`,
    `- Status atual persistido: ${input.draft.status || "desconhecido"}`,
    `- Cliente vinculado: ${input.draft.client_name || "nao vinculado"}`,
    `- Embarcacao vinculada: ${input.draft.vessel_name || "nao vinculada"}`,
    `- Itens persistidos: ${input.itemCount}`,
    `- Perguntas pendentes persistidas: ${input.pendingQuestionCount}`,
    `- Acoes sensiveis abertas: ${input.openActionCount}`,
  ];

  if (input.formalQuote) {
    lines.push(
      `- Orcamento formal: existe (${input.formalQuote.quote_number || "sem numero"}, status ${input.formalQuote.status || "desconhecido"})`
    );
  } else {
    lines.push("- Orcamento formal: nao ha orcamento formal em external_quotes para este draft");
  }

  if (input.officialServiceOrder) {
    lines.push(
      `- Ordem de Servico oficial: existe (${input.officialServiceOrder.service_order_number || "sem numero"}, status ${input.officialServiceOrder.status || "desconhecido"})`
    );
  } else {
    lines.push("- Ordem de Servico oficial: nao ha Ordem de Servico oficial criada para este draft");
  }

  lines.push(
    "Nao afirme aprovacao do cliente, orcamento aprovado, formalizacao ou conversao em OS sem evidencia neste snapshot."
  );

  return lines.join("\n");
}

export function buildGroundedInformationalResponse(input: {
  draft: DraftForExternalQuoteFormalization;
  itemCount: number;
  pendingQuestionCount: number;
  formalQuote: FormalQuoteSummary;
  officialServiceOrder: OfficialServiceOrderSummary;
}): string {
  const status = input.draft.status || "desconhecido";
  const formalQuoteText = input.formalQuote
    ? `Ja existe um orcamento formal vinculado (${input.formalQuote.quote_number || "sem numero"}), em status ${input.formalQuote.status || "desconhecido"}.`
    : "Ainda nao existe orcamento formal em external_quotes para este rascunho.";
  const soText = input.officialServiceOrder
    ? `Ja existe uma OS oficial vinculada (${input.officialServiceOrder.service_order_number || "sem numero"}).`
    : "Nenhuma OS oficial foi criada.";

  return [
    `O estado persistido atual deste rascunho e **${status}**.`,
    `${formalQuoteText} ${soText}`,
    `Ele possui ${input.itemCount} itens persistidos e ${input.pendingQuestionCount} pergunta(s) pendente(s).`,
    "O procedimento correto e: primeiro formalizar o draft como orcamento no ERP, revisar/cotar os itens pendentes, aprovar o orcamento formal no modulo de orcamentos e somente depois avaliar uma conversao para OS por fluxo proprio. Nao vou propor OS direta a partir deste draft de orcamento.",
  ].join("\n\n");
}

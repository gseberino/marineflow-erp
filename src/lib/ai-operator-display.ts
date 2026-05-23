const UUID_PATTERN =
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

export function sanitizeOperatorText(text: string) {
  return text.replace(UUID_PATTERN, "[referencia interna oculta]");
}

// Mapas centralizados de exibição — todo lugar que pinta status/kind do
// rascunho deve consumir daqui para garantir consistência de PT-BR e
// evitar técnico vazando na UI.

export const DRAFT_KIND_LABELS: Record<string, string> = {
  quote: "Orçamento",
  diagnosis: "Diagnóstico",
  service_plan: "Plano de serviço",
  agenda_proposal: "Proposta de agenda",
  response_suggestion: "Sugestão de resposta",
  note: "Nota técnica",
};

export const DRAFT_STATUS_LABELS: Record<string, string> = {
  draft: "Em elaboração",
  awaiting_info: "Aguardando informações",
  awaiting_approval: "Aguardando aprovação",
  approved: "Aprovado",
  rejected: "Rejeitado",
  converted: "Convertido em OS",
  cancelled: "Cancelado",
};

export type StatusBadgeVariant = "default" | "secondary" | "destructive" | "outline";

export const DRAFT_STATUS_BADGE_VARIANT: Record<string, StatusBadgeVariant> = {
  draft: "secondary",
  awaiting_info: "outline",
  awaiting_approval: "outline",
  approved: "default",
  rejected: "destructive",
  converted: "default",
  cancelled: "destructive",
};

export const DRAFT_ITEM_KIND_LABELS: Record<string, string> = {
  service: "Mão de obra",
  product: "Produto",
  product_to_quote: "Item a cotar",
  displacement: "Deslocamento",
  engineering: "Engenharia / diagnóstico",
  pending_question: "Pergunta pendente",
  risk: "Risco / observação",
  reference: "Referência",
};

export function formatDraftKind(kind: string | null | undefined): string {
  if (!kind) return "Rascunho";
  return DRAFT_KIND_LABELS[kind] ?? kind;
}

export function formatDraftStatus(status: string | null | undefined): string {
  if (!status) return "Em elaboração";
  return DRAFT_STATUS_LABELS[status] ?? status;
}

export function formatDraftItemKind(kind: string | null | undefined): string {
  if (!kind) return "Item";
  return DRAFT_ITEM_KIND_LABELS[kind] ?? kind;
}

export function statusBadgeVariant(status: string | null | undefined): StatusBadgeVariant {
  if (!status) return "secondary";
  return DRAFT_STATUS_BADGE_VARIANT[status] ?? "outline";
}

// Estados considerados "ativos" para visualização padrão. Cancelados ficam
// fora da listagem principal por padrão; o usuário pode optar por exibi-los.
export const ACTIVE_DRAFT_STATUSES: ReadonlyArray<string> = [
  "draft",
  "awaiting_info",
  "awaiting_approval",
  "approved",
  "rejected",
  "converted",
];

export function isActiveStatus(status: string | null | undefined): boolean {
  if (!status) return true;
  return ACTIVE_DRAFT_STATUSES.includes(status);
}

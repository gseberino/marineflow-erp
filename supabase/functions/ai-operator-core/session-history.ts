export type PersistedConversationMessage = {
  role: string | null;
  content: string | null;
};

export type ModelConversationMessage = {
  role: "user" | "assistant";
  content: string;
};

export type DraftContextNoteInput = {
  title: string | null;
  status: string | null;
  summary: string | null;
  clientName: string | null;
  vesselName: string | null;
  pendingQuestions: string[];
  nextSteps: string[];
  hypotheses: string[];
  items: Array<{ item_kind: string; description: string }>;
};

const UUID_PATTERN =
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

export function redactUuidTokens(text: string) {
  return text.replace(UUID_PATTERN, "[referencia interna oculta]");
}

export function toModelConversationHistory(
  messages: PersistedConversationMessage[]
): ModelConversationMessage[] {
  return messages.flatMap((message) => {
    if ((message.role !== "user" && message.role !== "assistant") || !message.content) return [];
    return [{ role: message.role, content: redactUuidTokens(message.content) }];
  });
}

export function buildDraftContextNote(input: DraftContextNoteInput): string {
  const lines = [
    "Rascunho ativo:",
    `- Titulo: ${input.title || "Sem titulo"}`,
    `- Status: ${input.status || "draft"}`,
    `- Cliente: ${input.clientName || "nao vinculado"}`,
    `- Embarcacao: ${input.vesselName || "nao vinculada"}`,
  ];

  if (input.summary) lines.push(`- Resumo: ${input.summary}`);
  if (input.pendingQuestions.length > 0) lines.push(`- Perguntas pendentes: ${input.pendingQuestions.join(" | ")}`);
  if (input.nextSteps.length > 0) lines.push(`- Proximos passos: ${input.nextSteps.join(" | ")}`);
  if (input.hypotheses.length > 0) lines.push(`- Hipoteses: ${input.hypotheses.join(" | ")}`);
  if (input.items.length > 0) {
    lines.push(
      `- Itens tecnicos: ${input.items
        .slice(0, 8)
        .map((item) => `${item.item_kind}: ${item.description}`)
        .join(" | ")}`
    );
  }

  return lines.join("\n");
}

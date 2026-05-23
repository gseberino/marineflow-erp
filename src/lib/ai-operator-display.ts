const UUID_PATTERN =
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

export function sanitizeOperatorText(text: string) {
  return text.replace(UUID_PATTERN, "[referencia interna oculta]");
}

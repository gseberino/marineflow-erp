import { describe, expect, it } from "vitest";
import { sanitizeOperatorText } from "@/lib/ai-operator-display";

describe("AI Operator - user-visible text sanitization", () => {
  it("redacts UUIDs from assistant-visible text", () => {
    const text =
      "Criei o rascunho 6a5a1ba0-789c-403b-a391-8b0fc605e9b7 para o cliente.";

    expect(sanitizeOperatorText(text)).toBe(
      "Criei o rascunho [referencia interna oculta] para o cliente."
    );
  });

  it("keeps normal business text intact", () => {
    const text = "Criei um rascunho interno de orçamento. Ele ainda não é uma Ordem de Serviço.";

    expect(sanitizeOperatorText(text)).toBe(text);
  });
});

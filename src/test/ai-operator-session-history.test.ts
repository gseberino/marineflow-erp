import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import {
  buildDraftContextNote,
  toModelConversationHistory,
} from "../../supabase/functions/ai-operator-core/session-history.ts";

describe("AI Operator - session history continuity", () => {
  it("keeps only user and assistant conversation when rebuilding model history", () => {
    const result = toModelConversationHistory([
      { role: "system", content: "ignore" },
      { role: "user", content: "Preciso de um orçamento." },
      { role: "assistant", content: "Posso estruturar um rascunho." },
      { role: "tool", content: '{"ok":true}' },
      { role: "assistant", content: null },
    ]);

    expect(result).toEqual([
      { role: "user", content: "Preciso de um orçamento." },
      { role: "assistant", content: "Posso estruturar um rascunho." },
    ]);
  });

  it("builds structured draft context without leaking raw UUIDs", () => {
    const note = buildDraftContextNote({
      title: "Orçamento: Instalação Raymarine Axiom 12 no Fly",
      status: "awaiting_info",
      summary: "Escopo preliminar para eletrônica de navegação.",
      clientName: "Celio Yudi Shiokawa Junior",
      vesselName: null,
      pendingQuestions: ["Qual é a embarcação?"],
      nextSteps: ["Confirmar modelo da tela"],
      hypotheses: ["Pode haver backbone NMEA 2000 incompleto"],
      items: [{ item_kind: "service", description: "Mão de obra de instalação" }],
    });

    expect(note).toContain("Rascunho ativo");
    expect(note).toContain("Celio Yudi Shiokawa Junior");
    expect(note).toContain("Qual é a embarcação?");
    expect(note).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
  });
});

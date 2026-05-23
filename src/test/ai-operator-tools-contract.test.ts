import { describe, expect, it } from "vitest";
// @ts-ignore Vitest resolve .ts
import { OPERATOR_TOOLS } from "../../supabase/functions/ai-operator-core/tools.ts";
// @ts-ignore Vitest resolve .ts
import { buildSystemPrompt } from "../../supabase/functions/ai-operator-core/prompt.ts";

function findTool(name: string) {
  return OPERATOR_TOOLS.find((tool) => tool.function.name === name);
}

describe("AI Operator - tools contract for explicit entity linking", () => {
  it("does not expose entity linking as a model tool", () => {
    const names = OPERATOR_TOOLS.map((tool) => tool.function.name);
    expect(names).not.toContain("link_draft_entities");
  });

  it("create_draft, update_draft and register_memory_candidate no longer expose client_id or vessel_id", () => {
    for (const name of ["create_draft", "update_draft", "register_memory_candidate"]) {
      const tool = findTool(name);
      expect(tool).toBeDefined();
      const properties = tool?.function.parameters.properties ?? {};
      expect(properties).not.toHaveProperty("client_id");
      expect(properties).not.toHaveProperty("vessel_id");
    }
  });

  it("update_draft remains focused on draft content, not entity links", () => {
    const tool = findTool("update_draft");
    expect(tool?.function.description).toMatch(/resumo|status|perguntas|proximos passos|hipoteses/i);
    expect(tool?.function.description).not.toMatch(/vinculos seguros|cliente|embarcacao/i);
  });

  it("search_vessels does not accept model-controlled client_id filters", () => {
    const tool = findTool("search_vessels");
    expect(tool).toBeDefined();
    const properties = tool?.function.parameters.properties ?? {};
    expect(properties).not.toHaveProperty("client_id");
    expect(tool?.function.description).not.toMatch(/client_id/i);
  });

  it("draft-scoped tools do not require model-controlled draft_id for the active draft", () => {
    for (const name of ["update_draft", "add_draft_item", "ask_pending_question", "propose_action"]) {
      const tool = findTool(name);
      expect(tool).toBeDefined();
      const properties = tool?.function.parameters.properties ?? {};
      const required = tool?.function.parameters.required ?? [];
      expect(properties).not.toHaveProperty("draft_id");
      expect(required).not.toContain("draft_id");
    }
  });

  it("exposes propose_entity_link with human terms, not model-controlled UUIDs", () => {
    const tool = findTool("propose_entity_link");
    expect(tool).toBeDefined();
    const properties = tool?.function.parameters.properties ?? {};
    expect(properties).not.toHaveProperty("draft_id");
    expect(properties).not.toHaveProperty("client_id");
    expect(properties).not.toHaveProperty("vessel_id");
    expect(properties).toHaveProperty("client_query");
    expect(properties).toHaveProperty("vessel_query");
    expect(tool?.function.description).toMatch(/nao grava|nao escolhe|confirmar|interface/i);
    expect(tool?.function.description).toMatch(/nome|termos humanos/i);
  });

  it("resume_draft is a backend action endpoint, not a model tool — the model cannot trigger session switches", () => {
    const names = OPERATOR_TOOLS.map((tool) => tool.function.name);
    expect(names).not.toContain("resume_draft");
  });

  it("the system prompt forbids model-controlled entity linking and points to the authenticated UI flow", () => {
    const prompt = buildSystemPrompt({
      userName: "Tester",
      userRole: "admin",
      dateStr: "sexta-feira, 23 de maio de 2026",
      timeStr: "10:00",
      companyName: "HBR Marine",
      defaultHourlyRate: "200",
      diagnosticHourlyRate: "300",
      costPerKm: "0",
      defaultProfitMargin: "30",
      channel: "web",
      routeOrChannel: "/operator",
      entityContext: "nenhum",
    });

    expect(prompt).toMatch(/nunca use create_draft, update_draft ou register_memory_candidate para vincular cliente ou embarcacao/i);
    expect(prompt).toMatch(/link_draft_entities/i);
    expect(prompt).not.toMatch(/vinculos seguros/i);
  });
});

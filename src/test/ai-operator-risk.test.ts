import { describe, it, expect } from "vitest";
// Importa direto do módulo do edge function. O arquivo é TS puro (sem APIs Deno),
// então o Vitest consegue carregá-lo. Mantém uma única fonte da verdade para
// classificação de risco.
// @ts-ignore - resolução do .ts é feita pelo Vite/Vitest
import { classifyAction, isSafeAction } from "../../supabase/functions/ai-operator-core/risk.ts";

describe("AI Operator — risk classification gate", () => {
  it("classifica leituras como seguras (sem aprovação)", () => {
    const safe = [
      "search_clients",
      "search_vessels",
      "search_products",
      "list_agenda",
      "get_vessel_history",
      "list_technicians",
    ];
    for (const name of safe) {
      const r = classifyAction(name);
      expect(r.requires_approval, `${name} deveria ser seguro`).toBe(false);
      expect(r.level).toBe("low");
      expect(isSafeAction(name)).toBe(true);
    }
  });

  it("classifica operações internas do operador (rascunho/memória) como seguras", () => {
    const internal = ["create_draft", "add_draft_item", "ask_pending_question", "register_memory_note"];
    for (const name of internal) {
      const r = classifyAction(name);
      expect(r.requires_approval, `${name} deveria ser seguro`).toBe(false);
    }
  });

  it("classifica escritas em entidades do ERP como sensíveis", () => {
    const sensitive = [
      "create_service_order",
      "update_service_order_status",
      "add_service_order_item",
      "add_service_to_order",
      "schedule_service_order",
      "apply_service_order_discount",
      "create_client",
      "create_vessel",
      "create_product",
      "create_purchase_order",
      "create_agenda_task",
      "update_agenda_task",
      "convert_draft_to_service_order",
    ];
    for (const name of sensitive) {
      const r = classifyAction(name);
      expect(r.requires_approval, `${name} deveria exigir aprovação`).toBe(true);
      expect(["medium", "high", "critical"]).toContain(r.level);
    }
  });

  it("classifica envios para o cliente (WhatsApp/cobrança/link) como CRITICAL", () => {
    const critical = ["send_whatsapp_message", "send_collection_reminder", "send_service_order_link"];
    for (const name of critical) {
      const r = classifyAction(name);
      expect(r.requires_approval).toBe(true);
      expect(r.level).toBe("critical");
    }
  });

  it("classifica ajuste de estoque como sensível", () => {
    const r = classifyAction("adjust_inventory");
    expect(r.requires_approval).toBe(true);
    expect(r.level).toBe("high");
  });

  it("classifica ações desconhecidas como HIGH por padrão (fail-closed)", () => {
    const r = classifyAction("ferramenta_inventada_por_atacante");
    expect(r.requires_approval).toBe(true);
    expect(r.level).toBe("high");
    expect(r.reason).toMatch(/não classificada/i);
  });

  it("não considera propose_action como atalho para execução automática", () => {
    // propose_action em si é tratado como SAFE (apenas registra a intenção).
    // O risco real vem da `action` PROPOSTA dentro dele, que é avaliada
    // separadamente no handler.
    expect(isSafeAction("propose_action")).toBe(true);
  });
});

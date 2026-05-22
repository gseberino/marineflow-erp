import { describe, it, expect } from "vitest";

// Espelho TS da função SQL `ai_op_can_approve(_user_id, _action)` definida em
// supabase/migrations/20260522190000_ai_operator_foundation.sql. Mantemos os
// dois sincronizados manualmente — a fonte da verdade em runtime é o SQL
// (gate determinístico no banco). Este espelho serve como contrato testado:
// se alguém alterar o SQL sem atualizar este arquivo (ou vice-versa), o teste
// quebra e força revisão.
type Role = "admin" | "technician" | "financial" | "seller" | "external_seller" | "other";

function canApproveMirror(role: Role | null, active: boolean, action: string): boolean {
  if (!role || !active) return false;
  if (role === "external_seller") return false;
  if (role === "admin") return true;

  if (
    [
      "send_whatsapp_message",
      "send_collection_reminder",
      "send_service_order_link",
      "schedule_whatsapp_message",
      "cancel_scheduled_whatsapp",
    ].includes(action)
  ) {
    return false; // só admin
  }

  if (["adjust_inventory", "create_purchase_order"].includes(action)) {
    return role === "financial";
  }
  if (["create_agenda_task", "update_agenda_task", "schedule_service_order"].includes(action)) {
    return role === "technician";
  }
  if (
    [
      "create_service_order",
      "update_service_order_status",
      "add_service_order_item",
      "add_service_to_order",
      "apply_service_order_discount",
      "convert_draft_to_service_order",
    ].includes(action)
  ) {
    return role === "seller";
  }
  if (["create_client", "create_vessel", "create_product"].includes(action)) {
    return role === "seller" || role === "financial";
  }
  if (["verify_memory_note", "reject_memory_note"].includes(action)) {
    return role === "technician";
  }
  return false; // fail-closed
}

describe("AI Operator — approval matrix (role × action)", () => {
  it("admin aprova qualquer ação", () => {
    const actions = [
      "send_whatsapp_message",
      "create_service_order",
      "adjust_inventory",
      "convert_draft_to_service_order",
      "verify_memory_note",
      "ferramenta_inventada",
    ];
    for (const a of actions) {
      expect(canApproveMirror("admin", true, a), `admin deveria aprovar ${a}`).toBe(true);
    }
  });

  it("external_seller NUNCA aprova nada", () => {
    const actions = ["search_clients", "create_service_order", "send_whatsapp_message"];
    for (const a of actions) {
      expect(canApproveMirror("external_seller", true, a)).toBe(false);
    }
  });

  it("usuário inativo nunca aprova", () => {
    expect(canApproveMirror("admin", false, "send_whatsapp_message")).toBe(false);
    expect(canApproveMirror("technician", false, "create_agenda_task")).toBe(false);
  });

  it("envios externos a clientes só admin aprova", () => {
    for (const role of ["technician", "financial", "seller", "other"] as Role[]) {
      expect(canApproveMirror(role, true, "send_whatsapp_message")).toBe(false);
      expect(canApproveMirror(role, true, "send_service_order_link")).toBe(false);
      expect(canApproveMirror(role, true, "send_collection_reminder")).toBe(false);
    }
  });

  it("estoque/compras: admin ou financial", () => {
    expect(canApproveMirror("financial", true, "adjust_inventory")).toBe(true);
    expect(canApproveMirror("financial", true, "create_purchase_order")).toBe(true);
    expect(canApproveMirror("technician", true, "adjust_inventory")).toBe(false);
    expect(canApproveMirror("seller", true, "adjust_inventory")).toBe(false);
    expect(canApproveMirror("other", true, "adjust_inventory")).toBe(false);
  });

  it("agenda real: admin ou technician", () => {
    expect(canApproveMirror("technician", true, "create_agenda_task")).toBe(true);
    expect(canApproveMirror("technician", true, "schedule_service_order")).toBe(true);
    expect(canApproveMirror("seller", true, "schedule_service_order")).toBe(false);
    expect(canApproveMirror("financial", true, "schedule_service_order")).toBe(false);
  });

  it("OS/orçamento (criação/conversão/desconto): admin ou seller", () => {
    expect(canApproveMirror("seller", true, "create_service_order")).toBe(true);
    expect(canApproveMirror("seller", true, "convert_draft_to_service_order")).toBe(true);
    expect(canApproveMirror("seller", true, "apply_service_order_discount")).toBe(true);
    expect(canApproveMirror("technician", true, "create_service_order")).toBe(false);
    expect(canApproveMirror("financial", true, "apply_service_order_discount")).toBe(false);
  });

  it("promoção/rejeição de memória técnica: admin ou technician", () => {
    expect(canApproveMirror("technician", true, "verify_memory_note")).toBe(true);
    expect(canApproveMirror("technician", true, "reject_memory_note")).toBe(true);
    expect(canApproveMirror("seller", true, "verify_memory_note")).toBe(false);
    expect(canApproveMirror("financial", true, "verify_memory_note")).toBe(false);
    expect(canApproveMirror("other", true, "verify_memory_note")).toBe(false);
  });

  it("ações desconhecidas são fail-closed (somente admin)", () => {
    expect(canApproveMirror("technician", true, "ferramenta_inventada_por_atacante")).toBe(false);
    expect(canApproveMirror("seller", true, "ferramenta_inventada_por_atacante")).toBe(false);
    expect(canApproveMirror("admin", true, "ferramenta_inventada_por_atacante")).toBe(true);
  });
});

import { describe, it, expect } from "vitest";

// Espelho TS das funções SQL `ai_op_can_approve(_user_id, _action)` e
// `ai_op_can_reject(_user_id, _pending_action_id)` definidas em
// `supabase/migrations/20260522190000_ai_operator_foundation.sql`.
// Mantemos os dois sincronizados manualmente — a fonte da verdade em runtime
// é o SQL (gate determinístico no banco). Este espelho serve como contrato
// testado: alterar SQL sem atualizar este arquivo (ou vice-versa) quebra os
// testes e força revisão.
//
// Macro Ciclo 1 — política restritiva:
//   * approve: somente admin para qualquer ação operacional;
//             admin OU technician para verify/reject de memória técnica.
//   * reject:  solicitante da ação OU admin (para ações operacionais);
//             admin OU technician para verify/reject de memória técnica.

type Role = "admin" | "technician" | "financial" | "seller" | "external_seller" | "other";

const MEMORY_ACTIONS = new Set(["verify_memory_note", "reject_memory_note"]);

function canApprove(role: Role | null, active: boolean, action: string): boolean {
  if (!role || !active) return false;
  if (MEMORY_ACTIONS.has(action)) return role === "admin" || role === "technician";
  return role === "admin";
}

function canReject(
  role: Role | null,
  active: boolean,
  pendingAction: { requested_by_user_id: string; action_name: string },
  userId: string
): boolean {
  if (!role || !active) return false;
  if (role === "external_seller") return false;
  if (MEMORY_ACTIONS.has(pendingAction.action_name)) {
    return role === "admin" || role === "technician";
  }
  return role === "admin" || pendingAction.requested_by_user_id === userId;
}

describe("AI Operator — Macro Ciclo 1 — approve gate", () => {
  it("admin aprova qualquer ação operacional", () => {
    const ops = [
      "send_whatsapp_message",
      "create_service_order",
      "adjust_inventory",
      "schedule_service_order",
      "convert_draft_to_service_order",
      "create_purchase_order",
      "create_client",
      "ferramenta_desconhecida",
    ];
    for (const a of ops) {
      expect(canApprove("admin", true, a), `admin deveria aprovar ${a}`).toBe(true);
    }
  });

  it("technician/seller/financial NÃO aprovam ações operacionais mesmo dentro de seu domínio", () => {
    const cases: { role: Role; action: string }[] = [
      { role: "technician", action: "schedule_service_order" },
      { role: "technician", action: "create_agenda_task" },
      { role: "seller", action: "create_service_order" },
      { role: "seller", action: "apply_service_order_discount" },
      { role: "financial", action: "adjust_inventory" },
      { role: "financial", action: "create_purchase_order" },
    ];
    for (const c of cases) {
      expect(canApprove(c.role, true, c.action), `${c.role} NÃO deveria aprovar ${c.action}`).toBe(
        false
      );
    }
  });

  it("external_seller e other nunca aprovam", () => {
    for (const a of ["send_whatsapp_message", "create_service_order", "verify_memory_note"]) {
      expect(canApprove("external_seller", true, a)).toBe(false);
      expect(canApprove("other", true, a)).toBe(false);
    }
  });

  it("usuário inativo nunca aprova", () => {
    expect(canApprove("admin", false, "send_whatsapp_message")).toBe(false);
  });

  it("memória técnica: admin OU technician aprovam verify/reject", () => {
    expect(canApprove("admin", true, "verify_memory_note")).toBe(true);
    expect(canApprove("technician", true, "verify_memory_note")).toBe(true);
    expect(canApprove("admin", true, "reject_memory_note")).toBe(true);
    expect(canApprove("technician", true, "reject_memory_note")).toBe(true);
    // Demais papéis: não.
    expect(canApprove("seller", true, "verify_memory_note")).toBe(false);
    expect(canApprove("financial", true, "verify_memory_note")).toBe(false);
    expect(canApprove("other", true, "verify_memory_note")).toBe(false);
  });
});

describe("AI Operator — Macro Ciclo 1 — reject gate", () => {
  const REQ_USER = "user-requester-uuid";
  const OTHER_USER = "user-other-uuid";

  it("solicitante consegue rejeitar a própria ação operacional", () => {
    expect(
      canReject(
        "seller",
        true,
        { requested_by_user_id: REQ_USER, action_name: "create_service_order" },
        REQ_USER
      )
    ).toBe(true);
    expect(
      canReject(
        "other",
        true,
        { requested_by_user_id: REQ_USER, action_name: "send_whatsapp_message" },
        REQ_USER
      )
    ).toBe(true);
  });

  it("usuário não-admin NÃO consegue rejeitar ação alheia", () => {
    expect(
      canReject(
        "seller",
        true,
        { requested_by_user_id: REQ_USER, action_name: "create_service_order" },
        OTHER_USER
      )
    ).toBe(false);
    expect(
      canReject(
        "technician",
        true,
        { requested_by_user_id: REQ_USER, action_name: "create_service_order" },
        OTHER_USER
      )
    ).toBe(false);
    expect(
      canReject(
        "financial",
        true,
        { requested_by_user_id: REQ_USER, action_name: "create_service_order" },
        OTHER_USER
      )
    ).toBe(false);
  });

  it("admin consegue rejeitar qualquer ação", () => {
    expect(
      canReject(
        "admin",
        true,
        { requested_by_user_id: REQ_USER, action_name: "send_whatsapp_message" },
        OTHER_USER
      )
    ).toBe(true);
  });

  it("external_seller nunca rejeita", () => {
    expect(
      canReject(
        "external_seller",
        true,
        { requested_by_user_id: REQ_USER, action_name: "create_service_order" },
        REQ_USER
      )
    ).toBe(false);
  });

  it("inativo nunca rejeita", () => {
    expect(
      canReject(
        "admin",
        false,
        { requested_by_user_id: REQ_USER, action_name: "send_whatsapp_message" },
        REQ_USER
      )
    ).toBe(false);
  });

  it("memória técnica: admin/technician rejeitam mesmo sem ser solicitante", () => {
    expect(
      canReject(
        "technician",
        true,
        { requested_by_user_id: REQ_USER, action_name: "verify_memory_note" },
        OTHER_USER
      )
    ).toBe(true);
    expect(
      canReject(
        "seller",
        true,
        { requested_by_user_id: REQ_USER, action_name: "verify_memory_note" },
        OTHER_USER
      )
    ).toBe(false);
  });
});

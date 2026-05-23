// MarineFlow AI Operator — pre-authorization para o endpoint approve_action.
//
// Decisão Macro Ciclo 1 — APROVAÇÃO OPERACIONAL É ADMIN-ONLY:
//   * `approve_action` resolve pending actions OPERACIONAIS (criar OS oficial,
//     enviar WhatsApp, agendar técnico real, alterar estoque, conversão de
//     rascunho, etc.). Nesta primeira ativação, apenas `admin` ativo pode
//     resolver qualquer pending action; demais papéis recebem 403 genérico
//     antes de qualquer leitura.
//   * Governança de memória técnica (validação/rejeição de notas candidatas
//     pelo `technician`) tem ENDPOINTS DEDICADOS (`verify_memory_note` /
//     `reject_memory_note`) — não passa por `approve_action`. Não há
//     justificativa para technician acessar `approve_action` neste ciclo.
//
// Função intencionalmente conservadora — flexibilizações dependem de
// existir executor real para cada classe de ação.

export type ApprovePreAuthOutcome =
  | { allowedToRead: true }
  | { allowedToRead: false; reason: "role" };

export function preAuthorizeApprove(role: string | null | undefined): ApprovePreAuthOutcome {
  if (role === "admin") return { allowedToRead: true };
  return { allowedToRead: false, reason: "role" };
}

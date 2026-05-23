// MarineFlow AI Operator — pre-authorization para o endpoint approve_action.
//
// Antes de consultar o pending_action, papéis que jamais poderiam aprovar
// (nem operacional, nem memória técnica) são rejeitados imediatamente com
// resposta genérica 403, sem expor existência/status da ação.
//
// Decisão Macro Ciclo 1:
//   * admin       → pode aprovar qualquer ação pendente (operacional ou memória).
//   * technician  → pode aprovar verify/reject de memória técnica apenas.
//   * demais      → não passam dessa porta. 403 genérico, audit reason='role'.
//
// O escopo final (technician × memory) é re-verificado no DB-side via
// `ai_op_can_approve` depois que a ação é lida. Esta função apenas reduz
// a superfície de leitura.

export type ApprovePreAuthOutcome =
  | { allowedToRead: true }
  | { allowedToRead: false; reason: "role" };

export function preAuthorizeApprove(role: string | null | undefined): ApprovePreAuthOutcome {
  if (role === "admin" || role === "technician") return { allowedToRead: true };
  return { allowedToRead: false, reason: "role" };
}

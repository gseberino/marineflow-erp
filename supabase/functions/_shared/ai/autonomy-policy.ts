import type { RiskLevel } from "./tools/registry.ts";

/**
 * Política de autonomia item-a-item (Onda 2).
 *
 * O dono libera ações específicas para o agente executar sozinho gravando
 * `app_settings.ai_autonomy_<nome_da_tool> = 'auto'`. Qualquer outro valor (ou ausência)
 * mantém o comportamento padrão: ação sensível pede confirmação.
 *
 * Fica em módulo próprio porque é usado tanto pelo loop do agente quanto pelas tools que
 * leem/alteram a configuração — importar um do outro criaria ciclo.
 */

/**
 * TETO RÍGIDO — estas ações NUNCA rodam sozinhas, mesmo que a chave seja gravada no banco.
 * Critério: mexe em dinheiro ou é destrutivo/difícil de desfazer. Autonomia se conquista
 * nas ações reversíveis; aqui a confirmação humana é permanente por decisão de projeto.
 */
export const NEVER_AUTONOMOUS = new Set<string>([
  "register_payment",
  "register_deposit_and_convert",
  "receive_purchase_order",
  "cancel_service_order",
  "reopen_service_order",
]);

/** Prefixo das chaves em app_settings. */
export const AUTONOMY_PREFIX = "ai_autonomy_";

export function autonomyKey(toolName: string): string {
  return `${AUTONOMY_PREFIX}${toolName}`;
}

/** true = pode executar direto (sem card/"sim"). */
export function isAutonomyGranted(
  toolName: string,
  effectiveRisk: RiskLevel,
  settings: Record<string, string> | undefined,
): boolean {
  if (effectiveRisk === "low") return true; // já é execução direta por natureza
  if (NEVER_AUTONOMOUS.has(toolName)) return false;
  return String(settings?.[autonomyKey(toolName)] ?? "").trim().toLowerCase() === "auto";
}

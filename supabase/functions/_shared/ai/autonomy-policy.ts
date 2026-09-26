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
  // Macros de fluxo (Onda 2b): approve_quote_full move dinheiro (chama o convert); o batch de
  // cobrança dispara muitos envios de uma vez — o dono escolheu SEMPRE confirmar o lote.
  "approve_quote_full",
  "send_bulk_collection_reminders",
  // Confiança Graduada (comms, Fase 3): cobrança individual NUNCA vira autônoma (dinheiro +
  // sensível). RFQ a fornecedor e follow-up de OS (send_supplier_quote_request /
  // send_service_order_link) NÃO estão aqui de propósito — o dono PODE liberá-los via
  // set_tool_autonomy quando a qualidade provar (são de baixo risco). Desde 26/09/2026 o
  // send_service_order_link só é liberável no formato 'link': o PDF fica em
  // NEVER_AUTONOMOUS_WHEN, logo abaixo.
  "send_collection_reminder",
  // "Deixar a IA acompanhar" (Fase 1, copiloto por 30 dias — decisão do dono de 30/08/2026):
  // é a IA falando com TERCEIRO em nome da empresa. Autonomia por tipo só na Fase 3, e aí
  // sai daqui de propósito, com a promoção/demoção do dossiê.
  "followup_send_touch",
]);

/**
 * TETO RÍGIDO POR ARGUMENTO — a mesma ação pode ser liberável num modo e nunca em outro.
 * true = este pedido NUNCA roda sozinho, mesmo com a chave 'auto' gravada.
 *
 * send_service_order_link (decisão do dono, 26/09/2026): só o formato 'link' continua
 * liberável pela Confiança Graduada. O formato 'pdf_e_link' — o PADRÃO — manda ao cliente um
 * arquivo com preço, dados bancários e a chave PIX, que não se desfaz: sempre com o "sim".
 * Sem `formato`, vale o padrão da tool (o PDF), então trava. Qualquer valor que não seja
 * exatamente "link" (depois de tirar espaço e maiúscula) também trava: errar para o lado da
 * confirmação custa um "sim"; errar para o outro lado manda o PDF sem ninguém ver.
 * A tool normaliza igual (formatoDoEnvio em tools/whatsapp.ts) e o teste confere.
 */
export const NEVER_AUTONOMOUS_WHEN: Record<string, (args: Record<string, unknown> | undefined) => boolean> = {
  send_service_order_link: (args) => String(args?.formato ?? "").trim().toLowerCase() !== "link",
};

/** Explicação da trava por argumento, para o que o agente diz ao liberar/listar autonomia. */
export const EXPLICACAO_DA_TRAVA_POR_ARGUMENTO: Record<string, string> = {
  send_service_order_link:
    "Só o envio de 'só o link' pode agir sozinho. O PDF anexado ao cliente (o padrão) pede confirmação SEMPRE — leva preço e PIX num arquivo que não se desfaz.",
};

/** Prefixo das chaves em app_settings. */
export const AUTONOMY_PREFIX = "ai_autonomy_";

export function autonomyKey(toolName: string): string {
  return `${AUTONOMY_PREFIX}${toolName}`;
}

/**
 * true = pode executar direto (sem card/"sim").
 *
 * `args` são os argumentos DESTA chamada — sem eles, uma ação com trava por argumento é
 * tratada pelo pior caso (não roda sozinha).
 */
export function isAutonomyGranted(
  toolName: string,
  effectiveRisk: RiskLevel,
  settings: Record<string, string> | undefined,
  args?: Record<string, unknown>,
): boolean {
  if (effectiveRisk === "low") return true; // já é execução direta por natureza
  if (NEVER_AUTONOMOUS.has(toolName)) return false;
  if (NEVER_AUTONOMOUS_WHEN[toolName]?.(args)) return false;
  return String(settings?.[autonomyKey(toolName)] ?? "").trim().toLowerCase() === "auto";
}

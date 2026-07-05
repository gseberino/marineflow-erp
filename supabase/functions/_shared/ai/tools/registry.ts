// Contrato comum de todas as tools do AI Operator.

export type RiskLevel = "low" | "medium" | "high";

/** Cargo de app_users.role. */
export type Role = "admin" | "technician" | "financial" | "seller" | "external_seller";

/** Contexto de execução passado a toda tool — mesmo shape do executor original. */
export interface ToolCtx {
  /** Client autenticado com o JWT do usuário — RLS ativo. Usar por padrão. */
  sb: any;
  /** Client service-role — só usar onde o executor original já usava (bypassa RLS). */
  admin: any;
  userId: string;
  /** Cargo do usuário — defesa em profundidade (Fase 3): revalidar em código além do
   * filtro de `roles` que já tira a tool da lista enviada ao modelo. Necessário para o
   * canal WhatsApp (Fase 4), que roda com service-role e não tem RLS de usuário. */
  userRole: Role | "unknown";
  jwt: string;
  appOrigin: string;
  settings: Record<string, string>;
}

/** Cargos que podem ver/chamar tools financeiras/compras/preço (todos menos technician —
 * mesma regra já documentada no prompt: "TECHNICIAN não deve acessar preços, financeiro,
 * produtos ou configurações"). */
export const NON_TECHNICIAN_ROLES: Role[] = ["admin", "financial", "seller", "external_seller"];

/** Defesa em profundidade (Fase 3): revalida o cargo dentro do execute(), além do
 * filtro de `roles` que já tira a tool da lista enviada ao modelo — necessário para o
 * canal WhatsApp (Fase 4), que roda com service-role e não tem RLS de usuário. */
export function blockTechnician(ctx: ToolCtx): { error: string } | null {
  if (ctx.userRole === "technician") return { error: "Cargo não autorizado para esta ação." };
  return null;
}

export interface ToolDef {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
  /**
   * Metadado de risco. low = executa direto. medium/high = interceptado por
   * runAgentLoop (Fase 3): grava ai_operator_pending_actions em vez de executar, e só
   * roda de fato via o fluxo determinístico de confirm_action (sem chamada de LLM).
   */
  risk: RiskLevel;
  /**
   * Só para tools cujo risco depende dos argumentos (ex: send_whatsapp_message —
   * medium para equipe, high para cliente). Quando presente, sobrepõe `risk` na hora
   * de decidir interceptação. `risk` continua sendo o valor "pior caso" usado pra
   * filtrar a lista de tools por cargo.
   */
  computeRisk?: (args: any) => RiskLevel;
  /** undefined = todos os cargos autenticados podem chamar (comportamento atual, via RLS). */
  roles?: Role[];
  execute: (args: any, ctx: ToolCtx) => Promise<unknown>;
}

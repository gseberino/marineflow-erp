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
  jwt: string;
  appOrigin: string;
  settings: Record<string, string>;
}

export interface ToolDef {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
  /**
   * Metadado de risco (Fase 1: só classificação, sem interceptação — isso é Fase 3).
   * low = leitura; medium = escrita atual; ver tabela da Fase 3 para tools futuras.
   */
  risk: RiskLevel;
  /** undefined = todos os cargos autenticados podem chamar (comportamento atual, via RLS). */
  roles?: Role[];
  execute: (args: any, ctx: ToolCtx) => Promise<unknown>;
}

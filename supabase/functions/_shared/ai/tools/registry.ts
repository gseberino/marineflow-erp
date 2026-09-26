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
  /**
   * Recusa barata, chamada pelo runAgentLoop ANTES de gravar a pendência (só para ações que
   * pediriam confirmação). Devolve o `{ error }` que vira o resultado da tool, ou null para
   * seguir. Sem banco e sem efeito: só argumentos e cargo.
   *
   * Existe para o dono não ver no sino (ou no "sim <PIN>") um pedido que a execução vai
   * recusar de qualquer jeito — foi o caso do vendedor externo pedindo o PDF ao cliente: a
   * pendência dizia "PDF anexado" e só falhava depois do "sim". O `execute` continua
   * revalidando tudo; isto não substitui a checagem de lá.
   */
  preValidar?: (args: any, ctx: ToolCtx) => ({ error: string } & Record<string, unknown>) | null;
  /**
   * true = a pendência leva QUEM PEDIU: o runAgentLoop grava `{ user_id, nome, cargo }` no
   * payload, na chave CHAVE_DO_SOLICITANTE, e uma linha "Pedido por" no resumo.
   *
   * Por quê: a pendência é executada com o ctx de quem CONFIRMA — e um admin pode aprovar no
   * painel a pendência de outro. Tool cuja permissão depende do cargo tem de revalidar com o
   * cargo de quem pediu (lerSolicitante), não com o de quem clicou em aprovar.
   *
   * Opt-in de propósito: há tools que repassam os argumentos inteiros adiante, e uma chave a
   * mais no payload delas não é inofensiva.
   */
  gravarSolicitante?: boolean;
  execute: (args: any, ctx: ToolCtx) => Promise<unknown>;
}

/** Chave do payload da pendência onde o runAgentLoop grava quem pediu (ToolDef.gravarSolicitante). */
export const CHAVE_DO_SOLICITANTE = "_solicitante";

/** Quem pediu a ação que ficou pendente. */
export interface Solicitante {
  user_id: string;
  nome: string | null;
  cargo: Role | "unknown";
}

/**
 * Lê quem pediu, do payload da pendência. null = o payload não traz (pendência antiga, tool
 * sem gravarSolicitante, ou execução direta sem pendência). Cargo ausente ou torto vira
 * "unknown" — que não está em lista de cargo nenhuma, então nega.
 */
export function lerSolicitante(args: unknown): Solicitante | null {
  const s = (args as Record<string, unknown> | null | undefined)?.[CHAVE_DO_SOLICITANTE];
  if (!s || typeof s !== "object") return null;
  const bruto = s as Record<string, unknown>;
  const cargos: Role[] = ["admin", "technician", "financial", "seller", "external_seller"];
  const cargo = cargos.find((c) => c === bruto.cargo) ?? "unknown";
  return {
    user_id: String(bruto.user_id ?? ""),
    nome: typeof bruto.nome === "string" && bruto.nome.trim() ? bruto.nome.trim() : null,
    cargo,
  };
}

/**
 * Os cargos que têm de ter permissão para ESTA execução: o de quem executa (ctx) e, se a
 * pendência gravou, o de quem pediu. Os dois, e não só um: o de quem pediu impede o admin de
 * "lavar" com o próprio cargo o pedido do vendedor externo; o de quem executa impede que um
 * `_solicitante` vindo dos argumentos do modelo (numa execução direta, sem pendência) amplie
 * permissão. Acrescentar um cargo à lista só pode restringir.
 */
export function cargosQueContam(args: unknown, ctx: Pick<ToolCtx, "userRole">): Array<Role | "unknown"> {
  const solicitante = lerSolicitante(args);
  return solicitante ? [ctx.userRole, solicitante.cargo] : [ctx.userRole];
}

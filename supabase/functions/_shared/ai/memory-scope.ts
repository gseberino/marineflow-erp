/**
 * Política de memória por entidade — fonte única.
 *
 * Estava duplicada (uma cópia em tools/entity-memory.ts, outra inline no ai-agent) logo depois
 * de eu escrever as duas; centralizado aqui antes que divergissem.
 */

/** Escopos de entidade aceitos pelo CHECK de ai_operator_memory_notes. */
export const ESCOPOS_DE_ENTIDADE = ["client", "vessel", "supplier"] as const;
export type EscopoEntidade = (typeof ESCOPOS_DE_ENTIDADE)[number];

/**
 * Único status que entra no contexto do modelo.
 * Nota `candidate` é sugestão aguardando o dono e NÃO pode influenciar resposta;
 * `rejected` foi descartada. Só `verified` vale.
 */
export const STATUS_INJETAVEL = "verified";

/** Coluna de vínculo da nota conforme o tipo de entidade. null = escopo não suportado. */
export function colunaDaEntidade(
  entityType: string | null | undefined,
): "client_id" | "vessel_id" | "supplier_id" | null {
  switch (entityType) {
    case "client":
      return "client_id";
    case "vessel":
      return "vessel_id";
    case "supplier":
      return "supplier_id";
    default:
      return null;
  }
}

/**
 * A nota deve entrar no contexto automático?
 * Regra deliberadamente restritiva: só entra o que o dono aprovou.
 */
export function podeInjetar(nota: { verification_status?: string | null } | null | undefined): boolean {
  return !!nota && nota.verification_status === STATUS_INJETAVEL;
}

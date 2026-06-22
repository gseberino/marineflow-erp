// AI Operator — orquestrador (núcleo puro, SEM efeitos colaterais)
//
// GARANTIA DE SEGURANÇA: este núcleo NUNCA executa escrita nem envio. Ele
// classifica a intenção, aplica o Motor de Regras de Saída e devolve um PLANO.
// Quem executa é o caminho seguro já existente (hook/edge), e só quando o plano
// disser que pode. `executedWrite` é sempre false aqui — é uma invariante.
//
// Fluxo:
//   texto → roteador determinístico
//     ├─ search_*        → plano de leitura (read)            [inócuo]
//     ├─ create_*        → plano de criação (create)          [não executa]
//     ├─ send_to_client  → Motor de Regras (evaluateOutbound) [shadow/decisão]
//     └─ unknown         → fallback LLM (se injetado)         [só texto]

import { routeIntent, type OperatorIntent } from "./intent-router.ts";
import {
  evaluateOutbound,
  type OutboundAction,
  type PolicyConfig,
  type PolicyContext,
  type PolicyDecision,
} from "../_shared/outbound-policy/index.ts";

export type PlanType =
  | "read" // buscar/consultar (caller executa leitura segura)
  | "create" // criar OS/orçamento (caller executa via camada compartilhada)
  | "outbound" // envio ao cliente (decisão do motor de regras)
  | "llm" // escalado ao modelo
  | "none"; // nada a fazer

export interface OperatorTurnInput {
  text: string;
  /** Quando a ação é de saída, o caller fornece os detalhes concretos. */
  outboundAction?: OutboundAction;
  outboundContext?: PolicyContext;
}

export interface OperatorDeps {
  policy: PolicyConfig;
  /** Fallback opcional para o modelo (só chamado quando intenção = unknown). */
  llm?: (text: string) => Promise<string>;
}

export interface OperatorTurnResult {
  intent: OperatorIntent;
  plan: PlanType;
  /** Decisão do motor quando plan === "outbound". */
  policyDecision?: PolicyDecision;
  /** Parâmetros úteis ao caller (query de busca, dados da criação, etc.). */
  params: Record<string, string>;
  /** Texto do LLM quando plan === "llm". */
  llmText?: string;
  /** Resumo legível. */
  message: string;
  /** INVARIANTE DE SEGURANÇA: o núcleo nunca escreve. Sempre false. */
  executedWrite: false;
}

export async function handleOperatorTurn(
  input: OperatorTurnInput,
  deps: OperatorDeps,
): Promise<OperatorTurnResult> {
  const intent = routeIntent(input.text);
  const base = { intent, params: intent.params, executedWrite: false as const };

  switch (intent.kind) {
    case "search_client":
    case "search_vessel":
    case "search_product":
      return {
        ...base,
        plan: "read",
        message: `Busca planejada (${intent.kind}). Leitura é executada pelo caminho seguro.`,
      };

    case "create_quote":
    case "create_service_order":
      return {
        ...base,
        plan: "create",
        message:
          `Criação planejada (${intent.kind}). Será executada pela camada ` +
          `compartilhada — mesmo caminho do cadastro manual.`,
      };

    case "send_to_client": {
      // Saída exige detalhes concretos do caller. Sem eles, vira pedido de dados.
      if (!input.outboundAction || !input.outboundContext) {
        return {
          ...base,
          plan: "outbound",
          message: "Envio identificado, aguardando detalhes (destinatário/conteúdo) para avaliar regras.",
        };
      }
      const decision = evaluateOutbound(
        input.outboundAction,
        input.outboundContext,
        deps.policy,
      );
      return {
        ...base,
        plan: "outbound",
        policyDecision: decision,
        message: `Saída avaliada pelo motor: ${decision.decision}${decision.shadow ? " (shadow — não executa)" : ""}.`,
      };
    }

    case "unknown":
    default: {
      if (deps.llm) {
        const llmText = await deps.llm(input.text);
        return { ...base, plan: "llm", llmText, message: "Escalado ao modelo." };
      }
      return { ...base, plan: "none", message: "Sem regra determinística e sem LLM configurado." };
    }
  }
}

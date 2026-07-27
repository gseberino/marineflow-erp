// Tipos da conciliação bancária.
//
// O motor de matching (matching.ts) é puro: recebe uma transação do extrato e uma
// lista de candidatos já montada, e devolve sugestões pontuadas. Quem lê o banco é a
// edge function banking-reconcile — assim a regra de casamento fica testável sem rede.

/** Linha do extrato já importada em bank_transactions. */
export interface BankTx {
  id: string;
  transaction_date: string;              // YYYY-MM-DD
  description: string;
  amount: number;                        // sempre positivo; o sentido está em transaction_type
  transaction_type: "credit" | "debit";
  pix_end_to_end_id?: string | null;
  counterparty_document?: string | null; // só dígitos
  counterparty_name?: string | null;
}

/**
 * O que a transação pode estar pagando. Os três primeiros já existiam na tela;
 * quote_deposit e service_order_balance são os que faltavam e explicam por que
 * um sinal de orçamento nunca era encontrado.
 */
export type CandidateKind =
  | "receivable"
  | "payable"
  | "collection"
  | "quote_deposit"
  | "service_order_balance"
  /**
   * Pagamento que JÁ foi registrado no ERP e ainda não foi ligado a nenhuma linha do
   * extrato. É o fluxo real de quem lança o recebimento na hora e importa o extrato
   * depois: o dinheiro não precisa de baixa nova, precisa de vínculo. Conciliar este
   * tipo não cria lançamento nenhum — só amarra a transação ao pagamento existente.
   */
  | "existing_payment";

export interface Candidate {
  kind: CandidateKind;
  id: string;
  /** Texto mostrado ao usuário, ex.: "Sinal do ORÇ-00042". */
  label: string;
  /** Valor esperado: saldo em aberto, ou o sinal calculado do orçamento. */
  amount: number;
  direction: "credit" | "debit";
  /** Vencimento, quando existe. Orçamento aguardando sinal não tem. */
  dueDate?: string | null;
  /** Data de referência quando não há vencimento (criação/envio do orçamento). */
  referenceDate?: string | null;
  clientId?: string | null;
  clientName?: string | null;
  clientDocument?: string | null;
  /** Documento identificador que pode aparecer no histórico do extrato (ORÇ-00042, OS-00013). */
  documentNumber?: string | null;
  /** EndToEndId do Pix quando a cobrança foi emitida por nós. */
  pixEndToEndId?: string | null;
  serviceOrderId?: string | null;
  /**
   * Conciliar este candidato aprova um orçamento e o converte em OS
   * (efeito do gatilho on_quote_deposit_paid). A UI avisa antes de confirmar.
   */
  convertsQuote?: boolean;
  /**
   * De onde saiu o valor esperado do sinal:
   * - "condicao": da condição acordada no orçamento — é o valor que o cliente viu;
   * - "padrao": da condição padrão da casa (100% materiais + 50% mão de obra), quando o
   *   orçamento não define uma. É previsível, mas não foi acordado por escrito;
   * - "percentual": último recurso, percentual liso sobre o total, para orçamentos que
   *   não dá para decompor. A UI precisa deixar claro que é estimativa.
   */
  amountSource?: "condicao" | "padrao" | "percentual";
  /** Rótulo da condição de pagamento, ex.: "50% mão de obra + 100% materiais antecipados". */
  conditionLabel?: string | null;
}

export interface MatchReason {
  /** Sinal avaliado: valor, documento, nome, data, referência. */
  signal: string;
  /** Explicação em linguagem de gente, mostrada na sugestão. */
  detail: string;
  points: number;
}

export type MatchTier = "certain" | "probable" | "weak";

export interface Suggestion {
  candidate: Candidate;
  /** 0 a 100. */
  score: number;
  tier: MatchTier;
  reasons: MatchReason[];
  /** Recebido menos esperado. Positivo = entrou mais (juros?), negativo = entrou menos (tarifa? parcial?). */
  difference: number;
  /** Só a camada de certeza concilia sozinha — decisão do usuário em 27/07/2026. */
  autoApply: boolean;
}

/** Um depósito só que paga várias contas do mesmo cliente. */
export interface GroupSuggestion {
  candidates: Candidate[];
  /** Soma das contas do grupo. */
  total: number;
  /** Recebido menos a soma do grupo. */
  difference: number;
  clientName: string | null;
  detail: string;
}

export interface MatchOptions {
  /** Tolerância percentual sobre o valor esperado. Padrão 2%. */
  amountTolerancePct: number;
  /** Teto absoluto da tolerância, em reais. Padrão 50. Vence o mais conservador. */
  amountToleranceMax: number;
  /** Dias que a transação pode anteceder o vencimento. Padrão 2. */
  daysBefore: number;
  /** Dias que a transação pode suceder o vencimento. Padrão 5. */
  daysAfter: number;
  /** Janela ampla para sinal de orçamento, que não tem vencimento. Padrão 90 dias. */
  quoteWindowDays: number;
  /** Score mínimo para a sugestão aparecer. Padrão 35. */
  minScore: number;
}

export const DEFAULT_MATCH_OPTIONS: MatchOptions = {
  amountTolerancePct: 2,
  amountToleranceMax: 50,
  daysBefore: 2,
  daysAfter: 5,
  quoteWindowDays: 90,
  minScore: 35,
};

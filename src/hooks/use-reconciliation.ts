import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/** Espelha os tipos de `supabase/functions/_shared/banking/types.ts`. */
export type CandidateKind =
  | 'receivable' | 'payable' | 'collection' | 'quote_deposit' | 'service_order_balance';

export interface ReconcileCandidate {
  kind: CandidateKind;
  id: string;
  label: string;
  amount: number;
  direction: 'credit' | 'debit';
  dueDate?: string | null;
  referenceDate?: string | null;
  clientId?: string | null;
  clientName?: string | null;
  clientDocument?: string | null;
  documentNumber?: string | null;
  serviceOrderId?: string | null;
  convertsQuote?: boolean;
  /**
   * "condicao" = combinado no orçamento; "padrao" = condição padrão da casa
   * (100% materiais + 50% mão de obra); "percentual" = estimativa liso sobre o total.
   */
  amountSource?: 'condicao' | 'padrao' | 'percentual';
  conditionLabel?: string | null;
}

export interface ReconcileSuggestion {
  candidate: ReconcileCandidate;
  score: number;
  tier: 'certain' | 'probable' | 'weak';
  reasons: { signal: string; detail: string; points: number }[];
  difference: number;
  autoApply: boolean;
}

/** Um depósito só que paga várias contas do mesmo cliente. */
export interface ReconcileGroup {
  candidates: ReconcileCandidate[];
  total: number;
  difference: number;
  clientName: string | null;
  detail: string;
}

export interface ReconcileResponse {
  transactions: {
    transaction: { id: string };
    suggestions: ReconcileSuggestion[];
    groups?: ReconcileGroup[];
  }[];
  applied: { transaction_id: string; candidate: ReconcileCandidate; message: string }[];
  summary: {
    pendentes: number; conciliadas: number; sugeridas: number;
    sem_candidato: number; candidatos_avaliados?: number;
  };
}

async function callReconcile(body: Record<string, unknown>): Promise<ReconcileResponse> {
  const { data, error } = await supabase.functions.invoke('banking-reconcile', { body });
  if (error) throw error;
  if ((data as any)?.error) throw new Error((data as any).error);
  return data as ReconcileResponse;
}

/**
 * Sugestões do motor para todas as transações pendentes.
 * Fica em cache curto porque conciliar uma transação muda os candidatos das outras
 * (uma conta baixada deixa de ser candidata).
 */
export function useReconcileSuggestions(enabled = true) {
  return useQuery({
    queryKey: ['reconcile-suggestions'],
    queryFn: () => callReconcile({ action: 'suggest' }),
    enabled,
    staleTime: 30_000,
  });
}

/** Roda as camadas e concilia sozinho apenas o que é certeza. */
export function useAutoReconcile() {
  const qc = useQueryClient();
  return useMutation<ReconcileResponse, Error, boolean>({
    mutationFn: (dryRun: boolean) => callReconcile({ action: 'auto', dry_run: dryRun }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['reconcile-suggestions'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
    },
  });
}

/**
 * Aplica uma sugestão escolhida na tela.
 *
 * Passa pela edge function em vez de escrever daqui para que exista um único caminho de
 * escrita no financeiro — o mesmo que a conciliação automática e o agente usam — e para
 * que toda confirmação alimente a memória de conciliação. Sinal de orçamento continua
 * passando pela rotina do botão "Receber sinal", então o gatilho que aprova o orçamento
 * dispara igual.
 */
export function useApplySuggestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { transactionId: string; candidate: ReconcileCandidate }) => {
      const { data, error } = await supabase.functions.invoke('banking-reconcile', {
        body: { action: 'apply', transaction_id: input.transactionId, candidate: input.candidate },
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      return data as { ok: boolean; message: string };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['reconcile-suggestions'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
    },
  });
}

/** Rótulo curto do tipo de candidato, para a etiqueta na sugestão. */
export const CANDIDATE_LABELS: Record<CandidateKind, string> = {
  receivable: 'Conta a receber',
  payable: 'Conta a pagar',
  collection: 'Cobrança',
  quote_deposit: 'Sinal de orçamento',
  service_order_balance: 'Saldo de OS',
};

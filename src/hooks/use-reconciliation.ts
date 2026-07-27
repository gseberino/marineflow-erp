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
}

export interface ReconcileSuggestion {
  candidate: ReconcileCandidate;
  score: number;
  tier: 'certain' | 'probable' | 'weak';
  reasons: { signal: string; detail: string; points: number }[];
  difference: number;
  autoApply: boolean;
}

export interface ReconcileResponse {
  transactions: { transaction: { id: string }; suggestions: ReconcileSuggestion[] }[];
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
 * Sinal de orçamento passa pela mesma rotina do botão "Receber sinal", para que o
 * gatilho que aprova o orçamento dispare igual; os demais tipos passam pela rotina
 * atômica de baixa. O objetivo é não criar um segundo caminho de escrita no financeiro.
 */
export function useApplySuggestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      transactionId: string;
      amount: number;
      date: string;
      description: string;
      candidate: ReconcileCandidate;
    }) => {
      const { candidate } = input;
      let paymentId: string | null = null;

      if (candidate.kind === 'receivable' || candidate.kind === 'payable') {
        const { data, error } = await supabase.rpc('register_payment_and_update_balance', {
          p_receivable_id: candidate.kind === 'receivable' ? candidate.id : null,
          p_payable_id: candidate.kind === 'payable' ? candidate.id : null,
          p_amount: input.amount,
          p_payment_date: input.date,
          p_payment_method: 'bank_transfer',
          p_installments: 1,
          p_card_fee_percent: 0,
          p_net_amount: input.amount,
          p_notes: `Conciliação — ${input.description}`.slice(0, 500),
        });
        if (error) throw error;
        paymentId = (data as any)?.payment_id ?? null;
      } else if (candidate.kind === 'quote_deposit') {
        const { data, error } = await supabase.rpc('register_deposit_and_convert', {
          p_service_order_id: candidate.serviceOrderId!,
          p_amount: input.amount,
          p_payment_date: input.date,
          p_payment_method: 'bank_transfer',
          p_card_fee_percent: 0,
          p_notes: `Conciliação — ${input.description}`.slice(0, 500),
        });
        if (error) throw error;
        paymentId = (data as any)?.payment_id ?? null;
      } else {
        throw new Error('Este tipo precisa ser conciliado pelas opções abaixo.');
      }

      const { error: txErr } = await supabase.from('bank_transactions').update({
        reconciled: true,
        reconciled_payment_id: paymentId,
        reconciled_service_order_id: candidate.serviceOrderId ?? null,
      }).eq('id', input.transactionId);
      if (txErr) throw txErr;

      return { paymentId };
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

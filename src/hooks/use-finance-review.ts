// Caixa de entrada financeira: propostas do sistema aguardando decisão do gestor.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/** Acima deste valor a proposta sai do lote e exige olhar individual (decisão do usuário). */
export const LIMITE_LOTE = 500;

export interface PropostaFinanceira {
  id: string;
  kind: 'create_payable' | 'create_receivable' | 'internal_transfer' | 'categorize' | 'anomaly';
  status: 'pending' | 'approved' | 'rejected' | 'superseded';
  bank_transaction_id: string | null;
  related_transaction_id: string | null;
  title: string;
  reasoning: string | null;
  confidence: number;
  suggested_amount: number | null;
  suggested_date: string | null;
  suggested_category: string | null;
  suggested_description: string | null;
  suggested_supplier_id: string | null;
  dre_group: string | null;
  /** Regra que classificou esta proposta — permite auditar a regra pelo resultado. */
  applied_rule_id: string | null;
  created_at: string;
}

export interface Correcao {
  category?: string;
  description?: string;
  amount?: number;
  date?: string;
}

/**
 * Mesma leitura de corpo de erro usada na conciliação: `functions.invoke` devolve só
 * "non-2xx status code", e o motivo real (fornecedor inválido, cliente faltando) fica no
 * corpo. Sem isto o gestor vê "erro" e não sabe o que corrigir.
 */
async function invokeReview<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('finance-review', { body });

  if (error) {
    const resposta = (error as any)?.context as Response | undefined;
    if (resposta && typeof resposta.json === 'function') {
      try {
        const corpo = await resposta.json();
        if (corpo?.error) {
          throw new Error(corpo.detail ? `${corpo.error}: ${corpo.detail}` : String(corpo.error));
        }
      } catch (e) {
        if (e instanceof Error && e.message && !e.message.includes('non-2xx')) throw e;
      }
    }
    throw error;
  }
  if ((data as any)?.error) throw new Error((data as any).error);
  return data as T;
}

/** Fila pendente, mais confiáveis primeiro — o lote começa pelo que é seguro aprovar em bloco. */
export function useFinanceReviewQueue() {
  return useQuery({
    queryKey: ['finance-review-queue'],
    queryFn: async (): Promise<PropostaFinanceira[]> => {
      const { data, error } = await supabase
        .from('finance_review_queue')
        .select('*')
        .eq('status', 'pending')
        .order('confidence', { ascending: false })
        .order('suggested_amount', { ascending: false })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as unknown as PropostaFinanceira[];
    },
    staleTime: 30_000,
  });
}

/**
 * Só a CONTAGEM da fila, para o menu.
 *
 * Consulta separada de propósito: o menu monta em toda tela do sistema e não pode arrastar
 * as 500 linhas da fila junto. `head: true` traz o total sem trazer linha nenhuma.
 */
export function useFinanceReviewCount() {
  return useQuery({
    queryKey: ['finance-review-count'],
    queryFn: async (): Promise<number> => {
      const { count, error } = await supabase
        .from('finance_review_queue')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'pending');
      if (error) throw error;
      return count ?? 0;
    },
    staleTime: 60_000,
  });
}

export function useGerarPropostas() {
  const qc = useQueryClient();
  type Resposta = { ok: boolean; criadas: number; message: string; elegiveis_lote?: number };
  return useMutation<Resposta, Error, boolean>({
    mutationFn: (incluirHistorico: boolean) =>
      invokeReview<Resposta>({ action: 'generate', incluir_historico: incluirHistorico }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível gerar as propostas'),
  });
}

export function useAprovarPropostas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { ids: string[]; overrides?: Record<string, Correcao> }) =>
      invokeReview<{ ok: boolean; aprovadas: number; falhas: string[]; message: string }>({
        action: 'approve', ids: v.ids, overrides: v.overrides ?? {},
      }),
    onSuccess: (r) => {
      if (r.falhas?.length) toast.warning(r.message, { description: r.falhas.slice(0, 3).join(' · ') });
      else toast.success(r.message);
      // Aprovar cria despesa e baixa a transação: as duas listas mudam.
      for (const k of [['finance-review-queue'], ['payables'], ['receivables'], ['bank-transactions'], ['financial-summary']]) {
        qc.invalidateQueries({ queryKey: k });
      }
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível aprovar'),
  });
}

/** Uma regra que o gestor ensinou — ou que a IA propôs e aguarda o aceite dele. */
export interface RegraFinanceira {
  id: string;
  match_type: 'document' | 'supplier' | 'counterparty' | 'text';
  match_value: string;
  direction: 'debit' | 'credit' | 'any';
  min_amount: number | null;
  max_amount: number | null;
  set_category: string | null;
  set_dre_group: string | null;
  set_supplier_id: string | null;
  autonomy: 'suggest' | 'apply';
  origin: 'user' | 'ai';
  status: 'active' | 'paused' | 'proposed' | 'rejected';
  reasoning: string | null;
  note: string | null;
  times_applied: number;
  last_applied_at: string | null;
  created_at: string;
}

export function useFinanceRules() {
  return useQuery({
    queryKey: ['finance-rules'],
    queryFn: async (): Promise<RegraFinanceira[]> => {
      const { data, error } = await supabase
        .from('finance_rules')
        .select('*')
        .in('status', ['active', 'paused', 'proposed'])
        // Propostas primeiro: são as que pedem uma decisão, não as que já trabalham.
        .order('status', { ascending: true })
        .order('times_applied', { ascending: false })
        .limit(300);
      if (error) throw error;
      return (data ?? []) as unknown as RegraFinanceira[];
    },
    staleTime: 60_000,
  });
}

export function useSalvarRegra() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (r: Partial<RegraFinanceira> & { id?: string }) => {
      if (r.id) {
        const { error } = await supabase.from('finance_rules').update(r as never).eq('id', r.id);
        if (error) throw error;
        return r.id;
      }
      const { data, error } = await supabase
        .from('finance_rules').insert(r as never).select('id').single();
      if (error) throw error;
      return (data as any).id as string;
    },
    onSuccess: () => {
      toast.success('Regra salva');
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
    },
    onError: (e: Error) => {
      // Violação do índice de alvo único vira a explicação real do problema: já existe
      // uma regra viva para o mesmo alvo, e duas instruções para o mesmo fato dariam
      // resultado imprevisível.
      const msg = /finance_rules_uma_por_alvo|duplicate key/i.test(e.message)
        ? 'Já existe uma regra para este mesmo alvo. Edite a existente em vez de criar outra.'
        : e.message || 'Não foi possível salvar a regra';
      toast.error(msg);
    },
  });
}

export function useMudarStatusRegra() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { id: string; status: RegraFinanceira['status'] }) => {
      const { error } = await supabase
        .from('finance_rules').update({ status: v.status } as never).eq('id', v.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['finance-rules'] }),
    onError: (e: Error) => toast.error(e.message),
  });
}

/** Pede ao sistema que olhe as decisões já tomadas e proponha regras. */
export function useProporRegras() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => invokeReview<{ ok: boolean; propostas: number; message: string }>({ action: 'suggest_rules' }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

/**
 * Marca a transação como duplicata e descarta a proposta que nasceu dela.
 *
 * As duas coisas juntas de propósito: só recusar a proposta deixaria a transação na fila
 * para ser proposta de novo na próxima varredura.
 */
export function useMarcarDuplicata() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { propostaId: string; bankTransactionId: string | null }) => {
      if (v.bankTransactionId) {
        const { error } = await supabase.from('bank_transactions')
          .update({ reconciled: true, dismissed_reason: 'Duplicata' } as never)
          .eq('id', v.bankTransactionId);
        if (error) throw error;
      }
      const { error: e2 } = await supabase.from('finance_review_queue')
        .update({ status: 'rejected', decision_note: 'Duplicata' } as never)
        .eq('id', v.propostaId);
      if (e2) throw e2;
    },
    onSuccess: () => {
      toast.success('Marcada como duplicata');
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export function useRecusarPropostas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { ids: string[]; note?: string }) =>
      invokeReview<{ ok: boolean; message: string }>({ action: 'reject', ids: v.ids, note: v.note }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível recusar'),
  });
}

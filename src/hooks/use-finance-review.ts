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

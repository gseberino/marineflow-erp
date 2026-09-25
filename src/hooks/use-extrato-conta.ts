// O Extrato de UMA conta, com saldo dia a dia, e o que o sistema lançou sozinho.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface LinhaDoExtrato {
  id: string;
  data: string;
  descricao: string | null;
  contraparte: string | null;
  documento: string | null;
  tipo: 'credit' | 'debit';
  /** Com sinal: entrada positiva, saída negativa. */
  valor: number;
  /** Saldo depois desta linha; null enquanto a conta não tem linha de base. */
  saldo_apos: number | null;
  situacao: 'nova' | 'lancada' | 'conciliada' | 'fora' | 'sem_rastro';
  pendente: boolean;
  lancamento_tipo: 'payable' | 'receivable' | null;
  lancamento_id: string | null;
  lancamento_descricao: string | null;
  categoria: string | null;
  quem: string | null;
  tipo_fora: string | null;
  motivo_fora: string | null;
  proposta_id: string | null;
}

/**
 * Linhas de uma conta no período, da mais recente para a mais antiga. O saldo é o MESMO
 * cálculo da conferência de saldo (base + soma com sinal), feito no banco — a tela e o
 * alerta não têm como discordar.
 */
export function useExtratoDaConta(conexaoId: string | null, de: string, ate: string) {
  return useQuery({
    queryKey: ['extrato-da-conta', conexaoId, de, ate],
    enabled: !!conexaoId,
    queryFn: async (): Promise<LinhaDoExtrato[]> => {
      const { data, error } = await supabase.rpc('extrato_da_conta' as never, {
        p_conexao: conexaoId, p_de: de, p_ate: ate,
      } as never);
      if (error) throw error;
      return ((data ?? []) as unknown as LinhaDoExtrato[]).map((l) => ({
        ...l, valor: Number(l.valor), saldo_apos: l.saldo_apos == null ? null : Number(l.saldo_apos),
      }));
    },
    staleTime: 30_000,
  });
}

export interface LancadoSozinho {
  id: string;
  title: string;
  suggested_amount: number;
  suggested_category: string | null;
  suggested_date: string | null;
  decided_at: string | null;
  decision_note: string | null;
  automatica: 'regra' | 'confianca';
  created_payable_id: string | null;
  created_receivable_id: string | null;
  bank_transactions?: { bank_connection_id: string | null } | null;
}

/** O que foi lançado sem clique nos últimos 30 dias — para conferir e desfazer. */
export function useLancadosSozinhos() {
  return useQuery({
    queryKey: ['lancados-sozinhos'],
    queryFn: async (): Promise<LancadoSozinho[]> => {
      const desde = new Date(Date.now() - 30 * 86_400_000).toISOString();
      const { data, error } = await supabase
        .from('finance_review_queue')
        .select(`id, title, suggested_amount, suggested_category, suggested_date, decided_at, decision_note,
                 automatica, created_payable_id, created_receivable_id,
                 bank_transactions!finance_review_queue_bank_transaction_id_fkey (bank_connection_id)`)
        .not('automatica', 'is', null)
        .eq('status', 'approved')
        .gte('decided_at', desde)
        .order('decided_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      return (data ?? []) as unknown as LancadoSozinho[];
    },
    staleTime: 30_000,
  });
}

// Fechamento de período e trilha de conciliação.
//
// Fechar o mês é dizer "estes números não mudam mais". Sem isso, uma conciliação feita
// hoje altera o resultado de um mês já entregue ao contador — e ninguém percebe, porque o
// relatório é recalculado a cada abertura. A trava real está no banco (gatilho em payables
// e receivables); esta camada só oferece o gesto e mostra o que já aconteceu.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export interface PeriodoFechado {
  id: string;
  ano: number;
  mes: number;
  fechado_em: string;
  reaberto_em: string | null;
  motivo_da_reabertura: string | null;
}

export function usePeriodosFechados() {
  return useQuery({
    queryKey: ['periodos-fechados'],
    queryFn: async (): Promise<PeriodoFechado[]> => {
      const { data, error } = await supabase
        .from('periodos_fechados')
        .select('id, ano, mes, fechado_em, reaberto_em, motivo_da_reabertura')
        .order('ano', { ascending: false })
        .order('mes', { ascending: false })
        .limit(36);
      if (error) throw error;
      return (data ?? []) as PeriodoFechado[];
    },
    staleTime: 60_000,
  });
}

export function useFecharPeriodo() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { ano: number; mes: number }) => {
      const { error } = await supabase.from('periodos_fechados')
        .insert({ ano: v.ano, mes: v.mes } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Período fechado. Lançamentos nesta data passam a ser recusados.');
      qc.invalidateQueries({ queryKey: ['periodos-fechados'] });
    },
    onError: (e: Error) => {
      const msg = /duplicate key|periodos_fechados_ano_mes/i.test(e.message)
        ? 'Este mês já está fechado.'
        : e.message;
      toast.error(msg);
    },
  });
}

/**
 * Reabrir EXIGE motivo.
 *
 * É a diferença entre corrigir um erro e maquiar um número: quem reabre um mês entregue
 * precisa deixar escrito por quê, e isso fica na tabela para sempre.
 */
export function useReabrirPeriodo() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { id: string; motivo: string }) => {
      const motivo = v.motivo.trim();
      if (!motivo) throw new Error('Diga por que está reabrindo — o motivo fica registrado.');
      const { error } = await supabase.from('periodos_fechados').update({
        reaberto_em: new Date().toISOString(),
        motivo_da_reabertura: motivo,
      } as never).eq('id', v.id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Período reaberto, com o motivo registrado.');
      qc.invalidateQueries({ queryKey: ['periodos-fechados'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export interface LinhaDaTrilha {
  id: string;
  ocorrido_em: string;
  acao: string;
  valor: number | null;
  detalhe: string | null;
  autor: string | null;
}

export const ROTULO_DA_ACAO: Record<string, string> = {
  aprovou_proposta: 'Aprovou proposta',
  ignorou: 'Tirou da fila',
  devolveu: 'Devolveu à fila',
  conciliou: 'Conciliou',
  reclassificou: 'Reclassificou',
  fechou_periodo: 'Fechou período',
};

/** O que foi feito, por quem e quando — a trilha que nenhuma tela apagava antes. */
export function useTrilhaDeConciliacao(limite = 200) {
  return useQuery({
    queryKey: ['trilha-conciliacao', limite],
    queryFn: async (): Promise<LinhaDaTrilha[]> => {
      const { data, error } = await supabase
        .from('reconciliation_log')
        .select('id, ocorrido_em, acao, valor, detalhe, autor')
        .order('ocorrido_em', { ascending: false })
        .limit(limite);
      if (error) throw error;
      return (data ?? []) as LinhaDaTrilha[];
    },
    staleTime: 30_000,
  });
}

/** Conferências de saldo: a prova de que nenhuma transação ficou pelo caminho. */
export function useConferenciasDeSaldo() {
  return useQuery({
    queryKey: ['conferencias-saldo'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bank_balance_checks')
        .select('id, conferido_em, saldo_do_provedor, saldo_calculado, diferenca, fecha, observacao, bank_connection_id')
        .order('conferido_em', { ascending: false })
        .limit(50);
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 60_000,
  });
}

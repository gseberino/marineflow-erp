// Orçamento técnico com IA: pedido → fila ai_jobs (HBR AI Gateway, Claude da assinatura do dono)
// → proposta → rascunho de orçamento. As regras do pedido e da criação do rascunho moram no banco
// (ai_orcamento_tecnico_solicitar / ai_orcamento_tecnico_criar_rascunho); aqui é só a ponte da tela.
import { useEffect } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { mensagemDoErro } from '@/hooks/use-lancamentos';
import type { JobDeOrcamento } from '@/lib/orcamento-tecnico-ia';

const CHAVE = 'orcamento-tecnico-ia';
const COLUNAS_DO_JOB =
  'id, status, created_at, started_at, completed_at, model, model_used, duration_ms, error, error_code, prompt, response, metadata, attempts, max_attempts';

export type ModeloDoOrcamento = 'opus' | 'sonnet';

export interface PedidoRecente {
  id: string;
  status: string;
  created_at: string;
  completed_at: string | null;
  model: string;
  prompt: string;
  error_code: string | null;
}

export interface RascunhoCriado {
  service_order_id: string;
  numero: string;
  ja_existia: boolean;
  pecas?: number;
  servicos?: number;
  produtos_pendentes_criados?: number;
  total_geral?: number;
}

/** Últimos pedidos (para reabrir uma proposta depois de fechar a janela). */
export function usePedidosDeOrcamentoTecnico(ativo: boolean) {
  return useQuery({
    queryKey: [CHAVE, 'recentes'],
    enabled: ativo,
    queryFn: async (): Promise<PedidoRecente[]> => {
      const { data, error } = await supabase
        .from('ai_jobs')
        .select('id, status, created_at, completed_at, model, prompt, error_code')
        .filter('metadata->>tipo', 'eq', 'orcamento_tecnico')
        .order('created_at', { ascending: false })
        .limit(5);
      if (error) throw error;
      return data ?? [];
    },
  });
}

/** Um pedido, acompanhado pelo Realtime; enquanto não termina, confere também a cada 10 s. */
export function useJobDeOrcamentoTecnico(jobId: string | null) {
  const qc = useQueryClient();
  const query = useQuery({
    queryKey: [CHAVE, 'job', jobId],
    enabled: !!jobId,
    queryFn: async (): Promise<JobDeOrcamento> => {
      const { data, error } = await supabase.from('ai_jobs').select(COLUNAS_DO_JOB).eq('id', jobId!).single();
      if (error) throw error;
      return data as JobDeOrcamento;
    },
    refetchInterval: (q) => {
      const status = q.state.data?.status;
      return !status || status === 'pending' || status === 'processing' ? 10_000 : false;
    },
  });

  useEffect(() => {
    if (!jobId) return;
    // A RLS de ai_jobs só entrega o evento a quem pediu (ou ao admin); o evento só dispara a releitura.
    const canal = supabase
      .channel(`ai-job-${jobId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'ai_jobs', filter: `id=eq.${jobId}` }, () => {
        qc.invalidateQueries({ queryKey: [CHAVE, 'job', jobId] });
        qc.invalidateQueries({ queryKey: [CHAVE, 'recentes'] });
      })
      .subscribe();
    return () => {
      supabase.removeChannel(canal);
    };
  }, [jobId, qc]);

  return query;
}

export function useSolicitarOrcamentoTecnico() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { pedido: string; modelo: ModeloDoOrcamento }): Promise<string> => {
      const { data, error } = await supabase.rpc('ai_orcamento_tecnico_solicitar', { p_pedido: v.pedido, p_modelo: v.modelo });
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [CHAVE, 'recentes'] }),
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

export function useCriarRascunhoDoOrcamentoTecnico() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { jobId: string; indice: number; clienteId: string; ativoId: string }): Promise<RascunhoCriado> => {
      const { data, error } = await supabase.rpc('ai_orcamento_tecnico_criar_rascunho', {
        p_job_id: v.jobId,
        p_indice: v.indice,
        p_client_id: v.clienteId,
        p_vessel_id: v.ativoId,
      });
      if (error) throw error;
      return data as unknown as RascunhoCriado;
    },
    onSuccess: (_r, v) => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: [CHAVE, 'job', v.jobId] });
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

export function useCancelarPedidoDeOrcamentoTecnico() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (jobId: string): Promise<string> => {
      const { data, error } = await supabase.rpc('ai_job_cancel', { p_job_id: jobId });
      if (error) throw error;
      return data;
    },
    onSuccess: (_r, jobId) => {
      qc.invalidateQueries({ queryKey: [CHAVE, 'job', jobId] });
      qc.invalidateQueries({ queryKey: [CHAVE, 'recentes'] });
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

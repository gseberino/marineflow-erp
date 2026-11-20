// Via do técnico v2, F2 (20/11/2026): a ponte da tela com o núcleo das instruções sugeridas (canal A).
// Uma consulta por OS (via_instrucao_pendentes), feita na seção de serviços e passada a cada linha. Enquanto há pedido aberto
// ao assistente, relê a cada 10 s (a mesma função entrega o job pronto: não há gatilho em ai_jobs). Molde: use-orcamento-tecnico-ia.ts.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import type { Json } from '@/integrations/supabase/types';
import { mensagemDoErro } from '@/hooks/use-lancamentos';
import {
  resumoDaDecisao,
  resumoDoPedido,
  type ResultadoDaDecisao,
  type ResultadoDoPedido,
  type RetratoDasInstrucoes,
} from '@/lib/instrucoes-sugeridas';

export const CHAVE_INSTRUCOES = 'instrucoes-sugeridas';

/** O retrato das sugestões de uma OS. `orderId` vazio = desligado (OS nova, ou quem não é admin). */
export function useInstrucoesSugeridas(orderId: string | undefined) {
  return useQuery({
    queryKey: [CHAVE_INSTRUCOES, orderId],
    enabled: !!orderId,
    queryFn: async (): Promise<RetratoDasInstrucoes> => {
      const { data, error } = await supabase.rpc('via_instrucao_pendentes', { p_service_order_id: orderId! });
      if (error) throw error;
      return data as unknown as RetratoDasInstrucoes;
    },
    refetchInterval: (q) => {
      const status = q.state.data?.job?.status;
      return status === 'pending' || status === 'processing' ? 10_000 : false;
    },
  });
}

export function usePedirInstrucoes(orderId: string | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (): Promise<ResultadoDoPedido> => {
      const { data, error } = await supabase.rpc('via_instrucao_pedir', { p_service_order_id: orderId!, p_via: 'tela' });
      if (error) throw error;
      return data as unknown as ResultadoDoPedido;
    },
    onSuccess: (r) => {
      toast.success(resumoDoPedido(r));
      qc.invalidateQueries({ queryKey: [CHAVE_INSTRUCOES, orderId] });
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

export interface DecisaoDeInstrucao {
  id: string;
  acao: 'aprovar' | 'descartar';
  /** O texto do cartão (editado ou não). Sem texto = o sugerido. */
  texto?: string;
}

/** Aprovar, corrigir ou descartar. `itens` nulo = "aprovar todas" com o texto sugerido. */
export function useDecidirInstrucoes(orderId: string | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (itens: DecisaoDeInstrucao[] | null): Promise<ResultadoDaDecisao> => {
      const { data, error } = await supabase.rpc('via_instrucao_decidir', {
        p_itens: itens as unknown as Json,
        p_via: 'tela',
        p_service_order_id: orderId!,
      });
      if (error) throw error;
      return data as unknown as ResultadoDaDecisao;
    },
    onSuccess: (r) => {
      toast.success(resumoDaDecisao(r));
      qc.invalidateQueries({ queryKey: [CHAVE_INSTRUCOES, orderId] });
      qc.invalidateQueries({ queryKey: ['so-services', orderId] });
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/** Desiste do pedido ao assistente (o mesmo ai_job_cancel do orçamento técnico). */
export function useCancelarPedidoDeInstrucoes(orderId: string | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (jobId: string): Promise<string> => {
      const { data, error } = await supabase.rpc('ai_job_cancel', { p_job_id: jobId });
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [CHAVE_INSTRUCOES, orderId] }),
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

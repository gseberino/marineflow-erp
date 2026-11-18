/**
 * "Agrupar para o cliente" — leituras e ações do conjunto (migration 20270124100000_agrupar_para_cliente).
 * O conjunto não mexe em documento nenhum: ao gravar ou desfazer, só as leituras do próprio conjunto mudam.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { type Conjunto, type LeituraParaConjunto, normalizarConjunto, normalizarLeitura } from '@/lib/conjunto';

function recarregar(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['conjunto'] });
  qc.invalidateQueries({ queryKey: ['conjunto-candidatos'] });
}

/** O conjunto ATIVO de um documento (null se não está em nenhum). */
export function useConjuntoDoDocumento(id: string | null | undefined) {
  return useQuery({
    queryKey: ['conjunto', id],
    enabled: !!id,
    staleTime: 30_000,
    queryFn: async (): Promise<Conjunto | null> => {
      const { data, error } = await supabase.rpc('conjunto_do_documento', { p_os: id! });
      if (error) throw error;
      return normalizarConjunto(data);
    },
  });
}

/** Os documentos do mesmo cliente e embarcação, cada um com o motivo de não poder entrar (ou ser fundido). */
export function useDocumentosParaConjunto(id: string | null | undefined, enabled: boolean) {
  return useQuery({
    queryKey: ['conjunto-candidatos', id],
    enabled: enabled && !!id,
    staleTime: 0,
    refetchOnMount: 'always',
    queryFn: async (): Promise<LeituraParaConjunto | null> => {
      const { data, error } = await supabase.rpc('documentos_para_conjunto', { p_os: id! });
      if (error) throw error;
      return normalizarLeitura(data);
    },
  });
}

export interface ResultadoDoConjunto {
  ok: boolean;
  conjunto_id: string;
  nome: string;
  avisos: string[];
  conjunto: Conjunto | null;
}

export function useAgruparParaCliente() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { ids: string[]; principal?: string | null }): Promise<ResultadoDoConjunto> => {
      const { data, error } = await supabase.rpc('agrupar_para_cliente', {
        p_ids: args.ids,
        ...(args.principal ? { p_principal: args.principal } : {}),
      });
      if (error) throw error;
      const r = (data ?? {}) as Record<string, unknown>;
      return {
        ok: !!r.ok,
        conjunto_id: String(r.conjunto_id ?? ''),
        nome: String(r.nome ?? ''),
        avisos: Array.isArray(r.avisos) ? r.avisos.map(String) : [],
        conjunto: normalizarConjunto(r.conjunto),
      };
    },
    onSuccess: () => recarregar(qc),
  });
}

export function useDesfazerConjunto() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (conjuntoId: string) => {
      const { data, error } = await supabase.rpc('desfazer_conjunto', { p_conjunto: conjuntoId });
      if (error) throw error;
      return data;
    },
    onSuccess: () => recarregar(qc),
  });
}

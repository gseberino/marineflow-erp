// Agrupar / desagrupar orçamentos (15/10/2026). As regras moram no banco (agrupar_orcamentos /
// desagrupar_orcamentos, migration 20261015180000): aqui é só a ponte da tela. Em erro, a mensagem do
// banco já é a frase final em português — sobe como está. O autor é sempre o usuário da sessão (p_autor
// nunca sai daqui), e merged_into_id só é gravado pelas funções: nenhum payload desta tela o leva.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { CandidatoAgrupar } from '@/lib/agrupar-orcamentos';

const COLUNAS_DO_CANDIDATO =
  'id, service_order_number, status, quote_status, grand_total, created_at, client_id, vessel_id, signed_at, converted_to_os_at, merged_into_id, discount_amount, tax_amount, commission_rate, commissioned_user_id, commissioned_person, payment_condition_preset_id, payment_conditions, travel_cost_total, problem_description';

export interface ResultadoAgrupar {
  service_order_id: string;
  numero: string;
  agrupamento_id: string;
  origens: string[];
  principal: string;
  servicos: number;
  pecas: number;
  envios_cancelados: number;
  total_geral: number;
  comissao: number | null;
}

export interface ResultadoDesagrupar {
  agrupado_id: string;
  agrupado: string;
  origens: string[];
  origens_ids: string[];
  envios_cancelados: number;
  /** Envios agendados das origens que o agrupar tinha cancelado e voltaram para a fila. */
  envios_reativados?: number;
}

export interface AgrupamentoDoOrcamento {
  /** Este orçamento reúne outros (agrupamento ativo): os originais, na ordem do agrupamento. */
  comoAgrupado: { agrupamentoId: string; origens: Array<{ id: string; numero: string }> } | null;
  /**
   * Este orçamento foi agrupado em outro (fica cancelado como histórico). `agrupadoEmAberto`: o agrupado
   * ainda é orçamento em aberto (rascunho, não convertido, não assinado), ou seja, ainda dá para desagrupar.
   */
  comoOrigem: { agrupadoId: string; agrupadoNumero: string; agrupadoEmAberto: boolean } | null;
}

function recarregar(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['service-orders'] });
  qc.invalidateQueries({ queryKey: ['agrupar-candidatos'] });
  qc.invalidateQueries({ queryKey: ['agrupamento'] });
}

/**
 * Orçamentos em aberto do cliente + embarcação (os candidatos ao agrupamento), do mais antigo ao mais novo.
 * Sempre relê ao abrir: o total mostrado vira o `p_total_esperado`, e um total de cache (editado noutra tela
 * há menos de 1 min) faria o banco recusar com "Os orçamentos mudaram" até o cache vencer.
 */
export function useCandidatosParaAgrupar(v: { clientId: string; vesselId: string; enabled: boolean }) {
  return useQuery({
    queryKey: ['agrupar-candidatos', v.clientId, v.vesselId],
    enabled: v.enabled && !!v.clientId && !!v.vesselId,
    staleTime: 0,
    refetchOnMount: 'always',
    queryFn: async (): Promise<CandidatoAgrupar[]> => {
      const { data, error } = await supabase
        .from('service_orders')
        .select(COLUNAS_DO_CANDIDATO)
        .eq('client_id', v.clientId)
        .eq('vessel_id', v.vesselId)
        .eq('status', 'draft')
        .is('converted_to_os_at', null)
        .is('merged_into_id', null)
        .order('created_at', { ascending: true })
        .order('id', { ascending: true });
      if (error) throw error;
      return data ?? [];
    },
  });
}

export function useAgruparOrcamentos() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { p_orcamentos: string[]; p_base: string; p_total_esperado: number }): Promise<ResultadoAgrupar> => {
      const { data, error } = await supabase.rpc('agrupar_orcamentos', args);
      if (error) throw new Error(error.message);
      return data as unknown as ResultadoAgrupar;
    },
    onSuccess: () => recarregar(qc),
    // Recusa ("mudaram", "já foi agrupado", "virou OS"…): a lista na tela pode estar velha — relê.
    onError: () => qc.invalidateQueries({ queryKey: ['agrupar-candidatos'] }),
  });
}

export function useDesagruparOrcamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { p_agrupado: string }): Promise<ResultadoDesagrupar> => {
      const { data, error } = await supabase.rpc('desagrupar_orcamentos', args);
      if (error) throw new Error(error.message);
      return data as unknown as ResultadoDesagrupar;
    },
    onSuccess: (r) => {
      // A tela abre um original em seguida: sem isto, o cache dele (de quando foi agrupado) pisca primeiro
      // como cancelado, com a faixa "foi agrupado em…", até o refetch chegar.
      for (const id of r?.origens_ids ?? []) {
        qc.removeQueries({ queryKey: ['service-orders', id] });
        qc.removeQueries({ queryKey: ['agrupamento', id] });
      }
      recarregar(qc);
    },
  });
}

/**
 * Se o orçamento aberto reúne outros (pode desagrupar) ou foi agrupado em outro (mostra para onde foi).
 * Devolve a consulta com `comoAgrupado` / `comoOrigem` também no primeiro nível (null enquanto carrega),
 * para a tela ler direto sem `data?.`.
 */
export function useAgrupamentoDoOrcamento(id: string | null | undefined) {
  const consulta = useQuery({
    queryKey: ['agrupamento', id],
    enabled: !!id,
    queryFn: async (): Promise<AgrupamentoDoOrcamento> => {
      const [grupo, proprio] = await Promise.all([
        supabase
          .from('orcamento_agrupamentos')
          .select('id')
          .eq('agrupado_id', id!)
          .is('desfeito_em', null)
          .maybeSingle(),
        supabase.from('service_orders').select('merged_into_id').eq('id', id!).maybeSingle(),
      ]);
      if (grupo.error) throw grupo.error;
      if (proprio.error) throw proprio.error;

      let comoAgrupado: AgrupamentoDoOrcamento['comoAgrupado'] = null;
      if (grupo.data) {
        const { data: origens, error } = await supabase
          .from('orcamento_agrupamento_origens')
          .select('origem_id, numero, ordem')
          .eq('agrupamento_id', grupo.data.id)
          .order('ordem', { ascending: true });
        if (error) throw error;
        comoAgrupado = {
          agrupamentoId: grupo.data.id,
          origens: (origens ?? []).map((o) => ({ id: o.origem_id, numero: o.numero })),
        };
      }

      let comoOrigem: AgrupamentoDoOrcamento['comoOrigem'] = null;
      const destino = proprio.data?.merged_into_id;
      if (destino) {
        const { data: agrupado, error } = await supabase
          .from('service_orders')
          .select('service_order_number, status, converted_to_os_at, signed_at')
          .eq('id', destino)
          .maybeSingle();
        if (error) throw error;
        comoOrigem = {
          agrupadoId: destino,
          agrupadoNumero: agrupado?.service_order_number ?? 'outro orçamento',
          agrupadoEmAberto: !!agrupado && agrupado.status === 'draft' && !agrupado.converted_to_os_at && !agrupado.signed_at,
        };
      }

      return { comoAgrupado, comoOrigem };
    },
  });
  return {
    ...consulta,
    comoAgrupado: consulta.data?.comoAgrupado ?? null,
    comoOrigem: consulta.data?.comoOrigem ?? null,
  };
}

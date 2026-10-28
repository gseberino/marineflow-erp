// Agrupar / desagrupar orçamentos (15/10/2026). As regras moram no banco (agrupar_orcamentos /
// desagrupar_orcamentos, migration 20261015180000): aqui é só a ponte da tela. Em erro, a mensagem do
// banco já é a frase final em português — sobe como está. O autor é sempre o usuário da sessão (p_autor
// nunca sai daqui), e merged_into_id só é gravado pelas funções: nenhum payload desta tela o leva.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { CandidatoAgrupar } from '@/lib/agrupar-orcamentos';
import { origemAgrupadaDeOs, osAgrupadaDesagrupavel } from '@/lib/agrupar-os';

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

/**
 * De que agrupamento se trata: de orçamentos (agrupar_orcamentos) ou de OS (agrupar_os, 28/10/2026). Vem das
 * ORIGENS, não da coluna orcamento_agrupamentos.tipo: origem de orçamento nunca tem converted_to_os_at (o banco
 * recusa agrupar o que já virou OS e trava a origem enquanto agrupada); a de OS tem, ou — OS antiga sem ele —
 * leva o motivo "Agrupada em OS-N…" (origemAgrupadaDeOs).
 */
export type TipoDoAgrupamento = 'orcamento' | 'os';

export interface AgrupamentoDoOrcamento {
  /**
   * Este documento reúne outros (agrupamento ativo): os originais, na ordem do agrupamento. `assinada`: o
   * cliente tinha assinado aquela original (a assinatura fica nela; a OS agrupada nasce sem).
   */
  comoAgrupado: {
    agrupamentoId: string;
    tipo: TipoDoAgrupamento;
    origens: Array<{ id: string; numero: string; assinada: boolean }>;
  } | null;
  /**
   * Este documento foi agrupado em outro (fica cancelado como histórico). `agrupadoEmAberto`: ainda dá para
   * desagrupar — no orçamento, o agrupado ainda é orçamento em aberto (rascunho, não convertido, não
   * assinado); na OS, a agrupada ainda não começou (pela situação; o resto o banco confere).
   */
  comoOrigem: { agrupadoId: string; agrupadoNumero: string; agrupadoEmAberto: boolean; tipo: TipoDoAgrupamento } | null;
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
 * Se o orçamento/OS aberto reúne outros (pode desagrupar) ou foi agrupado em outro (mostra para onde foi).
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
        supabase.from('service_orders').select('merged_into_id, converted_to_os_at, cancellation_reason').eq('id', id!).maybeSingle(),
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
        const ids = (origens ?? []).map((o) => o.origem_id);
        const { data: dasOrigens, error: erroDasOrigens } = ids.length
          ? await supabase.from('service_orders').select('id, converted_to_os_at, cancellation_reason, signed_at').in('id', ids)
          : { data: [], error: null };
        if (erroDasOrigens) throw erroDasOrigens;
        const porId = new Map((dasOrigens ?? []).map((o) => [o.id, o]));
        comoAgrupado = {
          agrupamentoId: grupo.data.id,
          tipo: (dasOrigens ?? []).some(origemAgrupadaDeOs) ? 'os' : 'orcamento',
          origens: (origens ?? []).map((o) => ({ id: o.origem_id, numero: o.numero, assinada: !!porId.get(o.origem_id)?.signed_at })),
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
        const tipo: TipoDoAgrupamento = origemAgrupadaDeOs(proprio.data) ? 'os' : 'orcamento';
        comoOrigem = {
          agrupadoId: destino,
          tipo,
          agrupadoNumero: agrupado?.service_order_number ?? (tipo === 'os' ? 'outra OS' : 'outro orçamento'),
          agrupadoEmAberto: tipo === 'os'
            ? osAgrupadaDesagrupavel(agrupado)
            : !!agrupado && agrupado.status === 'draft' && !agrupado.converted_to_os_at && !agrupado.signed_at,
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

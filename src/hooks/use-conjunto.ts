/**
 * "Agrupar para o cliente" — leituras e ações do conjunto (migration 20270124100000_agrupar_para_cliente).
 * O conjunto não mexe em documento nenhum: ao gravar ou desfazer, só as leituras do próprio conjunto mudam.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { type Conjunto, type LeituraParaConjunto, normalizarConjunto, normalizarLeitura } from '@/lib/conjunto';
import {
  normalizarAprovacao,
  parcelasDaCondicao,
  type ResultadoDaAprovacao,
  sinalDoOrcamento,
} from '@/lib/conjunto-aprovacao';

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

// ── F2: aprovar o conjunto (migration 20270129100000_agrupar_para_cliente_aprovar) ─────────────────────────────────

async function chamarAprovacao(conjuntoId: string, ids: string[], ensaio: boolean): Promise<ResultadoDaAprovacao> {
  const { data, error } = await supabase.rpc('aprovar_conjunto', { p_conjunto: conjuntoId, p_ids: ids, p_ensaio: ensaio });
  if (error) throw error;
  const r = normalizarAprovacao(data);
  if (!r) throw new Error('O banco não devolveu o resultado da aprovação.');
  return r;
}

/** O que a aprovação FARIA com os orçamentos marcados (o banco decide; nada é gravado). */
export function useEnsaioDaAprovacao(conjuntoId: string | null | undefined, ids: string[], enabled: boolean) {
  const chave = [...ids].sort();
  return useQuery({
    queryKey: ['conjunto-aprovar-ensaio', conjuntoId, chave],
    enabled: enabled && !!conjuntoId,
    staleTime: 0,
    // Marcar/desmarcar não pisca a lista: mostra o plano anterior até chegar o novo (o botão espera).
    placeholderData: (anterior) => anterior,
    queryFn: () => chamarAprovacao(conjuntoId!, chave, true),
  });
}

export function useAprovarConjunto() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (args: { conjuntoId: string; ids: string[] }) => chamarAprovacao(args.conjuntoId, args.ids, false),
    onSuccess: () => {
      recarregar(qc);
      qc.invalidateQueries({ queryKey: ['conjunto-aprovar-ensaio'] });
      qc.invalidateQueries({ queryKey: ['complementos'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
    },
  });
}

/**
 * O sinal de cada orçamento, para mostrar na janela (3A: cada um o seu). A mesma resolução de parcelas do banco e a lib
 * única do sinal (discountRatio). Erro de leitura = sem valor (a janela não mostra R$ 0).
 */
export function useSinaisDosOrcamentos(ids: string[], enabled: boolean) {
  const chave = [...ids].sort();
  return useQuery({
    queryKey: ['conjunto-sinais', chave],
    enabled: enabled && chave.length > 0,
    staleTime: 0,
    queryFn: async (): Promise<Record<string, { valor: number; padrao: boolean }>> => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('id, labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total, subcontract_cost_total, is_travel_billable, discount_amount, tax_amount, payment_condition_preset_id, custom_payment_installments')
        .in('id', chave);
      if (error) throw error;
      const presetIds = [...new Set((data ?? []).map((o) => o.payment_condition_preset_id).filter((x): x is string => !!x))];
      let presets: Record<string, unknown> = {};
      if (presetIds.length > 0) {
        const p = await supabase.from('payment_condition_presets').select('id, installments').in('id', presetIds);
        if (p.error) throw p.error;
        presets = Object.fromEntries((p.data ?? []).map((x) => [x.id, x.installments]));
      }
      const saida: Record<string, { valor: number; padrao: boolean }> = {};
      for (const o of data ?? []) {
        const doPreset = o.payment_condition_preset_id ? presets[o.payment_condition_preset_id] : null;
        saida[o.id] = sinalDoOrcamento(o, parcelasDaCondicao(doPreset, o.custom_payment_installments));
      }
      return saida;
    },
  });
}

export interface Complementos {
  /** A OS que este documento complementa (5A). */
  complementa: { id: string; numero: string } | null;
  /** Os documentos que complementam este (vivos). */
  complementadaPor: { id: string; numero: string }[];
}

/**
 * A marca "complementa OS-X" dos dois lados. Leitura à parte do formulário: antes da migration aplicada a coluna não
 * existe, e a faixa só não aparece (nada mais da tela depende dela).
 */
export function useComplementos(id: string | null | undefined) {
  return useQuery({
    queryKey: ['complementos', id],
    enabled: !!id,
    staleTime: 30_000,
    retry: false,
    queryFn: async (): Promise<Complementos> => {
      const proprio = await supabase.from('service_orders').select('complementa_os_id').eq('id', id!).maybeSingle();
      if (proprio.error) throw proprio.error;
      let complementa: Complementos['complementa'] = null;
      const alvo = proprio.data?.complementa_os_id ?? null;
      if (alvo) {
        const a = await supabase.from('service_orders').select('id, service_order_number').eq('id', alvo).maybeSingle();
        if (a.error) throw a.error;
        if (a.data) complementa = { id: a.data.id, numero: a.data.service_order_number ?? '' };
      }
      const outros = await supabase
        .from('service_orders')
        .select('id, service_order_number, status')
        .eq('complementa_os_id', id!);
      if (outros.error) throw outros.error;
      return {
        complementa,
        complementadaPor: (outros.data ?? [])
          .filter((o) => o.status !== 'cancelled')
          .map((o) => ({ id: o.id, numero: o.service_order_number ?? '' })),
      };
    },
  });
}

// Agrupar / desagrupar ORDENS DE SERVIÇO (28/10/2026). As regras moram no banco (agrupar_os / desagrupar_os,
// migration 20261028120000): aqui é só a ponte da tela. Em erro, a mensagem do banco já é a frase final em
// português — sobe como está. O autor é sempre o usuário da sessão (p_autor nunca sai daqui), e merged_into_id
// só é gravado pelas funções: nenhum payload desta tela o leva.
// Se a OS reúne outras / foi agrupada em outra: useAgrupamentoDoOrcamento (use-agrupar-orcamentos.ts), que lê
// o mesmo histórico (orcamento_agrupamentos) e diz o tipo — uma consulta só por tela.
import { useMutation, useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  STATUS_AGRUPAVEIS_OS,
  desagrupavelPeloBanco,
  leituraDoBanco,
  type DesagrupavelPeloBanco,
  type LeituraDoBanco,
  type CandidataOs,
  type CompraDaPrevia,
  type RecebivelDaPrevia,
  type TarefaDaPrevia,
} from '@/lib/agrupar-os';

const COLUNAS_DA_CANDIDATA =
  'id, service_order_number, status, quote_status, grand_total, created_at, client_id, vessel_id, signed_at, converted_to_os_at, merged_into_id, discount_amount, tax_amount, commission_rate, commissioned_user_id, commissioned_person, payment_condition_preset_id, payment_conditions, travel_cost_total, problem_description, scheduled_start_at, card_fee_passthrough_enabled, operational_cost_total';

export interface ResultadoAgruparOs {
  service_order_id: string;
  numero: string;
  agrupamento_id: string;
  origens: string[];
  principal: string;
  servicos: number;
  pecas: number;
  recebiveis_movidos: number;
  cobrancas_movidas: number;
  tarefas_movidas: number;
  tecnicos: number;
  envios_cancelados: number;
  total_geral: number;
  comissao: number | null;
  /** Valor do "Saldo — OS-N" que o banco lançou quando as contas a receber das originais não cobriam o total; null = nenhum. */
  saldo_lancado?: number | null;
  avisos?: string[];
}

export interface ResultadoDesagruparOs {
  agrupado_id: string;
  agrupado: string;
  origens: string[];
  origens_ids: string[];
  registros_devolvidos: number;
  envios_cancelados: number;
  envios_reativados?: number;
}

export interface PreviaDoAgrupamentoOs {
  recebiveis: RecebivelDaPrevia[];
  tarefas: TarefaDaPrevia[];
  compras: CompraDaPrevia[];
}

/**
 * O que o agrupar/desagrupar de OS mexe além da própria OS: dinheiro (contas a receber, cobranças, conciliação,
 * caixa de entrada do financeiro), agenda, compras e as fichas do cliente e da embarcação. Prefixos de chave,
 * para pegar também as variações (['receivables', 'client', id], ['agenda-entity-tasks', …]).
 */
const PREFIXOS_QUE_MUDAM = new Set([
  'service-orders', 'agrupamento', 'agrupar-candidatas-os', 'agrupar-os-previa', 'agrupar-candidatos',
  'receivables', 'collections', 'collections-by-os', 'collection', 'finance-review-queue', 'finance-review-count',
  'financial-summary', 'contas-em-aberto-do-cliente',
  'purchase-orders', 'purchase-needs',
  'clients', 'vessels',
  'service-order-steps', 'so-services', 'so-parts', 'so-signatures',
]);

function recarregar(qc: QueryClient) {
  qc.invalidateQueries({
    predicate: (q) => {
      const raiz = String(q.queryKey[0] ?? '');
      return PREFIXOS_QUE_MUDAM.has(raiz) || raiz.startsWith('agenda');
    },
  });
}

/**
 * OS do cliente + embarcação que podem entrar (e as em execução, para a tela dizer por que não), da mais
 * antiga à mais nova. Sempre relê ao abrir: o total mostrado vira o `p_total_esperado`.
 */
export function useCandidatasOsParaAgrupar(v: { clientId: string; vesselId: string; enabled: boolean }) {
  return useQuery({
    queryKey: ['agrupar-candidatas-os', v.clientId, v.vesselId],
    enabled: v.enabled && !!v.clientId && !!v.vesselId,
    staleTime: 0,
    refetchOnMount: 'always',
    queryFn: async (): Promise<CandidataOs[]> => {
      const { data, error } = await supabase
        .from('service_orders')
        .select(COLUNAS_DA_CANDIDATA)
        .eq('client_id', v.clientId)
        .eq('vessel_id', v.vesselId)
        // Sem filtro por converted_to_os_at: há OS antigas sem ele e o banco as agrupa (a situação já tira o rascunho).
        .is('merged_into_id', null)
        .in('status', [...STATUS_AGRUPAVEIS_OS, 'in_progress'])
        .order('created_at', { ascending: true })
        .order('id', { ascending: true });
      if (error) throw error;
      return (data ?? []) as CandidataOs[];
    },
  });
}

/**
 * O que o banco diz de cada OS ativa da embarcação (os_para_agrupar): entra ou não e, se não, a MESMA frase que
 * o agrupar_os levantaria (nota fiscal, comissão, hora apontada, total desatualizado…). A tela usa para travar a
 * caixa antes do clique. Falhou a leitura: a janela segue com as regras que ela mesma enxerga, e o banco
 * recusa com a frase ao tentar — por isso aqui o erro não sobe.
 */
export function useLeituraOsParaAgrupar(v: { clientId: string; vesselId: string; incluir: string[]; enabled: boolean }) {
  const incluir = [...v.incluir].sort();
  return useQuery({
    queryKey: ['agrupar-candidatas-os', 'banco', v.clientId, v.vesselId, incluir.join('|')],
    enabled: v.enabled && !!v.vesselId,
    staleTime: 0,
    refetchOnMount: 'always',
    retry: false,
    queryFn: async (): Promise<LeituraDoBanco> => {
      const { data, error } = await supabase.rpc('os_para_agrupar', {
        p_vessel_id: v.vesselId,
        ...(v.clientId ? { p_client_id: v.clientId } : {}),
        ...(incluir.length ? { p_incluir: incluir } : {}),
      });
      if (error) return new Map();
      return leituraDoBanco(data);
    },
  });
}

/**
 * A OS agrupada ainda pode ser desagrupada? Pergunta ao banco (os_para_agrupar → agrupados_ativos), a mesma
 * régua do desagrupar_os e da guarda que recusa cancelar a agrupada desfazível. Sem isto a tela adivinhava
 * pela situação: uma agrupada 'open' com hora apontada ficava sem o Cancelar (que o banco aceitaria) e com
 * um Desagrupar que o banco recusa. Serve à agrupada e à origem (a origem passa o id da agrupada; a
 * embarcação é a mesma). null = sem resposta (carregando, sem cargo para ler, falha): a tela usa o palpite
 * osAgrupadaDesagrupavel — por isso o erro não sobe.
 */
export function useDesagrupavelDaOsAgrupada(v: { agrupadoId: string | null; vesselId: string | null | undefined; enabled: boolean }) {
  return useQuery({
    // Prefixo 'agrupar-candidatas-os': o agrupar/desagrupar já relê (recarregar e onError acima).
    queryKey: ['agrupar-candidatas-os', 'desagrupavel', v.vesselId ?? null, v.agrupadoId],
    enabled: v.enabled && !!v.agrupadoId && !!v.vesselId,
    staleTime: 0,
    refetchOnMount: 'always',
    retry: false,
    queryFn: async (): Promise<DesagrupavelPeloBanco | null> => {
      const { data, error } = await supabase.rpc('os_para_agrupar', { p_vessel_id: v.vesselId! });
      if (error) return null;
      return desagrupavelPeloBanco(data, v.agrupadoId!);
    },
  });
}

/**
 * O que acompanha as OS escolhidas para a nova: contas a receber/sinais ativos, tarefas manuais pendentes e
 * pedidos de compra. Só para a prévia — quem move é o banco, e é ele que confere as somas no fim.
 */
export function usePreviaDoAgrupamentoOs(ids: string[], enabled: boolean) {
  const chave = [...ids].sort();
  return useQuery({
    queryKey: ['agrupar-os-previa', chave.join('|')],
    enabled: enabled && chave.length > 0,
    staleTime: 0,
    queryFn: async (): Promise<PreviaDoAgrupamentoOs> => {
      const [recebiveis, tarefas, compras] = await Promise.all([
        // Os mesmos filtros do banco (_os_agrupar_mover): status "is distinct from 'cancelled'" inclui o nulo.
        supabase
          .from('receivables')
          .select('id, service_order_id, description, amount, paid_amount, status, is_deposit, due_date')
          .in('service_order_id', chave)
          .or('status.is.null,status.neq.cancelled')
          .order('due_date', { ascending: true }),
        // As automáticas (source 'automation') o motor de tarefas refaz sozinho na OS nova.
        supabase
          .from('agenda_tasks')
          .select('id, related_entity_id, title, due_at, scheduled_start_at')
          .in('related_entity_type', ['service_order', 'quote'])
          .in('related_entity_id', chave)
          .in('status', ['pending', 'in_progress'])
          .neq('source', 'automation'),
        supabase
          .from('purchase_orders')
          .select('id, service_order_id, po_number, status, total_amount')
          .in('service_order_id', chave)
          .or('status.is.null,status.neq.cancelled'),
      ]);
      if (recebiveis.error) throw recebiveis.error;
      if (tarefas.error) throw tarefas.error;
      if (compras.error) throw compras.error;
      return {
        recebiveis: (recebiveis.data ?? []) as RecebivelDaPrevia[],
        tarefas: (tarefas.data ?? []) as TarefaDaPrevia[],
        compras: (compras.data ?? []) as CompraDaPrevia[],
      };
    },
  });
}

export function useAgruparOs() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { p_os: string[]; p_base: string; p_total_esperado: number }): Promise<ResultadoAgruparOs> => {
      const { data, error } = await supabase.rpc('agrupar_os', args);
      if (error) throw new Error(error.message);
      return data as unknown as ResultadoAgruparOs;
    },
    onSuccess: () => recarregar(qc),
    // Recusa ("mudaram", "já começou", "nota fiscal"…): a lista na tela pode estar velha — relê.
    onError: () => {
      qc.invalidateQueries({ queryKey: ['agrupar-candidatas-os'] });
      qc.invalidateQueries({ queryKey: ['agrupar-os-previa'] });
    },
  });
}

export function useDesagruparOs() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { p_agrupado: string }): Promise<ResultadoDesagruparOs> => {
      const { data, error } = await supabase.rpc('desagrupar_os', args);
      if (error) throw new Error(error.message);
      return data as unknown as ResultadoDesagruparOs;
    },
    onSuccess: (r) => {
      // A tela abre uma original em seguida: sem isto, o cache dela (de quando foi agrupada) pisca primeiro
      // como cancelada, com a faixa "foi agrupada em…", até o refetch chegar.
      for (const id of r?.origens_ids ?? []) {
        qc.removeQueries({ queryKey: ['service-orders', id] });
        qc.removeQueries({ queryKey: ['agrupamento', id] });
      }
      recarregar(qc);
    },
  });
}

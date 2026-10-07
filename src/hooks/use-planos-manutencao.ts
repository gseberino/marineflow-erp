// Planos de manutenção com lembretes (07/10/2026) — leitura e ações das telas.
//
// Fonte: migration 20261007150000_planos_de_manutencao.sql (frente BANCO): view
// v_maintenance_plans_due, tabela maintenance_plan_events, colunas novas de maintenance_plans e as
// RPCs registrar_servico_do_plano / adiar_plano. Até regerar os tipos (07/10/2026), as tabelas e
// RPCs novas vão por string com `as never` (mesmo padrão de use-caixa.ts) e a forma do resultado
// vem das interfaces de src/lib/planos-manutencao.ts.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import {
  agruparRevisoes, alvosSemPlano, hojeEmBrasilia,
  type EventoDoPlano, type ItemDoHistorico, type OrdemDaEmbarcacao, type PlanoDeManutencao, type PlanoNaView,
} from '@/lib/planos-manutencao';

export const CHAVE_LEMBRETES_REVISAO = 'lembretes_revisao_ativo';
export const CHAVE_CAMPANHA_TEMPORADA = 'campanha_temporada_ativa';

function invalidarPlanos(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['maintenance-plans'] });
  qc.invalidateQueries({ queryKey: ['revisoes'] });
  qc.invalidateQueries({ queryKey: ['plano-eventos'] });
  // A R14 fecha a tarefa quando o ciclo muda; a lista da Agenda relê para refletir isso.
  qc.invalidateQueries({ queryKey: ['agenda-live-tasks'] });
  qc.invalidateQueries({ queryKey: ['agenda-entity-tasks'] });
}

/** Todos os planos ATIVOS com vencimento e situação calculados pelo banco (aba Revisões). */
export function useRevisoes() {
  return useQuery({
    queryKey: ['revisoes'],
    staleTime: 30_000,
    queryFn: async (): Promise<PlanoNaView[]> => {
      const { data, error } = await supabase
        .from('v_maintenance_plans_due' as never)
        .select('*')
        .order('next_due_on', { ascending: true })
        .limit(500);
      // Leitura que falha não vira "nenhuma revisão" (regra de 02/10/2026): a tela mostra o erro.
      if (error) throw error;
      return (data ?? []) as unknown as PlanoNaView[];
    },
  });
}

/** Planos da embarcação (inclusive desligados) + a linha da view de cada ativo. */
export function usePlanosDaEmbarcacao(vesselId: string | undefined) {
  return useQuery({
    queryKey: ['maintenance-plans', vesselId],
    enabled: !!vesselId,
    queryFn: async (): Promise<{ planos: PlanoDeManutencao[]; vencimentos: Record<string, PlanoNaView>; erroDaView: string | null }> => {
      const { data, error } = await supabase
        .from('maintenance_plans')
        .select('*')
        .eq('vessel_id', vesselId!)
        .order('created_at');
      if (error) throw error;
      const planos = (data ?? []) as unknown as PlanoDeManutencao[];
      // A view é lida à parte: se ela falhar, os planos continuam na tela e o vencimento diz que
      // não pôde ser lido — em vez de sumir com tudo ou inventar uma data no navegador.
      const { data: due, error: dueErr } = await supabase
        .from('v_maintenance_plans_due' as never)
        .select('*')
        .eq('vessel_id', vesselId!);
      const vencimentos: Record<string, PlanoNaView> = {};
      for (const l of ((due ?? []) as unknown as PlanoNaView[])) vencimentos[l.plan_id] = l;
      return { planos, vencimentos, erroDaView: dueErr ? dueErr.message : null };
    },
  });
}

export function useEventosDoPlano(planId: string | null | undefined) {
  return useQuery({
    queryKey: ['plano-eventos', planId],
    enabled: !!planId,
    queryFn: async (): Promise<EventoDoPlano[]> => {
      const { data, error } = await supabase
        .from('maintenance_plan_events' as never)
        .select('id, plan_id, due_on, tipo, toque, service_order_id, detalhe, created_at')
        .eq('plan_id', planId!)
        .order('created_at', { ascending: false })
        .limit(50);
      if (error) throw error;
      return (data ?? []) as unknown as EventoDoPlano[];
    },
  });
}

/** Histórico de serviços e peças das OS concluídas da embarcação — a base do "Sugerir planos". */
export function useHistoricoDaEmbarcacao(vesselId: string | undefined, ativo: boolean) {
  return useQuery({
    queryKey: ['historico-planos', vesselId],
    enabled: !!vesselId && ativo,
    queryFn: async (): Promise<ItemDoHistorico[]> => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, check_out_at, scheduled_end_at, updated_at, service_order_services(name_snapshot, service_system, line_total), service_order_parts(line_total_sale, products(name))')
        .eq('vessel_id', vesselId!)
        .in('status', ['completed', 'invoiced'])
        .limit(200);
      if (error) throw error;
      const itens: ItemDoHistorico[] = [];
      for (const os of (data ?? []) as any[]) {
        // OS não tem completed_at: a data do serviço é a saída, ou o fim agendado, ou a última
        // alteração (mesma regra do gatilho da frente BANCO), no dia de Brasília.
        const quando = os.check_out_at ?? os.scheduled_end_at ?? os.updated_at;
        const dia = quando ? hojeEmBrasilia(new Date(quando)) : '';
        if (!dia) continue;
        for (const s of os.service_order_services ?? []) {
          itens.push({ dia, osId: os.id, osNumero: os.service_order_number, sistema: s.service_system, texto: s.name_snapshot ?? '', valor: Number(s.line_total ?? 0) });
        }
        for (const p of os.service_order_parts ?? []) {
          itens.push({ dia, osId: os.id, osNumero: os.service_order_number, sistema: null, texto: p.products?.name ?? '', valor: Number(p.line_total_sale ?? 0) });
        }
      }
      return itens;
    },
  });
}

export interface PlanoInput {
  name: string;
  interval_months: number;
  estimated_value: number | null;
  scope: string | null;
  advance_days: number;
  service_system: string | null;
  service_verb: string | null;
  match_keywords: string[];
  client_reminder_enabled: boolean;
  /** Só na criação; depois, o último serviço muda pelo "Serviço feito" (que deixa evento). */
  last_service_at?: string | null;
  source?: 'manual' | 'sugerido';
}

export function useSalvarPlano(vesselId: string | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, input }: { id?: string; input: PlanoInput }) => {
      if (id) {
        const { last_service_at: _ignorado, source: _origem, ...patch } = input;
        const { error } = await supabase.from('maintenance_plans').update(patch as never).eq('id', id);
        if (error) throw error;
        return;
      }
      const { data: u } = await supabase.auth.getUser();
      const { error } = await supabase.from('maintenance_plans').insert({
        ...input,
        vessel_id: vesselId!,
        last_service_at: input.last_service_at || null,
        source: input.source ?? 'manual',
        created_by: u?.user?.id ?? null,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => invalidarPlanos(qc),
  });
}

export function useLigarPlano() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, active }: { id: string; active: boolean }) => {
      const { error } = await supabase.from('maintenance_plans').update({ active }).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => invalidarPlanos(qc),
  });
}

export function useApagarPlano() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('maintenance_plans').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => invalidarPlanos(qc),
  });
}

/** "Serviço feito": RPC registrar_servico_do_plano (data de Brasília por padrão, deixa evento 'serviced'). */
export function useRegistrarServico() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ planId, dia, osId }: { planId: string; dia?: string; osId?: string | null }) => {
      const { data, error } = await supabase.rpc('registrar_servico_do_plano' as never, {
        p_plano: planId,
        p_data: dia || hojeEmBrasilia(),
        p_os: osId ?? null,
      } as never);
      if (error) throw error;
      return data as unknown;
    },
    onSuccess: () => invalidarPlanos(qc),
  });
}

/** "Adiar": RPC adiar_plano (snoozed_until + evento 'snoozed'). */
export function useAdiarPlano() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ planId, ate, motivo }: { planId: string; ate: string; motivo?: string | null }) => {
      const { data, error } = await supabase.rpc('adiar_plano' as never, {
        p_plano: planId,
        p_ate: ate,
        p_motivo: motivo?.trim() || null,
      } as never);
      if (error) throw error;
      return data as unknown;
    },
    onSuccess: () => invalidarPlanos(qc),
  });
}

export interface PropostaDeLembrete {
  pending_action_id: string;
  title: string;
  summary_markdown: string;
  risk_level: 'medium' | 'high';
}

/**
 * "Pedir lembrete agora": a tela não monta a mensagem nem envia — pede ao assistente, que usa a
 * tool send_maintenance_reminder_now (frente BACKEND) e devolve a PENDÊNCIA com o texto exato.
 * É o mesmo caminho do "Analisar com IA" da conciliação (use-reconciliation.ts): mensagem ao
 * ai-agent nomeando a ferramenta. A resposta traz `proposal` quando a pendência nasceu; o envio só
 * acontece no "Confirmar" (confirm_action), igual ao card do assistente.
 */
export function usePedirLembreteAgora() {
  return useMutation({
    mutationFn: async (p: { planId: string; plano: string; embarcacao: string; cliente: string | null; vesselId: string }) => {
      const pedido =
        `Pedido da tela Revisões: prepare AGORA o lembrete de revisão do plano ${p.planId} ` +
        `("${p.plano}" da embarcação ${p.embarcacao}${p.cliente ? `, cliente ${p.cliente}` : ''}). ` +
        `Use send_maintenance_reminder_now com plan_id ${p.planId}. Não envie nada sem a minha confirmação.`;
      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: {
          messages: [{ role: 'user', content: pedido }],
          context: { route: '/v2/agenda', entityType: 'vessel', entityId: p.vesselId },
        },
      });
      if (error) throw error;
      const d = data as { proposal?: PropostaDeLembrete; message?: { content?: string } | string; error?: string } | null;
      if (d?.error) throw new Error(d.error);
      const texto = typeof d?.message === 'string' ? d.message : d?.message?.content ?? '';
      return { proposta: d?.proposal ?? null, texto };
    },
  });
}

/** Decide a pendência criada acima — mesmo corpo do usePendingActions (confirm_action, sem LLM). */
export function useDecidirLembrete() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, decisao, nota }: { id: string; decisao: 'approve' | 'reject'; nota?: string }) => {
      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: { type: 'confirm_action', pending_action_id: id, decision: decisao, note: nota || undefined },
      });
      if (error) throw error;
      const d = data as { error?: string; message?: { content?: string } } | null;
      if (d?.error) throw new Error(d.error);
      return d?.message?.content ?? '';
    },
    onSuccess: () => invalidarPlanos(qc),
  });
}

/**
 * Prospecção › Revisões preventivas (07/10/2026): os planos que vencem em 30 dias ou já venceram
 * (lembrete pelo fluxo do "sim") e as embarcações SEM plano com serviço concluído há 6+ meses
 * (ação: criar o plano). Leitura que falha aparece como erro, não como "tudo em dia".
 */
export function useAlvosDeRevisao() {
  const revisoes = useRevisoes();
  const ordens = useQuery({
    queryKey: ['revisoes', 'ordens-das-embarcacoes'],
    staleTime: 60_000,
    queryFn: async (): Promise<OrdemDaEmbarcacao[]> => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('vessel_id, status, created_at, check_out_at, scheduled_end_at, updated_at, vessels(name), clients(name, opt_out_whatsapp)')
        .not('vessel_id', 'is', null)
        .order('created_at', { ascending: false })
        .limit(1000);
      if (error) throw error;
      return ((data ?? []) as any[]).map((o) => ({
        vessel_id: o.vessel_id, status: o.status, created_at: o.created_at, check_out_at: o.check_out_at,
        scheduled_end_at: o.scheduled_end_at, updated_at: o.updated_at, vessel_name: o.vessels?.name ?? null,
        client_name: o.clients?.name ?? null, opt_out: o.clients?.opt_out_whatsapp ?? null,
      }));
    },
  });
  const linhas = revisoes.data ?? [];
  const grupos = agruparRevisoes(linhas);
  const planos = [...grupos.vencidas, ...grupos.vencendo];
  const semPlano = ordens.data ? alvosSemPlano(ordens.data, new Set(linhas.map((l) => l.vessel_id))) : [];
  return {
    planos,
    semPlano,
    receitaPrevista: grupos.receitaPrevista,
    isLoading: revisoes.isLoading || ordens.isLoading,
    erroPlanos: revisoes.error as Error | null,
    erroOrdens: ordens.error as Error | null,
  };
}

// "Deixar a IA acompanhar" — missões em que a IA cobra um terceiro (fornecedor/cliente) sobre um
// compromisso, redigindo cada mensagem para o dono aprovar no sino (Fase 1, copiloto).
// Dossiê: plans/marineflow-ia-acompanha.md. Tabelas: ai_followup_missions / ai_followup_events.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type FollowupMissionStatus = 'active' | 'waiting_reply' | 'resolved' | 'escalated' | 'cancelled' | 'expired';
export type FollowupContraparteTipo = 'client' | 'supplier' | 'lead';
export type FollowupOrigemTipo = 'agenda_task' | 'quote' | 'open_loop' | 'manual';

export interface FollowupMission {
  id: string;
  objetivo: string;
  contraparte_tipo: FollowupContraparteTipo;
  contraparte_id: string | null;
  contraparte_phone: string;
  contraparte_label: string;
  origem_tipo: FollowupOrigemTipo;
  origem_id: string | null;
  service_order_id: string | null;
  criterio_erp: string;
  prazo_final: string | null;
  max_toques: number;
  toques_feitos: number;
  proximo_toque_em: string | null;
  ultimo_toque_em: string | null;
  status: FollowupMissionStatus;
  resolucao: string | null;
  resolucao_evidencia: string | null;
  resolvida_em: string | null;
  created_at: string;
}

export interface FollowupEvent {
  id: string;
  mission_id: string;
  tipo: string;
  conteudo: string | null;
  classificacao: string | null;
  evidencia: string | null;
  pending_action_id: string | null;
  meta: Record<string, unknown> | null;
  created_at: string;
}

// Tabelas e RPCs novas: `types.ts` é regerado depois da migration entrar (gen types); até lá
// o cast evita que o tsc invente a forma errada.
const sb = supabase as any;

export const STATUS_EM_ANDAMENTO: FollowupMissionStatus[] = ['active', 'waiting_reply', 'escalated'];

export function useFollowupMissions(filtro: 'andamento' | 'encerradas' | 'todas' = 'andamento') {
  return useQuery({
    queryKey: ['followup-missions', filtro],
    staleTime: 15_000,
    queryFn: async (): Promise<FollowupMission[]> => {
      let q = sb.from('ai_followup_missions').select('*').order('created_at', { ascending: false }).limit(200);
      if (filtro === 'andamento') q = q.in('status', STATUS_EM_ANDAMENTO);
      if (filtro === 'encerradas') q = q.in('status', ['resolved', 'cancelled', 'expired']);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as FollowupMission[];
    },
  });
}

/** A missão em andamento aberta a partir desta origem (tarefa/orçamento), se houver. */
export function useFollowupMissionDaOrigem(origemTipo: FollowupOrigemTipo, origemId: string | null | undefined) {
  return useQuery({
    queryKey: ['followup-mission-origem', origemTipo, origemId],
    enabled: !!origemId,
    staleTime: 15_000,
    queryFn: async (): Promise<FollowupMission | null> => {
      const { data, error } = await sb.from('ai_followup_missions').select('*')
        .eq('origem_tipo', origemTipo).eq('origem_id', origemId)
        .in('status', STATUS_EM_ANDAMENTO)
        .order('created_at', { ascending: false }).limit(1).maybeSingle();
      if (error) throw error;
      return (data ?? null) as FollowupMission | null;
    },
  });
}

export function useFollowupEvents(missionId: string | null | undefined) {
  return useQuery({
    queryKey: ['followup-events', missionId],
    enabled: !!missionId,
    queryFn: async (): Promise<FollowupEvent[]> => {
      const { data, error } = await sb.from('ai_followup_events').select('*')
        .eq('mission_id', missionId).order('created_at', { ascending: true });
      if (error) throw error;
      return (data ?? []) as FollowupEvent[];
    },
  });
}

export interface CriarMissaoInput {
  origem_tipo: FollowupOrigemTipo;
  origem_id?: string | null;
  objetivo: string;
  prazo_final?: string | null;
  contraparte_tipo?: FollowupContraparteTipo | null;
  contraparte_id?: string | null;
  phone?: string | null;
  label?: string | null;
}

function invalidar(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['followup-missions'] });
  qc.invalidateQueries({ queryKey: ['followup-mission-origem'] });
  qc.invalidateQueries({ queryKey: ['followup-events'] });
}

export function useCreateFollowupMission() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: CriarMissaoInput): Promise<string> => {
      const { data, error } = await sb.rpc('create_followup_mission', {
        p_origem_tipo: input.origem_tipo,
        p_origem_id: input.origem_id ?? null,
        p_objetivo: input.objetivo,
        p_prazo_final: input.prazo_final ?? null,
        p_contraparte_tipo: input.contraparte_tipo ?? null,
        p_contraparte_id: input.contraparte_id ?? null,
        p_phone: input.phone ?? null,
        p_label: input.label ?? null,
      });
      if (error) throw new Error(error.message);
      return data as string;
    },
    onSuccess: () => invalidar(qc),
  });
}

export function useCancelFollowupMission() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, motivo }: { id: string; motivo?: string }) => {
      const { data, error } = await sb.rpc('cancel_followup_mission', { p_id: id, p_motivo: motivo ?? null });
      if (error) throw new Error(error.message);
      return Boolean(data);
    },
    onSuccess: () => invalidar(qc),
  });
}

/** Kill switch (app_settings.followup_missions_enabled) — sem deploy, tudo para. */
export function useFollowupSwitch() {
  const qc = useQueryClient();
  const query = useQuery({
    queryKey: ['followup-switch'],
    queryFn: async (): Promise<boolean> => {
      const { data } = await sb.from('app_settings').select('value').eq('key', 'followup_missions_enabled').maybeSingle();
      return String(data?.value ?? 'true').trim().toLowerCase() !== 'false';
    },
  });
  const mutation = useMutation({
    mutationFn: async (ligado: boolean) => {
      const { error } = await sb.from('app_settings')
        .upsert({ key: 'followup_missions_enabled', value: ligado ? 'true' : 'false' }, { onConflict: 'key' });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['followup-switch'] });
      qc.invalidateQueries({ queryKey: ['app-settings'] });
    },
  });
  return { ligado: query.data ?? true, isLoading: query.isLoading, alternar: mutation.mutateAsync, isPending: mutation.isPending };
}

export const STATUS_LABEL: Record<FollowupMissionStatus, string> = {
  active: 'Cobrando',
  waiting_reply: 'Respondeu — leia',
  escalated: 'Devolvida a você',
  resolved: 'Resolvida',
  cancelled: 'Encerrada',
  expired: 'Expirada',
};

export const EVENTO_LABEL: Record<string, string> = {
  created: 'Missão criada',
  erp_check: 'ERP conferido',
  erp_resolved: 'Resolvido pelo ERP — ninguém foi cobrado',
  draft: 'Rascunho para sua aprovação',
  touch_sent: 'Mensagem enviada',
  reply: 'Resposta recebida',
  skipped: 'Pulado',
  escalated: 'Devolvida a você',
  resolved: 'Resolvida',
  cancelled: 'Encerrada',
  expired: 'Expirada',
  note: 'Observação',
};

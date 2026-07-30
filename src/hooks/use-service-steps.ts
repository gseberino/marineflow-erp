import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Roteiro de Execução da OS — Ciclo do Serviço.
 * Plano: plans/marineflow-execucao-os-roteiro.md
 *
 * As tabelas deste módulo já estão em src/integrations/supabase/types.ts (tipos
 * regenerados após a migration de 29/07), então nada de cast: erro de coluna é
 * pego pelo tsc. As interfaces abaixo existem para os componentes conversarem
 * entre si sem depender do tipo gerado.
 */

export type StepStatus = 'pending' | 'in_progress' | 'done' | 'not_applicable' | 'blocked';
export type StepKind = 'do' | 'check' | 'safety' | 'evidence' | 'handoff';
export type StepMode = 'read_do' | 'do_confirm';
export type StepOrigin = 'template' | 'ai' | 'manual' | 'client_request';

export interface ServiceOrderStep {
  id: string;
  service_order_id: string;
  service_order_service_id: string | null;
  template_id: string | null;
  seq: number;
  block: string | null;
  title: string;
  detail: string | null;
  kind: StepKind;
  mode: StepMode;
  standard_minutes: number | null;
  is_killer: boolean;
  requires_photo: boolean;
  requires_measure: string | null;
  measure_unit: string | null;
  measure_value: number | null;
  status: StepStatus;
  na_reason: string | null;
  blocked_reason_code: string | null;
  blocked_note: string | null;
  assigned_user_id: string | null;
  started_at: string | null;
  completed_at: string | null;
  actual_minutes: number | null;
  origin: StepOrigin;
  notes: string | null;
  /** Preenchidos só quando origin='ai'. approved_at nulo = ainda é sugestão. */
  ai_confidence?: number | null;
  ai_source?: string | null;
  approved_at?: string | null;
}

export interface StopReason {
  code: string;
  label: string;
  category: string;
  counts_as_billable: boolean;
  sort: number;
}

const STEP_SELECT = `
  id, service_order_id, service_order_service_id, template_id, seq, block, title, detail,
  kind, mode, standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
  measure_value, status, na_reason, blocked_reason_code, blocked_note, assigned_user_id,
  started_at, completed_at, actual_minutes, origin, notes,
  ai_confidence, ai_source, approved_at
`;

/** Passos de uma OS, na ordem de execução. */
export function useServiceOrderSteps(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['service-order-steps', serviceOrderId],
    enabled: !!serviceOrderId,
    queryFn: async (): Promise<ServiceOrderStep[]> => {
      const { data, error } = await supabase
        .from('service_order_steps')
        .select(STEP_SELECT)
        .eq('service_order_id', serviceOrderId)
        .order('seq', { ascending: true });
      if (error) throw error;
      return (data || []) as ServiceOrderStep[];
    },
  });
}

/** Lista fechada de motivos de parada (8-12 no nível 1, por desenho). */
export function useStopReasons() {
  return useQuery({
    queryKey: ['work-stop-reasons'],
    staleTime: 60 * 60 * 1000, // muda raramente; revisão é trimestral
    queryFn: async (): Promise<StopReason[]> => {
      const { data, error } = await supabase
        .from('work_stop_reasons')
        .select('code, label, category, counts_as_billable, sort')
        .eq('active', true)
        .order('sort', { ascending: true });
      if (error) throw error;
      return (data || []) as StopReason[];
    },
  });
}

/**
 * Gera o roteiro a partir dos templates do catálogo.
 * Idempotente no banco: linha de serviço que já tem passos é pulada.
 */
export function useGenerateSteps() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (serviceOrderId: string): Promise<number> => {
      const { data, error } = await supabase.rpc('generate_service_order_steps', {
        p_service_order_id: serviceOrderId,
      });
      if (error) throw error;
      return (data as number) ?? 0;
    },
    onSuccess: (_n, serviceOrderId) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', serviceOrderId] });
    },
  });
}

/** Minutos decorridos desde started_at, com piso de 1 (toque rápido não vira zero). */
export function elapsedMinutesSince(startedAt: string | null | undefined): number {
  if (!startedAt) return 0;
  const ms = Date.now() - new Date(startedAt).getTime();
  return Math.max(1, Math.round(ms / 60000));
}

/**
 * Tempo total de um passo: o que já estava acumulado de trechos anteriores mais
 * o trecho em curso. É o que mantém o número honesto quando o técnico pausa,
 * atende o cliente e volta uma hora depois — sem isso, a hora parada entraria
 * como hora trabalhada.
 */
export function accumulatedMinutes(step: ServiceOrderStep): number | null {
  const previous = step.actual_minutes ?? 0;
  const current = step.started_at ? elapsedMinutesSince(step.started_at) : 0;
  const total = previous + current;
  // null (não zero) quando o passo nunca rodou: zero mentiria na estatística.
  return total > 0 ? total : null;
}

/**
 * Inicia (ou retoma) um passo. O técnico não "aponta hora": tocar em começar já
 * grava o relógio. Só um passo fica em execução por vez na mesma OS — sem isso o
 * mesmo minuto seria contado duas vezes.
 */
export function useStartStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ step }: { step: ServiceOrderStep }) => {
      const now = new Date().toISOString();

      // Pausa implícita do passo que estava rodando: fecha o trecho em curso
      // somando ao acumulado e zera started_at, para o relógio não continuar
      // correndo enquanto o técnico está em outro passo.
      const { data: running } = await supabase
        .from('service_order_steps')
        .select('id, actual_minutes, started_at')
        .eq('service_order_id', step.service_order_id)
        .eq('status', 'in_progress')
        .neq('id', step.id);

      for (const other of (running || []) as Array<{ id: string; actual_minutes: number | null; started_at: string | null }>) {
        await supabase
          .from('service_order_steps')
          .update({
            status: 'pending',
            actual_minutes: (other.actual_minutes ?? 0) + elapsedMinutesSince(other.started_at),
            started_at: null,
          })
          .eq('id', other.id);
      }

      const { error } = await supabase
        .from('service_order_steps')
        .update({ status: 'in_progress', started_at: now })
        .eq('id', step.id);
      if (error) throw error;
    },
    onSuccess: (_r, { step }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', step.service_order_id] });
    },
  });
}

export function useCompleteStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      step, measureValue, notes,
    }: { step: ServiceOrderStep; measureValue?: number | null; notes?: string }) => {
      const now = new Date().toISOString();
      const { error } = await supabase
        .from('service_order_steps')
        .update({
          status: 'done',
          completed_at: now,
          actual_minutes: accumulatedMinutes(step),
          started_at: null,
          ...(measureValue !== undefined ? { measure_value: measureValue } : {}),
          ...(notes !== undefined ? { notes } : {}),
        })
        .eq('id', step.id);
      if (error) throw error;
    },
    onSuccess: (_r, { step }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', step.service_order_id] });
      // Mesma chave usada por useServiceOrder (use-service-orders.ts): o rollup do
      // trigger altera service_order_services, que vem no detalhe da OS.
      qc.invalidateQueries({ queryKey: ['service-orders', step.service_order_id] });
    },
  });
}

/** "Não se aplica" é resposta legítima — mas exige motivo (o banco também exige). */
export function useSkipStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ step, reason }: { step: ServiceOrderStep; reason: string }) => {
      const trimmed = reason.trim();
      if (!trimmed) throw new Error('Diga em uma palavra por que não se aplica.');
      const { error } = await supabase
        .from('service_order_steps')
        .update({ status: 'not_applicable', na_reason: trimmed, completed_at: new Date().toISOString() })
        .eq('id', step.id);
      if (error) throw error;
    },
    onSuccess: (_r, { step }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', step.service_order_id] });
    },
  });
}

/** Travou: motivo da lista fechada, e o escritório fica sabendo na hora. */
export function useBlockStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      step, reasonCode, note,
    }: { step: ServiceOrderStep; reasonCode: string; note?: string }) => {
      if (!reasonCode) throw new Error('Escolha o motivo da parada.');
      const { error } = await supabase
        .from('service_order_steps')
        .update({
          status: 'blocked',
          blocked_reason_code: reasonCode,
          blocked_note: note?.trim() || null,
          // Fecha o trecho em curso: o tempo até travar é trabalho real; o
          // tempo travado não é, e por isso o relógio para aqui.
          actual_minutes: accumulatedMinutes(step),
          started_at: null,
        })
        .eq('id', step.id);
      if (error) throw error;
    },
    onSuccess: (_r, { step }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', step.service_order_id] });
    },
  });
}

/** Volta um passo para pendente — errar o toque não pode custar o dado. */
export function useReopenStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (step: ServiceOrderStep) => {
      const { error } = await supabase
        .from('service_order_steps')
        .update({
          // Desfazer é desfazer: o tempo do trecho anterior some junto, senão
          // o passo refeito nasceria com relógio adiantado.
          status: 'pending', completed_at: null, actual_minutes: null, started_at: null,
          na_reason: null, blocked_reason_code: null, blocked_note: null,
        })
        .eq('id', step.id);
      if (error) throw error;
    },
    onSuccess: (_r, step) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', step.service_order_id] });
    },
  });
}

/**
 * Passo novo. O tipo exige o que o banco exige (OS, título e posição) em vez de
 * aceitar um objeto parcial e descobrir o que falta só no erro do servidor.
 */
export type NewStep =
  Pick<ServiceOrderStep, 'service_order_id' | 'title' | 'seq'> &
  Partial<Pick<ServiceOrderStep, 'block' | 'detail' | 'kind' | 'mode' | 'standard_minutes'
    | 'is_killer' | 'requires_photo' | 'requires_measure' | 'measure_unit'
    | 'assigned_user_id' | 'origin' | 'notes'>>;

export function useCreateStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: NewStep): Promise<string> => {
      const { data, error } = await supabase
        .from('service_order_steps')
        .insert({ origin: 'manual', ...input })
        .select('id')
        .single();
      if (error) throw error;
      return data.id;
    },
    onSuccess: (_r, input) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', input.service_order_id] });
    },
  });
}

export function useUpdateStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id, serviceOrderId, patch,
    }: { id: string; serviceOrderId: string; patch: Partial<Omit<ServiceOrderStep, 'id' | 'service_order_id'>> }) => {
      const { error } = await supabase.from('service_order_steps').update(patch).eq('id', id);
      if (error) throw error;
    },
    onSuccess: (_r, { serviceOrderId }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', serviceOrderId] });
    },
  });
}

export function useDeleteStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id }: { id: string; serviceOrderId: string }) => {
      const { error } = await supabase.from('service_order_steps').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: (_r, { serviceOrderId }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', serviceOrderId] });
    },
  });
}

/** Troca a posição de dois passos consecutivos. */
export function useReorderSteps() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ a, b }: { a: ServiceOrderStep; b: ServiceOrderStep }) => {
      // seq tem unique só no template; aqui a troca direta é segura.
      const { error: e1 } = await supabase
        .from('service_order_steps').update({ seq: b.seq }).eq('id', a.id);
      if (e1) throw e1;
      const { error: e2 } = await supabase
        .from('service_order_steps').update({ seq: a.seq }).eq('id', b.id);
      if (e2) throw e2;
    },
    onSuccess: (_r, { a }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', a.service_order_id] });
    },
  });
}

// ── Resumo do roteiro ────────────────────────────────────────────────────────

export interface RouteSummary {
  total: number;
  done: number;
  blocked: number;
  notApplicable: number;
  pending: number;
  standardMinutes: number;
  actualMinutes: number;
  /** null quando ainda não há padrão para comparar. */
  variancePct: number | null;
  /** true quando todo passo chegou a um estado terminal. */
  finished: boolean;
}

export function summarizeRoute(steps: ServiceOrderStep[]): RouteSummary {
  const total = steps.length;
  const done = steps.filter((s) => s.status === 'done').length;
  const blocked = steps.filter((s) => s.status === 'blocked').length;
  const notApplicable = steps.filter((s) => s.status === 'not_applicable').length;
  const standardMinutes = steps.reduce((sum, s) => sum + (s.standard_minutes || 0), 0);
  const actualMinutes = steps.reduce((sum, s) => sum + (s.actual_minutes || 0), 0);
  return {
    total,
    done,
    blocked,
    notApplicable,
    pending: total - done - blocked - notApplicable,
    standardMinutes,
    actualMinutes,
    variancePct:
      standardMinutes > 0
        ? Math.round(((actualMinutes - standardMinutes) / standardMinutes) * 1000) / 10
        : null,
    finished: total > 0 && done + notApplicable === total,
  };
}

/** Agrupa por bloco preservando a ordem de seq. */
export function groupStepsByBlock(steps: ServiceOrderStep[]): Array<{ block: string; steps: ServiceOrderStep[] }> {
  const groups: Array<{ block: string; steps: ServiceOrderStep[] }> = [];
  for (const step of steps) {
    const label = step.block || 'Roteiro';
    const last = groups[groups.length - 1];
    if (last && last.block === label) last.steps.push(step);
    else groups.push({ block: label, steps: [step] });
  }
  return groups;
}

/** O próximo passo a executar: em andamento primeiro, senão o primeiro pendente. */
export function nextStep(steps: ServiceOrderStep[]): ServiceOrderStep | undefined {
  return steps.find((s) => s.status === 'in_progress') || steps.find((s) => s.status === 'pending');
}

// ── Rascunho da IA (IA-1) ────────────────────────────────────────────────────

/**
 * Passo proposto pela IA e ainda não julgado por um humano.
 * `approved_at` nulo com `origin='ai'` é o que separa sugestão de roteiro válido.
 */
export function isAiDraft(step: ServiceOrderStep & { approved_at?: string | null }): boolean {
  return step.origin === 'ai' && !step.approved_at;
}

/**
 * Aprova ou descarta um passo sugerido, registrando o veredito.
 *
 * O registro é o ponto: sem ele, a IA propõe para sempre a mesma coisa errada.
 * `edited` cobre o caso em que a pessoa aceitou a ideia mas reescreveu — que é
 * o sinal mais informativo dos três.
 */
export function useReviewAiStep() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      step, verdict, changeSummary,
    }: {
      step: ServiceOrderStep;
      verdict: 'accepted' | 'edited' | 'rejected';
      changeSummary?: string;
    }) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      if (verdict === 'rejected') {
        const { error } = await supabase.from('service_order_steps').delete().eq('id', step.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('service_order_steps')
          .update({ approved_by: reviewer, approved_at: new Date().toISOString() })
          .eq('id', step.id);
        if (error) throw error;
      }

      const { error: revErr } = await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'step',
        target_table: 'service_order_steps',
        target_id: step.id,
        suggested: {
          title: step.title, detail: step.detail, kind: step.kind,
          standard_minutes: step.standard_minutes, block: step.block,
        },
        approved: verdict === 'rejected' ? null : { title: step.title, standard_minutes: step.standard_minutes },
        verdict,
        change_summary: changeSummary ?? null,
        reviewer_id: reviewer,
      });
      if (revErr) throw revErr;
    },
    onSuccess: (_r, { step }) => {
      qc.invalidateQueries({ queryKey: ['service-order-steps', step.service_order_id] });
    },
  });
}

export function formatMinutes(min: number | null | undefined): string {
  if (min === null || min === undefined) return '—';
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m === 0 ? `${h}h` : `${h}h${String(m).padStart(2, '0')}`;
}

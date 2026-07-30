import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Levantamento antes de orçar — Fase 4 do Ciclo do Serviço.
 * Plano: plans/marineflow-execucao-os-roteiro.md (P15 a P18)
 */

export interface SurveyTrigger {
  precisa: boolean;
  motivos: string[];
  casos_conhecidos: number;
  dispersao_pct: number | null;
}

export interface CaseEstimate {
  tem_base: boolean;
  casos: number;
  mensagem?: string;
  p50_min?: number;
  p80_min?: number;
  contingencia_pct?: number;
  baseado_em?: Array<{ os: string; minutos: number; quando: string }>;
}

export interface SurveyQuestion {
  id: string;
  seq: number;
  question: string;
  help_text: string | null;
  answer_type: 'sim_nao' | 'escolha' | 'numero' | 'texto' | 'foto' | 'medida';
  options: string[] | null;
  price_impact: 'alto' | 'medio' | 'baixo';
  ask_remotely: boolean;
}

const IMPACT_ORDER: Record<string, number> = { alto: 0, medio: 1, baixo: 2 };

/**
 * O gatilho do P15: quatro contas sobre o histórico, nenhuma IA.
 * Só roda quando há serviço escolhido — sem isso não há o que avaliar.
 */
export function useSurveyTrigger(
  serviceId: string | undefined,
  opts: { clientId?: string | null; vesselId?: string | null; valor?: number | null } = {},
) {
  return useQuery({
    queryKey: ['survey-trigger', serviceId, opts.clientId, opts.valor],
    enabled: !!serviceId,
    queryFn: async (): Promise<SurveyTrigger> => {
      const { data, error } = await supabase.rpc('should_survey_service', {
        p_service_id: serviceId!,
        p_client_id: opts.clientId ?? null,
        p_vessel_id: opts.vesselId ?? null,
        p_valor: opts.valor ?? null,
      });
      if (error) throw error;
      return data as unknown as SurveyTrigger;
    },
  });
}

/** Estimativa por analogia. Devolve `tem_base: false` em vez de inventar número. */
export function useCaseEstimate(serviceId: string | undefined) {
  return useQuery({
    queryKey: ['case-estimate', serviceId],
    enabled: !!serviceId,
    queryFn: async (): Promise<CaseEstimate> => {
      const { data, error } = await supabase.rpc('estimate_from_cases', { p_service_id: serviceId! });
      if (error) throw error;
      return data as unknown as CaseEstimate;
    },
  });
}

/** Perguntas do serviço, já na ordem de impacto no preço e com teto de 9 (P16). */
export function useSurveyQuestions(serviceId: string | undefined, mode: 'local' | 'remoto' = 'local') {
  return useQuery({
    queryKey: ['survey-questions', serviceId, mode],
    enabled: !!serviceId,
    queryFn: async (): Promise<SurveyQuestion[]> => {
      const { data, error } = await supabase
        .from('service_survey_templates')
        .select('id, seq, question, help_text, answer_type, options, price_impact, ask_remotely')
        .eq('service_id', serviceId!)
        .eq('active', true);
      if (error) throw error;
      return ((data || []) as unknown as SurveyQuestion[])
        .filter((q) => (mode === 'remoto' ? q.ask_remotely : true))
        .sort((a, b) => (IMPACT_ORDER[a.price_impact] ?? 1) - (IMPACT_ORDER[b.price_impact] ?? 1) || a.seq - b.seq)
        .slice(0, 9);
    },
  });
}

export function useServiceOrderSurvey(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['service-survey', serviceOrderId],
    enabled: !!serviceOrderId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_surveys')
        .select('*, service_survey_answers(seq, question_snapshot, answer_value, skipped_reason)')
        .eq('service_order_id', serviceOrderId!)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });
}

export function useStartSurvey() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      serviceId: string; triggerReason: string; serviceOrderId?: string;
      clientId?: string | null; vesselId?: string | null; mode?: 'local' | 'remoto';
      questionsPlanned: number;
    }): Promise<string> => {
      const { data, error } = await supabase
        .from('service_surveys')
        .insert({
          service_id: input.serviceId,
          service_order_id: input.serviceOrderId ?? null,
          client_id: input.clientId ?? null,
          vessel_id: input.vesselId ?? null,
          trigger_reason: input.triggerReason,
          mode: input.mode ?? 'local',
          questions_planned: input.questionsPlanned,
        })
        .select('id')
        .single();
      if (error) throw error;
      return data.id;
    },
    onSuccess: (_id, input) => {
      qc.invalidateQueries({ queryKey: ['service-survey', input.serviceOrderId] });
    },
  });
}

export function useAnswerSurvey() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      surveyId: string; serviceOrderId?: string; seq: number; question: string;
      templateId?: string; answer?: string; skippedReason?: string;
    }) => {
      const { error } = await supabase.from('service_survey_answers').upsert(
        {
          survey_id: input.surveyId,
          template_id: input.templateId ?? null,
          seq: input.seq,
          question_snapshot: input.question,
          answer_value: input.answer ?? null,
          skipped_reason: input.skippedReason ?? null,
        },
        { onConflict: 'survey_id,seq' },
      );
      if (error) throw error;
    },
    onSuccess: (_r, input) => {
      qc.invalidateQueries({ queryKey: ['service-survey', input.serviceOrderId] });
    },
  });
}

/**
 * Fecha o levantamento. A confiança exige justificativa — o banco também impõe,
 * mas errar aqui daria erro feio na tela em vez de aviso claro.
 */
export function useCloseSurvey() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      surveyId: string; serviceOrderId?: string;
      confidence: 'alta' | 'media' | 'baixa'; rationale: string;
      estimate?: CaseEstimate | null;
    }) => {
      if (!input.rationale.trim()) {
        throw new Error('Escreva em uma linha o que você já sabe e o que ficou em aberto.');
      }
      const ajuste = input.confidence === 'baixa' ? 10 : input.confidence === 'media' ? 5 : 0;
      const base = input.estimate?.tem_base ? Number(input.estimate.contingencia_pct ?? 0) : null;

      const { error } = await supabase
        .from('service_surveys')
        .update({
          status: 'closed',
          confidence: input.confidence,
          confidence_rationale: input.rationale.trim(),
          estimated_minutes_p50: input.estimate?.p50_min ?? null,
          estimated_minutes_p80: input.estimate?.p80_min ?? null,
          contingency_pct: base === null ? null : base + ajuste,
          cases_used: (input.estimate?.baseado_em as any) ?? null,
          answered_at: new Date().toISOString(),
        })
        .eq('id', input.surveyId);
      if (error) throw error;
    },
    onSuccess: (_r, input) => {
      qc.invalidateQueries({ queryKey: ['service-survey', input.serviceOrderId] });
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

/**
 * Contingência final = a do histórico (dispersão dos casos) mais o ajuste pela
 * confiança de quem levantou. Separado para poder ser testado sem o banco.
 */
export function finalContingency(
  estimate: CaseEstimate | null | undefined,
  confidence: 'alta' | 'media' | 'baixa',
): number | null {
  if (!estimate?.tem_base) return null;
  const ajuste = confidence === 'baixa' ? 10 : confidence === 'media' ? 5 : 0;
  return Number(estimate.contingencia_pct ?? 0) + ajuste;
}

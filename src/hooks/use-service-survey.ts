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
/**
 * O questionário de um serviço, montado por composição.
 *
 * Pergunta escrita para o serviço específico ganha; se não houver nenhuma,
 * compõe pelo sistema e pelo verbo do serviço — os mesmos eixos do roteiro.
 * Sem isso seriam 261 questionários para escrever e manter, um por serviço.
 * O corte em 9 (P16) é feito no banco, na ordem de impacto no preço.
 */
export function useSurveyQuestions(serviceId: string | undefined, mode: 'local' | 'remoto' = 'local') {
  return useQuery({
    queryKey: ['survey-questions', serviceId, mode],
    enabled: !!serviceId,
    queryFn: async (): Promise<SurveyQuestion[]> => {
      const { data, error } = await supabase.rpc('compose_survey_for_service', {
        p_service_id: serviceId!,
        p_mode: mode,
      });
      if (error) throw error;
      return ((data || []) as unknown as SurveyQuestion[])
        .sort((a, b) => (IMPACT_ORDER[a.price_impact] ?? 1) - (IMPACT_ORDER[b.price_impact] ?? 1) || a.seq - b.seq);
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
        .select(
          // template_id vem junto porque a correção de uma resposta precisa
          // regravá-lo: sem ele a resposta deixa de casar com a pergunta do
          // catálogo, e some tanto do histórico do ativo quanto das regras de
          // material.
          '*, service_survey_answers(seq, template_id, question_snapshot, answer_value, skipped_reason, photo_path, answered_at)',
        )
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

export interface PreviousAnswer {
  template_id: string;
  question: string;
  answer: string;
  answered_at: string | null;
  service_order_number: string | null;
}

/**
 * O que já se sabe deste ativo, de levantamentos anteriores.
 *
 * Metade das perguntas de um levantamento tem a mesma resposta sempre — onde
 * fica o cilindro, a distância do banco ao quadro, se existe detector de gás.
 * Perguntar de novo o que não muda gasta o tempo de quem responde e ensina que
 * o levantamento é burocracia.
 *
 * A memória é do ATIVO, não do cliente: o cilindro fica no mesmo lugar do mesmo
 * motorhome, independentemente de quem o comprou depois.
 */
export function usePreviousAnswers(vesselId: string | null | undefined) {
  return useQuery({
    queryKey: ['survey-previous-answers', vesselId],
    enabled: !!vesselId,
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<Record<string, PreviousAnswer>> => {
      const { data, error } = await supabase.rpc('previous_survey_answers', {
        p_vessel_id: vesselId!,
      });
      if (error) throw error;
      return Object.fromEntries(
        ((data || []) as unknown as PreviousAnswer[]).map((r) => [r.template_id, r]),
      );
    },
  });
}

/**
 * A resposta anterior serve de atalho para esta pergunta?
 *
 * Se a pergunta virou "escolha" com outras opções desde a última vez, a resposta
 * antiga ainda informa quem está no local, mas não pode virar botão: jogá-la no
 * Select daria um clique que não muda nada na tela.
 */
export function canReuseAnswer(
  question: Pick<SurveyQuestion, 'answer_type' | 'options'> | undefined,
  previous: PreviousAnswer | undefined,
): boolean {
  if (!question || !previous?.answer) return false;
  if (question.answer_type !== 'escolha') return true;
  return !!question.options?.includes(previous.answer);
}

/** "há 3 meses", "há 2 anos" — a idade importa mais que a data exata. */
export function howLongAgo(iso: string | null | undefined): string {
  if (!iso) return 'levantamento anterior';
  const dias = Math.floor((Date.now() - new Date(iso).getTime()) / 86400000);
  if (dias < 1) return 'hoje';
  if (dias < 30) return `há ${dias} dia${dias > 1 ? 's' : ''}`;
  const meses = Math.floor(dias / 30);
  if (meses < 12) return `há ${meses} ${meses > 1 ? 'meses' : 'mês'}`;
  const anos = Math.floor(meses / 12);
  return `há ${anos} ano${anos > 1 ? 's' : ''}`;
}

/**
 * Sobe a foto do levantamento e devolve o caminho no bucket.
 *
 * A coluna `photo_path` existia desde o início e nunca tinha sido usada: dava
 * para marcar uma pergunta como do tipo "foto" e não havia onde anexar nada.
 * Em levantamento é a foto que sustenta o preço — quem orça de memória, orça
 * errado, e quem discorda depois não tem o que olhar.
 */
export async function uploadSurveyPhoto(
  surveyId: string, seq: number, file: File,
): Promise<string> {
  const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
  const path = `surveys/${surveyId}/${seq}-${Date.now()}.${ext}`;
  const { error } = await supabase.storage
    .from('service-order-photos')
    .upload(path, file, { upsert: true, contentType: file.type || 'image/jpeg' });
  if (error) throw error;
  return path;
}

/** URL pública da foto — o bucket de fotos de OS já é público. */
export function surveyPhotoUrl(path: string): string {
  return supabase.storage.from('service-order-photos').getPublicUrl(path).data.publicUrl;
}

export function useAnswerSurvey() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      surveyId: string; serviceOrderId?: string; seq: number; question: string;
      templateId?: string; answer?: string; skippedReason?: string; photoPath?: string;
    }) => {
      const { error } = await supabase.from('service_survey_answers').upsert(
        {
          survey_id: input.surveyId,
          template_id: input.templateId ?? null,
          seq: input.seq,
          question_snapshot: input.question,
          answer_value: input.answer ?? null,
          skipped_reason: input.skippedReason ?? null,
          ...(input.photoPath ? { photo_path: input.photoPath } : {}),
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

/**
 * Reabre um levantamento fechado, sem apagar nada.
 *
 * Fechar não pode ser ponto sem volta: voltou-se ao local, achou-se o que
 * faltava, e obrigar a refazer as nove perguntas do zero é o caminho mais curto
 * para ninguém mais levantar nada. A confiança e a estimativa são limpas de
 * propósito — foram um julgamento sobre um conjunto de respostas que agora vai
 * mudar, e mantê-las seria carimbar de novo o que não foi reavaliado.
 */
export function useReopenSurvey() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { surveyId: string; serviceOrderId?: string }) => {
      const { error } = await supabase
        .from('service_surveys')
        .update({
          status: 'draft',
          confidence: null,
          confidence_rationale: null,
          answered_at: null,
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

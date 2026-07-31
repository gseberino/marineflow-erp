import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { SYSTEM_LABEL, VERB_LABEL } from '@/hooks/use-step-blocks';

/**
 * Perguntas de levantamento do catálogo (service_survey_templates).
 * Plano: plans/marineflow-execucao-os-roteiro.md, seção 3-bis (P15-P18)
 *
 * Mesma arquitetura dos blocos de roteiro: a pergunta pertence ao SISTEMA ou
 * ao VERBO, não ao serviço — 16 conjuntos cobrem os 261 serviços. E, como nos
 * blocos, o banco impõe que pergunta de IA só vale depois de assinada.
 */

export type AnswerType = 'sim_nao' | 'escolha' | 'numero' | 'texto' | 'foto' | 'medida';
export type PriceImpact = 'alto' | 'medio' | 'baixo';

export interface SurveyTemplate {
  id: string;
  service_id: string | null;
  applies_to_system: string | null;
  applies_to_verb: string | null;
  seq: number;
  question: string;
  help_text: string | null;
  answer_type: AnswerType;
  price_impact: PriceImpact;
  ask_remotely: boolean;
  origin: 'manual' | 'ai';
  approved_by: string | null;
  approved_at: string | null;
  active: boolean;
}

const S_SELECT = `
  id, service_id, applies_to_system, applies_to_verb, seq, question, help_text,
  answer_type, price_impact, ask_remotely, origin, approved_by, approved_at, active
`;

export function useSurveyTemplates() {
  return useQuery({
    queryKey: ['survey-templates'],
    queryFn: async (): Promise<SurveyTemplate[]> => {
      const { data, error } = await supabase
        .from('service_survey_templates')
        .select(S_SELECT)
        .order('seq');
      if (error) throw error;
      return (data || []) as unknown as SurveyTemplate[];
    },
  });
}

export function surveyPendingApproval(q: SurveyTemplate): boolean {
  return q.origin === 'ai' && !q.approved_at;
}

export function useApproveSurveyQuestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ question, edited }: { question: SurveyTemplate; edited?: boolean }) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      const { error } = await supabase
        .from('service_survey_templates')
        .update({ approved_by: reviewer, approved_at: new Date().toISOString(), active: true })
        .eq('id', question.id);
      if (error) throw error;

      await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'survey_question',
        target_table: 'service_survey_templates',
        target_id: question.id,
        service_id: question.service_id,
        suggested: {
          question: question.question, help_text: question.help_text,
          answer_type: question.answer_type, price_impact: question.price_impact,
          eixo: question.applies_to_system ?? question.applies_to_verb,
        },
        approved: { question: question.question, price_impact: question.price_impact },
        verdict: edited ? 'edited' : 'accepted',
        reviewer_id: reviewer,
      });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['survey-templates'] }),
  });
}

export function useRejectSurveyQuestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (question: SurveyTemplate) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'survey_question',
        target_table: 'service_survey_templates',
        target_id: question.id,
        service_id: question.service_id,
        suggested: {
          question: question.question, help_text: question.help_text,
          answer_type: question.answer_type, price_impact: question.price_impact,
          eixo: question.applies_to_system ?? question.applies_to_verb,
        },
        approved: null,
        verdict: 'rejected',
        reviewer_id: reviewer,
      });

      const { error } = await supabase.from('service_survey_templates').delete().eq('id', question.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['survey-templates'] }),
  });
}

export function useUpdateSurveyQuestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id, patch,
    }: { id: string; patch: Partial<Pick<SurveyTemplate, 'question' | 'help_text' | 'ask_remotely'>> }) => {
      const { error } = await supabase.from('service_survey_templates').update(patch).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['survey-templates'] }),
  });
}

export interface SurveyGroup {
  key: string;
  eixoLabel: string;
  tipo: 'sistema' | 'verbo' | 'serviço';
  questions: SurveyTemplate[];
  pendentes: number;
  remotas: number;
}

export function groupSurveyQuestions(questions: SurveyTemplate[]): SurveyGroup[] {
  const mapa = new Map<string, SurveyGroup>();
  for (const q of questions) {
    const tipo: SurveyGroup['tipo'] =
      q.applies_to_system ? 'sistema' : q.applies_to_verb ? 'verbo' : 'serviço';
    const eixo = q.applies_to_system ?? q.applies_to_verb ?? q.service_id ?? '—';
    const key = `${tipo}:${eixo}`;
    let g = mapa.get(key);
    if (!g) {
      g = {
        key, tipo,
        eixoLabel:
          tipo === 'sistema' ? SYSTEM_LABEL[eixo] ?? eixo
          : tipo === 'verbo' ? VERB_LABEL[eixo] ?? eixo
          : 'Serviço específico',
        questions: [], pendentes: 0, remotas: 0,
      };
      mapa.set(key, g);
    }
    g.questions.push(q);
    if (surveyPendingApproval(q)) g.pendentes++;
    if (q.ask_remotely) g.remotas++;
  }
  const ordemTipo = { sistema: 0, verbo: 1, 'serviço': 2 } as const;
  return [...mapa.values()].sort(
    (a, b) => ordemTipo[a.tipo] - ordemTipo[b.tipo] || a.eixoLabel.localeCompare(b.eixoLabel),
  );
}

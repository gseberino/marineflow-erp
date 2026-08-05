import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * O levantamento compondo o orçamento.
 *
 * Uma regra diz: para esta pergunta, quando a resposta for assim, entra este
 * produto nesta quantidade. Antes disso, medir 14 metros e depois digitar o
 * cabo na mão era o trabalho que o levantamento existia para poupar.
 */

export type ConditionType = 'sempre' | 'igual' | 'contem' | 'faixa' | 'sim' | 'nao';
export type QtyMode = 'fixa' | 'proporcional' | 'por_unidade';

export interface MaterialRule {
  id: string;
  template_id: string;
  condition_type: ConditionType;
  match_value: string | null;
  min_value: number | null;
  max_value: number | null;
  product_id: string;
  qty_mode: QtyMode;
  qty_fixed: number;
  qty_factor: number;
  qty_slack_pct: number;
  qty_round: 'nenhum' | 'cima' | 'meio';
  rationale: string | null;
  origin: 'ai' | 'human';
  active: boolean;
  approved_at: string | null;
}

export interface SuggestedMaterial {
  rule_id: string;
  product_id: string;
  product_name: string;
  unit: string | null;
  question: string;
  answer: string;
  quantity: number | null;
  unit_sale: number;
  unit_cost: number;
  line_total: number | null;
  rationale: string | null;
  /** O que está errado com esta linha. Aparece junto do número, nunca depois. */
  alerta: string | null;
}

/**
 * O material que as respostas deste levantamento implicam.
 *
 * Recalcula a cada mudança de resposta em vez de guardar uma lista: corrigiu a
 * medida, a quantidade acompanha. Lista guardada envelheceria em silêncio.
 */
export function useSuggestedMaterials(surveyId: string | null | undefined) {
  return useQuery({
    queryKey: ['survey-suggested-materials', surveyId],
    enabled: !!surveyId,
    queryFn: async (): Promise<SuggestedMaterial[]> => {
      const { data, error } = await supabase.rpc('survey_suggested_materials', {
        p_survey_id: surveyId!,
      });
      if (error) throw error;
      return (data || []) as unknown as SuggestedMaterial[];
    },
  });
}

/** Lança no orçamento só o que foi conferido, uma regra por vez escolhida. */
export function useApplySurveyMaterials() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      surveyId: string; ruleIds: string[]; serviceOrderId?: string;
    }): Promise<{ ok: boolean; linhas_criadas?: number; mensagem: string }> => {
      const { data, error } = await supabase.rpc('apply_survey_materials', {
        p_survey_id: input.surveyId,
        p_rule_ids: input.ruleIds,
      });
      if (error) throw error;
      return data as unknown as { ok: boolean; linhas_criadas?: number; mensagem: string };
    },
    onSuccess: (_r, input) => {
      qc.invalidateQueries({ queryKey: ['service-order-parts', input.serviceOrderId] });
      qc.invalidateQueries({ queryKey: ['service-order', input.serviceOrderId] });
      qc.invalidateQueries({ queryKey: ['survey-suggested-materials', input.surveyId] });
    },
  });
}

/** As regras de uma pergunta, para a tela onde elas são escritas e aprovadas. */
export function useMaterialRules(templateId?: string) {
  return useQuery({
    queryKey: ['survey-material-rules', templateId ?? 'todas'],
    queryFn: async (): Promise<MaterialRule[]> => {
      let q = supabase.from('survey_material_rules').select('*').order('created_at');
      if (templateId) q = q.eq('template_id', templateId);
      const { data, error } = await q;
      if (error) throw error;
      return (data || []) as MaterialRule[];
    },
  });
}

export function useSaveMaterialRule() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (rule: Partial<MaterialRule> & { template_id: string; product_id: string }) => {
      const { id, ...campos } = rule;
      const { error } = id
        ? await supabase.from('survey_material_rules').update(campos).eq('id', id)
        : await supabase.from('survey_material_rules').insert(campos as any);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['survey-material-rules'] }),
  });
}

/**
 * Aprovar é o que liga a regra. Regra de material mexe em preço: entra inativa
 * e só passa a valer com nome e data de quem assumiu.
 */
export function useApproveMaterialRule() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { id: string; active: boolean }) => {
      const { data: user } = await supabase.auth.getUser();
      const { error } = await supabase
        .from('survey_material_rules')
        .update(
          input.active
            ? { active: true, approved_at: new Date().toISOString(), approved_by: user.user?.id ?? null }
            : { active: false },
        )
        .eq('id', input.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['survey-material-rules'] }),
  });
}

export function useDeleteMaterialRule() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('survey_material_rules').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['survey-material-rules'] }),
  });
}

/**
 * A regra em uma frase, do jeito que se diz em voz alta.
 *
 * Separado para poder ser testado sem o banco — e porque a tela de aprovação
 * vale pelo que essa frase diz: ninguém aprova um formulário de nove campos,
 * mas todo mundo aprova "2 m de cabo por metro medido, +15% de folga".
 */
export function ruleInWords(
  rule: Pick<MaterialRule, 'condition_type' | 'match_value' | 'min_value' | 'max_value'
    | 'qty_mode' | 'qty_fixed' | 'qty_factor' | 'qty_slack_pct'>,
  productName?: string,
  unit?: string | null,
): string {
  const quando =
    rule.condition_type === 'sempre' ? 'Sempre que respondida'
      : rule.condition_type === 'sim' ? 'Quando a resposta for sim'
      : rule.condition_type === 'nao' ? 'Quando a resposta for não'
      : rule.condition_type === 'igual' ? `Quando a resposta for "${rule.match_value}"`
      : rule.condition_type === 'contem' ? `Quando a resposta citar "${rule.match_value}"`
      : rule.min_value !== null && rule.max_value !== null ? `De ${rule.min_value} a ${rule.max_value}`
      : rule.min_value !== null ? `Acima de ${rule.min_value}`
      : `Até ${rule.max_value}`;

  const un = unit ? ` ${unit}` : '';
  const quanto =
    rule.qty_mode === 'fixa' ? `${rule.qty_fixed}${un}`
      : rule.qty_mode === 'proporcional' ? `${rule.qty_factor}${un} por unidade medida`
      : `${rule.qty_factor}${un} por item contado`;

  const folga = rule.qty_slack_pct > 0 ? `, +${rule.qty_slack_pct}% de folga` : '';
  return `${quando}: ${quanto}${folga} de ${productName ?? 'produto'}`;
}

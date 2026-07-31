import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { StepKind, StepMode } from '@/hooks/use-service-steps';

/**
 * Roteiros padrão do catálogo (service_step_templates).
 * Plano: plans/marineflow-execucao-os-roteiro.md (P1, P4, P14)
 *
 * Template rascunhado pela IA nasce inativo e sem aprovação. O banco impõe:
 * origin='ai' + active=true exige approved_by preenchido.
 */

export interface StepTemplate {
  id: string;
  service_id: string;
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
  origin: 'manual' | 'ai';
  approved_by: string | null;
  approved_at: string | null;
  active: boolean;
  version: number;
  services?: { name: string } | null;
}

const T_SELECT = `
  id, service_id, seq, block, title, detail, kind, mode, standard_minutes,
  is_killer, requires_photo, requires_measure, measure_unit,
  origin, approved_by, approved_at, active, version,
  services(name)
`;

/** Todos os roteiros padrão, agrupáveis por serviço. */
export function useStepTemplates() {
  return useQuery({
    queryKey: ['step-templates'],
    queryFn: async (): Promise<StepTemplate[]> => {
      const { data, error } = await supabase
        .from('service_step_templates')
        .select(T_SELECT)
        .order('service_id')
        .order('seq');
      if (error) throw error;
      return (data || []) as unknown as StepTemplate[];
    },
  });
}

/** Só o que aguarda decisão: rascunho da IA ainda sem assinatura. */
export function pendingApproval(t: StepTemplate): boolean {
  return t.origin === 'ai' && !t.approved_at;
}

/**
 * Aprova um passo padrão: assina e ativa.
 *
 * Ativar junto é o que faz o passo passar a valer — sem isso o template fica
 * aprovado e inerte, que é a pior combinação (parece resolvido e não é).
 */
export function useApproveTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ template, edited }: { template: StepTemplate; edited?: boolean }) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      const { error } = await supabase
        .from('service_step_templates')
        .update({ approved_by: reviewer, approved_at: new Date().toISOString(), active: true })
        .eq('id', template.id);
      if (error) throw error;

      // O diff alimenta a Fase 7: sem registro, a IA repete o mesmo erro.
      await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'step_template',
        target_table: 'service_step_templates',
        target_id: template.id,
        service_id: template.service_id,
        suggested: {
          title: template.title, detail: template.detail,
          kind: template.kind, standard_minutes: template.standard_minutes,
        },
        approved: { title: template.title, standard_minutes: template.standard_minutes },
        verdict: edited ? 'edited' : 'accepted',
        reviewer_id: reviewer,
      });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['step-templates'] }),
  });
}

export function useRejectTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (template: StepTemplate) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'step_template',
        target_table: 'service_step_templates',
        target_id: template.id,
        service_id: template.service_id,
        suggested: {
          title: template.title, detail: template.detail,
          kind: template.kind, standard_minutes: template.standard_minutes,
        },
        approved: null,
        verdict: 'rejected',
        reviewer_id: reviewer,
      });

      const { error } = await supabase.from('service_step_templates').delete().eq('id', template.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['step-templates'] }),
  });
}

/** Editar antes de aprovar é o caso mais informativo — vira verdict 'edited'. */
export function useUpdateTemplate() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id, patch,
    }: { id: string; patch: Partial<Pick<StepTemplate, 'title' | 'detail' | 'standard_minutes' | 'kind' | 'is_killer' | 'requires_photo' | 'block'>> }) => {
      const { error } = await supabase.from('service_step_templates').update(patch).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['step-templates'] }),
  });
}

export interface TemplateGroup {
  serviceId: string;
  serviceName: string;
  steps: StepTemplate[];
  pendentes: number;
  minutosTotais: number;
}

export function groupTemplatesByService(templates: StepTemplate[]): TemplateGroup[] {
  const mapa = new Map<string, TemplateGroup>();
  for (const t of templates) {
    let g = mapa.get(t.service_id);
    if (!g) {
      g = {
        serviceId: t.service_id,
        serviceName: t.services?.name || 'Serviço sem nome',
        steps: [], pendentes: 0, minutosTotais: 0,
      };
      mapa.set(t.service_id, g);
    }
    g.steps.push(t);
    if (pendingApproval(t)) g.pendentes++;
    g.minutosTotais += t.standard_minutes || 0;
  }
  return [...mapa.values()].sort((a, b) => b.pendentes - a.pendentes || a.serviceName.localeCompare(b.serviceName));
}

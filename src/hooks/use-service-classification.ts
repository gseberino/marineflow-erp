import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { SYSTEM_LABEL, VERB_LABEL } from '@/hooks/use-step-blocks';

/**
 * Revisão da classificação do catálogo (services.service_verb/service_system).
 * Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter (P27-P29)
 *
 * A classificação decide qual roteiro o serviço recebe: o sistema traz a
 * abertura e o fechamento de segurança, o verbo traz o corpo. Palavra-chave
 * fechou 154 dos 262; a IA fechou os outros 108 e marcou a própria confiança.
 * Aqui aparecem só os que ela mesma não garantiu — o combinado com o dono foi
 * "a IA classifica e eu reviso os incertos", não "reviso os 262".
 */

export const SISTEMAS = [
  'eletrico_dc', 'eletrico_ac', 'gas', 'hidraulico', 'eletronico',
  'refrigeracao', 'mecanico', 'estrutural', 'nenhum',
] as const;

export const VERBOS = [
  'instalacao', 'substituicao', 'reparo', 'diagnostico', 'manutencao',
  'remocao', 'configuracao', 'adequacao', 'logistica',
] as const;

export { SYSTEM_LABEL, VERB_LABEL };

export interface ClassifiedService {
  id: string;
  name: string;
  service_verb: string | null;
  service_system: string | null;
  classified_by: string | null;
  classification_confidence: number | null;
}

/** Abaixo de 0.9 a IA está dizendo "olha isso" — é essa a fila de revisão. */
const LIMITE_CONFIANCA = 0.9;

export function useServicesToReview() {
  return useQuery({
    queryKey: ['services-to-review'],
    queryFn: async (): Promise<ClassifiedService[]> => {
      const { data, error } = await supabase
        .from('services')
        .select('id, name, service_verb, service_system, classified_by, classification_confidence')
        .eq('active', true)
        .eq('classified_by', 'ai')
        .lt('classification_confidence', LIMITE_CONFIANCA)
        .order('classification_confidence')
        .order('name');
      if (error) throw error;
      return (data || []) as unknown as ClassifiedService[];
    },
  });
}

/**
 * Confirma ou corrige a classificação de um serviço.
 *
 * Passa a `classified_by='human'` com confiança 1: a partir daí nenhuma
 * varredura automática mexe nisso de novo, e o diff alimenta o aprendizado.
 */
/**
 * Tira o serviço do catálogo.
 *
 * Inativar, não apagar: as OS antigas que o referenciam continuam intactas e o
 * nome fica preservado no snapshot da linha. Ele só some de quem monta
 * orçamento — e da fila de revisão, porque classificar o que não se vende mais
 * é trabalho jogado fora.
 */
export function useDeactivateService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (service: ClassifiedService) => {
      const { error } = await supabase
        .from('services')
        .update({ active: false })
        .eq('id', service.id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['services-to-review'] });
      qc.invalidateQueries({ queryKey: ['services'] });
      qc.invalidateQueries({ queryKey: ['step-blocks-impact'] });
    },
  });
}

export function useConfirmClassification() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      service, system, verb,
    }: { service: ClassifiedService; system: string | null; verb: string | null }) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      const mudou = system !== service.service_system || verb !== service.service_verb;

      const { error } = await supabase
        .from('services')
        .update({
          service_system: system,
          service_verb: verb,
          classified_by: 'human',
          classified_at: new Date().toISOString(),
          classification_confidence: 1,
        })
        .eq('id', service.id);
      if (error) throw error;

      // Corrigir a classificação da IA é o sinal mais direto que existe sobre
      // onde ela erra — vale mais registrado que perdido.
      await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'step',
        target_table: 'services',
        target_id: service.id,
        service_id: service.id,
        suggested: {
          service_system: service.service_system,
          service_verb: service.service_verb,
          confianca: service.classification_confidence,
        },
        approved: { service_system: system, service_verb: verb },
        verdict: mudou ? 'edited' : 'accepted',
        reviewer_id: reviewer,
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['services-to-review'] });
      qc.invalidateQueries({ queryKey: ['step-blocks-impact'] });
    },
  });
}

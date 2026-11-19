import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type ModeloDeChecklist = { name: string; items: string[] };

/**
 * Lê os modelos de checklist (app_settings.task_checklist_templates).
 *
 * Leitura que falha (ou valor gravado que não é uma lista) LANÇA: "nenhum modelo" por erro fazia
 * o editor de Configurações gravar a lista nova por cima, apagando os outros modelos
 * (19/11/2026). Quem usa decide: o editor bloqueia, a tarefa só avisa.
 */
export async function lerModelosDeChecklist(): Promise<ModeloDeChecklist[]> {
  const { data, error } = await supabase.from('app_settings')
    .select('value').eq('key', 'task_checklist_templates').maybeSingle();
  if (error) throw new Error('Não consegui ler os modelos de checklist.');
  const bruto = (data as { value?: string | null } | null)?.value;
  if (!bruto) return [];
  let parsed: unknown;
  try { parsed = JSON.parse(bruto); } catch { throw new Error('Os modelos de checklist gravados estão ilegíveis.'); }
  if (!Array.isArray(parsed)) throw new Error('Os modelos de checklist gravados estão ilegíveis.');
  return parsed as ModeloDeChecklist[];
}

/** Modelos de checklist — padrão ServiceM8/FieldPulse. */
export function useChecklistTemplates() {
  return useQuery({ queryKey: ['task-checklist-templates'], queryFn: lerModelosDeChecklist });
}

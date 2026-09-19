import { supabase } from '@/integrations/supabase/client';

/**
 * D11 (decisão do dono, 17/09/2026): concluir uma OS exige levantamento RESPONDIDO nos
 * serviços marcados "exige levantamento" (services.requires_survey). Devolve os nomes dos
 * serviços que ainda não têm um levantamento fechado nesta OS — vazio = pode concluir.
 *
 * A mesma regra vive na tool update_service_order_status do agente; se mudar aqui, mude lá.
 */
export async function levantamentosPendentesParaConcluir(serviceOrderId: string): Promise<string[]> {
  const { data: linhas, error } = await supabase
    .from('service_order_services')
    .select('service_id, name_snapshot, services!inner(requires_survey)')
    .eq('service_order_id', serviceOrderId);
  if (error) throw error;
  const exigem = ((linhas ?? []) as Array<{ service_id: string; name_snapshot: string; services: { requires_survey: boolean } | null }>)
    .filter((l) => l.services?.requires_survey);
  if (exigem.length === 0) return [];

  const { data: fechados, error: e2 } = await supabase
    .from('service_surveys')
    .select('service_id')
    .eq('service_order_id', serviceOrderId)
    .eq('status', 'closed');
  if (e2) throw e2;
  const ok = new Set(((fechados ?? []) as Array<{ service_id: string | null }>).map((s) => String(s.service_id)));
  return exigem.filter((l) => !ok.has(String(l.service_id))).map((l) => l.name_snapshot);
}

import { supabase } from '@/integrations/supabase/client';

/**
 * D11 (decisão do dono, 17/09/2026): concluir uma OS exige levantamento RESPONDIDO nos
 * serviços marcados "exige levantamento" (services.requires_survey). Devolve os nomes dos
 * serviços que ainda não têm um levantamento fechado nesta OS — vazio = pode concluir.
 *
 * Desde 23/10/2026 (D7 da Agenda de Produção) o assistente não conclui OS: a tool
 * update_service_order_status recusa e manda concluir pela tela, então esta é a única cópia da
 * regra. A porta única de status (Fase 3), quando trouxer a conclusão pelo assistente, traz esta
 * regra junto.
 *
 * Fase 3 (P3): o assistente e as palavras do dono voltaram a concluir (os_registrar_andamento,
 * *concluiu*, *entreguei*), e o banco tem o espelho desta regra: _os_levantamentos_pendentes
 * (migration 20261026100200), com a mesma frase.
 *
 * Fase 3 (P7b, NOVO-agenda-24): a FONTE da regra passa a ser a porta (os_transicionar_status,
 * migration 20261026100700): toda conclusão — a lista rápida, os kanbans, este formulário, a
 * assinatura, a equipe, as palavras e o assistente — recusa com a mesma frase ("Para concluir,
 * responda o levantamento de: …"), e a tela mostra a recusa dela. Esta cópia fica só no botão do
 * formulário, para o front publicado antes daquela migration (o plano B da porta,
 * statusPelaTelaSemAPorta): quem tirar o plano B tira esta conferência junto.
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

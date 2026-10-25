/**
 * O que a porta aceita pela tela (Agenda de Produção, Fase 3, P7a — 24/10/2026).
 *
 * A lista rápida de status (StatusQuickChange) e os kanbans ofereciam opções que a porta recusa para aquele cargo e
 * estado — "Corrigir para Orçamento", "aguardando o cliente → aberta", concluir para quem não pode, faturar e reabrir
 * para quem não é administrador: o dono clicava e lia a recusa. Agora a tela pergunta antes ao banco (os_status_da_tela),
 * que responde pela MESMA regra da porta (_os_porta_regra): nenhuma lista de "quem pode" mora aqui. O que depende de dado
 * (o material, o dia no plano, as cobranças) continua aparecendo e a porta decide na hora, com a frase dela.
 *
 * PLANO B: a função ainda não está no banco (PGRST202/42883) ou a leitura falhou = null, e a tela mostra todas as opções,
 * como antes — a porta continua recusando o que não pode.
 */
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { ehPortaAusente } from '../../supabase/functions/_shared/porta-ausente';

/** {id da OS: status que a porta aceita pela tela}. */
export type StatusQueAPortaAceita = Record<string, string[]>;

export async function lerStatusQueAPortaAceita(ids: string[]): Promise<StatusQueAPortaAceita | null> {
  if (ids.length === 0) return {};
  const { data, error } = await supabase.rpc('os_status_da_tela', { p_os: ids });
  if (error) {
    if (ehPortaAusente(error)) return null;
    throw new Error((error as { message?: string }).message || 'O banco não disse o que a porta aceita.');
  }
  return (data ?? {}) as StatusQueAPortaAceita;
}

/**
 * Os status que a porta aceita pela tela para estas OS. `habilitado` = só quando a lista vai aparecer (o menu aberto, o
 * kanban na tela): uma lista com cem OS não pergunta cem vezes à toa. `versao` = o status de agora (o que a porta aceita
 * muda com ele: depois de mudar, a resposta velha não vale).
 */
export function useStatusQueAPortaAceita(ids: string[], habilitado = true, versao = '') {
  const chave = [...ids].sort();
  return useQuery({
    queryKey: ['status-que-a-porta-aceita', chave, versao],
    queryFn: () => lerStatusQueAPortaAceita(chave),
    enabled: habilitado && chave.length > 0,
    staleTime: 30_000,
    retry: false,
  });
}

/**
 * As opções da tela que a porta aceita. Sem resposta do banco (carregando, a função ausente, erro) = todas, como antes.
 * Cancelar não passa pela porta (é o botão Cancelar OS, com o estorno): fica sempre.
 */
export function opcoesQueAPortaAceita(
  opcoes: readonly string[],
  aceitos: StatusQueAPortaAceita | null | undefined,
  osId: string,
): string[] {
  if (!aceitos) return [...opcoes];
  const daOs = aceitos[osId];
  if (!Array.isArray(daOs)) return [...opcoes];
  return opcoes.filter((s) => s === 'cancelled' || daOs.includes(s));
}

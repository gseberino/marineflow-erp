/* Dados extras da ficha do cliente na OS: o saldo em aberto e os clientes das últimas OS. */
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useOptionalAuth } from '@/hooks/use-auth';
import { OS_TABELA, OS_VIEW_TECNICO, leDaViewDoTecnico } from '@/lib/service-orders-source';
import { resumirEmAberto, type ResumoEmAberto } from '@/lib/ficha-cliente';

/**
 * O que o cliente deve: soma do saldo dos títulos não pagos e não cancelados, e quantos já
 * venceram. Só admin e financeiro: a RLS de receivables só deixa esses cargos lerem — para os
 * outros a consulta nem sai (senão a ficha mostraria "nada em aberto", que é falso).
 * Chave sob ['receivables']: salvar a OS ou registrar pagamento já invalida esse prefixo.
 */
export function useSaldoEmAberto(clientId: string | null | undefined) {
  const cargo = useOptionalAuth()?.user?.role;
  const podeVer = cargo === 'admin' || cargo === 'financial';
  return useQuery({
    queryKey: ['receivables', 'client', clientId, 'em-aberto'],
    enabled: podeVer && !!clientId,
    queryFn: async (): Promise<ResumoEmAberto> => {
      const { data, error } = await supabase
        .from('receivables')
        .select('amount, paid_amount, balance_amount, due_date, status')
        .eq('client_id', clientId!)
        .not('status', 'in', '(paid,cancelled)');
      // Erro não vira "R$ 0": lança, e a ficha simplesmente não mostra a linha.
      if (error) throw error;
      return resumirEmAberto(data ?? []);
    },
    staleTime: 60 * 1000,
  });
}

/**
 * Os clientes das últimas OS/orçamentos, do mais recente para o mais antigo, sem repetir —
 * aparecem no topo da busca antes de digitar. O técnico lê pela view dele, como no resto da OS.
 * Chave sob ['service-orders']: criar ou salvar uma OS já invalida esse prefixo.
 */
export function useClientesRecentes(limite = 6) {
  const cargo = useOptionalAuth()?.user?.role;
  const pelaView = leDaViewDoTecnico(cargo);
  return useQuery({
    queryKey: ['service-orders', 'clientes-recentes', { fonte: pelaView ? OS_VIEW_TECNICO : OS_TABELA }],
    queryFn: async (): Promise<string[]> => {
      // Dois ramos, como em useServiceOrders: tabela e view têm tipos gerados diferentes.
      const { data, error } = pelaView
        ? await supabase.from(OS_VIEW_TECNICO).select('client_id, created_at')
          .order('created_at', { ascending: false }).limit(100)
        : await supabase.from(OS_TABELA).select('client_id, created_at')
          .order('created_at', { ascending: false }).limit(100);
      if (error) throw error;
      const ids: string[] = [];
      for (const r of (data ?? []) as Array<{ client_id: string | null }>) {
        if (r.client_id && !ids.includes(r.client_id)) ids.push(r.client_id);
        if (ids.length >= limite) break;
      }
      return ids;
    },
    staleTime: 5 * 60 * 1000,
  });
}

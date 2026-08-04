import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/**
 * Vínculo entre a mercadoria que chegou e a OS que a motivou.
 *
 * Sem isto, a peça entra no estoque e a OS continua parada esperando: nada liga uma
 * coisa à outra, e se duas OS aguardam o mesmo produto, ele fica com quem consumir
 * primeiro. Medido em 04/08/2026: das 4 notas em produção, nenhuma estava vinculada
 * a pedido, e 2 OS aguardavam peça.
 *
 * O vínculo é por ITEM (não pela nota) porque uma nota costuma trazer peça de várias
 * OS — compra-se do fornecedor uma vez só, para economizar frete. Amarrar a nota
 * inteira a uma OS seria falso.
 */

/** Status em que a OS ainda pode receber material. */
const STATUS_ATIVOS = ['approved', 'scheduled', 'in_progress', 'awaiting_parts'];

export interface ServiceOrderOption {
  id: string;
  number: string;
  status: string;
  clientName: string | null;
}

/** OS que podem receber material — as que já foram entregues não entram. */
export function useServiceOrdersForLinking() {
  return useQuery({
    queryKey: ['service-orders-for-linking'],
    queryFn: async (): Promise<ServiceOrderOption[]> => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, clients(name)')
        .in('status', STATUS_ATIVOS)
        .order('created_at', { ascending: false })
        .limit(100);
      if (error) throw error;
      return (data ?? []).map((r: any) => ({
        id: r.id,
        number: r.service_order_number,
        status: r.status,
        clientName: r.clients?.name ?? null,
      }));
    },
    staleTime: 60_000,
  });
}

export interface NoteSuggestion {
  service_order_id: string;
  os: string;
  quantidade_na_os: number;
  motivo: string;
}

/**
 * O que o sistema já sabe: qual OS está esperando cada peça desta nota.
 * Devolve mapa item_id → sugestão. Só sugere; quem decide é a tela.
 */
export function useNfeServiceOrderSuggestions(noteId: string | undefined) {
  return useQuery({
    queryKey: ['nfe-so-suggestions', noteId],
    enabled: !!noteId,
    queryFn: async (): Promise<Record<string, NoteSuggestion>> => {
      const { data, error } = await (supabase.rpc as any)('suggest_nfe_service_orders', {
        p_note_id: noteId,
      });
      if (error) throw error;
      return (data ?? {}) as Record<string, NoteSuggestion>;
    },
    staleTime: 30_000,
  });
}

/**
 * Grava o vínculo DEPOIS da confirmação da importação.
 *
 * Por que depois e não dentro de `confirm_nfe_import`: aquela função tem 7.387
 * caracteres e mexe em estoque e contas a pagar — alterá-la para carregar mais um
 * parâmetro seria risco desproporcional. As linhas de `fiscal_note_items` só passam
 * a existir quando a nota é confirmada (o gatilho as cria), então este é também o
 * primeiro momento em que há onde gravar.
 *
 * A chave é o `item_index`, que é o número do item na NF-e — estável e o mesmo que
 * a tela usa para casar preview com item.
 */
export function useLinkNoteItemsToServiceOrders() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ noteId, byIndex }: { noteId: string; byIndex: Record<number, string> }) => {
      const entradas = Object.entries(byIndex).filter(([, soId]) => soId && soId !== '__none');
      if (!entradas.length) return { vinculados: 0 };

      // Um update por OS (não por item): quem compra 10 itens para a mesma OS não
      // deve gerar 10 requisições.
      const porOS = new Map<string, number[]>();
      for (const [idx, soId] of entradas) {
        const lista = porOS.get(soId) ?? [];
        lista.push(Number(idx));
        porOS.set(soId, lista);
      }

      let vinculados = 0;
      for (const [soId, indices] of porOS) {
        const { data, error } = await supabase
          .from('fiscal_note_items')
          .update({ service_order_id: soId } as any)
          .eq('fiscal_note_id', noteId)
          .in('item_index', indices)
          .select('id');
        if (error) throw error;
        vinculados += (data ?? []).length;
      }
      return { vinculados };
    },
    onSuccess: (r, v) => {
      if (r.vinculados > 0) {
        toast.success(`${r.vinculados} ${r.vinculados === 1 ? 'item vinculado' : 'itens vinculados'} à ordem de serviço`);
      }
      qc.invalidateQueries({ queryKey: ['nfe-so-suggestions', v.noteId] });
      qc.invalidateQueries({ queryKey: ['purchase-needs'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
    // Falhar aqui NÃO invalida a importação, que já foi confirmada: o estoque entrou
    // e a conta a pagar existe. Por isso é aviso, não erro fatal.
    onError: (e: any) =>
      toast.warning(`Mercadoria importada, mas o vínculo com a OS não foi salvo: ${e.message}`),
  });
}

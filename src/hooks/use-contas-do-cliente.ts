// As contas a receber de um cliente, com o número e a situação da OS de cada uma (embed pela FK). É a leitura da ficha
// do cliente (ClientDetailV2) e da cobrança do cliente pela tela (CobrarClienteDialog), com a MESMA chave de cache: o
// extrato e a cobrança mostram as mesmas contas, e o envio invalida as duas (prefixo ['receivables']).
//
// Chave própria (com o número e a situação da OS): a ficha v1 usa ['receivables', 'client', id] com select('*'), e o
// cache de uma serviria a outra sem os campos da OS.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { ClienteParaCobrar } from '@/components/client/CobrarJuntasDialog';

export type ContaDoClienteComOs = {
  id: string; description: string; due_date: string; status?: string | null; amount: number;
  paid_amount?: number | null; balance_amount?: number | null; service_order_id?: string | null;
  /** Número da OS da conta (embed pela FK): a conta pode ser de OS de outro cliente (pagador). */
  numero_os?: string | null;
  /** Situação da OS da conta: só OS que já começou entra no "Cobrar juntas". */
  os?: { status?: string | null; merged_into_id?: string | null } | null;
  /** A fatura FAT-N da conta (Fechar juntas F1), se estiver numa. */
  invoice_id?: string | null;
};

type OsDaConta = { service_order_number?: string | null; status?: string | null; merged_into_id?: string | null } | null;

export function useContasDoCliente(id: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['receivables', 'client', id, 'com-os'],
    queryFn: async (): Promise<ContaDoClienteComOs[]> => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('receivables').select('*, service_orders!receivables_service_order_id_fkey(service_order_number, status, merged_into_id)').eq('client_id', id)
        .order('due_date', { ascending: false });
      if (error) throw error;
      return ((data ?? []) as unknown as Array<ContaDoClienteComOs & { service_orders?: OsDaConta }>)
        .map(({ service_orders, ...r }) => ({ ...r, numero_os: service_orders?.service_order_number ?? null, os: service_orders ?? null }));
    },
    enabled: enabled && !!id,
  });
}

/**
 * O cadastro para a cobrança. A coluna generico é pedida pelo nome: sem ela a leitura falha e nada sai (falha fechada,
 * como conferirEEnviar). null = o cliente não existe mais.
 */
export function useCadastroParaCobrar(clienteId: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['clients', 'para-cobrar', clienteId],
    enabled: enabled && !!clienteId,
    queryFn: async (): Promise<ClienteParaCobrar | null> => {
      const { data, error } = await supabase.from('clients')
        .select('id, name, generico, opt_out_whatsapp, whatsapp, phone').eq('id', clienteId!).maybeSingle();
      if (error) throw new Error(`Não consegui ler o cadastro do cliente: ${error.message}`);
      return (data as ClienteParaCobrar | null) ?? null;
    },
    staleTime: 30 * 1000,
  });
}

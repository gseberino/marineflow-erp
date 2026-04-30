import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type ExternalQuoteStatus = 
  | 'draft' 
  | 'pending_approval' 
  | 'pending_product' 
  | 'approved' 
  | 'sent' 
  | 'converted' 
  | 'cancelled';

export type ClientType = 'person' | 'vessel' | 'motorhome';

export interface ExternalQuote {
  id: string;
  created_at: string;
  updated_at: string;
  seller_user_id: string;
  status: ExternalQuoteStatus;
  client_name: string;
  client_phone: string;
  client_type: ClientType;
  vessel_name?: string;
  converted_service_order_id?: string;
  commission_rate: number;
  commission_amount: number;
  commission_status: 'pending' | 'approved' | 'paid';
  commission_paid_at?: string;
  approved_by?: string;
  approved_at?: string;
  rejection_reason?: string;
  internal_notes?: string;
  subtotal: number;
  discount_amount: number;
  grand_total: number;
  seller?: {
    id: string;
    full_name: string;
  };
  items?: ExternalQuoteItem[];
}

export interface ExternalQuoteItem {
  id: string;
  external_quote_id: string;
  product_id?: string;
  product_name_manual?: string;
  product_description?: string;
  quantity: number;
  unit_price: number;
  line_total: number;
  status: 'ok' | 'pending_product_registration';
}

export function useExternalQuotes(filters?: { status?: string; seller_id?: string }) {
  return useQuery({
    queryKey: ['external-quotes', filters],
    queryFn: async () => {
      let query = supabase
        .from('external_quotes')
        .select(`
          *,
          seller:app_users!seller_user_id(id, full_name),
          items:external_quote_items(*)
        `)
        .order('created_at', { ascending: false });

      if (filters?.status) query = query.eq('status', filters.status);
      if (filters?.seller_id) query = query.eq('seller_user_id', filters.seller_id);

      const { data, error } = await query;
      if (error) throw error;
      return data as ExternalQuote[];
    },
  });
}

export function useExternalQuote(id: string) {
  return useQuery({
    queryKey: ['external-quote', id],
    queryFn: async () => {
      if (!id) return null;
      const { data, error } = await supabase
        .from('external_quotes')
        .select(`
          *,
          seller:app_users!seller_user_id(id, full_name),
          items:external_quote_items(*)
        `)
        .eq('id', id)
        .single();

      if (error) throw error;
      return data as ExternalQuote;
    },
    enabled: !!id,
  });
}

export function useCreateExternalQuote() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (quote: Partial<ExternalQuote> & { items: Partial<ExternalQuoteItem>[] }) => {
      const { items, ...quoteData } = quote;
      
      // 1. Inserir orçamento
      const { data: newQuote, error: quoteError } = await supabase
        .from('external_quotes')
        .insert([quoteData])
        .select()
        .single();

      if (quoteError) throw quoteError;

      // 2. Inserir itens
      if (items && items.length > 0) {
        const itemsToInsert = items.map(item => ({
          ...item,
          external_quote_id: newQuote.id,
          line_total: (item.quantity || 0) * (item.unit_price || 0)
        }));

        const { error: itemsError } = await supabase
          .from('external_quote_items')
          .insert(itemsToInsert);

        if (itemsError) throw itemsError;
      }

      return newQuote;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['external-quotes'] });
      toast.success('Orçamento criado com sucesso!');
    },
    onError: (error: any) => {
      toast.error('Erro ao criar orçamento: ' + error.message);
    }
  });
}

export function useUpdateExternalQuoteStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, status, rejection_reason }: { id: string; status: ExternalQuoteStatus; rejection_reason?: string }) => {
      const { data, error } = await supabase
        .from('external_quotes')
        .update({ 
          status, 
          rejection_reason,
          approved_at: status === 'approved' ? new Date().toISOString() : undefined,
          approved_by: status === 'approved' ? (await supabase.auth.getUser()).data.user?.id : undefined
        })
        .eq('id', id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['external-quotes'] });
      toast.success('Status do orçamento atualizado!');
    },
  });
}

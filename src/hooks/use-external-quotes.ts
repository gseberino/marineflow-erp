import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import type { Database } from '@/integrations/supabase/types';

export type ExternalQuote = Database['public']['Tables']['external_quotes']['Row'] & {
  seller?: {
    id: string;
    full_name: string;
  };
  parts?: Database['public']['Tables']['external_quote_parts']['Row'][];
  services?: Database['public']['Tables']['external_quote_services']['Row'][];
  client?: Database['public']['Tables']['clients']['Row'];
  vessel?: Database['public']['Tables']['vessels']['Row'];
};

export function useExternalQuotes(filters?: { status?: string; created_by?: string }) {
  return useQuery({
    queryKey: ['external-quotes', filters],
    queryFn: async () => {
      let query = supabase
        .from('external_quotes')
        .select(`
          *,
          seller:app_users!created_by(id, full_name),
          client:clients(id, full_name_or_company_name, phone),
          vessel:vessels(id, boat_name)
        `)
        .order('created_at', { ascending: false });

      if (filters?.status) query = query.eq('status', filters.status);
      if (filters?.created_by) query = query.eq('created_by', filters.created_by);

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
          seller:app_users!created_by(id, full_name),
          client:clients(*),
          vessel:vessels(*),
          parts:external_quote_parts(*),
          services:external_quote_services(*)
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
    mutationFn: async (quote: any) => {
      const { parts, services, ...quoteData } = quote;
      
      const { data: newQuote, error: quoteError } = await supabase
        .from('external_quotes')
        .insert([quoteData])
        .select()
        .single();

      if (quoteError) throw quoteError;

      if (parts && parts.length > 0) {
        const { error: partsError } = await supabase
          .from('external_quote_parts')
          .insert(parts.map((p: any) => ({ ...p, external_quote_id: newQuote.id })));
        if (partsError) throw partsError;
      }

      if (services && services.length > 0) {
        const { error: servicesError } = await supabase
          .from('external_quote_services')
          .insert(services.map((s: any) => ({ ...s, external_quote_id: newQuote.id })));
        if (servicesError) throw servicesError;
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
    mutationFn: async ({ id, status, rejection_reason }: { id: string; status: string; rejection_reason?: string }) => {
      const { data, error } = await supabase
        .from('external_quotes')
        .update({ 
          status, 
          rejection_reason,
          reviewed_at: (status === 'approved' || status === 'rejected') ? new Date().toISOString() : undefined,
          reviewed_by: (status === 'approved' || status === 'rejected') ? (await supabase.auth.getUser()).data.user?.id : undefined
        } as any)
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

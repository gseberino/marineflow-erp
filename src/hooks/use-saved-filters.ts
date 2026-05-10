import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type SavedFilterType =
  | 'payable'
  | 'receivable'
  | 'service_orders'
  | 'products'
  | 'vessels'
  | 'agenda'
  | 'clients'
  | 'suppliers'
  | 'marinas'
  | 'services'
  | 'inventory'
  | 'purchase_orders'
  | 'collections'
  | 'crm'
  | 'external_quotes'
  | 'whatsapp_leads'
  | 'whatsapp_scheduled'
  | 'whatsapp_logs'
  | string;

export function useSavedFilters(filterType: SavedFilterType) {
  return useQuery({
    queryKey: ['saved-filters', filterType],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('saved_filters')
        .select('*')
        .eq('filter_type', filterType)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
  });
}

export function useCreateSavedFilter() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (f: { name: string; filter_type: SavedFilterType; filter_config: any }) => {
      const { data, error } = await supabase.from('saved_filters').insert(f).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: ['saved-filters', vars.filter_type] }),
  });
}

export function useDeleteSavedFilter() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('saved_filters').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['saved-filters'] }),
  });
}

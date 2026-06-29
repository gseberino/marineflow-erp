import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type SavedFilterType =
  | 'payable'
  | 'receivable'
  | 'service_orders'
  | 'quotes'
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

export interface SavedFilter {
  id: string;
  name: string;
  filter_type: SavedFilterType;
  filter_config: Record<string, any>;
  is_default: boolean;
  created_at: string;
  user_id?: string | null;
}

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
      return data as SavedFilter[];
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

/** Set or unset a preset as the default for its filter_type.
 *  Enforces at most one default per filter_type at the app level:
 *  first clears all defaults for the type, then sets the chosen one. */
export function useSetDefaultFilter() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id,
      filterType,
      filterConfig,
      isDefault,
    }: {
      id: string;
      filterType: SavedFilterType;
      filterConfig: Record<string, any>;
      isDefault: boolean;
    }) => {
      // Clear all existing defaults for this filter_type
      const { error: e1 } = await supabase
        .from('saved_filters')
        .update({ is_default: false })
        .eq('filter_type', filterType);
      if (e1) throw e1;

      if (isDefault) {
        const { error: e2 } = await supabase
          .from('saved_filters')
          .update({ is_default: true })
          .eq('id', id);
        if (e2) throw e2;
        localStorage.setItem(`mf-default-${filterType}`, JSON.stringify(filterConfig));
      } else {
        localStorage.removeItem(`mf-default-${filterType}`);
      }
    },
    onSuccess: (_d, vars) =>
      qc.invalidateQueries({ queryKey: ['saved-filters', vars.filterType] }),
  });
}

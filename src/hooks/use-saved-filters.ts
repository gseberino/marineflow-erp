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

// ─── localStorage helpers ────────────────────────────────────────────────────

const cacheKey = (ft: string) => `mf:default:${ft}`;

export function getDefaultFilterCache(filterType: SavedFilterType): any | null {
  try {
    const raw = localStorage.getItem(cacheKey(filterType));
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function setDefaultFilterCache(filterType: SavedFilterType, config: any) {
  try {
    localStorage.setItem(cacheKey(filterType), JSON.stringify(config));
  } catch {}
}

export function clearDefaultFilterCache(filterType: SavedFilterType) {
  try {
    localStorage.removeItem(cacheKey(filterType));
  } catch {}
}

// ─── Queries & Mutations ─────────────────────────────────────────────────────

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
    mutationFn: async ({ id, filterType, isDefault }: { id: string; filterType: SavedFilterType; isDefault: boolean }) => {
      const { error } = await supabase.from('saved_filters').delete().eq('id', id);
      if (error) throw error;
      if (isDefault) clearDefaultFilterCache(filterType);
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: ['saved-filters', vars.filterType] }),
  });
}

export function useSetDefaultFilter() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id,
      filterType,
      config,
      makeDefault,
    }: {
      id: string;
      filterType: SavedFilterType;
      config: any;
      makeDefault: boolean;
    }) => {
      // Clear any existing default for this type first
      await supabase
        .from('saved_filters')
        .update({ is_default: false })
        .eq('filter_type', filterType)
        .eq('is_default', true);

      if (makeDefault) {
        const { error } = await supabase
          .from('saved_filters')
          .update({ is_default: true })
          .eq('id', id);
        if (error) throw error;
        setDefaultFilterCache(filterType, config);
      } else {
        clearDefaultFilterCache(filterType);
      }
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: ['saved-filters', vars.filterType] }),
  });
}

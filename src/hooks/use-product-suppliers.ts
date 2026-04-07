import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { TablesInsert } from '@/integrations/supabase/types';

export function useProductSuppliers(productId: string | undefined) {
  return useQuery({
    queryKey: ['product-suppliers', productId],
    enabled: !!productId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('product_suppliers')
        .select('*, suppliers(supplier_name)')
        .eq('product_id', productId!)
        .order('is_preferred', { ascending: false })
        .order('created_at');
      if (error) throw error;
      return data;
    },
  });
}

export function useAddProductSupplier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (row: TablesInsert<'product_suppliers'>) => {
      const { data, error } = await supabase.from('product_suppliers').insert(row).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_, vars) => qc.invalidateQueries({ queryKey: ['product-suppliers', vars.product_id] }),
  });
}

export function useUpdateProductSupplier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, product_id, ...rest }: { id: string; product_id: string; [k: string]: any }) => {
      const { data, error } = await supabase.from('product_suppliers').update(rest).eq('id', id).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_, vars) => qc.invalidateQueries({ queryKey: ['product-suppliers', vars.product_id] }),
  });
}

export function useRemoveProductSupplier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, product_id }: { id: string; product_id: string }) => {
      const { error } = await supabase.from('product_suppliers').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: (_, vars) => qc.invalidateQueries({ queryKey: ['product-suppliers', vars.product_id] }),
  });
}

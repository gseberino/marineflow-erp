import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { Tables, TablesInsert } from '@/integrations/supabase/types';

export type Supplier = Tables<'suppliers'>;

export function useSuppliers() {
  return useQuery({
    queryKey: ['suppliers'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('suppliers')
        .select('*, name:supplier_name')
        .order('supplier_name');
      if (error) throw error;
      return data as Supplier[];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useCreateSupplier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (supplier: TablesInsert<'suppliers'>) => {
      const { data, error } = await supabase.from('suppliers').insert(supplier).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['suppliers'] }),
  });
}

export function useUpdateSupplier() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...rest }: TablesInsert<'suppliers'> & { id: string }) => {
      const { data, error } = await supabase.from('suppliers').update(rest).eq('id', id).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['suppliers'] }),
  });
}

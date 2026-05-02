import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { Tables, TablesInsert, TablesUpdate } from '@/integrations/supabase/types';

export type ProductCategory = Tables<'product_categories'>;

export function useProductCategories() {
  return useQuery({
    queryKey: ['product-categories'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('product_categories')
        .select('*')
        .eq('active', true)
        .order('name', { ascending: true });
      if (error) throw error;
      return data as ProductCategory[];
    },
    staleTime: 10 * 60 * 1000,
  });
}

export function useAllProductCategories() {
  return useQuery({
    queryKey: ['product-categories-all'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('product_categories')
        .select('*')
        .order('name', { ascending: true });
      if (error) throw error;
      return data as ProductCategory[];
    },
    staleTime: 10 * 60 * 1000,
  });
}

export function useCreateProductCategory() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: TablesInsert<'product_categories'>) => {
      const { data, error } = await supabase.from('product_categories').insert(input).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['product-categories'] });
      qc.invalidateQueries({ queryKey: ['product-categories-all'] });
    },
  });
}

export function useUpdateProductCategory() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: TablesUpdate<'product_categories'> & { id: string }) => {
      const { data, error } = await supabase.from('product_categories').update(input).eq('id', id).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['product-categories'] });
      qc.invalidateQueries({ queryKey: ['product-categories-all'] });
    },
  });
}

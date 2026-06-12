import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { Tables, TablesInsert, TablesUpdate } from '@/integrations/supabase/types';

export type Product = Tables<'products'>;

export function useProducts() {
  return useQuery({
    queryKey: ['products'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('products')
        .select('*, product_categories(name)')
        .order('name', { ascending: true });
      if (error) throw error;
      return data as Product[];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useCreateProduct() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: TablesInsert<'products'>) => {
      const { data, error } = await supabase.from('products').insert(input).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['products'] }),
  });
}

export function useUpdateProduct() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: TablesUpdate<'products'> & { id: string }) => {
      const { data, error } = await supabase.from('products').update(input).eq('id', id).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['products'] }),
  });
}

export function usePriceSuggestions() {
  return useQuery({
    queryKey: ['price-suggestions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('price_update_suggestions')
        .select('*, products(name, sku, cost_price)')
        .eq('status', 'pending')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useApplyPriceSuggestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ suggestionId, productId, newPrice }: { suggestionId: string, productId: string, newPrice: number }) => {
      // 1. Atualiza o preço do produto
      const { error: prodErr } = await supabase
        .from('products')
        .update({ sale_price: newPrice })
        .eq('id', productId);
      
      if (prodErr) throw prodErr;

      // 2. Marca a sugestão como aplicada
      const { error: sugErr } = await supabase
        .from('price_update_suggestions')
        .update({ status: 'applied' })
        .eq('id', suggestionId);
      
      if (sugErr) throw sugErr;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['price-suggestions'] });
      qc.invalidateQueries({ queryKey: ['products'] });
    },
  });
}

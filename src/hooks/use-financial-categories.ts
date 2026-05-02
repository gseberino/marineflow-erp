import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export function useFinancialCategories(type?: 'payable' | 'receivable') {
  return useQuery({
    queryKey: ['financial-categories', type],
    queryFn: async () => {
      let q = supabase.from('financial_categories').select('*').eq('active', true).order('name');
      if (type) q = q.eq('type', type);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },
    staleTime: 10 * 60 * 1000,
  });
}

export function useCreateFinancialCategory() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (cat: { name: string; type: 'payable' | 'receivable'; color?: string }) => {
      const { data, error } = await supabase.from('financial_categories').insert(cat).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['financial-categories'] }),
  });
}

export function useUpdateFinancialCategory() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...rest }: { id: string; name?: string; color?: string; active?: boolean }) => {
      const { data, error } = await supabase.from('financial_categories').update(rest).eq('id', id).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['financial-categories'] }),
  });
}

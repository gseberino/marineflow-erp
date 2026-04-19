import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { Tables, TablesInsert, TablesUpdate } from '@/integrations/supabase/types';

export type Marina = Tables<'marinas'>;

export function useMarinas() {
  return useQuery({
    queryKey: ['marinas'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('marinas')
        .select('*')
        .order('marina_name', { ascending: true });
      if (error) throw error;
      return data as Marina[];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useCreateMarina() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: TablesInsert<'marinas'>) => {
      const { data, error } = await supabase.from('marinas').insert(input).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['marinas'] }),
  });
}

export function useUpdateMarina() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: TablesUpdate<'marinas'> & { id: string }) => {
      const { data, error } = await supabase.from('marinas').update(input).eq('id', id).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['marinas'] }),
  });
}

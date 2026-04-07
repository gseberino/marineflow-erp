import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { Tables, TablesInsert, TablesUpdate } from '@/integrations/supabase/types';

export type Vessel = Tables<'vessels'>;

export function useVessels() {
  return useQuery({
    queryKey: ['vessels'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('vessels')
        .select('*, clients!vessels_client_id_fkey(full_name_or_company_name), marinas!vessels_marina_id_fkey(marina_name)')
        .order('boat_name', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}

export function useVessel(id: string | undefined) {
  return useQuery({
    queryKey: ['vessels', id],
    queryFn: async () => {
      if (!id) throw new Error('No id');
      const { data, error } = await supabase
        .from('vessels')
        .select('*, clients!vessels_client_id_fkey(full_name_or_company_name), marinas!vessels_marina_id_fkey(marina_name)')
        .eq('id', id)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    enabled: !!id,
  });
}

export function useVesselsForClient(clientId: string | undefined) {
  return useQuery({
    queryKey: ['vessels', 'client', clientId],
    queryFn: async () => {
      if (!clientId) return [];
      const { data, error } = await supabase
        .from('vessels')
        .select('*, marinas!vessels_marina_id_fkey(marina_name)')
        .eq('client_id', clientId)
        .order('boat_name');
      if (error) throw error;
      return data;
    },
    enabled: !!clientId,
  });
}

export function useCreateVessel() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: TablesInsert<'vessels'>) => {
      const { data, error } = await supabase.from('vessels').insert(input).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['vessels'] }),
  });
}

export function useUpdateVessel() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: TablesUpdate<'vessels'> & { id: string }) => {
      const { data, error } = await supabase.from('vessels').update(input).eq('id', id).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ['vessels'] });
      qc.invalidateQueries({ queryKey: ['vessels', vars.id] });
    },
  });
}

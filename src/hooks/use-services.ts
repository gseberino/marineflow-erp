import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export function useServices() {
  return useQuery({
    queryKey: ['services'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('services')
        .select('*, name:service_name, price:default_price')
        .order('service_name', { ascending: true });
      if (error) throw error;
      return data;
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useCreateService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: Record<string, any>) => {
      const { name, ...rest } = values;
      const payload = {
        ...rest,
        service_name: name || values.service_name,
      };
      const { data, error } = await supabase
        .from('services')
        .insert(payload as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['services'] });
    },
  });
}

export function useUpdateService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...values }: { id: string } & Record<string, any>) => {
      const { name, ...rest } = values;
      const payload = {
        ...rest,
        service_name: name || values.service_name,
      };
      const { data, error } = await supabase
        .from('services')
        .update(payload as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['services'] });
    },
  });
}

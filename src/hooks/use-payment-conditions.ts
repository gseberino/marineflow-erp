import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export function usePaymentConditionPresets() {
  return useQuery({
    queryKey: ['payment-condition-presets'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('payment_condition_presets')
        .select('*')
        .eq('active', true)
        .order('sort_order', { ascending: true });
      if (error) throw error;
      return data || [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useAllPaymentConditionPresets() {
  return useQuery({
    queryKey: ['payment-condition-presets', 'all'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('payment_condition_presets')
        .select('*')
        .order('sort_order', { ascending: true });
      if (error) throw error;
      return data || [];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useCreatePaymentConditionPreset() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (label: string) => {
      const { data, error } = await supabase
        .from('payment_condition_presets')
        .insert({ label })
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['payment-condition-presets'] });
    },
  });
}

export function useUpdatePaymentConditionPreset() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: {
      id: string; label?: string; active?: boolean; sort_order?: number;
    }) => {
      const { data, error } = await supabase
        .from('payment_condition_presets')
        .update(input)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['payment-condition-presets'] });
    },
  });
}

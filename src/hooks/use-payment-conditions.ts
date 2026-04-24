import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export interface PaymentInstallment {
  label: string;
  services_pct: number;
  parts_pct: number;
  expenses_pct: number;
  days_after_approval: number;
  /** @deprecated use services_pct/parts_pct/expenses_pct instead */
  percent?: number;
}

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
    mutationFn: async ({
      id,
      patch,
    }: {
      id: string;
      patch: Partial<{
        label: string;
        active: boolean;
        sort_order: number;
        installments: PaymentInstallment[];
        auto_generate_collections: boolean;
      }>;
    }) => {
      const { data, error } = await supabase
        .from('payment_condition_presets')
        .update(patch as never)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['payment-condition-presets'] });
      toast.success('Condição atualizada');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao atualizar'),
  });
}

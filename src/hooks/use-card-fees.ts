import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export function useCardFees() {
  return useQuery({
    queryKey: ['card-fees'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('card_installment_fees')
        .select('*')
        .order('installments', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}

export function useUpdateCardFee() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ installments, fee_percent }: { installments: number; fee_percent: number }) => {
      const { error } = await supabase
        .from('card_installment_fees')
        .update({ fee_percent } as any)
        .eq('installments', installments);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['card-fees'] });
    },
  });
}

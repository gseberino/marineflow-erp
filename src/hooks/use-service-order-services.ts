import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { recalcTotals } from '@/hooks/use-service-orders';

export function useUpdateServiceOrderService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      id: string;
      service_order_id: string;
      service_id?: string | null;
      name_snapshot?: string;
      description_snapshot?: string | null;
      billing_unit_snapshot?: string;
      quantity?: number;
      unit_price_snapshot?: number;
      notes?: string | null;
      technician_user_id?: string | null;
      discount_pct?: number;
      discount_amount?: number;
    }) => {
      const { id, service_order_id, ...rest } = values;
      const patch: Record<string, any> = { ...rest };
      if (typeof rest.quantity === 'number' && typeof rest.unit_price_snapshot === 'number') {
        // discount_amount (R$) é a fonte da verdade — subtração exata, sem
        // passar pelo percentual (que perde centavos, numeric(5,2)).
        const discountAmount = rest.discount_amount || 0;
        patch.line_total = Math.round((rest.quantity * rest.unit_price_snapshot - discountAmount) * 100) / 100;
      }

      // Snapshot dos campos alterados antes de gravar — necessário para
      // reverter caso o novo total fique abaixo do que o cliente já pagou.
      const { data: before } = await supabase
        .from('service_order_services')
        .select(Object.keys(patch).join(','))
        .eq('id', id)
        .single();

      const { error } = await supabase
        .from('service_order_services')
        .update(patch as any)
        .eq('id', id);
      if (error) throw error;

      try {
        await recalcTotals(service_order_id);
      } catch (e) {
        if (before) {
          await supabase.from('service_order_services').update(before as any).eq('id', id);
        }
        await recalcTotals(service_order_id).catch(() => {});
        throw e;
      }
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-services', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
    },
  });
}

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
    }) => {
      const { id, service_order_id, ...rest } = values;
      const patch: Record<string, any> = { ...rest };
      if (typeof rest.quantity === 'number' && typeof rest.unit_price_snapshot === 'number') {
        patch.line_total = Math.round(rest.quantity * rest.unit_price_snapshot * 100) / 100;
      }
      const { error } = await supabase
        .from('service_order_services')
        .update(patch as any)
        .eq('id', id);
      if (error) throw error;
      await recalcTotals(service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-services', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
    },
  });
}

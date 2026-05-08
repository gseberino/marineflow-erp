import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { recalcTotals } from '@/hooks/use-service-orders';
import { updateReceivableFromSO } from '@/lib/cascade-updates';

/**
 * Update an existing service_order_parts row. Adjusts stock & inventory_movements
 * to compensate for any quantity delta, then recalculates the OS totals.
 */
export function useUpdateServiceOrderPart() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      id: string;
      service_order_id: string;
      product_id: string;
      previous_quantity: number;
      quantity: number;
      unit_cost_snapshot: number;
      unit_sale_snapshot: number;
      notes?: string | null;
    }) => {
      const line_total_cost =
        Math.round(values.quantity * values.unit_cost_snapshot * 100) / 100;
      const line_total_sale =
        Math.round(values.quantity * values.unit_sale_snapshot * 100) / 100;

      const { error } = await supabase
        .from('service_order_parts')
        .update({
          product_id: values.product_id,
          quantity: values.quantity,
          unit_cost_snapshot: values.unit_cost_snapshot,
          unit_sale_snapshot: values.unit_sale_snapshot,
          notes: values.notes ?? null,
          line_total_cost,
          line_total_sale,
        } as any)
        .eq('id', values.id);
      if (error) throw error;

      const delta = values.quantity - values.previous_quantity;
      if (delta !== 0) {
        const { data: prod } = await supabase
          .from('products')
          .select('stock_quantity')
          .eq('id', values.product_id)
          .single();
        const currentStock = prod?.stock_quantity || 0;
        if (delta > 0 && currentStock < delta) {
          throw new Error(`Estoque insuficiente. Disponível: ${currentStock}, solicitado adicional: ${delta}`);
        }
        await supabase
          .from('products')
          .update({ stock_quantity: currentStock - delta })
          .eq('id', values.product_id);

        await supabase.from('inventory_movements').insert({
          product_id: values.product_id,
          movement_type: 'adjustment',
          quantity_delta: -delta,
          reference_type: 'service_order',
          reference_id: values.service_order_id,
          unit_cost_snapshot: values.unit_cost_snapshot,
          notes: 'Ajuste por edição de peça da OS',
        });
      }

      await recalcTotals(values.service_order_id);
      const { data: updatedSO } = await supabase
        .from('service_orders').select('grand_total').eq('id', values.service_order_id).single();
      await updateReceivableFromSO(values.service_order_id, updatedSO?.grand_total || 0);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-parts', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['pdf-data'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
    },
  });
}

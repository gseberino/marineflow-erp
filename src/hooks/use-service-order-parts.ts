import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { recalcTotals, isStockModelV2 } from '@/hooks/use-service-orders';

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
      discount_pct?: number;
      discount_amount?: number;
    }) => {
      // discount_amount (R$) é a fonte da verdade, aplicado só ao preço de
      // venda (não ao custo) — subtração exata, sem passar pelo percentual.
      const discountPct = values.discount_pct || 0;
      const discountAmount = values.discount_amount || 0;
      const line_total_cost =
        Math.round(values.quantity * values.unit_cost_snapshot * 100) / 100;
      const line_total_sale =
        Math.round((values.quantity * values.unit_sale_snapshot - discountAmount) * 100) / 100;

      const patch = {
        product_id: values.product_id,
        quantity: values.quantity,
        unit_cost_snapshot: values.unit_cost_snapshot,
        unit_sale_snapshot: values.unit_sale_snapshot,
        notes: values.notes ?? null,
        discount_pct: discountPct,
        discount_amount: discountAmount,
        line_total_cost,
        line_total_sale,
      };

      // Snapshot dos campos alterados antes de gravar — necessário para
      // reverter caso o novo total fique abaixo do que o cliente já pagou.
      const { data: before } = await supabase
        .from('service_order_parts')
        .select(Object.keys(patch).join(','))
        .eq('id', values.id)
        .single();

      const { error } = await supabase
        .from('service_order_parts')
        .update(patch as any)
        .eq('id', values.id);
      if (error) throw error;

      // Modelo v2: o banco gerencia estoque (reserva/baixa na conclusão); a edição de qty NÃO
      // baixa estoque nem BLOQUEIA por falta — a restrição só aparece na efetivação. Com a flag
      // OFF, mantém o comportamento de hoje (ajuste + bloqueio de estoque insuficiente).
      const v2 = await isStockModelV2();
      const delta = values.quantity - values.previous_quantity;
      let stockBeforeAdjustment: number | null = null;
      if (!v2 && delta !== 0) {
        const { data: prod } = await supabase
          .from('products')
          .select('stock_quantity')
          .eq('id', values.product_id)
          .single();
        const currentStock = prod?.stock_quantity || 0;
        stockBeforeAdjustment = currentStock;
        if (delta > 0 && currentStock < delta) {
          throw new Error(`Estoque insuficiente. Disponível: ${currentStock}, solicitado adicional: ${delta}`);
        }
        await supabase
          .from('products')
          .update({ stock_quantity: currentStock - delta })
          .eq('id', values.product_id);

        await supabase.from('inventory_movements').insert({
          product_id: values.product_id,
          movement_type: 'manual_adjustment',
          quantity_delta: -delta,
          reference_type: 'service_order',
          reference_id: values.service_order_id,
          unit_cost_snapshot: values.unit_cost_snapshot,
          notes: 'Ajuste por edição de peça da OS',
        });
      }

      try {
        await recalcTotals(values.service_order_id);
      } catch (e) {
        if (before) {
          await supabase.from('service_order_parts').update(before as any).eq('id', values.id);
        }
        if (stockBeforeAdjustment !== null) {
          await supabase.from('products').update({ stock_quantity: stockBeforeAdjustment }).eq('id', values.product_id);
        }
        await recalcTotals(values.service_order_id).catch(() => {});
        throw e;
      }
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

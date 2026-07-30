import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { computePurchaseNeeds, type PurchaseNeeds } from '@/lib/purchase-needs';

/**
 * Necessidade de compra de uma OS. Busca os quatro insumos e delega o cálculo
 * para a lib pura (src/lib/purchase-needs.ts), que é onde a regra vive e é testada.
 *
 * A disponibilidade sai de `product_availability` (físico − reservado) e não da
 * tabela products crua, para não ignorar as reservas do modelo de estoque v2.
 */

/** Status de OC que ainda vão entregar mercadoria. */
const OPEN_PO_STATUSES = ['draft', 'sent', 'partial'];

export async function fetchPurchaseNeeds(serviceOrderId: string): Promise<PurchaseNeeds> {
  const [partsRes, servicesRes] = await Promise.all([
    supabase
      .from('service_order_parts')
      .select('id, product_id, quantity, unit_cost_snapshot, products(name, unit)')
      .eq('service_order_id', serviceOrderId),
    supabase
      .from('service_order_services')
      .select('id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot')
      .eq('service_order_id', serviceOrderId),
  ]);
  if (partsRes.error) throw partsRes.error;
  if (servicesRes.error) throw servicesRes.error;

  const parts = (partsRes.data ?? []).map((p: any) => ({
    id: p.id,
    product_id: p.product_id,
    quantity: p.quantity,
    unit_cost_snapshot: p.unit_cost_snapshot,
    product_name: p.products?.name ?? null,
    product_unit: p.products?.unit ?? null,
  }));

  const productIds = [...new Set(parts.map(p => p.product_id).filter(Boolean))];

  // Sem peça no catálogo não há o que consultar de estoque nem de OC.
  let availability: any[] = [];
  let onOrder: any[] = [];
  if (productIds.length) {
    const [availRes, poRes] = await Promise.all([
      supabase
        .from('product_availability')
        .select('id, stock_quantity, reserved_quantity')
        .in('id', productIds),
      supabase
        .from('purchase_order_items')
        .select('product_id, quantity, received_qty, purchase_orders!inner(status)')
        .in('product_id', productIds)
        .in('purchase_orders.status', OPEN_PO_STATUSES),
    ]);
    if (availRes.error) throw availRes.error;
    if (poRes.error) throw poRes.error;
    availability = availRes.data ?? [];
    onOrder = (poRes.data ?? []).map((i: any) => ({
      product_id: i.product_id,
      quantity: i.quantity,
      received_qty: i.received_qty,
    }));
  }

  return computePurchaseNeeds({
    serviceOrderId,
    parts,
    freeTextItems: (servicesRes.data ?? []) as any[],
    availability,
    onOrder,
  });
}

export function usePurchaseNeeds(serviceOrderId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['purchase-needs', serviceOrderId],
    queryFn: () => fetchPurchaseNeeds(serviceOrderId!),
    enabled: !!serviceOrderId && enabled,
    staleTime: 30_000,
  });
}

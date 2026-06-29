import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type POStatus = 'draft' | 'sent' | 'partial' | 'received' | 'cancelled';

export interface PurchaseOrderItem {
  id: string;
  purchase_order_id: string;
  product_id: string | null;
  description: string;
  quantity: number;
  unit_cost: number;
  received_qty: number;
  created_at: string;
  products?: { name: string; sku?: string | null } | null;
}

export interface PurchaseOrder {
  id: string;
  po_number: string;
  status: POStatus;
  supplier_id: string | null;
  service_order_id: string | null;
  expected_date: string | null;
  received_date: string | null;
  notes: string | null;
  total_amount: number;
  created_by: string;
  created_at: string;
  updated_at: string;
  suppliers?: { name: string; contact_name?: string | null } | null;
  service_orders?: { service_order_number: string } | null;
  purchase_order_items?: PurchaseOrderItem[];
}

const PO_LIST_SELECT = `
  *,
  suppliers(name, contact_name),
  service_orders(service_order_number)
`;

const PO_DETAIL_SELECT = `
  *,
  suppliers(name, contact_name, email, phone),
  service_orders(service_order_number),
  purchase_order_items(*, products(name, sku))
`;

async function generatePONumber(): Promise<string> {
  const { data } = await supabase
    .from('purchase_orders')
    .select('po_number')
    .order('created_at', { ascending: false })
    .limit(1);
  let seq = 1;
  if (data?.[0]?.po_number) {
    // Handles both legacy 'PO-2026-0001' and new 'OC-00001' formats
    const match = data[0].po_number.match(/(\d+)$/);
    if (match) seq = parseInt(match[1], 10) + 1;
  }
  return `OC-${String(seq).padStart(5, '0')}`;
}

// ── Queries ────────────────────────────────────────────────────────────────────

export function usePurchaseOrders(filters?: { status?: string; search?: string }) {
  return useQuery({
    queryKey: ['purchase-orders', filters],
    queryFn: async () => {
      let q = supabase
        .from('purchase_orders')
        .select(PO_LIST_SELECT)
        .order('created_at', { ascending: false });
      if (filters?.status && filters.status !== 'all') {
        q = q.eq('status', filters.status);
      }
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as PurchaseOrder[];
    },
    staleTime: 30 * 1000,
  });
}

export function usePurchaseOrder(id: string | undefined) {
  return useQuery({
    queryKey: ['purchase-orders', id],
    queryFn: async () => {
      if (!id) return null;
      const { data, error } = await supabase
        .from('purchase_orders')
        .select(PO_DETAIL_SELECT)
        .eq('id', id)
        .maybeSingle();
      if (error) throw error;
      return data as unknown as PurchaseOrder | null;
    },
    enabled: !!id,
  });
}

// ── Mutations ─────────────────────────────────────────────────────────────────

export function useCreatePurchaseOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: Partial<PurchaseOrder> & { items?: Partial<PurchaseOrderItem>[] }) => {
      const poNumber = await generatePONumber();
      const { items, purchase_order_items: _items, ...poFields } = values as any;
      const { data: po, error } = await supabase
        .from('purchase_orders')
        .insert({ ...poFields, po_number: poNumber })
        .select()
        .single();
      if (error) throw error;
      if (items?.length) {
        const { error: itemsErr } = await supabase.from('purchase_order_items').insert(
          items.map((i: any) => ({ ...i, purchase_order_id: po.id }))
        );
        if (itemsErr) throw itemsErr;
      }
      return po;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['purchase-orders'] });
      toast.success('Ordem de compra criada');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao criar PO'),
  });
}

export function useUpdatePurchaseOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...values }: Partial<PurchaseOrder> & { id: string }) => {
      const { purchase_order_items: _items, suppliers: _s, service_orders: _so, ...fields } = values as any;
      const { data, error } = await supabase
        .from('purchase_orders')
        .update(fields)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['purchase-orders'] });
      toast.success('Ordem de compra atualizada');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao atualizar PO'),
  });
}

export function useDeletePurchaseOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('purchase_orders').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['purchase-orders'] });
      toast.success('Ordem de compra removida');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao remover PO'),
  });
}

export function useAddPOItem() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (item: Omit<PurchaseOrderItem, 'id' | 'created_at'>) => {
      const { data, error } = await supabase
        .from('purchase_order_items')
        .insert(item as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_d, v) => qc.invalidateQueries({ queryKey: ['purchase-orders', v.purchase_order_id] }),
    onError: (e: any) => toast.error(e.message),
  });
}

export function useRemovePOItem() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ itemId, poId }: { itemId: string; poId: string }) => {
      const { error } = await supabase.from('purchase_order_items').delete().eq('id', itemId);
      if (error) throw error;
      return poId;
    },
    onSuccess: (_d, v) => qc.invalidateQueries({ queryKey: ['purchase-orders', v.poId] }),
    onError: (e: any) => toast.error(e.message),
  });
}

// ── receive_po() — atomic: stock in + payable + status ────────────────────────

export function useReceivePO() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      poId,
      items,
      dueDays = 30,
    }: {
      poId: string;
      items: { po_item_id: string; received_qty: number }[];
      dueDays?: number;
    }) => {
      const { data, error } = await supabase.rpc('receive_po', {
        p_po_id:    poId,
        p_items:    items,
        p_due_days: dueDays,
      });
      if (error) throw error;
      return data as { status: string; payable_id: string | null; all_received: boolean };
    },
    onSuccess: (result) => {
      qc.invalidateQueries({ queryKey: ['purchase-orders'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      if (result?.all_received) {
        toast.success('Recebimento registrado. Estoque atualizado e conta a pagar gerada.');
      } else {
        toast.success('Recebimento parcial registrado.');
      }
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao registrar recebimento'),
  });
}

// ── Create PO directly from a service order (sob encomenda) ───────────────────

export function useCreatePOFromOS() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (params: {
      serviceOrderId: string;
      productId: string;
      productName: string;
      quantity: number;
      unitCost: number;
      supplierId?: string;
      expectedDate?: string;
      notes?: string;
    }) => {
      const poNumber = await generatePONumber();

      // Create PO linked to OS
      const { data: po, error: poErr } = await supabase
        .from('purchase_orders')
        .insert({
          po_number:        poNumber,
          service_order_id: params.serviceOrderId,
          supplier_id:      params.supplierId ?? null,
          expected_date:    params.expectedDate ?? null,
          notes:            params.notes ?? null,
          status:           'draft',
        })
        .select()
        .single();
      if (poErr) throw poErr;

      // Add item
      const { error: itemErr } = await supabase
        .from('purchase_order_items')
        .insert({
          purchase_order_id: po.id,
          product_id:        params.productId,
          description:       params.productName,
          quantity:          params.quantity,
          unit_cost:         params.unitCost,
        });
      if (itemErr) throw itemErr;

      // Move OS to awaiting_parts if not already there
      await supabase
        .from('service_orders')
        .update({ status: 'awaiting_parts' })
        .eq('id', params.serviceOrderId)
        .in('status', ['open', 'in_progress', 'approved', 'scheduled']);

      return po;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['purchase-orders'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      toast.success('Ordem de compra criada. OS movida para "Aguardando Peças".');
    },
    onError: (e: any) => toast.error(e.message || 'Erro ao criar PO'),
  });
}

// ── Query POs linked to a specific service order ───────────────────────────────

export function useSOLinkedPOs(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['purchase-orders', 'by-so', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('purchase_orders')
        .select(`
          *,
          suppliers(name),
          purchase_order_items(*, products(name, sku))
        `)
        .eq('service_order_id', serviceOrderId!)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as PurchaseOrder[];
    },
    enabled: !!serviceOrderId,
    staleTime: 30_000,
  });
}

// ── Status helpers ─────────────────────────────────────────────────────────────

export const PO_STATUS_LABELS: Record<POStatus, string> = {
  draft:      'Rascunho',
  sent:       'Enviada ao fornecedor',
  partial:    'Recebimento parcial',
  received:   'Recebida',
  cancelled:  'Cancelada',
};

export const PO_STATUS_COLORS: Record<POStatus, string> = {
  draft:     'bg-muted text-muted-foreground',
  sent:      'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300',
  partial:   'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300',
  received:  'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300',
  cancelled: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300',
};

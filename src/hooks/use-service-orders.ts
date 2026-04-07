import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

const SO_SELECT = `
  *,
  clients!service_orders_client_id_fkey(full_name_or_company_name),
  vessels!service_orders_vessel_id_fkey(boat_name, manufacturer, model),
  marinas!service_orders_marina_id_fkey(marina_name, latitude, longitude)
`;

const SO_DETAIL_SELECT = `
  *,
  clients!service_orders_client_id_fkey(full_name_or_company_name),
  vessels!service_orders_vessel_id_fkey(boat_name, manufacturer, model, current_dock_position),
  marinas!service_orders_marina_id_fkey(marina_name, latitude, longitude),
  service_order_parts(*, products(*)),
  service_order_technicians(*, app_users(*)),
  time_entries(*, app_users!time_entries_technician_user_id_fkey(*))
`;

export function useServiceOrders() {
  return useQuery({
    queryKey: ['service-orders'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_orders')
        .select(SO_SELECT)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
  });
}

export function useServiceOrder(id: string | undefined) {
  return useQuery({
    queryKey: ['service-orders', id],
    queryFn: async () => {
      if (!id) return null;
      const { data, error } = await supabase
        .from('service_orders')
        .select(SO_DETAIL_SELECT)
        .eq('id', id)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    enabled: !!id,
  });
}

async function generateSONumber(): Promise<string> {
  const year = new Date().getFullYear();
  const { data } = await supabase
    .from('service_orders')
    .select('service_order_number')
    .order('created_at', { ascending: false })
    .limit(1);
  let seq = 1;
  if (data?.[0]?.service_order_number) {
    const match = data[0].service_order_number.match(/(\d+)$/);
    if (match) seq = parseInt(match[1], 10) + 1;
  }
  return `SO-${year}-${String(seq).padStart(5, '0')}`;
}

export function useCreateServiceOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: Record<string, any>) => {
      const soNumber = await generateSONumber();
      const payload = { ...values, service_order_number: soNumber };
      const { data, error } = await supabase
        .from('service_orders')
        .insert(payload as any)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

export function useUpdateServiceOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...values }: { id: string } & Record<string, any>) => {
      const { data, error } = await supabase
        .from('service_orders')
        .update(values as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.id] });
    },
  });
}

export function useUpdateServiceOrderStatus() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => {
      const updates: Record<string, any> = { status };
      if (status === 'in_progress') {
        const { data: current } = await supabase
          .from('service_orders')
          .select('check_in_at')
          .eq('id', id)
          .single();
        if (!current?.check_in_at) updates.check_in_at = new Date().toISOString();
      }
      if (status === 'completed') {
        const { data: current } = await supabase
          .from('service_orders')
          .select('check_out_at, grand_total, client_id, service_order_number, vessel_id')
          .eq('id', id)
          .single();
        if (!current?.check_out_at) updates.check_out_at = new Date().toISOString();
        // Auto-generate receivable
        if (current) {
          const { data: vessel } = await supabase
            .from('vessels')
            .select('boat_name')
            .eq('id', current.vessel_id)
            .single();
          const today = new Date().toISOString().slice(0, 10);
          const due = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);
          await supabase.from('receivables').insert({
            client_id: current.client_id,
            service_order_id: id,
            description: `OS ${current.service_order_number} - ${vessel?.boat_name || ''}`,
            issue_date: today,
            due_date: due,
            amount: current.grand_total || 0,
            balance_amount: current.grand_total || 0,
            status: 'pending',
          });
        }
      }
      const { data, error } = await supabase
        .from('service_orders')
        .update(updates as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.id] });
    },
  });
}

// Parts
export function useServiceOrderParts(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['so-parts', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_parts')
        .select('*, products(*)')
        .eq('service_order_id', serviceOrderId!)
        .order('created_at', { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!serviceOrderId,
  });
}

async function recalcTotals(soId: string) {
  const { data: parts } = await supabase
    .from('service_order_parts')
    .select('line_total_sale')
    .eq('service_order_id', soId);
  const partsCost = (parts || []).reduce((s, p) => s + (p.line_total_sale || 0), 0);

  // Service lines for labor cost (billing)
  const { data: serviceLines } = await supabase
    .from('service_order_services')
    .select('line_total')
    .eq('service_order_id', soId);
  const laborCost = (serviceLines || []).reduce((s, l) => s + (l.line_total || 0), 0);

  // Time entries for internal hours tracking only
  const { data: te } = await supabase
    .from('time_entries')
    .select('duration_minutes, billable')
    .eq('service_order_id', soId);
  const { data: so } = await supabase
    .from('service_orders')
    .select('travel_cost_total, subcontract_cost_total, discount_amount, tax_amount')
    .eq('id', soId)
    .single();

  const billableMinutes = (te || [])
    .filter((e) => e.billable)
    .reduce((s, e) => s + (e.duration_minutes || 0), 0);
  const laborHours = Math.round((billableMinutes / 60) * 100) / 100;

  const grand =
    laborCost +
    partsCost +
    (so?.travel_cost_total || 0) +
    (so?.subcontract_cost_total || 0) -
    (so?.discount_amount || 0) +
    (so?.tax_amount || 0);

  await supabase.from('service_orders').update({
    parts_cost_total: partsCost,
    labor_hours_total: laborHours,
    labor_cost_total: Math.round(laborCost * 100) / 100,
    grand_total: Math.round(grand * 100) / 100,
  }).eq('id', soId);
}

export function useAddServiceOrderPart() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      service_order_id: string;
      product_id: string;
      quantity: number;
      unit_cost_snapshot: number;
      unit_sale_snapshot: number;
      notes?: string;
    }) => {
      const line_total_cost = values.quantity * values.unit_cost_snapshot;
      const line_total_sale = values.quantity * values.unit_sale_snapshot;
      const { error } = await supabase.from('service_order_parts').insert({
        ...values,
        line_total_cost,
        line_total_sale,
      });
      if (error) throw error;

      // Decrement stock
      const { data: prod } = await supabase
        .from('products')
        .select('stock_quantity')
        .eq('id', values.product_id)
        .single();
      await supabase
        .from('products')
        .update({ stock_quantity: (prod?.stock_quantity || 0) - values.quantity })
        .eq('id', values.product_id);

      // Inventory movement
      await supabase.from('inventory_movements').insert({
        product_id: values.product_id,
        movement_type: 'service_usage',
        quantity_delta: -values.quantity,
        reference_type: 'service_order',
        reference_id: values.service_order_id,
        unit_cost_snapshot: values.unit_cost_snapshot,
      });

      await recalcTotals(values.service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-parts', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['products'] });
    },
  });
}

export function useRemoveServiceOrderPart() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (part: {
      id: string;
      service_order_id: string;
      product_id: string;
      quantity: number;
      unit_cost_snapshot: number;
    }) => {
      const { error } = await supabase
        .from('service_order_parts')
        .delete()
        .eq('id', part.id);
      if (error) throw error;

      // Restore stock
      const { data: prod } = await supabase
        .from('products')
        .select('stock_quantity')
        .eq('id', part.product_id)
        .single();
      await supabase
        .from('products')
        .update({ stock_quantity: (prod?.stock_quantity || 0) + part.quantity })
        .eq('id', part.product_id);

      // Inventory movement
      await supabase.from('inventory_movements').insert({
        product_id: part.product_id,
        movement_type: 'return',
        quantity_delta: part.quantity,
        reference_type: 'service_order',
        reference_id: part.service_order_id,
        unit_cost_snapshot: part.unit_cost_snapshot,
      });

      await recalcTotals(part.service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-parts', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['products'] });
    },
  });
}

// Time entries
export function useTimeEntries(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['time-entries', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('time_entries')
        .select('*, app_users!time_entries_technician_user_id_fkey(full_name)')
        .eq('service_order_id', serviceOrderId!)
        .order('started_at', { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!serviceOrderId,
  });
}

export function useAddTimeEntry() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      service_order_id: string;
      technician_user_id: string;
      started_at: string;
      ended_at?: string;
      duration_minutes: number;
      billable: boolean;
      notes?: string;
    }) => {
      const { error } = await supabase.from('time_entries').insert(values);
      if (error) throw error;
      await recalcTotals(values.service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['time-entries', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
  });
}

export function useRemoveTimeEntry() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, service_order_id }: { id: string; service_order_id: string }) => {
      const { error } = await supabase.from('time_entries').delete().eq('id', id);
      if (error) throw error;
      await recalcTotals(service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['time-entries', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
  });
}

// App users
export function useAppUsers() {
  return useQuery({
    queryKey: ['app-users'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_users')
        .select('*')
        .eq('active', true)
        .order('full_name');
      if (error) throw error;
      return data;
    },
  });
}

// Status transitions
export const STATUS_TRANSITIONS: Record<string, string[]> = {
  draft: ['scheduled', 'open', 'cancelled'],
  scheduled: ['open', 'cancelled'],
  open: ['in_progress', 'awaiting_parts', 'awaiting_client', 'cancelled'],
  in_progress: ['awaiting_parts', 'awaiting_client', 'completed', 'cancelled'],
  awaiting_parts: ['in_progress', 'cancelled'],
  awaiting_client: ['in_progress', 'completed', 'cancelled'],
  completed: ['invoiced'],
  invoiced: [],
  cancelled: [],
};

// Service order services (labor lines)
export function useServiceOrderServices(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['so-services', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_order_services')
        .select('*, services(service_name)')
        .eq('service_order_id', serviceOrderId!)
        .order('created_at', { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!serviceOrderId,
  });
}

export function useAddServiceOrderService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (values: {
      service_order_id: string;
      service_id?: string;
      service_name_snapshot: string;
      description_snapshot?: string;
      billing_unit_snapshot: string;
      quantity: number;
      unit_price_snapshot: number;
      notes?: string;
    }) => {
      const line_total = Math.round(values.quantity * values.unit_price_snapshot * 100) / 100;
      const { error } = await supabase.from('service_order_services').insert({
        ...values,
        line_total,
      });
      if (error) throw error;
      await recalcTotals(values.service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-services', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
  });
}

export function useRemoveServiceOrderService() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, service_order_id }: { id: string; service_order_id: string }) => {
      const { error } = await supabase
        .from('service_order_services')
        .delete()
        .eq('id', id);
      if (error) throw error;
      await recalcTotals(service_order_id);
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['so-services', vars.service_order_id] });
      qc.invalidateQueries({ queryKey: ['service-orders', vars.service_order_id] });
    },
  });
}

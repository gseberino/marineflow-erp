import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export function useAgendaOrders(dateFrom: string, dateTo: string) {
  return useQuery({
    queryKey: ['agenda-orders', dateFrom, dateTo],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_orders')
        .select(`
          id, service_order_number, status, scheduled_start_at, scheduled_end_at,
          clients!service_orders_client_id_fkey(full_name_or_company_name),
          vessels!service_orders_vessel_id_fkey(boat_name),
          service_order_technicians(user_id, app_users(id, full_name))
        `)
        .gte('scheduled_start_at', dateFrom)
        .lte('scheduled_start_at', dateTo)
        .neq('status', 'cancelled')
        .order('scheduled_start_at', { ascending: true });
      if (error) throw error;
      return data || [];
    },
  });
}

export function useTechnicians() {
  return useQuery({
    queryKey: ['agenda-technicians'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_users')
        .select('id, full_name')
        .eq('active', true)
        .eq('role', 'technician')
        .order('full_name');
      if (error) throw error;
      return data || [];
    },
  });
}

export function useSchedulableOrders() {
  return useQuery({
    queryKey: ['agenda-schedulable'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_orders')
        .select(`
          id, service_order_number, status,
          clients!service_orders_client_id_fkey(full_name_or_company_name),
          vessels!service_orders_vessel_id_fkey(boat_name)
        `)
        .in('status', ['draft', 'scheduled', 'open', 'in_progress'])
        .order('created_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      return data || [];
    },
  });
}

export function useQuickSchedule() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      service_order_id: string;
      technician_user_id: string;
      scheduled_start_at: string;
      scheduled_end_at: string | null;
    }) => {
      const { data: current, error: getErr } = await supabase
        .from('service_orders')
        .select('status')
        .eq('id', input.service_order_id)
        .single();
      if (getErr) throw getErr;

      const updatePayload: Record<string, any> = {
        scheduled_start_at: input.scheduled_start_at,
        scheduled_end_at: input.scheduled_end_at,
      };
      if (current?.status === 'draft') updatePayload.status = 'scheduled';

      const { error: updateErr } = await supabase
        .from('service_orders')
        .update(updatePayload)
        .eq('id', input.service_order_id);
      if (updateErr) throw updateErr;

      const { data: existing } = await supabase
        .from('service_order_technicians')
        .select('user_id')
        .eq('service_order_id', input.service_order_id)
        .eq('user_id', input.technician_user_id)
        .maybeSingle();

      if (!existing) {
        const { error: techErr } = await supabase
          .from('service_order_technicians')
          .insert({
            service_order_id: input.service_order_id,
            user_id: input.technician_user_id,
            role_in_order: 'technician',
          });
        if (techErr) throw techErr;
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['agenda-orders'] });
      qc.invalidateQueries({ queryKey: ['agenda-schedulable'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

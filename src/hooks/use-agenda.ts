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
          clients(name),
          vessels(name),
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

export function useAgendaTasks(dateFrom: string, dateTo: string) {
  return useQuery({
    queryKey: ['agenda-tasks', dateFrom, dateTo],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('agenda_tasks')
        .select(`
          id, title, description, assignee_user_id, scheduled_start_at, scheduled_end_at,
          priority, status, location, client_id, notes,
          app_users:assignee_user_id(id, full_name),
          clients:client_id(id, name)
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
          clients(name),
          vessels(name)
        `)
        // Valid schedulable statuses — includes draft/approved so newly created/approved
        // orders appear in the Agenda scheduling dialog before being assigned a technician
        .in('status', ['draft', 'pending', 'approved', 'scheduled', 'in_progress', 'waiting_parts', 'waiting_approval', 'reopened'])
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
      // Guard: check for technician scheduling conflicts before saving
      if (input.scheduled_end_at) {
        const { data: conflicts, error: conflictErr } = await supabase
          .from('service_orders')
          .select('id, service_order_number, service_order_technicians!inner(user_id)')
          .eq('service_order_technicians.user_id', input.technician_user_id)
          .neq('id', input.service_order_id)
          .neq('status', 'cancelled')
          .lt('scheduled_start_at', input.scheduled_end_at)
          .gt('scheduled_end_at', input.scheduled_start_at);

        // Only block on conflict if the query itself succeeded
        if (!conflictErr && conflicts && conflicts.length > 0) {
          const conflictNums = conflicts.map((c: any) => c.service_order_number).join(', ');
          throw new Error(`Conflito de agenda: o técnico já está alocado na(s) OS ${conflictNums} nesse horário.`);
        }
      }

      const { data: current, error: getErr } = await supabase
        .from('service_orders')
        .select('status')
        .eq('id', input.service_order_id)
        .single();
      if (getErr) throw getErr;

      const updatePayload: { scheduled_start_at: string; scheduled_end_at: string | null; status?: string } = {
        scheduled_start_at: input.scheduled_start_at,
        scheduled_end_at: input.scheduled_end_at,
      };
      // Transition to 'scheduled' only from statuses that precede it
      if (current?.status === 'pending') updatePayload.status = 'scheduled';

      const { error: updateErr } = await supabase
        .from('service_orders')
        .update(updatePayload)
        .eq('id', input.service_order_id);
      if (updateErr) throw updateErr;

      // Use upsert to safely assign the technician — avoids unique-constraint
      // errors when the technician is already linked to this OS
      const { error: techErr } = await supabase
        .from('service_order_technicians')
        .upsert(
          {
            service_order_id: input.service_order_id,
            user_id: input.technician_user_id,
            role_in_order: 'technician',
          },
          { onConflict: 'service_order_id,user_id', ignoreDuplicates: true }
        );
      if (techErr) throw techErr;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['agenda-orders'] });
      qc.invalidateQueries({ queryKey: ['agenda-schedulable'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

export type AgendaTaskInput = {
  id?: string;
  title: string;
  description?: string | null;
  assignee_user_id: string;
  scheduled_start_at: string;
  scheduled_end_at: string | null;
  priority?: string;
  status?: string;
  location?: string | null;
  client_id?: string | null;
  notes?: string | null;
};

export function useSaveAgendaTask() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: AgendaTaskInput) => {
      // Guard: check for assignee scheduling conflicts in agenda_tasks before saving
      if (input.scheduled_end_at && input.assignee_user_id) {
        let conflictQuery = supabase
          .from('agenda_tasks')
          .select('id, title, scheduled_start_at')
          .eq('assignee_user_id', input.assignee_user_id)
          .neq('status', 'cancelled')
          .lt('scheduled_start_at', input.scheduled_end_at)
          .gt('scheduled_end_at', input.scheduled_start_at);

        // Exclude the record being edited — must reassign since filter returns new builder
        if (input.id) conflictQuery = conflictQuery.neq('id', input.id);

        const { data: conflicts, error: conflictErr } = await conflictQuery;
        // Only block on actual conflicts — ignore query errors (e.g. missing table)
        if (!conflictErr && conflicts && conflicts.length > 0) {
          const conflictTitles = conflicts.map((c: any) => `"${c.title}"`).join(', ');
          throw new Error(`Conflito de agenda: técnico já tem tarefa ${conflictTitles} nesse horário.`);
        }
      }

      if (input.id) {
        const { error } = await supabase
          .from('agenda_tasks')
          .update({
            title: input.title,
            description: input.description ?? null,
            assignee_user_id: input.assignee_user_id,
            scheduled_start_at: input.scheduled_start_at,
            scheduled_end_at: input.scheduled_end_at,
            priority: input.priority ?? 'normal',
            status: input.status ?? 'pending',
            location: input.location ?? null,
            client_id: input.client_id ?? null,
            notes: input.notes ?? null,
          })
          .eq('id', input.id);
        if (error) throw error;
      } else {
        const { data: u } = await supabase.auth.getUser();
        const { error } = await supabase.from('agenda_tasks').insert({
          title: input.title,
          description: input.description ?? null,
          assignee_user_id: input.assignee_user_id,
          scheduled_start_at: input.scheduled_start_at,
          scheduled_end_at: input.scheduled_end_at,
          priority: input.priority ?? 'normal',
          status: input.status ?? 'pending',
          location: input.location ?? null,
          client_id: input.client_id ?? null,
          notes: input.notes ?? null,
          created_by: u?.user?.id ?? null,
        });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['agenda-tasks'] });
    },
  });
}

export function useUpdateAgendaTaskStatus() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => {
      const { error } = await supabase.from('agenda_tasks').update({ status }).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['agenda-tasks'] });
    },
  });
}

export function useDeleteAgendaTask() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('agenda_tasks').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['agenda-tasks'] });
    },
  });
}

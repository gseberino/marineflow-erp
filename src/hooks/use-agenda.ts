import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

// Tipos de entidade vinculável a uma tarefa (espelha o CHECK de agenda_tasks)
export type RelatedEntityType =
  | 'service_order' | 'quote' | 'external_quote' | 'client' | 'vessel'
  | 'receivable' | 'payable' | 'purchase_order' | 'collection' | 'stock_item';

export type ReminderInput = { remind_at: string; channel: 'app' | 'whatsapp' };

const TASK_SELECT = `
  id, title, description, kind, assignee_user_id, scheduled_start_at, scheduled_end_at,
  due_at, all_day, priority, status, location, client_id, notes, source, is_private,
  related_entity_type, related_entity_id, checklist, snoozed_until, completed_at, rrule,
  app_users:assignee_user_id(id, full_name),
  clients:client_id(id, name)
`;

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
        .select(TASK_SELECT)
        .gte('scheduled_start_at', dateFrom)
        .lte('scheduled_start_at', dateTo)
        .neq('status', 'cancelled')
        .order('scheduled_start_at', { ascending: true });
      if (error) throw error;
      return data || [];
    },
  });
}

/** Tarefas vivas (pendentes/em andamento) — visão Hoje, widget do Dashboard. */
export function useLiveTasks() {
  return useQuery({
    queryKey: ['agenda-live-tasks'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('agenda_tasks')
        .select(TASK_SELECT)
        .in('status', ['pending', 'in_progress'])
        .order('due_at', { ascending: true, nullsFirst: false })
        .limit(500);
      if (error) throw error;
      return data || [];
    },
  });
}

/** Tarefas de uma entidade do ERP (vivas + concluídas recentes) — EntityTasksPanel. */
export function useEntityTasks(entityType: RelatedEntityType, entityId: string | undefined) {
  return useQuery({
    queryKey: ['agenda-entity-tasks', entityType, entityId],
    enabled: !!entityId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('agenda_tasks')
        .select(TASK_SELECT)
        .eq('related_entity_type', entityType)
        .eq('related_entity_id', entityId!)
        .neq('status', 'cancelled')
        .order('status', { ascending: false }) // pending/in_progress antes de done
        .order('created_at', { ascending: false })
        .limit(20);
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

/** Todos os usuários ativos — responsável de tarefa não é só técnico. */
export function useActiveUsers() {
  return useQuery({
    queryKey: ['agenda-active-users'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_users')
        .select('id, full_name, role')
        .eq('active', true)
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

/** Conflitos de agenda (tarefas + OS) via RPC única — mesma checagem para UI, IA e motor. */
async function fetchConflicts(params: {
  userId: string; startISO: string; endISO: string;
  excludeTask?: string; excludeSo?: string;
}) {
  const { data, error } = await supabase.rpc('get_agenda_conflicts', {
    p_user_id: params.userId,
    p_start: params.startISO,
    p_end: params.endISO,
    p_exclude_task: params.excludeTask,
    p_exclude_so: params.excludeSo,
  });
  if (error) return []; // não bloquear salvamento por erro da checagem
  return data || [];
}

function conflictMessage(conflicts: any[]): string {
  const labels = conflicts.map((c: any) =>
    c.source === 'service_order' ? `OS ${c.label}` : `"${c.label}"`).join(', ');
  return `Conflito de agenda: o responsável já tem ${labels} nesse horário.`;
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
      if (input.scheduled_end_at) {
        const conflicts = await fetchConflicts({
          userId: input.technician_user_id,
          startISO: input.scheduled_start_at,
          endISO: input.scheduled_end_at,
          excludeSo: input.service_order_id,
        });
        if (conflicts.length > 0) throw new Error(conflictMessage(conflicts));
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
  kind?: 'task' | 'appointment';
  assignee_user_id?: string | null;
  scheduled_start_at?: string | null;
  scheduled_end_at?: string | null;
  due_at?: string | null;
  priority?: string;
  status?: string;
  location?: string | null;
  client_id?: string | null;
  notes?: string | null;
  is_private?: boolean;
  related_entity_type?: RelatedEntityType | null;
  related_entity_id?: string | null;
  checklist?: { text: string; done: boolean }[];
  rrule?: string | null;
  /** Substitui TODOS os lembretes da tarefa quando presente. */
  reminders?: ReminderInput[];
};

function invalidateTaskQueries(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['agenda-tasks'] });
  qc.invalidateQueries({ queryKey: ['agenda-live-tasks'] });
  qc.invalidateQueries({ queryKey: ['agenda-entity-tasks'] });
}

export function useSaveAgendaTask() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: AgendaTaskInput) => {
      const kind = input.kind ?? (input.scheduled_start_at ? 'appointment' : 'task');

      // Compromisso com início+fim: checar conflito (tarefas + OS) antes de salvar
      if (kind === 'appointment' && input.assignee_user_id
          && input.scheduled_start_at && input.scheduled_end_at) {
        const conflicts = await fetchConflicts({
          userId: input.assignee_user_id,
          startISO: input.scheduled_start_at,
          endISO: input.scheduled_end_at,
          excludeTask: input.id,
        });
        if (conflicts.length > 0) throw new Error(conflictMessage(conflicts));
      }

      const row = {
        title: input.title,
        description: input.description ?? null,
        kind,
        assignee_user_id: input.assignee_user_id ?? null,
        scheduled_start_at: input.scheduled_start_at ?? null,
        scheduled_end_at: input.scheduled_end_at ?? null,
        due_at: input.due_at ?? null,
        priority: input.priority ?? 'normal',
        status: input.status ?? 'pending',
        location: input.location ?? null,
        client_id: input.client_id ?? null,
        notes: input.notes ?? null,
        is_private: input.is_private ?? false,
        related_entity_type: input.related_entity_type ?? null,
        related_entity_id: input.related_entity_id ?? null,
        checklist: input.checklist ?? [],
        rrule: input.rrule ?? null,
      };

      let taskId = input.id;
      if (input.id) {
        const { error } = await supabase.from('agenda_tasks').update(row).eq('id', input.id);
        if (error) throw error;
      } else {
        const { data: u } = await supabase.auth.getUser();
        const { data, error } = await supabase
          .from('agenda_tasks')
          .insert({ ...row, source: 'manual', created_by: u?.user?.id ?? null })
          .select('id')
          .single();
        if (error) throw error;
        taskId = data.id;
      }

      // Lembretes: substituição integral (delete + insert) quando o campo veio
      if (input.reminders && taskId) {
        await supabase.from('task_reminders').delete().eq('task_id', taskId).is('sent_at', null);
        if (input.reminders.length > 0) {
          const { error: remErr } = await supabase.from('task_reminders').insert(
            input.reminders.map((r) => ({ task_id: taskId!, remind_at: r.remind_at, channel: r.channel }))
          );
          if (remErr) throw remErr;
        }
      }
      return taskId;
    },
    onSuccess: () => invalidateTaskQueries(qc),
  });
}

export function useCompleteTask() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, done }: { id: string; done: boolean }) => {
      const { data: u } = await supabase.auth.getUser();
      const { error } = await supabase
        .from('agenda_tasks')
        .update(done
          ? { status: 'done', completed_at: new Date().toISOString(), completed_by: u?.user?.id ?? null }
          : { status: 'pending', completed_at: null, completed_by: null })
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => invalidateTaskQueries(qc),
  });
}

export function useSnoozeTask() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, until }: { id: string; until: string | null }) => {
      const { error } = await supabase.from('agenda_tasks').update({ snoozed_until: until }).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => invalidateTaskQueries(qc),
  });
}

export function useUpdateAgendaTaskStatus() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => {
      const { error } = await supabase.from('agenda_tasks').update({ status }).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => invalidateTaskQueries(qc),
  });
}

export function useDeleteAgendaTask() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('agenda_tasks').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => invalidateTaskQueries(qc),
  });
}

/** Lembretes pendentes de uma tarefa (para edição no dialog). */
export function useTaskReminders(taskId: string | undefined) {
  return useQuery({
    queryKey: ['agenda-task-reminders', taskId],
    enabled: !!taskId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('task_reminders')
        .select('id, remind_at, channel, sent_at')
        .eq('task_id', taskId!)
        .is('sent_at', null)
        .order('remind_at');
      if (error) throw error;
      return data || [];
    },
  });
}

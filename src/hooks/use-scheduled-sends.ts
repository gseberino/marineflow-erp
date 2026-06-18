import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type RecurrenceType = 'once' | 'daily' | 'weekly' | 'monthly';

export interface ScheduledSendRow {
  id: string;
  target_kind: 'service_order' | 'receivable';
  service_order_id: string | null;
  receivable_id: string | null;
  client_id: string | null;
  phone: string;
  message: string;
  send_mode: 'link' | 'document';
  context: string | null;
  link_title: string | null;
  link_description: string | null;
  scheduled_at: string;
  recurrence_type: RecurrenceType;
  recurrence_days_of_week: number[] | null;
  recurrence_day_of_month: number | null;
  recurrence_end_date: string | null;
  next_run_at: string;
  last_run_at: string | null;
  status: 'pending' | 'processing' | 'sent' | 'failed' | 'cancelled';
  attempt_count: number;
  max_attempts: number;
  auto_retry: boolean;
  last_error: string | null;
  created_at: string;
}

export interface CreateScheduledSendInput {
  target_kind: 'service_order' | 'receivable';
  service_order_id?: string | null;
  receivable_id?: string | null;
  client_id?: string | null;
  phone: string;
  message: string;
  send_mode: 'link' | 'document';
  context?: string;
  link_title?: string;
  link_description?: string;
  pdf_filename?: string;
  document_url?: string;
  caption?: string;
  include_link_in_caption?: boolean;
  scheduled_at: string; // ISO
  recurrence_type: RecurrenceType;
  recurrence_days_of_week?: number[];
  recurrence_day_of_month?: number;
  recurrence_end_date?: string | null;
  auto_retry?: boolean;
  max_attempts?: number;
}

export function useScheduledSends(filters?: { status?: string; targetId?: string }) {
  return useQuery({
    queryKey: ['whatsapp-scheduled-sends', filters],
    queryFn: async () => {
      let q = supabase
        .from('whatsapp_scheduled_sends' as any)
        .select('*')
        .order('next_run_at', { ascending: true });
      if (filters?.status) q = q.eq('status', filters.status);
      if (filters?.targetId) {
        q = q.or(`service_order_id.eq.${filters.targetId},receivable_id.eq.${filters.targetId}`);
      }
      const { data, error } = await q;
      if (error) throw error;
      return (data || []) as unknown as ScheduledSendRow[];
    },
  });
}

export function useCreateScheduledSend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: CreateScheduledSendInput) => {
      const phoneClean = input.phone.replace(/\D/g, '');
      if (phoneClean.length < 10) throw new Error('Telefone inválido');
      const payload = {
        ...input,
        phone: phoneClean,
        next_run_at: input.scheduled_at,
        include_link_in_caption: input.include_link_in_caption ?? true,
        auto_retry: input.auto_retry ?? true,
        max_attempts: input.max_attempts ?? 3,
      };
      const { data, error } = await (supabase as any)
        .from('whatsapp_scheduled_sends')
        .insert(payload)
        .select('*')
        .single();
      if (error) throw error;
      return data as ScheduledSendRow;
    },
    onSuccess: () => {
      toast.success('Envio agendado com sucesso');
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled-sends'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao agendar'),
  });
}

export function useCancelScheduledSend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await (supabase as any)
        .from('whatsapp_scheduled_sends')
        .update({ status: 'cancelled' })
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Agendamento cancelado');
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled-sends'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao cancelar'),
  });
}

export function useDeleteScheduledSend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await (supabase as any)
        .from('whatsapp_scheduled_sends')
        .delete()
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Agendamento removido');
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled-sends'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao remover'),
  });
}

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import type { Database } from '@/integrations/supabase/types';

export type ScheduledSend = Database['public']['Tables']['whatsapp_scheduled_sends']['Row'] & {
  service_order?: { id: string; order_number: string } | null;
};

export type ScheduledSendStatus = 'pending' | 'processing' | 'sent' | 'failed' | 'cancelled';

export function useWhatsAppScheduled(filters?: { status?: string }) {
  return useQuery({
    queryKey: ['whatsapp-scheduled', filters],
    queryFn: async () => {
      let q = supabase
        .from('whatsapp_scheduled_sends')
        .select(`
          *,
          service_order:service_orders(id, order_number)
        `)
        .order('next_run_at', { ascending: true });

      if (filters?.status && filters.status !== 'all') {
        q = q.eq('status', filters.status);
      }

      const { data, error } = await q;
      if (error) throw error;
      return data as unknown as ScheduledSend[];
    },
    refetchInterval: 30_000,
  });
}

export function useUpdateScheduledSend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...update }: { id: string; scheduled_at?: string; next_run_at?: string; message?: string; status?: string }) => {
      const { data, error } = await supabase
        .from('whatsapp_scheduled_sends')
        .update(update as any)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled'] });
      toast.success('Agendamento atualizado!');
    },
    onError: (e: any) => toast.error('Erro: ' + e.message),
  });
}

export function useCancelScheduledSend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('whatsapp_scheduled_sends')
        .update({ status: 'cancelled' })
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled'] });
      toast.success('Agendamento cancelado.');
    },
    onError: (e: any) => toast.error('Erro: ' + e.message),
  });
}

export function useDeleteScheduledSend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('whatsapp_scheduled_sends')
        .delete()
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled'] });
      toast.success('Agendamento removido.');
    },
    onError: (e: any) => toast.error('Erro: ' + e.message),
  });
}

export function useSendNow() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      // Marca para processar imediatamente: zera next_run_at para agora
      const { error } = await supabase
        .from('whatsapp_scheduled_sends')
        .update({ status: 'pending', next_run_at: new Date().toISOString() })
        .eq('id', id);
      if (error) throw error;

      // Dispara o worker manualmente
      const { error: fnErr } = await supabase.functions.invoke('whatsapp-process-scheduled', { body: {} });
      if (fnErr) throw fnErr;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled'] });
      toast.success('Mensagem enviada agora!');
    },
    onError: (e: any) => toast.error('Falha ao enviar: ' + e.message),
  });
}

export function useCreateScheduledSend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (payload: Database['public']['Tables']['whatsapp_scheduled_sends']['Insert']) => {
      const { data, error } = await supabase
        .from('whatsapp_scheduled_sends')
        .insert([payload])
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-scheduled'] });
      toast.success('Mensagem agendada com sucesso!');
    },
    onError: (e: any) => toast.error('Erro ao agendar: ' + e.message),
  });
}

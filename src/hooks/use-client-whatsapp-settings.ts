import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type ClientWhatsAppContext = 'service_order' | 'quote' | 'billing';

export interface ClientWhatsAppSetting {
  id: string;
  client_id: string;
  context: ClientWhatsAppContext;
  message_body: string | null;
  link_title: string | null;
  link_description: string | null;
  pdf_filename_pattern: string | null;
  created_at: string;
  updated_at: string;
}

export function useClientWhatsAppSettings(clientId: string | null | undefined) {
  return useQuery({
    queryKey: ['client-whatsapp-settings', clientId],
    enabled: !!clientId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('client_whatsapp_settings')
        .select('*')
        .eq('client_id', clientId!);
      if (error) throw error;
      return (data || []) as ClientWhatsAppSetting[];
    },
  });
}

export function useUpsertClientWhatsAppSetting() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (payload: {
      client_id: string;
      context: ClientWhatsAppContext;
      message_body?: string | null;
      link_title?: string | null;
      link_description?: string | null;
      pdf_filename_pattern?: string | null;
    }) => {
      const { error } = await supabase
        .from('client_whatsapp_settings')
        .upsert(payload, { onConflict: 'client_id,context' });
      if (error) throw error;
    },
    onSuccess: (_d, vars) => {
      toast.success('Mensagem padrão salva.');
      qc.invalidateQueries({ queryKey: ['client-whatsapp-settings', vars.client_id] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao salvar mensagem padrão.'),
  });
}

export function useDeleteClientWhatsAppSetting() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (vars: { client_id: string; context: ClientWhatsAppContext }) => {
      const { error } = await supabase
        .from('client_whatsapp_settings')
        .delete()
        .eq('client_id', vars.client_id)
        .eq('context', vars.context);
      if (error) throw error;
    },
    onSuccess: (_d, vars) => {
      toast.success('Configuração removida.');
      qc.invalidateQueries({ queryKey: ['client-whatsapp-settings', vars.client_id] });
    },
  });
}

export function pickClientSetting(
  settings: ClientWhatsAppSetting[] | undefined,
  context: ClientWhatsAppContext,
): ClientWhatsAppSetting | undefined {
  return settings?.find(s => s.context === context);
}

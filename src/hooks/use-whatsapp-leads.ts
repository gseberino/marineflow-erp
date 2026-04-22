import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export function useWhatsAppLeads(status?: string) {
  return useQuery({
    queryKey: ['whatsapp-leads', status || 'all'],
    queryFn: async () => {
      let q = supabase
        .from('whatsapp_leads')
        .select('*, linked_client:clients(id, full_name_or_company_name)')
        .order('last_message_at', { ascending: false })
        .limit(200);
      if (status && status !== 'all') q = q.eq('status', status);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },
  });
}

export function useWhatsAppLeadMessages(phone?: string, opts?: { inboundOnly?: boolean }) {
  return useQuery({
    queryKey: ['whatsapp-messages', phone, opts?.inboundOnly ? 'inbound' : 'all'],
    queryFn: async () => {
      let q = supabase
        .from('whatsapp_messages')
        .select('*')
        .eq('phone_normalized', phone!)
        .order('occurred_at', { ascending: true })
        .limit(500);
      if (opts?.inboundOnly) q = q.eq('direction', 'inbound');
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },
    enabled: !!phone,
  });
}

export function useLinkLeadToClient() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ leadId, clientId }: { leadId: string; clientId: string }) => {
      const { error } = await supabase
        .from('whatsapp_leads')
        .update({ status: 'linked', linked_client_id: clientId })
        .eq('id', leadId);
      if (error) throw error;
      // Vincula também as mensagens já recebidas
      const { data: lead } = await supabase
        .from('whatsapp_leads')
        .select('phone_normalized')
        .eq('id', leadId)
        .single();
      if (lead?.phone_normalized) {
        await supabase
          .from('whatsapp_messages')
          .update({ client_id: clientId })
          .eq('phone_normalized', lead.phone_normalized)
          .is('client_id', null);
      }
    },
    onSuccess: () => {
      toast.success('Lead vinculado ao cliente.');
      qc.invalidateQueries({ queryKey: ['whatsapp-leads'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao vincular lead.'),
  });
}

export function useConvertLeadToClient() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ leadId, fullName, type = 'individual' }: { leadId: string; fullName: string; type?: string }) => {
      const { data: lead, error: lerr } = await supabase
        .from('whatsapp_leads')
        .select('phone_normalized, display_name')
        .eq('id', leadId)
        .single();
      if (lerr) throw lerr;

      const { data: client, error: cerr } = await supabase
        .from('clients')
        .insert({
          full_name_or_company_name: fullName || lead.display_name || `Lead ${lead.phone_normalized}`,
          type,
          whatsapp: lead.phone_normalized,
          phone: lead.phone_normalized,
          active: true,
        })
        .select('id')
        .single();
      if (cerr) throw cerr;

      await supabase
        .from('whatsapp_leads')
        .update({ status: 'converted', linked_client_id: client.id })
        .eq('id', leadId);

      await supabase
        .from('whatsapp_messages')
        .update({ client_id: client.id })
        .eq('phone_normalized', lead.phone_normalized)
        .is('client_id', null);

      return client.id;
    },
    onSuccess: () => {
      toast.success('Lead convertido em cliente.');
      qc.invalidateQueries({ queryKey: ['whatsapp-leads'] });
      qc.invalidateQueries({ queryKey: ['clients'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao converter lead.'),
  });
}

export function useDiscardLead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (leadId: string) => {
      const { error } = await supabase
        .from('whatsapp_leads')
        .update({ status: 'discarded' })
        .eq('id', leadId);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Lead descartado.');
      qc.invalidateQueries({ queryKey: ['whatsapp-leads'] });
    },
  });
}

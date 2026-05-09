import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

// ---------- Blocklist ----------
export function useBlockedNumbers() {
  return useQuery({
    queryKey: ['wa-blocked'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('whatsapp_blocked_numbers')
        .select('*')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
  });
}

export function useAddBlockedNumber() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ phone, reason }: { phone: string; reason?: string }) => {
      const cleaned = phone.replace(/\D/g, '');
      if (cleaned.length < 10) throw new Error('Telefone inválido');
      const { error } = await supabase
        .from('whatsapp_blocked_numbers')
        .insert({ phone_normalized: cleaned, reason: reason || null });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Número bloqueado.');
      qc.invalidateQueries({ queryKey: ['wa-blocked'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao bloquear.'),
  });
}

export function useRemoveBlockedNumber() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('whatsapp_blocked_numbers').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Desbloqueado.');
      qc.invalidateQueries({ queryKey: ['wa-blocked'] });
    },
  });
}

// ---------- Quick replies ----------
export function useQuickReplies() {
  return useQuery({
    queryKey: ['wa-quick-replies'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('whatsapp_quick_replies')
        .select('*')
        .eq('active', true)
        .order('sort_order', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}

export function useUpsertQuickReply() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (row: { id?: string; shortcut: string; body: string; sort_order?: number }) => {
      if (row.id) {
        const { error } = await supabase.from('whatsapp_quick_replies').update(row).eq('id', row.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('whatsapp_quick_replies').insert(row);
        if (error) throw error;
      }
    },
    onSuccess: () => {
      toast.success('Resposta rápida salva.');
      qc.invalidateQueries({ queryKey: ['wa-quick-replies'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao salvar.'),
  });
}

export function useDeleteQuickReply() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('whatsapp_quick_replies').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['wa-quick-replies'] }),
  });
}

// ---------- Send text via Z-API ----------
export function useSendWhatsAppText() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ phone, message }: { phone: string; message: string }) => {
      const { data, error } = await supabase.functions.invoke('whatsapp-send-text', {
        body: { phone, message },
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      return data;
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['whatsapp-messages', vars.phone.replace(/\D/g, '')] });
      qc.invalidateQueries({ queryKey: ['whatsapp-leads'] });
      qc.invalidateQueries({ queryKey: ['wa-conversations'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao enviar mensagem.'),
  });
}

// ---------- Conversas (inbox unificado: leads + clientes) ----------
export function useWhatsAppConversations() {
  return useQuery({
    queryKey: ['wa-conversations'],
    queryFn: async () => {
      // Inbox mostra apenas mensagens recebidas (inbound) — outbound de lembretes do sistema
      // não devem poluir o inbox; ficam visíveis na página de Logs.
      const { data: msgs, error } = await supabase
        .from('whatsapp_messages')
        .select('phone_normalized, occurred_at, body, direction, client_id, lead_id, is_broadcast')
        .eq('direction', 'inbound')
        .order('occurred_at', { ascending: false })
        .limit(1000);
      if (error) throw error;

      const map = new Map<string, any>();
      for (const m of msgs || []) {
        if (!map.has(m.phone_normalized)) {
          map.set(m.phone_normalized, {
            phone: m.phone_normalized,
            last_at: m.occurred_at,
            last_body: m.body,
            last_direction: m.direction,
            client_id: m.client_id,
            lead_id: m.lead_id,
            is_broadcast: m.is_broadcast,
          });
        }
      }

      const phones = Array.from(map.keys());
      if (phones.length === 0) return [];

      // Enriquecer com clients e leads
      const [{ data: clients }, { data: leads }] = await Promise.all([
        supabase.from('clients').select('id, name, phone, whatsapp').eq('active', true),
        supabase.from('whatsapp_leads').select('phone_normalized, name, status, unread_count, assigned_to').in('phone_normalized', phones),
      ]);

      const norm = (s: string | null | undefined) => (s || '').replace(/\D/g, '');
      const clientByPhone = new Map<string, any>();
      for (const c of clients || []) {
        const wa = norm(c.whatsapp);
        const ph = norm(c.phone);
        if (wa) clientByPhone.set(wa, c);
        if (ph) clientByPhone.set(ph, c);
      }
      const leadByPhone = new Map<string, any>();
      for (const l of leads || []) leadByPhone.set(l.phone_normalized, l);

      return Array.from(map.values()).map((conv) => {
        const client = clientByPhone.get(conv.phone);
        const lead = leadByPhone.get(conv.phone);
        return {
          ...conv,
          client_name: client?.name || null,
          client_id: client?.id || conv.client_id,
          lead_status: lead?.status || null,
          unread_count: lead?.unread_count || 0,
          name: client?.name || lead?.name || null,
        };
      });
    },
    refetchInterval: 15000,
  });
}

export function useMarkConversationRead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (phone: string) => {
      const cleaned = phone.replace(/\D/g, '');
      await supabase
        .from('whatsapp_leads')
        .update({ unread_count: 0 })
        .eq('phone_normalized', cleaned);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['wa-conversations'] }),
  });
}

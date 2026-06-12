import { useEffect, useRef } from 'react';
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

// ---------- Send text via WhatsApp ----------
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
      // Carrega as 1000 mensagens mais recentes (qualquer direção) para determinar
      // quais conversas existem e qual foi a última mensagem de cada uma.
      // Apenas phones que receberam pelo menos uma mensagem inbound aparecem no inbox
      // (evita que envios em lote ou lembretes automáticos criem "conversas fantasma").
      const { data: msgs, error } = await supabase
        .from('whatsapp_messages')
        .select('phone_normalized, occurred_at, body, direction, client_id, lead_id, is_broadcast')
        .order('occurred_at', { ascending: false })
        .limit(1000);
      if (error) throw error;

      const phonesWithInbound = new Set<string>();
      const map = new Map<string, any>();
      for (const m of msgs || []) {
        if (m.direction === 'inbound') phonesWithInbound.add(m.phone_normalized);
        if (!map.has(m.phone_normalized)) {
          map.set(m.phone_normalized, {
            phone: m.phone_normalized,
            last_at: m.occurred_at,
            last_body: m.body,
            last_direction: m.direction,
            client_id: m.client_id,
            lead_id: m.lead_id,
            is_broadcast: m.is_broadcast || false,
          });
        }
      }
      // Remove conversas que só têm outbound (envios automáticos do sistema)
      for (const phone of Array.from(map.keys())) {
        if (!phonesWithInbound.has(phone)) map.delete(phone);
      }

      const phones = Array.from(map.keys());
      if (phones.length === 0) return [];

      // Enriquecer com clients e leads
      // whatsapp_leads has a "name" column (renamed from display_name).
      // linked_client_id references clients.id for manually confirmed links.
      const [{ data: clients }, { data: leads }] = await Promise.all([
        supabase.from('clients').select('id, name, phone, whatsapp').eq('active', true),
        supabase
          .from('whatsapp_leads')
          .select('phone_normalized, name, status, unread_count, assigned_to, linked_client_id')
          .in('phone_normalized', phones),
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
      const clientById = new Map<string, any>();
      for (const c of clients || []) clientById.set(c.id, c);

      return Array.from(map.values())
        .map((conv) => {
          const lead = leadByPhone.get(conv.phone);

          // Confirmed client: from message FK (set by webhook) or from lead's confirmed link
          const clientFromMsg = conv.client_id ? clientById.get(conv.client_id) : null;
          const clientFromLead = lead?.linked_client_id ? clientById.get(lead.linked_client_id) : null;
          const effectiveClient = clientFromMsg || clientFromLead;

          // Suggested client: phone matches a client but no confirmed FK link yet
          const clientFromPhone = clientByPhone.get(conv.phone);
          const suggestedClient =
            !clientFromMsg && !clientFromLead && clientFromPhone
              ? { id: clientFromPhone.id, name: clientFromPhone.name }
              : null;

          return {
            ...conv,
            client_name: effectiveClient?.name || null,
            client_id: conv.client_id || clientFromMsg?.id || null,
            lead_status: lead?.status || null,
            unread_count: lead?.unread_count || 0,
            name: effectiveClient?.name || lead?.name || null,
            suggested_client: suggestedClient,
          };
        })
        .sort((a, b) => new Date(b.last_at).getTime() - new Date(a.last_at).getTime());
    },
    refetchInterval: 30000, // Fallback — Realtime (useWhatsAppInboxRealtime) cuida das atualizações frequentes
  });
}

// ---------- Realtime (Inbox) ----------
// Subscreve INSERT em whatsapp_messages + UPDATE em whatsapp_leads.
// Invalida as queries de mensagens e conversas automaticamente, sem necessidade de polling frequente.
// onNewInbound é chamado quando chega uma mensagem inbound nova (para tocar som / atualizar badge).
export function useWhatsAppInboxRealtime(onNewInbound?: (phone: string) => void) {
  const qc = useQueryClient();
  // Ref evita que a mudança do callback recrie a subscription a cada render
  const cbRef = useRef(onNewInbound);
  cbRef.current = onNewInbound;

  useEffect(() => {
    const ch = supabase
      .channel('wa-inbox-realtime')
      .on(
        'postgres_changes' as any,
        { event: 'INSERT', schema: 'public', table: 'whatsapp_messages' },
        (payload: any) => {
          const phone: string | undefined = payload.new?.phone_normalized;
          if (phone) {
            qc.invalidateQueries({ queryKey: ['whatsapp-messages', phone] });
            qc.invalidateQueries({ queryKey: ['wa-conversations'] });
            if (payload.new?.direction === 'inbound') {
              cbRef.current?.(phone);
            }
          }
        },
      )
      .on(
        'postgres_changes' as any,
        { event: 'UPDATE', schema: 'public', table: 'whatsapp_leads' },
        () => {
          qc.invalidateQueries({ queryKey: ['wa-conversations'] });
        },
      )
      .subscribe();
    return () => { void supabase.removeChannel(ch); };
  }, [qc]);
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

// ---------- Criar lead manualmente a partir do Inbox ----------
export function useCreateWhatsAppLead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ phone, displayName }: { phone: string; displayName?: string | null }) => {
      const { error } = await supabase
        .from('whatsapp_leads')
        .insert({
          phone_normalized: phone,
          name: displayName || null,
          status: 'pending',
        });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Lead criado. Acesse a aba Leads para gerenciar.');
      qc.invalidateQueries({ queryKey: ['wa-conversations'] });
      qc.invalidateQueries({ queryKey: ['whatsapp-leads'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao criar lead.'),
  });
}

// ---------- Vincular conversa a cliente existente (sem lead prévio) ----------
export function useLinkConversationToClient() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      phone,
      clientId,
      clientName,
    }: {
      phone: string;
      clientId: string;
      clientName?: string | null;
    }) => {
      // Create or update lead record with confirmed link
      const { error: upsertErr } = await supabase
        .from('whatsapp_leads')
        .upsert(
          {
            phone_normalized: phone,
            name: clientName || null,
            status: 'linked',
            linked_client_id: clientId,
          },
          { onConflict: 'phone_normalized' },
        );
      if (upsertErr) throw upsertErr;

      // Backfill client_id on all previous messages for this phone
      await supabase
        .from('whatsapp_messages')
        .update({ client_id: clientId })
        .eq('phone_normalized', phone)
        .is('client_id', null);
    },
    onSuccess: () => {
      toast.success('Conversa vinculada ao cliente.');
      qc.invalidateQueries({ queryKey: ['wa-conversations'] });
      qc.invalidateQueries({ queryKey: ['whatsapp-leads'] });
    },
    onError: (e: any) => toast.error(e?.message || 'Falha ao vincular conversa.'),
  });
}

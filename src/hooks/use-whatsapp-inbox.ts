import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

// Mirrors the webhook's normalizePhone for consistent matching of client phone fields.
// Strips non-digits, adds Brazil DDI (55) for 10-11 digit numbers.
function normalizePhoneFE(raw: string | null | undefined): string {
  if (!raw) return '';
  const digits = String(raw).replace(/\D/g, '');
  if (!digits) return '';
  if (digits.length === 10 || digits.length === 11) return `55${digits}`;
  return digits;
}

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
      // Two queries run in parallel:
      // 1. Inbound — determines which phones have conversations (primary anchor)
      // 2. All outbound — used to update preview/last_at for existing conversations
      //    AND to add new entries for fromMe (sent_by IS NULL) with a lead or client.
      //    ERP-sent outbound (sent_by IS NOT NULL) only updates preview, never adds new entries.
      const [inboundRes, outboundRes] = await Promise.all([
        supabase
          .from('whatsapp_messages')
          .select('phone_normalized, occurred_at, body, direction, client_id, lead_id, is_broadcast')
          .eq('direction', 'inbound')
          .order('occurred_at', { ascending: false })
          .limit(1000),
        supabase
          .from('whatsapp_messages')
          .select('phone_normalized, occurred_at, body, direction, client_id, lead_id, is_broadcast, sent_by')
          .eq('direction', 'outbound')
          .order('occurred_at', { ascending: false })
          .limit(500),
      ]);

      if (inboundRes.error) throw inboundRes.error;

      // Build map keyed by phone — last inbound per phone (for fallback preview)
      const map = new Map<string, any>();

      // Build conversation map from inbound (most recent per phone)
      for (const m of inboundRes.data || []) {
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

      // Process outbound messages
      for (const m of outboundRes.data || []) {
        if (map.has(m.phone_normalized)) {
          // Update preview for any phone already in the conversation list (inbound existed)
          const existing = map.get(m.phone_normalized)!;
          if (new Date(m.occurred_at) > new Date(existing.last_at)) {
            existing.last_at = m.occurred_at;
            existing.last_body = m.body;
            existing.last_direction = m.direction;
          }
        } else if (!m.sent_by && (m.client_id || m.lead_id)) {
          // New entry only for fromMe webhook messages (sent_by IS NULL) with a known contact
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
      // whatsapp_leads does NOT have a "name" column — only display_name.
      // linked_client_id references clients.id for manually confirmed links.
      const [{ data: clients }, { data: leads }] = await Promise.all([
        supabase.from('clients').select('id, name, phone, whatsapp').eq('active', true),
        supabase
          .from('whatsapp_leads')
          .select('phone_normalized, display_name, status, unread_count, assigned_to, linked_client_id')
          .in('phone_normalized', phones),
      ]);

      // Map by normalized phone for clients (using same DDI-aware normalization as webhook)
      const clientByPhone = new Map<string, any>();
      for (const c of clients || []) {
        const wa = normalizePhoneFE(c.whatsapp);
        const ph = normalizePhoneFE(c.phone);
        if (wa) clientByPhone.set(wa, c);
        if (ph && !clientByPhone.has(ph)) clientByPhone.set(ph, c);
      }

      // Map by ID for direct FK lookups
      const clientById = new Map<string, any>();
      for (const c of clients || []) clientById.set(c.id, c);

      const leadByPhone = new Map<string, any>();
      for (const l of leads || []) leadByPhone.set(l.phone_normalized, l);

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
            // Best available display name (confirmed links only, not suggestions)
            name: effectiveClient?.name || lead?.display_name || null,
            // Unconfirmed client match found by phone normalization
            suggested_client: suggestedClient,
          };
        })
        .sort((a, b) => new Date(b.last_at).getTime() - new Date(a.last_at).getTime());
    },
    refetchInterval: 15000,
  });
}

export function useMarkConversationRead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (phone: string) => {
      const cleaned = phone.replace(/\D/g, '');
      // Silently no-ops if no lead exists for this phone (unknown conversation)
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
          display_name: displayName || null,
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
            display_name: clientName || null,
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

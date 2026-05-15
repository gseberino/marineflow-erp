import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/hooks/use-auth';

export interface WhatsAppUnreadInfo {
  count: number;
  lastMessageAt: string | null;
  lastReadAt: string | null;
}

/**
 * Conta mensagens INBOUND criadas após `last_read_at` do usuário atual.
 * Atualiza em tempo real via Supabase channel.
 */
export function useWhatsAppUnread(): WhatsAppUnreadInfo & { markAllRead: () => Promise<void> } {
  const { user } = useAuth();
  const qc = useQueryClient();
  const [lastReadAt, setLastReadAt] = useState<string | null>(null);
  const [count, setCount] = useState(0);
  const [lastMessageAt, setLastMessageAt] = useState<string | null>(null);

  // Carrega last_read_at
  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('whatsapp_read_state')
        .select('last_read_at')
        .eq('user_id', user.id)
        .maybeSingle();
      if (cancelled) return;
      setLastReadAt(data?.last_read_at || null);
    })();
    return () => { cancelled = true; };
  }, [user]);

  // Conta mensagens não lidas
  const refreshCount = useCallback(async () => {
    if (!user) return;
    let q = supabase
      .from('whatsapp_messages')
      .select('id, occurred_at', { count: 'exact', head: false })
      .eq('direction', 'inbound')
      .order('occurred_at', { ascending: false })
      .limit(1);
    if (lastReadAt) q = q.gt('occurred_at', lastReadAt);
    const { data, count: c } = await q;
    setCount(c || 0);
    setLastMessageAt(data?.[0]?.occurred_at || null);
  }, [user, lastReadAt]);

  useEffect(() => { refreshCount(); }, [refreshCount]);

  // Realtime subscription
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel('whatsapp-unread')
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'whatsapp_messages' },
        (payload: any) => {
          const dir = payload?.new?.direction;
          // Bell counter only increments for inbound messages
          if (dir === 'inbound') {
            refreshCount();
            qc.invalidateQueries({ queryKey: ['whatsapp-leads'] });
          }
          // Conversations and message thread refresh for any new message,
          // including outbound replies and fromMe (physical phone) messages.
          qc.invalidateQueries({ queryKey: ['whatsapp-messages'] });
          qc.invalidateQueries({ queryKey: ['wa-conversations'] });
        })
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'whatsapp_leads' },
        () => qc.invalidateQueries({ queryKey: ['whatsapp-leads'] }))
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user, refreshCount, qc]);

  const markAllRead = useCallback(async () => {
    if (!user) return;
    const now = new Date().toISOString();
    await supabase
      .from('whatsapp_read_state')
      .upsert({ user_id: user.id, last_read_at: now }, { onConflict: 'user_id' });
    setLastReadAt(now);
    setCount(0);
  }, [user]);

  return { count, lastMessageAt, lastReadAt, markAllRead };
}

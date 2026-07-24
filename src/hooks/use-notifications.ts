import { useQuery } from '@tanstack/react-query';
import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/use-auth';

export type NotificationType =
  | 'OVERDUE_RECEIVABLE'
  | 'LOW_STOCK'
  | 'OS_UPCOMING'
  | 'OS_STALE'
  | 'QUOTE_APPROVED'
  | 'QUOTE_REJECTED'
  | 'TASK_REMINDER'
  | 'TASK_ASSIGNED';

export interface AppNotification {
  id: string;
  type: NotificationType;
  title: string;
  description: string;
  created_at: string;
  navigate_to: string;
}

const READ_KEY = 'notifications:read';

function getReadIds(): Set<string> {
  try {
    const raw = localStorage.getItem(READ_KEY);
    if (!raw) return new Set();
    return new Set(JSON.parse(raw) as string[]);
  } catch {
    return new Set();
  }
}

function saveReadIds(ids: Set<string>) {
  localStorage.setItem(READ_KEY, JSON.stringify(Array.from(ids)));
}

async function generateNotifications(userId: string, role: string): Promise<AppNotification[]> {
  const notifications: AppNotification[] = [];
  const now = Date.now();
  const today = new Date().toISOString().split('T')[0];
  const tomorrow = new Date(now + 86400000).toISOString().split('T')[0];
  const fiveDaysAgo = new Date(now - 5 * 86400000).toISOString().split('T')[0];
  const threeDaysAgo = new Date(now - 3 * 86400000).toISOString().split('T')[0];

  const fmtCurrency = (v: number) =>
    new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v || 0);

  const isExternal = role === 'external_seller';
  const isAdmin = role === 'admin';
  const isFinancial = role === 'financial';
  const isStaff = ['admin', 'financial', 'technician', 'seller'].includes(role);

  // 1) Quote status changes (Only for external seller or admin)
  if (isExternal || isAdmin) {
    const { data: quotes } = await supabase
      .from('external_quotes')
      .select('id, quote_number, status, updated_at, lead:external_quote_leads(name)')
      .eq('created_by', userId)
      .in('status', ['approved', 'cancelled'])
      .order('updated_at', { ascending: false })
      .limit(10);

    (quotes || []).forEach((q: any) => {
      const isApproved = q.status === 'approved';
      notifications.push({
        id: `quote:${q.id}:${q.status}`,
        type: isApproved ? 'QUOTE_APPROVED' : 'QUOTE_REJECTED',
        title: isApproved ? 'Orçamento Aprovado' : 'Orçamento Reprovado',
        description: `${q.quote_number} — ${q.lead?.name ?? 'Cliente'}`,
        created_at: q.updated_at,
        navigate_to: `/external-quotes/${q.id}`,
      });
    });
  }

  // 2) Overdue receivables (Financial/Admin)
  if (isAdmin || isFinancial) {
    const { data: overdue } = await supabase
      .from('receivables')
      .select('id, balance_amount, due_date, clients(name)')
      .not('status', 'in', '("paid","cancelled")')
      .lt('due_date', threeDaysAgo)
      .limit(5);

    (overdue || []).forEach((r: any) => {
      notifications.push({
        id: `overdue:${r.id}`,
        type: 'OVERDUE_RECEIVABLE',
        title: 'Recebível em atraso',
        description: `${fmtCurrency(Number(r.balance_amount || 0))} — ${r.clients?.name ?? 'Cliente'}`,
        created_at: r.due_date,
        navigate_to: '/financial?tab=receivables',
      });
    });
  }

  // 3) Low stock (Staff - mostly Admin/Financial/Inventory)
  if (isAdmin || isFinancial) {
    const { data: products } = await supabase
      .from('products')
      .select('id, name, stock_quantity, minimum_stock')
      .eq('active', true)
      .gt('minimum_stock', 0)
      .limit(20);

    (products || [])
      .filter((p: any) => (p.stock_quantity || 0) < (p.minimum_stock || 0))
      .forEach((p: any) => {
        notifications.push({
          id: `lowstock:${p.id}`,
          type: 'LOW_STOCK',
          title: 'Estoque baixo',
          description: `${p.name} (${p.stock_quantity || 0}/${p.minimum_stock})`,
          created_at: new Date().toISOString(),
          navigate_to: '/inventory',
        });
      });
  }

  // 4) Upcoming OS (Internal Staff only)
  if (isStaff && !isExternal) {
    const { data: upcoming } = await supabase
      .from('service_orders')
      .select('id, service_order_number, scheduled_start_at, clients(name)')
      .in('status', ['scheduled', 'open'])
      .gte('scheduled_start_at', today)
      .lte('scheduled_start_at', tomorrow + 'T23:59:59')
      .limit(5);

    (upcoming || []).forEach((o: any) => {
      const dt = o.scheduled_start_at ? new Date(o.scheduled_start_at) : null;
      const timeStr = dt
        ? dt.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
        : '';
      notifications.push({
        id: `upcoming:${o.id}`,
        type: 'OS_UPCOMING',
        title: 'OS agendada',
        description: `${o.service_order_number} — ${o.clients?.name ?? ''} às ${timeStr}`,
        created_at: o.scheduled_start_at || new Date().toISOString(),
        navigate_to: `/service-orders/${o.id}`,
      });
    });
  }

  notifications.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  return notifications.slice(0, 20);
}

export function useNotifications() {
  const { user } = useAuth();

  const query = useQuery({
    queryKey: ['notifications', user?.id, user?.role],
    queryFn: () => generateNotifications(user?.id ?? '', user?.role ?? ''),
    enabled: !!user,
    refetchInterval: 5 * 60 * 1000,
  });

  // Notificações PERSISTENTES (app_notifications — lembretes de tarefa etc.).
  // Estado de leitura vive no banco (read_at), não no localStorage.
  const dbQuery = useQuery({
    queryKey: ['app-notifications', user?.id],
    enabled: !!user,
    refetchInterval: 60 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('app_notifications')
        .select('id, type, title, body, navigate_to, read_at, created_at')
        .order('created_at', { ascending: false })
        .limit(30);
      if (error) return [];
      return data || [];
    },
  });

  // Realtime: novo lembrete aparece no sino sem esperar o polling
  useEffect(() => {
    if (!user?.id) return;
    const channel = supabase
      .channel('app-notifications-bell')
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'app_notifications', filter: `user_id=eq.${user.id}` },
        () => { dbQuery.refetch(); })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  const [readIds, setReadIds] = useState<Set<string>>(() => getReadIds());

  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === READ_KEY) setReadIds(getReadIds());
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const markAsRead = useCallback((id: string) => {
    if (id.startsWith('db:')) {
      supabase.from('app_notifications')
        .update({ read_at: new Date().toISOString() })
        .eq('id', id.slice(3))
        .then(() => dbQuery.refetch());
      return;
    }
    setReadIds(prev => {
      const next = new Set(prev);
      next.add(id);
      saveReadIds(next);
      return next;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const dbItems: AppNotification[] = (dbQuery.data || []).map((n: any) => ({
    id: `db:${n.id}`,
    type: (n.type === 'task_reminder' ? 'TASK_REMINDER'
      : n.type === 'task_assigned' ? 'TASK_ASSIGNED'
      : 'TASK_REMINDER') as NotificationType,
    title: n.title,
    description: n.body || '',
    created_at: n.created_at,
    navigate_to: n.navigate_to || '/agenda',
  }));
  const dbUnread = new Set(
    (dbQuery.data || []).filter((n: any) => !n.read_at).map((n: any) => `db:${n.id}`),
  );

  const markAllAsRead = useCallback(() => {
    const all = new Set(readIds);
    (query.data || []).forEach(n => all.add(n.id));
    saveReadIds(all);
    setReadIds(all);
    if (dbUnread.size > 0) {
      supabase.from('app_notifications')
        .update({ read_at: new Date().toISOString() })
        .is('read_at', null)
        .then(() => dbQuery.refetch());
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query.data, readIds, dbUnread.size]);

  const items = [...dbItems, ...(query.data || [])]
    .sort((a, b) => (a.created_at < b.created_at ? 1 : -1))
    .slice(0, 30);
  const unreadCount = items.filter(n =>
    n.id.startsWith('db:') ? dbUnread.has(n.id) : !readIds.has(n.id)).length;

  return {
    notifications: items,
    unreadCount,
    isLoading: query.isLoading,
    isRead: (id: string) => (id.startsWith('db:') ? !dbUnread.has(id) : readIds.has(id)),
    markAsRead,
    markAllAsRead,
  };
}

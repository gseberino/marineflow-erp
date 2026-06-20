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
  | 'QUOTE_REJECTED';

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

  const [readIds, setReadIds] = useState<Set<string>>(() => getReadIds());

  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === READ_KEY) setReadIds(getReadIds());
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const markAsRead = useCallback((id: string) => {
    setReadIds(prev => {
      const next = new Set(prev);
      next.add(id);
      saveReadIds(next);
      return next;
    });
  }, []);

  const markAllAsRead = useCallback(() => {
    const all = new Set(readIds);
    (query.data || []).forEach(n => all.add(n.id));
    saveReadIds(all);
    setReadIds(all);
  }, [query.data, readIds]);

  const items = query.data || [];
  const unreadCount = items.filter(n => !readIds.has(n.id)).length;

  return {
    notifications: items,
    unreadCount,
    isLoading: query.isLoading,
    isRead: (id: string) => readIds.has(id),
    markAsRead,
    markAllAsRead,
  };
}

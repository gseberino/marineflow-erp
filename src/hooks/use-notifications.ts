import { useQuery } from '@tanstack/react-query';
import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';

export type NotificationType = 'OVERDUE_RECEIVABLE' | 'LOW_STOCK' | 'OS_UPCOMING' | 'OS_STALE';

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

async function generateNotifications(): Promise<AppNotification[]> {
  const notifications: AppNotification[] = [];
  const now = Date.now();
  const today = new Date().toISOString().split('T')[0];
  const tomorrow = new Date(now + 86400000).toISOString().split('T')[0];
  const threeDaysAgo = new Date(now - 3 * 86400000).toISOString().split('T')[0];
  const fiveDaysAgo = new Date(now - 5 * 86400000).toISOString().split('T')[0];

  const fmtCurrency = (v: number) =>
    new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v || 0);

  // 1) Overdue receivables
  const { data: overdue } = await supabase
    .from('receivables')
    .select('id, balance_amount, due_date, clients(full_name_or_company_name)')
    .not('status', 'in', '("paid","cancelled")')
    .lt('due_date', threeDaysAgo)
    .limit(5);

  (overdue || []).forEach((r: any) => {
    notifications.push({
      id: `overdue:${r.id}`,
      type: 'OVERDUE_RECEIVABLE',
      title: 'Recebível em atraso',
      description: `${fmtCurrency(Number(r.balance_amount || 0))} — ${r.clients?.full_name_or_company_name ?? 'Cliente'}`,
      created_at: r.due_date,
      navigate_to: '/financial?tab=receivables',
    });
  });

  // 2) Low stock
  const { data: products } = await supabase
    .from('products')
    .select('id, product_name, stock_quantity, minimum_stock')
    .eq('active', true)
    .gt('minimum_stock', 0)
    .limit(50);

  (products || [])
    .filter((p: any) => (p.stock_quantity || 0) < (p.minimum_stock || 0))
    .slice(0, 10)
    .forEach((p: any) => {
      notifications.push({
        id: `lowstock:${p.id}`,
        type: 'LOW_STOCK',
        title: 'Estoque baixo',
        description: `${p.product_name} (${p.stock_quantity || 0}/${p.minimum_stock})`,
        created_at: new Date().toISOString(),
        navigate_to: '/inventory',
      });
    });

  // 3) Upcoming OS (next 24h)
  const { data: upcoming } = await supabase
    .from('service_orders')
    .select('id, service_order_number, scheduled_start_at, clients(full_name_or_company_name)')
    .in('status', ['scheduled', 'open'])
    .gte('scheduled_start_at', today)
    .lte('scheduled_start_at', tomorrow + 'T23:59:59')
    .limit(5);

  (upcoming || []).forEach((o: any) => {
    const dt = o.scheduled_start_at ? new Date(o.scheduled_start_at) : null;
    const timeStr = dt
      ? dt.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
      : '';
    const dayLabel = dt && dt.toISOString().split('T')[0] === today ? 'hoje' : 'amanhã';
    notifications.push({
      id: `upcoming:${o.id}`,
      type: 'OS_UPCOMING',
      title: 'OS agendada',
      description: `${o.service_order_number} — ${o.clients?.full_name_or_company_name ?? ''} — ${dayLabel} às ${timeStr}`,
      created_at: o.scheduled_start_at || new Date().toISOString(),
      navigate_to: `/service-orders/${o.id}`,
    });
  });

  // 4) Stale OS (no update > 5 days)
  const { data: stale } = await supabase
    .from('service_orders')
    .select('id, service_order_number, updated_at, clients(full_name_or_company_name)')
    .in('status', ['open', 'in_progress'])
    .lt('updated_at', fiveDaysAgo + 'T00:00:00')
    .limit(5);

  (stale || []).forEach((o: any) => {
    const days = Math.floor((now - new Date(o.updated_at).getTime()) / 86400000);
    notifications.push({
      id: `stale:${o.id}`,
      type: 'OS_STALE',
      title: 'OS parada',
      description: `${o.service_order_number} sem atualização há ${days} dias`,
      created_at: o.updated_at,
      navigate_to: `/service-orders/${o.id}`,
    });
  });

  notifications.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  return notifications.slice(0, 20);
}

export function useNotifications() {
  const query = useQuery({
    queryKey: ['notifications'],
    queryFn: generateNotifications,
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

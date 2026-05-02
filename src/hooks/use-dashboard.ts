import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export function useDashboardData() {
  const today = new Date().toISOString().split('T')[0];
  const firstOfMonth = `${today.substring(0, 7)}-01`;
  const firstOfLastMonth = (() => {
    const d = new Date();
    d.setMonth(d.getMonth() - 1);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
  })();
  const lastOfLastMonth = (() => {
    const d = new Date();
    d.setDate(0);
    return d.toISOString().split('T')[0];
  })();
  const in7days = new Date(Date.now() + 7 * 86400000).toISOString().split('T')[0];

  return useQuery({
    queryKey: ['dashboard'],
    queryFn: async () => {
      const [
        receivablesRes,
        payablesRes,
        collectedThisMonthRes,
        collectedLastMonthRes,
        overdueReceivablesRes,
        openOrdersRes,
        ordersByStatusRes,
        completedThisMonthRes,
        upcomingOrdersRes,
        revenueChartRes,
      ] = await Promise.all([
        supabase.from('receivables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")'),

        supabase.from('payables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")'),

        supabase.from('payments')
          .select('amount')
          .not('receivable_id', 'is', null)
          .eq('status', 'confirmed')
          .gte('payment_date', firstOfMonth),

        supabase.from('payments')
          .select('amount')
          .not('receivable_id', 'is', null)
          .eq('status', 'confirmed')
          .gte('payment_date', firstOfLastMonth)
          .lte('payment_date', lastOfLastMonth),

        supabase.from('receivables')
          .select('balance_amount')
          .not('status', 'in', '("paid","cancelled")')
          .lt('due_date', today),

        supabase.from('service_orders')
          .select('id, service_order_number, status, grand_total, scheduled_start_at, clients(full_name_or_company_name), vessels(boat_name)')
          .not('status', 'in', '("completed","invoiced","cancelled")')
          .order('created_at', { ascending: false })
          .limit(8),

        supabase.from('service_orders')
          .select('status')
          .not('status', 'in', '("cancelled")'),

        supabase.from('service_orders')
          .select('grand_total')
          .in('status', ['completed', 'invoiced'])
          .gte('updated_at', firstOfMonth),

        supabase.from('service_orders')
          .select('id, service_order_number, scheduled_start_at, clients(full_name_or_company_name), vessels(boat_name), status')
          .in('status', ['scheduled', 'open'])
          .gte('scheduled_start_at', today)
          .lte('scheduled_start_at', in7days)
          .order('scheduled_start_at', { ascending: true })
          .limit(5),

        supabase.from('payments')
          .select('payment_date, amount')
          .not('receivable_id', 'is', null)
          .eq('status', 'confirmed')
          .gte('payment_date', (() => {
            const d = new Date();
            d.setMonth(d.getMonth() - 5);
            return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
          })())
          .order('payment_date', { ascending: true }),
      ]);

      // Low stock (separate query since we need JS filter for column comparison)
      const lowStockRes = await supabase
        .from('products')
        .select('id, product_name, stock_quantity, minimum_stock, category')
        .eq('active', true)
        .gt('minimum_stock', 0)
        .order('product_name')
        .limit(50);

      const lowStock = (lowStockRes.data || [])
        .filter(p => (p.stock_quantity ?? 0) < (p.minimum_stock ?? 0))
        .slice(0, 5);

      // Process revenue chart data
      const monthNames = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      const now = new Date();
      const revenueByMonth: Record<string, number> = {};
      for (let i = 5; i >= 0; i--) {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        revenueByMonth[key] = 0;
      }
      for (const p of revenueChartRes.data || []) {
        const key = p.payment_date.substring(0, 7);
        if (revenueByMonth[key] !== undefined) {
          revenueByMonth[key] += Number(p.amount);
        }
      }
      const revenueChart = Object.entries(revenueByMonth).map(([key, value]) => {
        const [, m] = key.split('-');
        return {
          month: `${monthNames[parseInt(m) - 1]}/${key.slice(2, 4)}`,
          revenue: Math.round(value * 100) / 100,
        };
      });

      // Process status counts
      const statusCounts: Record<string, number> = {};
      for (const so of ordersByStatusRes.data || []) {
        statusCounts[so.status] = (statusCounts[so.status] || 0) + 1;
      }

      // Sum helpers
      const sum = (rows: any[] | null, field = 'balance_amount') =>
        (rows || []).reduce((s: number, r: any) => s + Number(r[field] || 0), 0);

      const collectedThisMonth = sum(collectedThisMonthRes.data, 'amount');
      const collectedLastMonth = sum(collectedLastMonthRes.data, 'amount');
      const revenueGrowth = collectedLastMonth > 0
        ? Math.round(((collectedThisMonth - collectedLastMonth) / collectedLastMonth) * 100)
        : null;

      return {
        totalReceivable: sum(receivablesRes.data),
        totalPayable: sum(payablesRes.data),
        collectedThisMonth,
        collectedLastMonth,
        revenueGrowth,
        overdueReceivables: sum(overdueReceivablesRes.data),

        openOrders: openOrdersRes.data || [],
        openOrdersCount: (openOrdersRes.data || []).length,
        statusCounts,
        completedThisMonth: completedThisMonthRes.data?.length || 0,
        completedThisMonthValue: sum(completedThisMonthRes.data || [], 'grand_total'),
        upcomingOrders: upcomingOrdersRes.data || [],

        revenueChart,
        lowStock,
      };
    },
    staleTime: 60 * 1000,
    refetchInterval: 5 * 60 * 1000,
  });
}

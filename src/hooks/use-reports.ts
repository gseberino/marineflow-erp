import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

function daysAgo(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString();
}

// ============ TAB 1: REVENUE ============
export function useRevenueReport(periodDays: number) {
  return useQuery({
    queryKey: ['reports', 'revenue', periodDays],
    queryFn: async () => {
      const since = daysAgo(periodDays);

      const [paymentsRes, ordersRes, partsRes] = await Promise.all([
        supabase
          .from('payments')
          .select('amount, payment_date, status, receivable_id')
          .eq('status', 'confirmed')
          .gte('payment_date', since.slice(0, 10)),
        supabase
          .from('service_orders')
          .select('id, grand_total, parts_cost_total, status, payment_status, client_id, created_at, clients(full_name_or_company_name)')
          .gte('created_at', since),
        supabase
          .from('service_order_parts')
          .select('line_total_cost, service_order_id, service_orders!inner(created_at)')
          .gte('service_orders.created_at', since),
      ]);

      if (paymentsRes.error) throw paymentsRes.error;
      if (ordersRes.error) throw ordersRes.error;
      if (partsRes.error) throw partsRes.error;

      const payments = paymentsRes.data ?? [];
      const orders = ordersRes.data ?? [];
      const parts = partsRes.data ?? [];

      const totalReceived = payments.reduce((s, p) => s + Number(p.amount || 0), 0);
      const completedOrders = orders.filter(o => o.status === 'completed' || o.status === 'invoiced');
      const avgTicket = completedOrders.length
        ? completedOrders.reduce((s, o) => s + Number(o.grand_total || 0), 0) / completedOrders.length
        : 0;
      const invoicedCount = orders.filter(o => o.status === 'invoiced' || o.payment_status === 'paid').length;
      const totalRevenue = orders.reduce((s, o) => s + Number(o.grand_total || 0), 0);
      const totalPartsCost = parts.reduce((s, p) => s + Number(p.line_total_cost || 0), 0);
      const margin = totalRevenue - totalPartsCost;

      // Revenue by month (last 6 months) — based on payments
      const monthMap = new Map<string, number>();
      for (let i = 5; i >= 0; i--) {
        const d = new Date();
        d.setMonth(d.getMonth() - i);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        monthMap.set(key, 0);
      }
      const sixMonthsAgo = new Date();
      sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 5);
      sixMonthsAgo.setDate(1);

      const { data: allPayments } = await supabase
        .from('payments')
        .select('amount, payment_date, status')
        .eq('status', 'confirmed')
        .gte('payment_date', sixMonthsAgo.toISOString().slice(0, 10));

      (allPayments ?? []).forEach(p => {
        const key = String(p.payment_date).slice(0, 7);
        if (monthMap.has(key)) {
          monthMap.set(key, (monthMap.get(key) ?? 0) + Number(p.amount || 0));
        }
      });
      const monthlyRevenue = Array.from(monthMap.entries()).map(([month, value]) => {
        const [, m] = month.split('-');
        const monthNames = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
        return { month: monthNames[Number(m) - 1], value };
      });

      // Top 10 clients
      const clientMap = new Map<string, { name: string; revenue: number }>();
      orders.forEach(o => {
        const name = (o.clients as any)?.full_name_or_company_name ?? '—';
        const cur = clientMap.get(o.client_id) ?? { name, revenue: 0 };
        cur.revenue += Number(o.grand_total || 0);
        clientMap.set(o.client_id, cur);
      });
      const topClients = Array.from(clientMap.values())
        .sort((a, b) => b.revenue - a.revenue)
        .slice(0, 10);

      return { totalReceived, avgTicket, invoicedCount, margin, monthlyRevenue, topClients };
    },
  });
}

// ============ TAB 2: OS PERFORMANCE ============
export function useOsPerformanceReport() {
  return useQuery({
    queryKey: ['reports', 'os-performance'],
    queryFn: async () => {
      const { data: orders, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, scheduled_start_at, scheduled_end_at, check_out_at, created_at, updated_at, clients(full_name_or_company_name)');
      if (error) throw error;

      const all = orders ?? [];
      const open = all.filter(o => !['completed', 'invoiced', 'cancelled'].includes(o.status));
      const completed = all.filter(o => o.status === 'completed' || o.status === 'invoiced');

      // Avg completion time (scheduled_start → check_out_at)
      const completionTimes = completed
        .filter(o => o.scheduled_start_at && o.check_out_at)
        .map(o => (new Date(o.check_out_at!).getTime() - new Date(o.scheduled_start_at!).getTime()) / (1000 * 60 * 60));
      const avgCompletionHours = completionTimes.length
        ? completionTimes.reduce((s, h) => s + h, 0) / completionTimes.length
        : 0;

      // Conversion: drafts → approved (anything not draft/cancelled)
      const drafts = all.filter(o => o.status === 'draft').length;
      const approved = all.filter(o => !['draft', 'cancelled'].includes(o.status)).length;
      const totalQuotes = drafts + approved;
      const conversionRate = totalQuotes > 0 ? (approved / totalQuotes) * 100 : 0;

      // Overdue
      const today = new Date().toISOString();
      const overdue = all.filter(
        o => o.scheduled_end_at && o.scheduled_end_at < today && !['completed', 'invoiced', 'cancelled'].includes(o.status),
      );

      // Status distribution
      const statusMap = new Map<string, number>();
      all.forEach(o => statusMap.set(o.status, (statusMap.get(o.status) ?? 0) + 1));
      const statusDistribution = Array.from(statusMap.entries()).map(([name, value]) => ({ name, value }));

      // Stale (open > 7 days no update)
      const sevenDaysAgo = new Date();
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
      const staleOrders = open
        .filter(o => new Date(o.updated_at) < sevenDaysAgo)
        .map(o => ({
          id: o.id,
          number: o.service_order_number,
          client: (o.clients as any)?.full_name_or_company_name ?? '—',
          status: o.status,
          last_update: o.updated_at,
          days_since: Math.floor((Date.now() - new Date(o.updated_at).getTime()) / (1000 * 60 * 60 * 24)),
        }))
        .sort((a, b) => b.days_since - a.days_since);

      return {
        openCount: open.length,
        completedCount: completed.length,
        avgCompletionHours,
        conversionRate,
        overdueCount: overdue.length,
        statusDistribution,
        staleOrders,
      };
    },
  });
}

// ============ TAB 3: PARTS USAGE ============
export function usePartsUsageReport(periodDays: number) {
  return useQuery({
    queryKey: ['reports', 'parts-usage', periodDays],
    queryFn: async () => {
      const since = daysAgo(periodDays);

      const { data, error } = await supabase
        .from('service_order_parts')
        .select('product_id, quantity, line_total_sale, unit_sale_snapshot, created_at, products(product_name)')
        .gte('created_at', since);
      if (error) throw error;

      const map = new Map<string, { name: string; qty: number; revenue: number; prices: number[] }>();
      (data ?? []).forEach(p => {
        const name = (p.products as any)?.product_name ?? '—';
        const cur = map.get(p.product_id) ?? { name, qty: 0, revenue: 0, prices: [] };
        cur.qty += Number(p.quantity || 0);
        cur.revenue += Number(p.line_total_sale || 0);
        cur.prices.push(Number(p.unit_sale_snapshot || 0));
        map.set(p.product_id, cur);
      });

      const rows = Array.from(map.values())
        .map(r => ({
          name: r.name,
          qty: r.qty,
          revenue: r.revenue,
          avg_price: r.prices.length ? r.prices.reduce((s, x) => s + x, 0) / r.prices.length : 0,
        }))
        .sort((a, b) => b.qty - a.qty);

      return { rows: rows.slice(0, 20), top10: rows.slice(0, 10) };
    },
  });
}

// ============ TAB 4: TECHNICIAN PRODUCTIVITY ============
export function useTechnicianProductivityReport() {
  return useQuery({
    queryKey: ['reports', 'tech-productivity'],
    queryFn: async () => {
      const [techsRes, assignsRes, timesRes, profitabilityRes] = await Promise.all([
        supabase.from('app_users').select('id, full_name, role').eq('role', 'technician'),
        supabase.from('service_order_technicians').select('user_id, service_order_id'),
        supabase.from('time_entries').select('technician_user_id, duration_minutes, billable'),
        supabase.from('vw_os_profitability').select('os_id, status, revenue, net_profit').in('status', ['completed', 'invoiced']),
      ]);

      if (techsRes.error) throw techsRes.error;
      if (assignsRes.error) throw assignsRes.error;
      if (timesRes.error) throw timesRes.error;
      if (profitabilityRes.error) throw profitabilityRes.error;

      const techs = techsRes.data ?? [];
      const assigns = assignsRes.data ?? [];
      const times = timesRes.data ?? [];
      const profitabilityData = profitabilityRes.data ?? [];
      
      const profitMap = new Map(profitabilityData.map(o => [o.os_id, { revenue: Number(o.revenue || 0), profit: Number(o.net_profit || 0) }]));
      const completedIds = new Set(profitabilityData.map(o => o.os_id));

      const rows = techs.map(t => {
        const myAssigns = assigns.filter(a => a.user_id === t.id && completedIds.has(a.service_order_id));
        const osCount = myAssigns.length;
        const totalMinutes = times
          .filter(te => te.technician_user_id === t.id)
          .reduce((s, te) => s + Number(te.duration_minutes || 0), 0);
        const totalHours = totalMinutes / 60;
        
        const revenue = myAssigns.reduce((s, a) => s + (profitMap.get(a.service_order_id)?.revenue ?? 0), 0);
        const profit = myAssigns.reduce((s, a) => s + (profitMap.get(a.service_order_id)?.profit ?? 0), 0);

        return {
          name: t.full_name,
          os_count: osCount,
          hours: Math.round(totalHours * 10) / 10,
          avg_per_os: osCount > 0 ? Math.round((totalHours / osCount) * 10) / 10 : 0,
          revenue,
          profit,
        };
      }).sort((a, b) => b.os_count - a.os_count);

      return { rows };
    },
  });
}

// ============ TAB 5: PROFITABILITY ============
export function useProfitabilityReport() {
  return useQuery({
    queryKey: ['reports', 'profitability'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('vw_os_profitability')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;

      const all = data ?? [];
      const completed = all.filter(o => o.status === 'completed' || o.status === 'invoiced');
      
      const totalRevenue = completed.reduce((s, o) => s + Number(o.revenue || 0), 0);
      const totalNetProfit = completed.reduce((s, o) => s + Number(o.net_profit || 0), 0);
      const avgMargin = completed.length 
        ? completed.reduce((s, o) => s + Number(o.net_margin_percent || 0), 0) / completed.length 
        : 0;

      // Top 10 most profitable OS
      const topOS = [...completed]
        .sort((a, b) => b.net_profit - a.net_profit)
        .slice(0, 10);

      // Monthly profit trend (last 6 months)
      const monthMap = new Map<string, { revenue: number; profit: number }>();
      for (let i = 5; i >= 0; i--) {
        const d = new Date();
        d.setMonth(d.getMonth() - i);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        monthMap.set(key, { revenue: 0, profit: 0 });
      }

      completed.forEach(o => {
        const key = String(o.created_at).slice(0, 7);
        if (monthMap.has(key)) {
          const cur = monthMap.get(key)!;
          cur.revenue += Number(o.revenue || 0);
          cur.profit += Number(o.net_profit || 0);
          monthMap.set(key, cur);
        }
      });

      const trend = Array.from(monthMap.entries()).map(([month, val]) => {
        const [, m] = month.split('-');
        const monthNames = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
        return { 
          name: monthNames[Number(m) - 1], 
          revenue: val.revenue, 
          profit: val.profit 
        };
      });

      return { totalRevenue, totalNetProfit, avgMargin, topOS, trend };
    },
  });
}

import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { serviceOrders, clients, vessels, marinas, receivables, payables, users, getClient, getVessel } from '@/data/mock-data';
import { DollarSign, TrendingUp, TrendingDown, ClipboardList, AlertTriangle, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';

export default function Dashboard() {
  const { t, formatCurrency } = useI18n();

  const revenueThisMonth = serviceOrders
    .filter(so => so.payment_status === 'paid')
    .reduce((s, so) => s + so.grand_total, 0);

  const expensesThisMonth = payables.reduce((s, p) => s + p.amount, 0);
  const openOrders = serviceOrders.filter(so => !['completed', 'invoiced', 'cancelled'].includes(so.status)).length;
  const pendingReceivables = receivables.filter(r => r.status !== 'paid' && r.status !== 'cancelled').reduce((s, r) => s + r.balance_amount, 0);
  const pendingPayables = payables.filter(p => p.status !== 'paid' && p.status !== 'cancelled').reduce((s, p) => s + p.balance_amount, 0);
  const scheduledToday = serviceOrders.filter(so => so.scheduled_start_at?.startsWith('2026-04-07')).length;

  const statusDistribution = Object.entries(
    serviceOrders.reduce((acc, so) => { acc[so.status] = (acc[so.status] || 0) + 1; return acc; }, {} as Record<string, number>)
  ).map(([name, value]) => ({ name: (t.status as Record<string, string>)[name] || name, value }));

  const COLORS = ['hsl(210,60%,25%)', 'hsl(174,60%,35%)', 'hsl(38,92%,50%)', 'hsl(152,60%,40%)', 'hsl(0,72%,51%)', 'hsl(215,12%,50%)'];

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.dashboard.title} description={t.dashboard.description} />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title={t.dashboard.revenueMonth.replace('{month}', t.months.apr)} value={formatCurrency(revenueThisMonth)} icon={TrendingUp} />
        <KPICard title={t.dashboard.expensesMonth.replace('{month}', t.months.apr)} value={formatCurrency(expensesThisMonth)} icon={TrendingDown} />
        <KPICard title={t.dashboard.grossProfit} value={formatCurrency(revenueThisMonth - expensesThisMonth)} icon={DollarSign} />
        <KPICard title={t.dashboard.openOrders} value={String(openOrders)} icon={ClipboardList} subtitle={t.dashboard.scheduledToday.replace('{count}', String(scheduledToday))} />
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title={t.dashboard.pendingReceivables} value={formatCurrency(pendingReceivables)} icon={AlertTriangle} />
        <KPICard title={t.dashboard.pendingPayables} value={formatCurrency(pendingPayables)} icon={AlertTriangle} />
        <KPICard title={t.dashboard.activeTechnicians} value={String(users.filter(u => u.role === 'technician' && u.active).length)} icon={Users} />
        <KPICard title={t.dashboard.activeClients} value={String(clients.filter(c => c.active).length)} icon={Users} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Status Distribution */}
        <div className="lg:col-span-2 rounded-xl border bg-card p-5 shadow-sm">
          <h3 className="text-sm font-semibold mb-4">{t.dashboard.orderStatus}</h3>
          {statusDistribution.length > 0 ? (
            <>
              <ResponsiveContainer width="100%" height={240}>
                <PieChart>
                  <Pie data={statusDistribution} cx="50%" cy="50%" innerRadius={50} outerRadius={80} paddingAngle={4} dataKey="value">
                    {statusDistribution.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
              <div className="mt-2 flex flex-wrap gap-2">
                {statusDistribution.map((item, i) => (
                  <div key={item.name} className="flex items-center gap-1.5 text-xs">
                    <div className="h-2 w-2 rounded-full" style={{ backgroundColor: COLORS[i % COLORS.length] }} />
                    <span className="text-muted-foreground">{item.name} ({item.value})</span>
                  </div>
                ))}
              </div>
            </>
          ) : (
            <p className="text-sm text-muted-foreground py-12 text-center">{t.dashboard.noDataYet}</p>
          )}
        </div>

        {/* Recent Service Orders */}
        <div className="rounded-xl border bg-card shadow-sm">
          <div className="flex items-center justify-between p-5 border-b">
            <h3 className="text-sm font-semibold">{t.dashboard.recentServiceOrders}</h3>
            <Link to="/service-orders" className="text-xs font-medium text-accent hover:underline">{t.common.viewAll} →</Link>
          </div>
          <div className="divide-y">
            {serviceOrders.slice(0, 5).map(so => {
              const client = getClient(so.client_id);
              const statusLabel = (t.status as Record<string, string>)[so.status] || so.status;
              return (
                <Link key={so.id} to={`/service-orders/${so.id}`} className="block p-4 hover:bg-muted/30 transition-colors">
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium text-accent">{so.service_order_number}</span>
                    <span className="text-xs font-medium">{formatCurrency(so.grand_total)}</span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-1">{client?.full_name_or_company_name}</p>
                  <p className="text-xs text-muted-foreground">{statusLabel}</p>
                </Link>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

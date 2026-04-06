import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { StatusBadge } from '@/components/StatusBadge';
import { formatCurrency, formatDate, statusConfig, priorityConfig, serviceTypeLabels } from '@/lib/constants';
import { serviceOrders, clients, vessels, marinas, receivables, payables, users, getClient, getVessel, getMarina } from '@/data/mock-data';
import { DollarSign, TrendingUp, TrendingDown, ClipboardList, CalendarDays, Clock, AlertTriangle, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';

const revenueThisMonth = 3020 + 816.50;
const expensesThisMonth = payables.reduce((s, p) => s + p.amount, 0);
const openOrders = serviceOrders.filter(so => !['completed', 'invoiced', 'cancelled'].includes(so.status)).length;
const pendingReceivables = receivables.filter(r => r.status !== 'paid' && r.status !== 'cancelled').reduce((s, r) => s + r.balance_amount, 0);
const pendingPayables = payables.filter(p => p.status !== 'paid' && p.status !== 'cancelled').reduce((s, p) => s + p.balance_amount, 0);
const scheduledToday = serviceOrders.filter(so => so.scheduled_start_at?.startsWith('2026-04-07')).length;

const statusDistribution = Object.entries(
  serviceOrders.reduce((acc, so) => { acc[so.status] = (acc[so.status] || 0) + 1; return acc; }, {} as Record<string, number>)
).map(([name, value]) => ({ name: statusConfig[name as keyof typeof statusConfig]?.label || name, value }));

const COLORS = ['hsl(210,60%,25%)', 'hsl(174,60%,35%)', 'hsl(38,92%,50%)', 'hsl(152,60%,40%)', 'hsl(0,72%,51%)', 'hsl(215,12%,50%)'];

const revenueByMonth = [
  { month: 'Jan', revenue: 8500 }, { month: 'Feb', revenue: 12300 }, { month: 'Mar', revenue: 15800 },
  { month: 'Apr', revenue: revenueThisMonth },
];

export default function Dashboard() {
  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Dashboard" description="Overview of your nautical service operations" />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title="Revenue (Apr)" value={formatCurrency(revenueThisMonth)} icon={TrendingUp} trend={{ value: '12% vs Mar', positive: true }} />
        <KPICard title="Expenses (Apr)" value={formatCurrency(expensesThisMonth)} icon={TrendingDown} />
        <KPICard title="Gross Profit" value={formatCurrency(revenueThisMonth - expensesThisMonth)} icon={DollarSign} />
        <KPICard title="Open Orders" value={String(openOrders)} icon={ClipboardList} subtitle={`${scheduledToday} scheduled today`} />
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title="Pending Receivables" value={formatCurrency(pendingReceivables)} icon={AlertTriangle} />
        <KPICard title="Pending Payables" value={formatCurrency(pendingPayables)} icon={AlertTriangle} />
        <KPICard title="Active Technicians" value={String(users.filter(u => u.role === 'technician' && u.active).length)} icon={Users} />
        <KPICard title="Active Clients" value={String(clients.filter(c => c.active).length)} icon={Users} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Revenue Chart */}
        <div className="lg:col-span-2 rounded-xl border bg-card p-5 shadow-sm">
          <h3 className="text-sm font-semibold mb-4">Revenue Trend</h3>
          <ResponsiveContainer width="100%" height={240}>
            <BarChart data={revenueByMonth}>
              <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
              <XAxis dataKey="month" className="text-xs" />
              <YAxis className="text-xs" />
              <Tooltip formatter={(v: number) => formatCurrency(v)} />
              <Bar dataKey="revenue" fill="hsl(174,60%,35%)" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        {/* Status Distribution */}
        <div className="rounded-xl border bg-card p-5 shadow-sm">
          <h3 className="text-sm font-semibold mb-4">Order Status</h3>
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
        </div>
      </div>

      {/* Recent Service Orders */}
      <div className="rounded-xl border bg-card shadow-sm">
        <div className="flex items-center justify-between p-5 border-b">
          <h3 className="text-sm font-semibold">Recent Service Orders</h3>
          <Link to="/service-orders" className="text-xs font-medium text-accent hover:underline">View all →</Link>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Order #</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Client</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Vessel</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Priority</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Type</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">Total</th>
              </tr>
            </thead>
            <tbody>
              {serviceOrders.slice(0, 6).map(so => {
                const client = getClient(so.client_id);
                const vessel = getVessel(so.vessel_id);
                const sc = statusConfig[so.status];
                const pc = priorityConfig[so.priority];
                return (
                  <tr key={so.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                    <td className="px-4 py-3">
                      <Link to={`/service-orders/${so.id}`} className="font-medium text-accent hover:underline">{so.service_order_number}</Link>
                    </td>
                    <td className="px-4 py-3">{client?.full_name_or_company_name}</td>
                    <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{vessel?.boat_name}</td>
                    <td className="px-4 py-3"><StatusBadge className={sc.className}>{sc.label}</StatusBadge></td>
                    <td className="px-4 py-3 hidden lg:table-cell"><span className={pc.className}>{pc.label}</span></td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{serviceTypeLabels[so.service_type]}</td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(so.grand_total)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

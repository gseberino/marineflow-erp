import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { formatCurrency } from '@/lib/constants';
import { serviceOrders, users, timeEntries, products, serviceOrderParts } from '@/data/mock-data';
import { BarChart3, Clock, Wrench, DollarSign, Users, Package } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';

const totalRevenue = serviceOrders.filter(so => so.payment_status === 'paid').reduce((s, so) => s + so.grand_total, 0);
const avgOrderValue = serviceOrders.length > 0 ? serviceOrders.reduce((s, so) => s + so.grand_total, 0) / serviceOrders.length : 0;
const totalBillableHours = timeEntries.filter(t => t.billable).reduce((s, t) => s + t.duration_minutes, 0) / 60;

// Service type distribution
const serviceTypeData = Object.entries(
  serviceOrders.reduce((acc, so) => { acc[so.service_type] = (acc[so.service_type] || 0) + 1; return acc; }, {} as Record<string, number>)
).map(([name, value]) => ({ name: name.replace('_', ' '), value }));

// Technician productivity
const techData = users.filter(u => u.role === 'technician').map(u => {
  const hours = timeEntries.filter(t => t.technician_user_id === u.id).reduce((s, t) => s + t.duration_minutes, 0) / 60;
  return { name: u.full_name.split(' ')[0], hours: Math.round(hours * 10) / 10 };
});

// Top parts
const partUsage = serviceOrderParts.reduce((acc, p) => {
  const product = products.find(pr => pr.id === p.product_id);
  if (product) {
    const key = product.product_name.substring(0, 30);
    acc[key] = (acc[key] || 0) + p.quantity;
  }
  return acc;
}, {} as Record<string, number>);
const topParts = Object.entries(partUsage).sort((a, b) => b[1] - a[1]).map(([name, qty]) => ({ name, qty }));

const COLORS = ['hsl(210,60%,25%)', 'hsl(174,60%,35%)', 'hsl(38,92%,50%)', 'hsl(152,60%,40%)', 'hsl(0,72%,51%)', 'hsl(215,12%,50%)', 'hsl(280,50%,45%)'];

export default function ReportsPage() {
  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Reports" description="Analytics and performance insights" />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title="Collected Revenue" value={formatCurrency(totalRevenue)} icon={DollarSign} />
        <KPICard title="Avg Order Value" value={formatCurrency(avgOrderValue)} icon={BarChart3} />
        <KPICard title="Billable Hours" value={`${totalBillableHours.toFixed(1)}h`} icon={Clock} />
        <KPICard title="Total Orders" value={String(serviceOrders.length)} icon={Wrench} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="rounded-xl border bg-card p-5 shadow-sm">
          <h3 className="text-sm font-semibold mb-4">Technician Hours</h3>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={techData} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
              <XAxis type="number" className="text-xs" />
              <YAxis type="category" dataKey="name" className="text-xs" width={70} />
              <Tooltip />
              <Bar dataKey="hours" fill="hsl(174,60%,35%)" radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="rounded-xl border bg-card p-5 shadow-sm">
          <h3 className="text-sm font-semibold mb-4">Service Type Distribution</h3>
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie data={serviceTypeData} cx="50%" cy="50%" outerRadius={80} dataKey="value" label={({ name, value }) => `${name} (${value})`}>
                {serviceTypeData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
              </Pie>
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="rounded-xl border bg-card p-5 shadow-sm">
        <h3 className="text-sm font-semibold mb-4">Most Used Parts</h3>
        <div className="space-y-3">
          {topParts.map((p, i) => (
            <div key={p.name} className="flex items-center gap-3">
              <span className="text-xs text-muted-foreground w-6">{i + 1}.</span>
              <div className="flex-1">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-sm font-medium">{p.name}</span>
                  <span className="text-sm text-muted-foreground">{p.qty} units</span>
                </div>
                <div className="h-1.5 rounded-full bg-muted overflow-hidden">
                  <div className="h-full rounded-full bg-accent" style={{ width: `${(p.qty / Math.max(...topParts.map(x => x.qty))) * 100}%` }} />
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

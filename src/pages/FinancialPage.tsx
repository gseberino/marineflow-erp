import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { StatusBadge } from '@/components/StatusBadge';
import { receivables, payables, getClient } from '@/data/mock-data';
import { formatCurrency, formatDate, paymentStatusConfig } from '@/lib/constants';
import { DollarSign, TrendingUp, TrendingDown, AlertTriangle } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

const totalReceivable = receivables.reduce((s, r) => s + r.amount, 0);
const totalPending = receivables.filter(r => r.status !== 'paid').reduce((s, r) => s + r.balance_amount, 0);
const totalPayable = payables.reduce((s, p) => s + p.amount, 0);
const totalPayablePending = payables.filter(p => p.status !== 'paid').reduce((s, p) => s + p.balance_amount, 0);
const overdue = receivables.filter(r => r.status === 'overdue').reduce((s, r) => s + r.balance_amount, 0);

const cashFlowData = [
  { month: 'Jan', inflow: 8500, outflow: 5200 },
  { month: 'Feb', inflow: 12300, outflow: 7800 },
  { month: 'Mar', inflow: 15800, outflow: 9100 },
  { month: 'Apr', inflow: 3836.50, outflow: 8850 },
];

export default function FinancialPage() {
  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title="Financial" description="Receivables, payables, and cash flow" />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title="Total Receivables" value={formatCurrency(totalReceivable)} icon={TrendingUp} />
        <KPICard title="Pending Collection" value={formatCurrency(totalPending)} icon={DollarSign} />
        <KPICard title="Overdue" value={formatCurrency(overdue)} icon={AlertTriangle} />
        <KPICard title="Pending Payables" value={formatCurrency(totalPayablePending)} icon={TrendingDown} />
      </div>

      <div className="rounded-xl border bg-card p-5 shadow-sm">
        <h3 className="text-sm font-semibold mb-4">Cash Flow</h3>
        <ResponsiveContainer width="100%" height={260}>
          <BarChart data={cashFlowData}>
            <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
            <XAxis dataKey="month" className="text-xs" />
            <YAxis className="text-xs" />
            <Tooltip formatter={(v: number) => formatCurrency(v)} />
            <Bar dataKey="inflow" fill="hsl(152,60%,40%)" radius={[4, 4, 0, 0]} name="Inflow" />
            <Bar dataKey="outflow" fill="hsl(0,72%,51%)" radius={[4, 4, 0, 0]} name="Outflow" />
          </BarChart>
        </ResponsiveContainer>
      </div>

      <Tabs defaultValue="receivables">
        <TabsList><TabsTrigger value="receivables">Receivables</TabsTrigger><TabsTrigger value="payables">Payables</TabsTrigger></TabsList>

        <TabsContent value="receivables" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Description</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Client</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Due Date</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">Amount</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">Balance</th>
              </tr></thead>
              <tbody>
                {receivables.map(r => {
                  const client = getClient(r.client_id);
                  const sc = paymentStatusConfig[r.status];
                  return (
                    <tr key={r.id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="px-4 py-3 font-medium">{r.description}</td>
                      <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{client?.full_name_or_company_name}</td>
                      <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{formatDate(r.due_date)}</td>
                      <td className="px-4 py-3"><StatusBadge className={sc?.className}>{sc?.label}</StatusBadge></td>
                      <td className="px-4 py-3 text-right font-medium">{formatCurrency(r.amount)}</td>
                      <td className="px-4 py-3 text-right hidden md:table-cell font-semibold">{formatCurrency(r.balance_amount)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </TabsContent>

        <TabsContent value="payables" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Description</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Category</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Due Date</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">Amount</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">Balance</th>
              </tr></thead>
              <tbody>
                {payables.map(p => {
                  const sc = paymentStatusConfig[p.status];
                  return (
                    <tr key={p.id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="px-4 py-3 font-medium">{p.description}</td>
                      <td className="px-4 py-3 hidden md:table-cell"><StatusBadge className="bg-secondary text-secondary-foreground">{p.expense_category}</StatusBadge></td>
                      <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{formatDate(p.due_date)}</td>
                      <td className="px-4 py-3"><StatusBadge className={sc?.className}>{sc?.label}</StatusBadge></td>
                      <td className="px-4 py-3 text-right font-medium">{formatCurrency(p.amount)}</td>
                      <td className="px-4 py-3 text-right hidden md:table-cell font-semibold">{formatCurrency(p.balance_amount)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

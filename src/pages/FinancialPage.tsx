import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { receivables, payables, getClient } from '@/data/mock-data';
import { DollarSign, TrendingUp, TrendingDown, AlertTriangle } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

export default function FinancialPage() {
  const { t, formatCurrency, formatDate } = useI18n();

  const totalReceivable = receivables.reduce((s, r) => s + r.amount, 0);
  const totalPending = receivables.filter(r => r.status !== 'paid').reduce((s, r) => s + r.balance_amount, 0);
  const totalPayablePending = payables.filter(p => p.status !== 'paid').reduce((s, p) => s + p.balance_amount, 0);
  const overdue = receivables.filter(r => r.status === 'overdue').reduce((s, r) => s + r.balance_amount, 0);

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.financial.title} description={t.financial.description} />

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard title={t.financial.totalReceivables} value={formatCurrency(totalReceivable)} icon={TrendingUp} />
        <KPICard title={t.financial.pendingCollection} value={formatCurrency(totalPending)} icon={DollarSign} />
        <KPICard title={t.financial.overdue} value={formatCurrency(overdue)} icon={AlertTriangle} />
        <KPICard title={t.financial.pendingPayables} value={formatCurrency(totalPayablePending)} icon={TrendingDown} />
      </div>

      <Tabs defaultValue="receivables">
        <TabsList>
          <TabsTrigger value="receivables">{t.financial.receivables}</TabsTrigger>
          <TabsTrigger value="payables">{t.financial.payables}</TabsTrigger>
        </TabsList>

        <TabsContent value="receivables" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.serviceOrders.client}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.financial.dueDate}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">{t.common.balance}</th>
              </tr></thead>
              <tbody>
                {receivables.map(r => {
                  const client = getClient(r.client_id);
                  return (
                    <tr key={r.id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="px-4 py-3 font-medium">{r.description}</td>
                      <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{client?.full_name_or_company_name}</td>
                      <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{formatDate(r.due_date)}</td>
                      <td className="px-4 py-3"><StatusBadge className={r.status === 'paid' ? 'bg-success/15 text-success' : r.status === 'overdue' ? 'bg-destructive/10 text-destructive' : 'bg-warning/15 text-warning'}>{(t.paymentStatus as Record<string, string>)[r.status]}</StatusBadge></td>
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
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.products.category}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.financial.dueDate}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">{t.common.balance}</th>
              </tr></thead>
              <tbody>
                {payables.map(p => (
                  <tr key={p.id} className="border-b last:border-0 hover:bg-muted/30">
                    <td className="px-4 py-3 font-medium">{p.description}</td>
                    <td className="px-4 py-3 hidden md:table-cell"><StatusBadge className="bg-secondary text-secondary-foreground">{p.expense_category}</StatusBadge></td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{formatDate(p.due_date)}</td>
                    <td className="px-4 py-3"><StatusBadge className={p.status === 'paid' ? 'bg-success/15 text-success' : p.status === 'overdue' ? 'bg-destructive/10 text-destructive' : 'bg-warning/15 text-warning'}>{(t.paymentStatus as Record<string, string>)[p.status]}</StatusBadge></td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(p.amount)}</td>
                    <td className="px-4 py-3 text-right hidden md:table-cell font-semibold">{formatCurrency(p.balance_amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

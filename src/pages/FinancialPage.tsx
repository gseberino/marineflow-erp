import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { DollarSign, TrendingUp, TrendingDown, AlertTriangle, ArrowUpCircle, ArrowDownCircle, Plus } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { useReceivables, usePayables, useFinancialSummary, useCashFlow } from '@/hooks/use-financial';
import { usePendingReimbursements } from '@/hooks/use-service-order-expenses';
import { PaymentDialog } from '@/components/PaymentDialog';
import { ReceivableFormDialog } from '@/components/ReceivableFormDialog';
import { PayableFormDialog } from '@/components/PayableFormDialog';
import { BankReconciliation } from '@/components/BankReconciliation';
import { ReimbursementsPanel } from '@/components/ReimbursementsPanel';
import { ResponsiveContainer, ComposedChart, Bar, Line, XAxis, YAxis, CartesianGrid, Tooltip } from 'recharts';

function getStatusBadgeClass(status: string, dueDate: string) {
  const isOverdue = status !== 'paid' && status !== 'cancelled' && new Date(dueDate) < new Date();
  if (isOverdue) return 'bg-destructive/10 text-destructive';
  if (status === 'paid') return 'bg-success/15 text-success';
  if (status === 'partially_paid') return 'bg-warning/15 text-warning';
  return 'bg-secondary text-secondary-foreground';
}

function getDisplayStatus(status: string, dueDate: string, t: any): string {
  const isOverdue = status !== 'paid' && status !== 'cancelled' && new Date(dueDate) < new Date();
  if (isOverdue) return (t.paymentStatus as Record<string, string>).overdue || 'Em Atraso';
  return (t.paymentStatus as Record<string, string>)[status] || status;
}

export default function FinancialPage() {
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: receivables, isLoading: loadingRec } = useReceivables();
  const { data: payables, isLoading: loadingPay } = usePayables();
  const { data: summary, isLoading: loadingSummary } = useFinancialSummary();
  const [cfMonths, setCfMonths] = useState(6);
  const { data: cashFlow } = useCashFlow(cfMonths);

  const [paymentTarget, setPaymentTarget] = useState<{ receivable?: any; payable?: any } | null>(null);
  const [showNewReceivable, setShowNewReceivable] = useState(false);
  const [showNewPayable, setShowNewPayable] = useState(false);
  const [recFilter, setRecFilter] = useState('all');
  const [payFilter, setPayFilter] = useState('all');
  const [recSearch, setRecSearch] = useState('');
  const [paySearch, setPaySearch] = useState('');
  const [paySubTab, setPaySubTab] = useState<'list' | 'reimbursements'>('list');
  const { data: pendingReimb } = usePendingReimbursements();

  const filterStatuses = ['all', 'pending', 'partially_paid', 'paid', 'overdue'] as const;

  const filteredReceivables = (receivables || []).filter(r => {
    const isOverdue = r.status !== 'paid' && r.status !== 'cancelled' && new Date(r.due_date) < new Date();
    const effectiveStatus = isOverdue ? 'overdue' : r.status;
    if (recFilter !== 'all' && effectiveStatus !== recFilter) return false;
    if (recSearch) {
      const s = recSearch.toLowerCase();
      return r.description.toLowerCase().includes(s) || ((r as any).clients?.full_name_or_company_name || '').toLowerCase().includes(s);
    }
    return true;
  });

  const filteredPayables = (payables || []).filter(p => {
    const isOverdue = p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) < new Date();
    const effectiveStatus = isOverdue ? 'overdue' : p.status;
    if (payFilter !== 'all' && effectiveStatus !== payFilter) return false;
    if (paySearch) {
      const s = paySearch.toLowerCase();
      return p.description.toLowerCase().includes(s) || (p.supplier_name || '').toLowerCase().includes(s);
    }
    return true;
  });

  const today = new Date();
  const in30 = new Date(today.getTime() + 30 * 86400000);
  const upcomingRec = (receivables || []).filter(r => r.status !== 'paid' && r.status !== 'cancelled' && new Date(r.due_date) <= in30).slice(0, 5);
  const upcomingPay = (payables || []).filter(p => p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) <= in30).slice(0, 5);

  const periodBalance = (cashFlow || []).reduce((s, m) => s + m.net, 0);

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.financial.title} description={t.financial.description} />

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">{t.financial.tabOverview}</TabsTrigger>
          <TabsTrigger value="receivables">{t.financial.tabReceivables}</TabsTrigger>
          <TabsTrigger value="payables">{t.financial.tabPayables}</TabsTrigger>
          <TabsTrigger value="reconciliation">{t.financial.tabReconciliation}</TabsTrigger>
        </TabsList>

        {/* === OVERVIEW === */}
        <TabsContent value="overview" className="mt-4 space-y-6">
          {loadingSummary ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">{[...Array(4)].map((_, i) => <Skeleton key={i} className="h-28 rounded-xl" />)}</div>
          ) : (
            <>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <KPICard title={t.financial.totalReceivables} value={formatCurrency(summary?.total_receivable || 0)} icon={TrendingUp} />
                <KPICard title={t.financial.overdue} value={formatCurrency(summary?.overdue_receivable || 0)} icon={AlertTriangle} className={summary?.overdue_receivable ? 'border-destructive/30' : ''} />
                <KPICard title={t.financial.pendingPayables} value={formatCurrency(summary?.total_payable || 0)} icon={TrendingDown} />
                <KPICard title={`${t.financial.overdue} (${t.financial.payables})`} value={formatCurrency(summary?.overdue_payable || 0)} icon={AlertTriangle} className={summary?.overdue_payable ? 'border-destructive/30' : ''} />
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <KPICard title={t.financial.collectedThisMonth} value={formatCurrency(summary?.collected_this_month || 0)} icon={ArrowUpCircle} />
                <KPICard title={t.financial.paidThisMonth} value={formatCurrency(summary?.paid_this_month || 0)} icon={ArrowDownCircle} />
              </div>
            </>
          )}

          {/* Cash Flow Chart */}
          <div className="rounded-xl border bg-card p-5 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold">{t.financial.cashFlowChart}</h3>
              <div className="flex gap-1">
                {[3, 6, 12].map(m => (
                  <Button key={m} size="sm" variant={cfMonths === m ? 'default' : 'outline'} onClick={() => setCfMonths(m)}>
                    {(t.financial as any)[`last${m}months`]}
                  </Button>
                ))}
              </div>
            </div>
            {cashFlow && cashFlow.length > 0 ? (
              <>
                <ResponsiveContainer width="100%" height={300}>
                  <ComposedChart data={cashFlow}>
                    <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
                    <XAxis dataKey="month" className="text-xs" />
                    <YAxis className="text-xs" tickFormatter={v => formatCurrency(v)} width={90} />
                    <Tooltip formatter={(v: number) => formatCurrency(v)} />
                    <Bar dataKey="inflow" name={t.financial.inflow} fill="hsl(var(--success))" radius={[4, 4, 0, 0]} />
                    <Bar dataKey="outflow" name={t.financial.outflow} fill="hsl(var(--destructive))" radius={[4, 4, 0, 0]} />
                    <Line dataKey="net" name={t.financial.netBalance} stroke="hsl(var(--primary))" strokeWidth={2} dot />
                  </ComposedChart>
                </ResponsiveContainer>
                <p className="text-sm mt-2">
                  {t.financial.periodBalance}: <span className={`font-bold ${periodBalance >= 0 ? 'text-success' : 'text-destructive'}`}>{formatCurrency(periodBalance)}</span>
                </p>
              </>
            ) : (
              <p className="text-sm text-muted-foreground py-8 text-center">{t.common.noResults}</p>
            )}
          </div>

          {/* Upcoming */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="font-semibold mb-3">{t.financial.upcomingReceivables}</h3>
              {upcomingRec.length === 0 ? <p className="text-sm text-muted-foreground">{t.common.noResults}</p> : (
                <div className="space-y-2">
                  {upcomingRec.map(r => (
                    <div key={r.id} className="flex items-center justify-between text-sm border-b pb-2">
                      <div>
                        <p className="font-medium">{(r as any).clients?.full_name_or_company_name}</p>
                        <p className="text-xs text-muted-foreground">{formatDate(r.due_date)}</p>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold">{formatCurrency(Number(r.balance_amount))}</span>
                        <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ receivable: r })}>
                          {t.financial.registerPayment}
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
            <div className="rounded-xl border bg-card p-5 shadow-sm">
              <h3 className="font-semibold mb-3">{t.financial.upcomingPayables}</h3>
              {upcomingPay.length === 0 ? <p className="text-sm text-muted-foreground">{t.common.noResults}</p> : (
                <div className="space-y-2">
                  {upcomingPay.map(p => (
                    <div key={p.id} className="flex items-center justify-between text-sm border-b pb-2">
                      <div>
                        <p className="font-medium">{p.description}</p>
                        <p className="text-xs text-muted-foreground">{formatDate(p.due_date)}</p>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold">{formatCurrency(Number(p.balance_amount))}</span>
                        <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ payable: p })}>
                          {t.financial.registerPayment}
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </TabsContent>

        {/* === RECEIVABLES === */}
        <TabsContent value="receivables" className="mt-4 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-lg">{t.financial.receivables}</h3>
            <Button onClick={() => setShowNewReceivable(true)}><Plus className="h-4 w-4 mr-1" />{t.financial.newReceivable}</Button>
          </div>
          <div className="flex flex-wrap gap-2">
            {filterStatuses.map(s => (
              <Button key={s} size="sm" variant={recFilter === s ? 'default' : 'outline'}
                onClick={() => setRecFilter(s)}>
                {s === 'all' ? t.common.all : (t.paymentStatus as Record<string, string>)[s] || s}
              </Button>
            ))}
            <Input placeholder={t.common.search} className="max-w-xs ml-auto" value={recSearch} onChange={e => setRecSearch(e.target.value)} />
          </div>

          {loadingRec ? <Skeleton className="h-64 rounded-xl" /> : (
            <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
              <table className="w-full text-sm">
                <thead><tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.financial.dueDate}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.serviceOrders.client}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">OS</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">{t.common.balance}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.actions}</th>
                </tr></thead>
                <tbody>
                  {filteredReceivables.length === 0 ? (
                    <tr><td colSpan={8} className="text-center py-8 text-muted-foreground">{t.common.noResults}</td></tr>
                  ) : filteredReceivables.map(r => {
                    const isOverdue = r.status !== 'paid' && r.status !== 'cancelled' && new Date(r.due_date) < new Date();
                    return (
                      <tr key={r.id} className={`border-b last:border-0 hover:bg-muted/30 ${isOverdue ? 'bg-destructive/5' : ''}`}>
                        <td className="px-4 py-3 text-muted-foreground">{formatDate(r.due_date)}</td>
                        <td className="px-4 py-3 hidden md:table-cell">{(r as any).clients?.full_name_or_company_name}</td>
                        <td className="px-4 py-3 font-medium">{r.description}</td>
                        <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{(r as any).service_orders?.service_order_number || '—'}</td>
                        <td className="px-4 py-3 text-right font-medium">{formatCurrency(Number(r.amount))}</td>
                        <td className="px-4 py-3 text-right hidden md:table-cell font-semibold">{formatCurrency(Number(r.balance_amount))}</td>
                        <td className="px-4 py-3"><StatusBadge className={getStatusBadgeClass(r.status || 'pending', r.due_date)}>{getDisplayStatus(r.status || 'pending', r.due_date, t)}</StatusBadge></td>
                        <td className="px-4 py-3 text-right">
                          {r.status !== 'paid' && (
                            <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ receivable: r })}>
                              {t.financial.registerPayment}
                            </Button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </TabsContent>

        {/* === PAYABLES === */}
        <TabsContent value="payables" className="mt-4 space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <h3 className="font-semibold text-lg">{t.financial.payables}</h3>
              <div className="flex gap-1 ml-4">
                <Button size="sm" variant={paySubTab === 'list' ? 'default' : 'outline'} onClick={() => setPaySubTab('list')}>
                  {t.financial.payables}
                </Button>
                <Button size="sm" variant={paySubTab === 'reimbursements' ? 'default' : 'outline'} onClick={() => setPaySubTab('reimbursements')}>
                  {t.financial.pendingReimbursements} ({pendingReimb?.length || 0})
                </Button>
              </div>
            </div>
            <Button onClick={() => setShowNewPayable(true)}><Plus className="h-4 w-4 mr-1" />{t.financial.newPayable}</Button>
          </div>

          {paySubTab === 'reimbursements' ? (
            <ReimbursementsPanel />
          ) : (
          <>
          <div className="flex flex-wrap gap-2">
            {filterStatuses.map(s => (
              <Button key={s} size="sm" variant={payFilter === s ? 'default' : 'outline'}
                onClick={() => setPayFilter(s)}>
                {s === 'all' ? t.common.all : (t.paymentStatus as Record<string, string>)[s] || s}
              </Button>
            ))}
            <Input placeholder={t.common.search} className="max-w-xs ml-auto" value={paySearch} onChange={e => setPaySearch(e.target.value)} />
          </div>

          {loadingPay ? <Skeleton className="h-64 rounded-xl" /> : (
            <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
              <table className="w-full text-sm">
                <thead><tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.financial.dueDate}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.suppliers.title}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.products.category}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">{t.common.balance}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.actions}</th>
                </tr></thead>
                <tbody>
                  {filteredPayables.length === 0 ? (
                    <tr><td colSpan={8} className="text-center py-8 text-muted-foreground">{t.common.noResults}</td></tr>
                  ) : filteredPayables.map(p => {
                    const isOverdue = p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) < new Date();
                    return (
                      <tr key={p.id} className={`border-b last:border-0 hover:bg-muted/30 ${isOverdue ? 'bg-destructive/5' : ''}`}>
                        <td className="px-4 py-3 text-muted-foreground">{formatDate(p.due_date)}</td>
                        <td className="px-4 py-3 hidden md:table-cell">{(p as any).suppliers?.supplier_name || p.supplier_name || '—'}</td>
                        <td className="px-4 py-3 hidden lg:table-cell"><StatusBadge className="bg-secondary text-secondary-foreground">{p.expense_category || '—'}</StatusBadge></td>
                        <td className="px-4 py-3 font-medium">{p.description}</td>
                        <td className="px-4 py-3 text-right font-medium">{formatCurrency(Number(p.amount))}</td>
                        <td className="px-4 py-3 text-right hidden md:table-cell font-semibold">{formatCurrency(Number(p.balance_amount))}</td>
                        <td className="px-4 py-3"><StatusBadge className={getStatusBadgeClass(p.status || 'pending', p.due_date)}>{getDisplayStatus(p.status || 'pending', p.due_date, t)}</StatusBadge></td>
                        <td className="px-4 py-3 text-right">
                          {p.status !== 'paid' && (
                            <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ payable: p })}>
                              {t.financial.registerPayment}
                            </Button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
          </>
          )}
        </TabsContent>

        {/* === RECONCILIATION === */}
        <TabsContent value="reconciliation" className="mt-4">
          <BankReconciliation />
        </TabsContent>
      </Tabs>

      {/* Dialogs */}
      {paymentTarget && (
        <PaymentDialog
          open={!!paymentTarget}
          onOpenChange={() => setPaymentTarget(null)}
          receivable={paymentTarget.receivable}
          payable={paymentTarget.payable}
        />
      )}
      <ReceivableFormDialog open={showNewReceivable} onOpenChange={setShowNewReceivable} />
      <PayableFormDialog open={showNewPayable} onOpenChange={setShowNewPayable} />
    </div>
  );
}

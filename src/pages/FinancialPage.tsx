import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { DollarSign, TrendingUp, TrendingDown, AlertTriangle, ArrowUpCircle, ArrowDownCircle, Plus, Info, Receipt as ReceiptIcon, Paperclip, Download } from 'lucide-react';
import { exportToCSV } from '@/lib/export';
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
import { DREPanel } from '@/components/DREPanel';
import { FinancialFilterPanel, applyFilters, defaultFilters, type FinancialFilters } from '@/components/FinancialFilterPanel';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { ResponsiveContainer, ComposedChart, Bar, Line, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip } from 'recharts';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { generatePDF, DEFAULT_PDF_OPTIONS, type PDFData } from '@/lib/pdf-generator';
import { toast } from 'sonner';
import { BulkBillingReminderDialog } from '@/components/BulkBillingReminderDialog';
import { SendViaZAPIDialog, type SendViaZAPITarget } from '@/components/SendViaZAPIDialog';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { Send } from 'lucide-react';

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

function getDueDateAlert(dueDate: string, status: string): { label: string; className: string } | null {
  if (status === 'paid' || status === 'cancelled') return null;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const due = new Date(dueDate); due.setHours(0, 0, 0, 0);
  const diffDays = Math.round((due.getTime() - today.getTime()) / 86400000);
  if (diffDays < 0) return { label: `${Math.abs(diffDays)}d em atraso`, className: 'bg-destructive/10 text-destructive font-semibold' };
  if (diffDays === 0) return { label: 'Vence hoje', className: 'bg-destructive/15 text-destructive font-bold' };
  if (diffDays <= 3) return { label: `Vence em ${diffDays}d`, className: 'bg-warning/15 text-warning font-medium' };
  if (diffDays <= 7) return { label: `Vence em ${diffDays}d`, className: 'bg-amber-100 text-amber-700' };
  return null;
}

function getOriginBadge(origin: string | null): { label: string; className: string } {
  switch (origin) {
    case 'service_order_expense': return { label: 'Despesa de OS', className: 'bg-blue-100 text-blue-700' };
    case 'bank_reconciliation': return { label: 'Conciliação', className: 'bg-purple-100 text-purple-700' };
    default: return { label: 'Manual', className: 'bg-muted text-muted-foreground' };
  }
}

function groupPayables(payables: any[], groupBy: string) {
  if (groupBy === 'none') return { 'Todos': payables };

  if (groupBy === 'month') {
    const dates = payables.map(p => new Date(p.due_date));
    const minDate = dates.length > 0 ? new Date(Math.min(...dates.map(d => d.getTime()))) : new Date();
    const maxDate = dates.length > 0 ? new Date(Math.max(...dates.map(d => d.getTime()))) : new Date();
    const allMonths: string[] = [];
    const cursor = new Date(minDate.getFullYear(), minDate.getMonth(), 1);
    const end = new Date(maxDate.getFullYear(), maxDate.getMonth(), 1);
    while (cursor <= end) {
      allMonths.push(cursor.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }));
      cursor.setMonth(cursor.getMonth() + 1);
    }
    const result: Record<string, any[]> = {};
    allMonths.forEach(m => result[m] = []);
    payables.forEach(p => {
      const key = new Date(p.due_date).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
      if (result[key]) result[key].push(p);
      else result[key] = [p];
    });
    return result;
  }

  return payables.reduce((acc: Record<string, any[]>, p: any) => {
    let key = '';
    if (groupBy === 'category') key = p.expense_category || 'Sem categoria';
    if (groupBy === 'supplier') key = (p as any).suppliers?.supplier_name || p.supplier_name || 'Sem fornecedor';
    if (!acc[key]) acc[key] = [];
    acc[key].push(p);
    return acc;
  }, {} as Record<string, any[]>);
}

export default function FinancialPage() {
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const { data: receivables, isLoading: loadingRec, error: recError } = useReceivables();
  const { data: payables, isLoading: loadingPay, error: payError } = usePayables();
  const { data: summary, isLoading: loadingSummary, error: summaryError } = useFinancialSummary();
  const [cfMonths, setCfMonths] = useState(6);
  const { data: cashFlow } = useCashFlow(cfMonths);

  const [paymentTarget, setPaymentTarget] = useState<{ receivable?: any; payable?: any } | null>(null);
  const [showNewReceivable, setShowNewReceivable] = useState(false);
  const [showNewPayable, setShowNewPayable] = useState(false);
  const [zapiTarget, setZapiTarget] = useState<SendViaZAPITarget | null>(null);
  const [recFilters, setRecFilters] = useState<FinancialFilters>({ ...defaultFilters });
  const [payFilters, setPayFilters] = useState<FinancialFilters>({ ...defaultFilters });
  const [paySubTab, setPaySubTab] = useState<'list' | 'reimbursements'>('list');
  const [groupBy, setGroupBy] = useState<'none' | 'category' | 'supplier' | 'month'>('none');
  const { data: pendingReimb } = usePendingReimbursements();

  const filteredReceivables = applyFilters(receivables || [], recFilters, 'receivable');
  const filteredPayables = applyFilters(payables || [], payFilters, 'payable');

  const today = new Date();
  const in30 = new Date(today.getTime() + 30 * 86400000);
  const upcomingRec = (receivables || []).filter(r => r.status !== 'paid' && r.status !== 'cancelled' && new Date(r.due_date) <= in30).slice(0, 5);
  const upcomingPay = (payables || []).filter(p => p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) <= in30).slice(0, 5);
  const periodBalance = (cashFlow || []).reduce((s, m) => s + m.net, 0);

  const payTotalBalance = filteredPayables.filter(p => p.status !== 'paid' && p.status !== 'cancelled').reduce((s, p) => s + Number(p.balance_amount), 0);
  const payTotalPaid = filteredPayables.reduce((s, p) => s + Number(p.paid_amount), 0);

  const grouped = groupPayables(filteredPayables, groupBy);

  if (recError || payError || summaryError) {
    return (
      <div className="flex h-96 flex-col items-center justify-center gap-4 text-center">
        <p className="text-destructive font-medium">Erro ao carregar dados financeiros.</p>
        <p className="text-sm text-muted-foreground">
          {(recError || payError || summaryError)?.message || 'Verifique sua conexão e tente novamente.'}
        </p>
        <button
          onClick={() => window.location.reload()}
          className="rounded-md border px-4 py-2 text-sm hover:bg-muted transition-colors"
        >
          Recarregar página
        </button>
      </div>
    );
  }

  const handleGenerateReceipt = async (r: any) => {
    try {
      const { data: settingsRows } = await supabase.from('app_settings').select('key, value');
      const sm: Record<string, string> = {};
      for (const row of (settingsRows || []) as Array<{ key: string; value: string }>) {
        if (row.key) sm[row.key] = String(row.value || '');
      }
      const get = (k: string) => sm[k] || '';

      // Find latest confirmed payment for this receivable
      const { data: pays } = await supabase
        .from('payments')
        .select('*')
        .eq('receivable_id', r.id)
        .eq('status', 'confirmed')
        .order('payment_date', { ascending: false })
        .limit(1);
      const lastPay = (pays || [])[0];

      const amount = lastPay ? Number(lastPay.amount) : Number(r.paid_amount || 0);
      if (amount <= 0) {
        toast.error('Não há pagamento confirmado para gerar recibo');
        return;
      }

      const pdfData: PDFData = {
        documentType: 'receipt',
        company: {
          name: get('company_name') || 'MarineFlow',
          address: [get('address_line_1'), get('address_number')].filter(Boolean).join(', '),
          city: get('city'), state: get('state'), postal_code: get('postal_code'),
          phone: get('phone'), email: get('email'), cnpj: get('cnpj'),
        },
        bank: {
          bank_name: get('bank_name') || undefined,
          bank_agency: get('bank_agency') || undefined,
          bank_account: get('bank_account') || undefined,
          pix_key: get('pix_key') || undefined,
        },
        serviceOrder: {
          service_order_number: (r as any).service_orders?.service_order_number || r.description || r.id.slice(0, 8),
          status: r.status || 'paid', created_at: r.created_at || new Date().toISOString(),
          grand_total: amount, labor_cost_total: 0, parts_cost_total: 0,
          travel_cost_total: 0, discount_amount: 0, tax_amount: 0,
        },
        client: {
          name: (r as any).clients?.full_name_or_company_name || '—',
          cpf_cnpj: (r as any).clients?.cpf_cnpj ?? undefined,
          phone: (r as any).clients?.phone ?? undefined,
          email: (r as any).clients?.email ?? undefined,
        },
        services: [], parts: [],
        receipt: {
          amount,
          payment_date: lastPay?.payment_date || new Date().toISOString(),
          payment_method: lastPay?.payment_method || r.payment_method || 'pix',
          reference: (r as any).service_orders?.service_order_number || r.description,
          notes: lastPay?.notes || undefined,
        },
      };
      generatePDF(pdfData, { ...DEFAULT_PDF_OPTIONS });
    } catch (e: any) {
      toast.error(e.message || 'Erro ao gerar recibo');
    }
  };

  const renderPayableRow = (p: any) => {
    const isOverdue = p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) < new Date();
    const alert = getDueDateAlert(p.due_date, p.status || 'pending');
    const origin = getOriginBadge((p as any).origin);
    return (
      <tr key={p.id} className={`border-b last:border-0 hover:bg-muted/30 ${isOverdue ? 'bg-destructive/5' : ''}`}>
        <td className="px-4 py-3">
          <div className="text-muted-foreground">{formatDate(p.due_date)}</div>
          {alert && <StatusBadge className={`${alert.className} text-xs mt-1`}>{alert.label}</StatusBadge>}
        </td>
        <td className="px-4 py-3 hidden md:table-cell">{(p as any).suppliers?.supplier_name || p.supplier_name || '—'}</td>
        <td className="px-4 py-3 hidden lg:table-cell">
          {p.expense_category ? <StatusBadge className="bg-secondary text-secondary-foreground">{p.expense_category}</StatusBadge> : '—'}
        </td>
        <td className="px-4 py-3">
          <div className="font-medium truncate max-w-[200px]">{p.description}</div>
          {p.notes && (
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger><Info className="h-3 w-3 text-muted-foreground inline ml-1" /></TooltipTrigger>
                <TooltipContent><p className="max-w-xs">{p.notes}</p></TooltipContent>
              </Tooltip>
            </TooltipProvider>
          )}
        </td>
        <td className="px-4 py-3 hidden lg:table-cell">
          {(p as any).service_orders?.service_order_number ? (
            <button className="text-primary hover:underline text-sm" onClick={() => navigate(`/service-orders/${p.linked_service_order_id}`)}>
              {(p as any).service_orders.service_order_number}
            </button>
          ) : '—'}
        </td>
        <td className="px-4 py-3 text-center hidden lg:table-cell">
          {(() => {
            const soeReceipt = (p as any).service_order_expenses?.find?.((e: any) => e?.receipt_url)?.receipt_url;
            const url = soeReceipt || (p as any).receipt_url;
            if (!url) return <span className="text-muted-foreground">—</span>;
            return (
              <a href={url} target="_blank" rel="noopener noreferrer" className="text-primary inline-flex items-center justify-center hover:underline" title="Ver comprovante">
                <Paperclip className="h-4 w-4" />
              </a>
            );
          })()}
        </td>
        <td className="px-4 py-3 hidden xl:table-cell">
          <StatusBadge className={origin.className}>{origin.label}</StatusBadge>
        </td>
        <td className="px-4 py-3 text-right font-medium">{formatCurrency(Number(p.amount))}</td>
        <td className="px-4 py-3 text-right hidden md:table-cell">
          <span className={Number(p.paid_amount) > 0 ? 'text-success' : ''}>{formatCurrency(Number(p.paid_amount))}</span>
        </td>
        <td className="px-4 py-3 text-right hidden md:table-cell font-semibold">{formatCurrency(Number(p.balance_amount))}</td>
        <td className="px-4 py-3">
          <StatusBadge className={getStatusBadgeClass(p.status || 'pending', p.due_date)}>
            {getDisplayStatus(p.status || 'pending', p.due_date, t)}
          </StatusBadge>
        </td>
        <td className="px-4 py-3 text-right">
          {p.status !== 'paid' && (
            <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ payable: p })}>
              {t.financial.registerPayment}
            </Button>
          )}
        </td>
      </tr>
    );
  };

  const payableTableHead = (
    <thead><tr className="border-b bg-muted/50">
      <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.financial.dueDate}</th>
      <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.suppliers.title}</th>
      <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.products.category}</th>
      <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
      <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">OS</th>
      <th className="px-4 py-3 text-center font-medium text-muted-foreground hidden lg:table-cell">Comprovante</th>
      <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden xl:table-cell">Origem</th>
      <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.total}</th>
      <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">Pago</th>
      <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">{t.common.balance}</th>
      <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
      <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.actions}</th>
    </tr></thead>
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.financial.title} description={t.financial.description} />

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">{t.financial.tabOverview}</TabsTrigger>
          <TabsTrigger value="dre">DRE / Avançado</TabsTrigger>
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
                    <RechartsTooltip formatter={(v: number) => formatCurrency(v)} />
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

        {/* === DRE === */}
        <TabsContent value="dre" className="mt-4 space-y-4 animate-fade-in">
          <DREPanel />
        </TabsContent>

        {/* === RECEIVABLES === */}
        <TabsContent value="receivables" className="mt-4 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-lg">{t.financial.receivables}</h3>
            <Button onClick={() => setShowNewReceivable(true)}><Plus className="h-4 w-4 mr-1" />{t.financial.newReceivable}</Button>
          </div>
          <FinancialFilterPanel type="receivable" filters={recFilters} onChange={setRecFilters} />

          {loadingRec ? <Skeleton className="h-64 rounded-xl" /> : (
            <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
              <table className="w-full text-sm min-w-[900px]">
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
                        <td className="px-4 py-3 font-medium max-w-[180px] truncate">{r.description}</td>
                        <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{(r as any).service_orders?.service_order_number || '—'}</td>
                        <td className="px-4 py-3 text-right font-medium">{formatCurrency(Number(r.amount))}</td>
                        <td className="px-4 py-3 text-right hidden md:table-cell font-semibold">{formatCurrency(Number(r.balance_amount))}</td>
                        <td className="px-4 py-3"><StatusBadge className={getStatusBadgeClass(r.status || 'pending', r.due_date)}>{getDisplayStatus(r.status || 'pending', r.due_date, t)}</StatusBadge></td>
                        <td className="px-4 py-3 text-right">
                          <div className="flex justify-end gap-1">
                            {Number(r.paid_amount || 0) > 0 && (
                              <Button size="sm" variant="ghost" title="Gerar Recibo" onClick={() => handleGenerateReceipt(r)}>
                                <ReceiptIcon className="h-4 w-4 mr-1" /> Recibo
                              </Button>
                            )}
                            <Button
                              size="sm"
                              variant="ghost"
                              title="Enviar via Z-API (Recibo/Cobrança)"
                              onClick={() => {
                                const client = (r as any).clients;
                                const so = (r as any).service_orders;
                                const target: SendViaZAPITarget = {
                                  kind: 'receivable',
                                  receivableId: r.id,
                                  description: r.description,
                                  serviceOrderId: so?.id || null,
                                  shareToken: so?.share_token || null,
                                  clientId: client?.id || (r as any).client_id || null,
                                  clientName: client?.full_name_or_company_name || null,
                                  clientPhone: client?.whatsapp || client?.phone || null,
                                  amount: Number(r.balance_amount ?? r.amount) || null,
                                  dueDate: r.due_date || null,
                                };
                                setZapiTarget(target);
                                void writeAuditLog({
                                  table_name: 'receivables',
                                  record_id: r.id,
                                  action: 'whatsapp_zapi_open' as any,
                                  new_value: {
                                    description: r.description,
                                    amount: Number(r.amount),
                                    balance: Number(r.balance_amount ?? r.amount),
                                    due_date: r.due_date,
                                    client_id: target.clientId,
                                    service_order_id: target.serviceOrderId,
                                    has_share_token: !!target.shareToken,
                                  },
                                  reason: 'Abriu envio Z-API de recibo/cobrança',
                                });
                              }}
                            >
                              <Send className="h-4 w-4 mr-1" /> Z-API
                            </Button>
                            {r.status !== 'paid' && (
                              <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ receivable: r })}>
                                {t.financial.registerPayment}
                              </Button>
                            )}
                          </div>
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
          <FinancialFilterPanel type="payable" filters={payFilters} onChange={setPayFilters} />
          <div className="flex flex-wrap gap-1 items-center">
            <span className="text-sm text-muted-foreground">{t.financial.groupBy}:</span>
            {([
              { v: 'none' as const, l: t.financial.groupByNone },
              { v: 'category' as const, l: t.financial.groupByCategory },
              { v: 'supplier' as const, l: t.financial.groupBySupplier },
              { v: 'month' as const, l: t.financial.groupByMonth },
            ]).map(({ v, l }) => (
              <Button key={v} size="sm" variant={groupBy === v ? 'secondary' : 'ghost'} onClick={() => setGroupBy(v)}>
                {l}
              </Button>
            ))}
          </div>

          {loadingPay ? <Skeleton className="h-64 rounded-xl" /> : (
            <>
              {groupBy === 'none' ? (
                <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
                  <table className="w-full text-sm min-w-[900px]">
                    {payableTableHead}
                    <tbody>
                      {filteredPayables.length === 0 ? (
                        <tr><td colSpan={12} className="text-center py-8 text-muted-foreground">{t.common.noResults}</td></tr>
                      ) : filteredPayables.map(renderPayableRow)}
                    </tbody>
                    <tfoot>
                      <tr className="bg-muted/50 border-t-2 font-medium">
                        <td colSpan={7} className="px-4 py-3">{t.common.total}: {filteredPayables.length} itens</td>
                        <td className="px-4 py-3 text-right">{formatCurrency(filteredPayables.reduce((s, p) => s + Number(p.amount), 0))}</td>
                        <td className="px-4 py-3 text-right hidden md:table-cell text-success">{formatCurrency(payTotalPaid)}</td>
                        <td className="px-4 py-3 text-right hidden md:table-cell">{formatCurrency(payTotalBalance)}</td>
                        <td colSpan={2} />
                      </tr>
                    </tfoot>
                  </table>
                  </div>
              ) : (
                <div className="space-y-4">
                  {Object.entries(grouped).map(([groupName, rawItems]) => {
                    const items = rawItems as any[];
                    const groupBalance = items.filter((p: any) => p.status !== 'paid' && p.status !== 'cancelled').reduce((s: number, p: any) => s + Number(p.balance_amount), 0);
                    return (
                      <Collapsible key={groupName} defaultOpen>
                        <CollapsibleTrigger className="flex items-center justify-between w-full rounded-lg border bg-card p-3 hover:bg-muted/50">
                          <span className="font-semibold">{groupName} <span className="text-muted-foreground font-normal">({items.length})</span></span>
                          <span className="font-semibold">{t.financial.subtotal}: {formatCurrency(groupBalance)}</span>
                        </CollapsibleTrigger>
                        <CollapsibleContent>
                          <div className="rounded-b-xl border border-t-0 bg-card shadow-sm overflow-x-auto scrollbar-thin">
                            <table className="w-full text-sm min-w-[900px]">
                              {payableTableHead}
                              <tbody>{items.map(renderPayableRow)}</tbody>
                              <tfoot>
                                <tr className="bg-muted/30 font-medium text-sm">
                                  <td colSpan={6} className="px-4 py-2">{t.financial.subtotal}</td>
                                  <td className="px-4 py-2 text-right">{formatCurrency(items.reduce((s: number, p: any) => s + Number(p.amount), 0))}</td>
                                  <td className="px-4 py-2 text-right hidden md:table-cell">{formatCurrency(items.reduce((s: number, p: any) => s + Number(p.paid_amount), 0))}</td>
                                  <td className="px-4 py-2 text-right hidden md:table-cell">{formatCurrency(groupBalance)}</td>
                                  <td colSpan={2} />
                                </tr>
                              </tfoot>
                            </table>
                          </div>
                        </CollapsibleContent>
                      </Collapsible>
                    );
                  })}
                </div>
              )}
            </>
          )}
          </>
          )}
        </TabsContent>

        {/* === RECONCILIATION === */}
        <TabsContent value="reconciliation" className="mt-4">
          <BankReconciliation />
        </TabsContent>
      </Tabs>

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
      <SendViaZAPIDialog
        open={!!zapiTarget}
        onOpenChange={v => { if (!v) setZapiTarget(null); }}
        target={zapiTarget}
      />
    </div>
  );
}

import { useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Download, DollarSign, Paperclip, Pencil, Plus } from 'lucide-react';
import {
  Bar, BarChart, CartesianGrid, ComposedChart, Line, ResponsiveContainer,
  Tooltip as RechartsTooltip, XAxis, YAxis,
} from 'recharts';
import { useI18n } from '@/i18n';
import { useReceivables, usePayables, useFinancialSummary, useCashFlow } from '@/hooks/use-financial';
import { usePendingReimbursements } from '@/hooks/use-service-order-expenses';
import { exportToCSV } from '@/lib/export';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { FinancialFilterPanel, applyFilters, defaultFilters, type FinancialFilters } from '@/components/FinancialFilterPanel';
import { PaymentDialog } from '@/components/PaymentDialog';
import { PayableFormDialog } from '@/components/PayableFormDialog';
import { DREPanel } from '@/components/DREPanel';
import { BankReconciliation } from '@/components/BankReconciliation';
import { BankSourcesPanel } from '@/components/BankSourcesPanel';
import { FinanceReviewInbox, type SementeDeRegra } from '@/components/FinanceReviewInbox';
import { FinanceRulesPanel, EditorDeRegra } from '@/components/FinanceRulesPanel';
import { IgnoradasPanel } from '@/components/IgnoradasPanel';
import { AgingReportPanel } from '@/components/AgingReportPanel';
import { ReimbursementsPanel } from '@/components/ReimbursementsPanel';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Onda B · Financeiro v2 — paridade com FinancialPage v1:
   visão geral (KPIs + fluxo de caixa 3/6/12m + próximos 30d), DRE,
   Pagáveis (filtros, busca por OS, agrupamento categoria/fornecedor/mês,
   comprovante, reembolsos, registrar pagamento, editar, CSV, totais),
   Conciliação e Aging (painéis reutilizados). Recebíveis vive em
   /v2/receivables — a aba redireciona. Estado da aba na URL (?tab=).
──────────────────────────────────────────────────────────────────────────── */

type PayableRow = {
  id: string;
  description: string;
  name?: string | null;
  amount: number | null;
  paid_amount?: number | null;
  balance_amount?: number | null;
  status?: string | null;
  due_date: string;
  notes?: string | null;
  expense_category?: string | null;
  origin?: string | null;
  receipt_url?: string | null;
  linked_service_order_id?: string | null;
  suppliers?: { name?: string } | null;
  service_orders?: { service_order_number?: string } | null;
  service_order_expenses?: { receipt_url?: string | null }[] | null;
};

const isOverdue = (p: PayableRow) => p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) < new Date();

function statusView(p: PayableRow): { label: string; tone: StatusTone } {
  if (isOverdue(p)) return { label: 'Em atraso', tone: 'critical' };
  if (p.status === 'paid') return { label: 'Pago', tone: 'success' };
  if (p.status === 'partially_paid') return { label: 'Parcial', tone: 'warning' };
  if (p.status === 'cancelled') return { label: 'Cancelado', tone: 'neutral' };
  return { label: 'Em aberto', tone: 'neutral' };
}

function dueAlert(p: PayableRow): { label: string; tone: StatusTone } | null {
  if (p.status === 'paid' || p.status === 'cancelled') return null;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const due = new Date(p.due_date); due.setHours(0, 0, 0, 0);
  const diff = Math.round((due.getTime() - today.getTime()) / 86400000);
  if (diff < 0) return { label: `${Math.abs(diff)}d em atraso`, tone: 'critical' };
  if (diff === 0) return { label: 'Vence hoje', tone: 'critical' };
  if (diff <= 7) return { label: `Vence em ${diff}d`, tone: 'warning' };
  return null;
}

const originView = (origin: string | null | undefined): { label: string; tone: StatusTone } => {
  switch (origin) {
    case 'service_order_expense': return { label: 'Despesa de OS', tone: 'info' };
    case 'bank_reconciliation': return { label: 'Conciliação', tone: 'info' };
    default: return { label: 'Manual', tone: 'neutral' };
  }
};

type GroupBy = 'none' | 'category' | 'supplier' | 'month';

function groupPayables(payables: PayableRow[], groupBy: GroupBy): Record<string, PayableRow[]> {
  if (groupBy === 'none') return { Todos: payables };
  const groups: Record<string, PayableRow[]> = {};
  const keyOf = (p: PayableRow) => {
    if (groupBy === 'category') return p.expense_category || 'Sem categoria';
    if (groupBy === 'supplier') return p.suppliers?.name || p.name || 'Sem fornecedor';
    return new Date(p.due_date).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
  };
  for (const p of payables) {
    const k = keyOf(p);
    (groups[k] ??= []).push(p);
  }
  return groups;
}

export default function FinancialV2() {
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();

  const { data: recData, error: recError } = useReceivables();
  const { data: payData, isLoading: loadingPay, error: payError } = usePayables();
  const { data: summary, isLoading: loadingSummary, error: summaryError } = useFinancialSummary();
  const [cfMonths, setCfMonths] = useState(6);
  const { data: cashFlow } = useCashFlow(cfMonths);
  const { data: pendingReimb } = usePendingReimbursements();

  const receivables = useMemo(() => (recData ?? []) as unknown as PayableRow[], [recData]);
  const payables = useMemo(() => (payData ?? []) as unknown as PayableRow[], [payData]);

  const tab = searchParams.get('tab') || 'overview';
  // Toda aba se comporta como aba. A de Recebíveis costumava NAVEGAR para outra página, e
  // o efeito para quem usa era a tela inteira trocar ao clicar numa aba — parecia bug
  // porque, do lado de fora, é bug: aba que leva embora não é aba.
  const setTab = (v: string) =>
    setSearchParams((prev) => { prev.set('tab', v); return prev; }, { replace: true });

  const [payFilters, setPayFilters] = useState<FinancialFilters>({ ...defaultFilters });
  const [payOsSearch, setPayOsSearch] = useState('');
  const [groupBy, setGroupBy] = useState<GroupBy>('none');
  const [paySort, setPaySort] = useState<SortState>({ key: 'due_date', dir: 'asc' });
  const [paySubTab, setPaySubTab] = useState<'list' | 'reimbursements'>('list');
  const [paymentTarget, setPaymentTarget] = useState<{ receivable?: PayableRow; payable?: PayableRow } | null>(null);
  const [showNewPayable, setShowNewPayable] = useState(false);
  const [editingPayable, setEditingPayable] = useState<PayableRow | null>(null);
  // Regra criada a partir de uma linha da caixa de entrada: o editor abre preenchido, sem
  // obrigar a redigitar o fornecedor que está na tela.
  const [sementeRegra, setSementeRegra] = useState<SementeDeRegra | null>(null);

  /**
   * "Contas a pagar" mostra o que se DEVE, não o histórico de despesa.
   *
   * A lista trazia as 1.663 despesas já quitadas junto com as 4 obrigações em aberto —
   * quase quatrocentas vindas de compra no cartão, cada uma parecendo uma conta a pagar.
   * Não são: a compra está paga do ponto de vista do gestor, e quem ele deve é o banco,
   * pela FATURA. Conta a pagar é obrigação viva; despesa liquidada é história, e história
   * se lê no resultado, não numa lista de cobrança.
   *
   * O histórico continua alcançável — é o botão "Mostrar já pagas".
   */
  const [mostrarPagas, setMostrarPagas] = useState(false);

  const filteredPayables = useMemo(() => {
    const base = (applyFilters(payables as never[], payFilters, 'payable') as unknown as PayableRow[])
      .filter((p) => mostrarPagas || (p.status !== 'paid' && p.status !== 'cancelled'))
      .filter((p) => !payOsSearch || p.service_orders?.service_order_number?.toLowerCase().includes(payOsSearch.toLowerCase()));
    return [...base].sort((a, b) => {
      const val = (p: PayableRow) =>
        ['amount', 'balance_amount', 'paid_amount'].includes(paySort.key)
          ? Number((p as Record<string, unknown>)[paySort.key] ?? 0)
          : String((p as Record<string, unknown>)[paySort.key] ?? '');
      const av = val(a);
      const bv = val(b);
      if (av < bv) return paySort.dir === 'asc' ? -1 : 1;
      if (av > bv) return paySort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [payables, payFilters, payOsSearch, paySort, mostrarPagas]);

  const pagasEscondidas = useMemo(
    () => payables.filter((p) => p.status === 'paid' || p.status === 'cancelled').length,
    [payables],
  );

  const payTotalBalance = filteredPayables.filter((p) => p.status !== 'paid' && p.status !== 'cancelled').reduce((s, p) => s + Number(p.balance_amount ?? 0), 0);
  const payTotalPaid = filteredPayables.reduce((s, p) => s + Number(p.paid_amount ?? 0), 0);
  const payTotalAmount = filteredPayables.reduce((s, p) => s + Number(p.amount ?? 0), 0);
  const grouped = useMemo(() => groupPayables(filteredPayables, groupBy), [filteredPayables, groupBy]);

  const today = new Date();
  const in30 = new Date(today.getTime() + 30 * 86400000);
  const upcomingRec = receivables.filter((r) => r.status !== 'paid' && r.status !== 'cancelled' && new Date(r.due_date) <= in30).slice(0, 5);
  const upcomingPay = payables.filter((p) => p.status !== 'paid' && p.status !== 'cancelled' && new Date(p.due_date) <= in30).slice(0, 5);
  const periodBalance = (cashFlow ?? []).reduce((s: number, m: { net: number }) => s + m.net, 0);

  const handlePaySort = (key: string) => {
    setPaySort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: key === 'due_date' ? 'asc' : 'desc' }));
  };

  const payColumns: DataColumn<PayableRow>[] = [
    {
      key: 'due_date', header: t.financial.dueDate, minWidth: 126, priority: 0, sortable: true,
      render: (p) => {
        const alert = dueAlert(p);
        return (
          <span className="block leading-tight">
            <span className="block">{formatDate(p.due_date)}</span>
            {alert && <StatusChip tone={alert.tone} className="mt-0.5">{alert.label}</StatusChip>}
          </span>
        );
      },
    },
    {
      key: 'who', header: 'Fornecedor · Descrição', minWidth: 225, priority: 1, detailLabel: 'Fornecedor',
      render: (p) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{p.suppliers?.name || p.name || '—'}</span>
          <span className="block truncate text-xs text-muted-foreground" title={p.notes ?? undefined}>{p.description}</span>
        </span>
      ),
    },
    {
      key: 'status', header: t.common.status, minWidth: 110, priority: 2, detailLabel: 'Status',
      render: (p) => {
        const s = statusView(p);
        return <StatusChip dot tone={s.tone}>{s.label}</StatusChip>;
      },
    },
    {
      key: 'balance_amount', header: t.common.balance, minWidth: 116, priority: 2, align: 'right', sortable: true, detailLabel: 'Saldo',
      render: (p) => <span className="font-semibold">{formatCurrency(Number(p.balance_amount ?? 0))}</span>,
    },
    {
      key: 'category', header: 'Categoria', minWidth: 128, priority: 3, detailLabel: 'Categoria',
      render: (p) => (p.expense_category ? <StatusChip tone="neutral">{p.expense_category}</StatusChip> : <span className="text-muted-foreground">—</span>),
    },
    {
      key: 'os', header: 'OS', minWidth: 100, priority: 4, detailLabel: 'OS',
      render: (p) =>
        p.service_orders?.service_order_number ? (
          <button
            type="button"
            className="font-semibold text-accent underline-offset-2 hover:underline"
            onClick={(e) => { e.stopPropagation(); if (p.linked_service_order_id) navigate(`/v2/service-orders/${p.linked_service_order_id}`); }}
          >
            {p.service_orders.service_order_number}
          </button>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
    {
      key: 'amount', header: t.common.total, minWidth: 112, priority: 4, align: 'right', sortable: true, detailLabel: 'Valor',
      render: (p) => formatCurrency(Number(p.amount ?? 0)),
    },
    {
      key: 'paid_amount', header: 'Pago', minWidth: 108, priority: 5, align: 'right', sortable: true, detailLabel: 'Pago',
      render: (p) => (
        <span className={Number(p.paid_amount) > 0 ? 'text-success' : 'text-muted-foreground'}>{formatCurrency(Number(p.paid_amount ?? 0))}</span>
      ),
    },
    {
      key: 'origin', header: 'Origem', minWidth: 118, priority: 5, detailLabel: 'Origem',
      render: (p) => {
        const o = originView(p.origin);
        return <StatusChip tone={o.tone}>{o.label}</StatusChip>;
      },
    },
    {
      key: 'receipt', header: 'Comprovante', minWidth: 104, priority: 6, detailLabel: 'Comprovante',
      render: (p) => {
        const soeReceipt = p.service_order_expenses?.find?.((e) => e?.receipt_url)?.receipt_url;
        const url = soeReceipt || p.receipt_url;
        if (!url) return <span className="text-muted-foreground">—</span>;
        return (
          <a
            href={url} target="_blank" rel="noopener noreferrer" title="Ver comprovante"
            className="inline-flex items-center gap-1 text-accent underline-offset-2 hover:underline"
            onClick={(e) => e.stopPropagation()}
          >
            <Paperclip className="h-4 w-4" /> Ver
          </a>
        );
      },
    },
  ];

  const payTable = (rows: PayableRow[]) => (
    <DataTable<PayableRow>
      rows={rows}
      rowKey={(p) => p.id}
      columns={payColumns}
      sort={paySort}
      onSort={handlePaySort}
      emptyMessage={t.common.noResults}
      rowClassName={(p) => (isOverdue(p) ? 'bg-destructive/5' : undefined)}
      rowActions={(p) => (
        <>
          {p.status !== 'paid' && (
            <Button
              variant="ghost" size="icon" className="h-8 w-8"
              aria-label="Registrar pagamento" title="Registrar pagamento"
              onClick={() => setPaymentTarget({ payable: p })}
            >
              <DollarSign className="h-4 w-4" />
            </Button>
          )}
          {p.status !== 'paid' && p.status !== 'cancelled' && (
            <Button
              variant="ghost" size="icon" className="h-8 w-8"
              aria-label="Editar pagável" title="Editar"
              onClick={() => setEditingPayable(p)}
            >
              <Pencil className="h-4 w-4" />
            </Button>
          )}
        </>
      )}
    />
  );

  if (recError || payError || summaryError) {
    return (
      <V2Shell>
        <div className="flex flex-col items-center justify-center gap-4 py-24 text-center">
          <p className="font-medium text-destructive">Erro ao carregar dados financeiros.</p>
          <p className="text-sm text-muted-foreground">{(recError || payError || summaryError)?.message || 'Verifique sua conexão e tente novamente.'}</p>
          <Button variant="outline" onClick={() => window.location.reload()}>Recarregar página</Button>
        </div>
      </V2Shell>
    );
  }

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Financeiro' }]}
        title={t.financial.title}
        description={t.financial.description}
      >
        <Tabs value={tab} onValueChange={setTab}>
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            <TabsTrigger value="overview">{t.financial.tabOverview}</TabsTrigger>
            <TabsTrigger value="dre">DRE / Avançado</TabsTrigger>
            {/* Contas a Receber NÃO é aba: é tela própria (/v2/receivables), com filtros,
                régua de cobrança e recibo. Era uma aba que navegava para fora — o pior dos
                dois mundos, porque prometia troca de conteúdo e entregava troca de página.
                Agora é item do menu, onde uma tela inteira deve estar. */}
            <TabsTrigger value="payables">{t.financial.tabPayables}</TabsTrigger>
            <TabsTrigger value="reconciliation">{t.financial.tabReconciliation}</TabsTrigger>
            {/* Conciliar é ligar dinheiro ao que já existe; a caixa de entrada é o que
                passou pela conta e nunca virou lançamento. Trabalhos com ritmos
                diferentes — o usuário pediu para manter separados. */}
            <TabsTrigger value="inbox">Caixa de entrada</TabsTrigger>
            {/* O que saiu da fila não pode sair do sistema. Sem esta aba, 380 transações
                tinham virado sumiço — e a suspeita, justa, foi de que a IA as tinha
                escondido. Toda saída da fila é reversível e diz quem, quando e por quê. */}
            <TabsTrigger value="ignoradas">Fora da fila</TabsTrigger>
            <TabsTrigger value="rules">Regras</TabsTrigger>
            <TabsTrigger value="banks">Contas bancárias</TabsTrigger>
            <TabsTrigger value="aging">Aging</TabsTrigger>
          </TabsList>

          {/* ── VISÃO GERAL ── */}
          <TabsContent value="overview" className="mt-4 space-y-4">
            {loadingSummary ? (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                {[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-24 rounded-lg" />)}
              </div>
            ) : (
              <>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  <KPIStat
                    label={t.financial.totalReceivables}
                    value={formatCurrency(summary?.total_receivable || 0)}
                    hint={summary?.overdue_receivable ? `${formatCurrency(summary.overdue_receivable)} vencidos` : 'sem atrasos'}
                    tone={summary?.overdue_receivable ? 'critical' : 'success'}
                    onClick={() => navigate('/v2/receivables')}
                  />
                  <KPIStat
                    label={t.financial.pendingPayables}
                    value={formatCurrency(summary?.total_payable || 0)}
                    hint={summary?.overdue_payable ? `${formatCurrency(summary.overdue_payable)} vencidos` : 'sem atrasos'}
                    tone={summary?.overdue_payable ? 'critical' : 'success'}
                    onClick={() => setTab('payables')}
                  />
                  <KPIStat label={t.financial.collectedThisMonth} value={formatCurrency(summary?.collected_this_month || 0)} tone="success" />
                  <KPIStat label={t.financial.paidThisMonth} value={formatCurrency(summary?.paid_this_month || 0)} />
                </div>

                <div className="overflow-hidden rounded-lg border bg-card p-4">
                  <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                    <h3 className="text-sm font-bold">{t.financial.cashFlowChart}</h3>
                    <div className="flex gap-1">
                      {[3, 6, 12].map((m) => (
                        <Button key={m} size="sm" variant={cfMonths === m ? 'secondary' : 'ghost'} onClick={() => setCfMonths(m)}>
                          {m}m
                        </Button>
                      ))}
                    </div>
                  </div>
                  {cashFlow && cashFlow.length > 0 ? (
                    <>
                      <ResponsiveContainer width="100%" height={280}>
                        <ComposedChart data={cashFlow}>
                          <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
                          <XAxis dataKey="month" tick={{ fontSize: 12, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} />
                          <YAxis tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }} tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`} width={44} axisLine={false} tickLine={false} />
                          <RechartsTooltip formatter={(v: number) => formatCurrency(v)} cursor={{ fill: 'hsl(var(--muted))' }} />
                          <Bar dataKey="inflow" name={t.financial.inflow} fill="hsl(var(--success))" radius={[3, 3, 0, 0]} />
                          <Bar dataKey="outflow" name={t.financial.outflow} fill="hsl(var(--destructive))" radius={[3, 3, 0, 0]} />
                          <Line dataKey="net" name={t.financial.netBalance} stroke="hsl(var(--primary))" strokeWidth={2} dot />
                        </ComposedChart>
                      </ResponsiveContainer>
                      <p className="mt-1 text-sm">
                        {t.financial.periodBalance}:{' '}
                        <span className={`font-bold tabular-nums ${periodBalance >= 0 ? 'text-success' : 'text-destructive'}`}>{formatCurrency(periodBalance)}</span>
                      </p>
                    </>
                  ) : (
                    <p className="py-8 text-center text-sm text-muted-foreground">{t.common.noResults}</p>
                  )}
                </div>

                <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                  <div className="rounded-lg border bg-card p-4">
                    <h3 className="mb-3 text-sm font-bold">{t.financial.upcomingReceivables}</h3>
                    {upcomingRec.length === 0 ? <p className="text-sm text-muted-foreground">{t.common.noResults}</p> : (
                      <div className="space-y-2">
                        {upcomingRec.map((r) => (
                          <div key={r.id} className="flex items-center justify-between gap-2 border-b pb-2 text-sm last:border-0">
                            <span className="min-w-0 overflow-hidden">
                              <span className="block truncate font-medium">{(r as PayableRow & { clients?: { name?: string } }).clients?.name || r.description}</span>
                              <span className="block truncate text-xs text-muted-foreground">{formatDate(r.due_date)}</span>
                            </span>
                            <span className="flex shrink-0 items-center gap-2">
                              <span className="font-semibold tabular-nums">{formatCurrency(Number(r.balance_amount ?? 0))}</span>
                              <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ receivable: r })}>{t.financial.registerPayment}</Button>
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                  <div className="rounded-lg border bg-card p-4">
                    <h3 className="mb-3 text-sm font-bold">{t.financial.upcomingPayables}</h3>
                    {upcomingPay.length === 0 ? <p className="text-sm text-muted-foreground">{t.common.noResults}</p> : (
                      <div className="space-y-2">
                        {upcomingPay.map((p) => (
                          <div key={p.id} className="flex items-center justify-between gap-2 border-b pb-2 text-sm last:border-0">
                            <span className="min-w-0 overflow-hidden">
                              <span className="block truncate font-medium">{p.description}</span>
                              <span className="block truncate text-xs text-muted-foreground">{formatDate(p.due_date)}</span>
                            </span>
                            <span className="flex shrink-0 items-center gap-2">
                              <span className="font-semibold tabular-nums">{formatCurrency(Number(p.balance_amount ?? 0))}</span>
                              <Button size="sm" variant="outline" onClick={() => setPaymentTarget({ payable: p })}>{t.financial.registerPayment}</Button>
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              </>
            )}
          </TabsContent>

          {/* ── DRE ── */}
          <TabsContent value="dre" className="mt-4"><DREPanel /></TabsContent>

          {/* ── PAGÁVEIS ── */}
          <TabsContent value="payables" className="mt-4 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex flex-wrap items-center gap-2">
                <h3 className="text-lg font-semibold">{t.financial.payables}</h3>
                <div className="flex flex-wrap gap-1 sm:ml-2">
                  <Button size="sm" variant={paySubTab === 'list' ? 'secondary' : 'ghost'} onClick={() => setPaySubTab('list')}>
                    {t.financial.payables}
                  </Button>
                  <Button size="sm" variant={paySubTab === 'reimbursements' ? 'secondary' : 'ghost'} onClick={() => setPaySubTab('reimbursements')}>
                    {t.financial.pendingReimbursements} ({pendingReimb?.length || 0})
                  </Button>
                </div>
              </div>
              {/* A lista é de obrigação VIVA. Despesa já quitada — inclusive as centenas
                  de compras no cartão — é história, e história se lê no resultado, não
                  numa lista de cobrança. Fica a um clique de distância, não escondida. */}
              {paySubTab === 'list' && pagasEscondidas > 0 && (
                <Button size="sm" variant={mostrarPagas ? 'secondary' : 'ghost'}
                  onClick={() => setMostrarPagas((v) => !v)}>
                  {mostrarPagas ? 'Só o que está em aberto' : `Mostrar as ${pagasEscondidas} já pagas`}
                </Button>
              )}
              <div className="flex gap-2">
                <Button
                  variant="outline" size="sm" className="gap-1.5"
                  onClick={() =>
                    exportToCSV(filteredPayables as never[], 'pagaveis', [
                      { key: 'description', label: 'Descrição' },
                      { key: 'amount', label: 'Valor', format: (v: number | null) => Number(v || 0).toFixed(2).replace('.', ',') },
                      { key: 'due_date', label: 'Vencimento', format: (v: string | null) => (v ? new Date(v).toLocaleDateString('pt-BR') : '') },
                      { key: 'status', label: 'Status' },
                      { key: 'name', label: 'Fornecedor' },
                    ] as never)
                  }
                >
                  <Download className="h-4 w-4" /> Exportar CSV
                </Button>
                <Button className="gap-1.5" onClick={() => setShowNewPayable(true)}>
                  <Plus className="h-4 w-4" /> {t.financial.newPayable}
                </Button>
              </div>
            </div>

            {paySubTab === 'reimbursements' ? (
              <ReimbursementsPanel />
            ) : (
              <>
                <FinancialFilterPanel type="payable" filters={payFilters} onChange={setPayFilters} />
                <div className="flex flex-wrap items-center gap-3">
                  <Input
                    placeholder="Filtrar por número da OS"
                    value={payOsSearch}
                    onChange={(e) => setPayOsSearch(e.target.value)}
                    className="h-9 w-full sm:w-64"
                  />
                  <div className="flex flex-wrap items-center gap-1">
                    <span className="text-sm text-muted-foreground">{t.financial.groupBy}:</span>
                    {([
                      { v: 'none', l: t.financial.groupByNone },
                      { v: 'category', l: t.financial.groupByCategory },
                      { v: 'supplier', l: t.financial.groupBySupplier },
                      { v: 'month', l: t.financial.groupByMonth },
                    ] as { v: GroupBy; l: string }[]).map(({ v, l }) => (
                      <Button key={v} size="sm" variant={groupBy === v ? 'secondary' : 'ghost'} onClick={() => setGroupBy(v)}>{l}</Button>
                    ))}
                  </div>
                </div>

                {loadingPay ? (
                  <Skeleton className="h-64 w-full rounded-lg" />
                ) : groupBy === 'none' ? (
                  <div className="hidden md:block">
                    {payTable(filteredPayables)}
                    <div className="mt-2 flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-muted/40 px-4 py-2 text-sm">
                      <span className="font-medium">{t.common.total}: {filteredPayables.length} itens</span>
                      <span className="flex flex-wrap gap-4 tabular-nums">
                        <span>Valor: <b>{formatCurrency(payTotalAmount)}</b></span>
                        <span className="text-success">Pago: <b>{formatCurrency(payTotalPaid)}</b></span>
                        <span>Saldo: <b>{formatCurrency(payTotalBalance)}</b></span>
                      </span>
                    </div>
                  </div>
                ) : (
                  <div className="hidden space-y-3 md:block">
                    {Object.entries(grouped).map(([groupName, items]) => {
                      const groupBalance = items.filter((p) => p.status !== 'paid' && p.status !== 'cancelled').reduce((s, p) => s + Number(p.balance_amount ?? 0), 0);
                      return (
                        <Collapsible key={groupName} defaultOpen>
                          <CollapsibleTrigger className="flex w-full items-center justify-between rounded-lg border bg-card p-3 hover:bg-muted/50">
                            <span className="font-semibold">{groupName} <span className="font-normal text-muted-foreground">({items.length})</span></span>
                            <span className="font-semibold tabular-nums">{t.financial.subtotal}: {formatCurrency(groupBalance)}</span>
                          </CollapsibleTrigger>
                          <CollapsibleContent className="pt-2">{payTable(items)}</CollapsibleContent>
                        </Collapsible>
                      );
                    })}
                  </div>
                )}

                {/* Mobile: lista compacta de pagáveis */}
                {!loadingPay && (
                  <div className="space-y-2.5 md:hidden">
                    {filteredPayables.map((p) => {
                      const s = statusView(p);
                      const alert = dueAlert(p);
                      return (
                        <div key={p.id} className={`rounded-lg border border-l-[3px] bg-card p-3.5 shadow-sm ${s.tone === 'critical' ? 'border-l-destructive' : s.tone === 'success' ? 'border-l-success' : 'border-l-transparent'}`}>
                          <div className="flex items-center justify-between gap-2">
                            <span className="min-w-0 truncate text-sm font-bold">{p.suppliers?.name || p.name || p.description}</span>
                            <StatusChip tone={s.tone}>{s.label}</StatusChip>
                          </div>
                          <p className="truncate text-sm text-muted-foreground">{p.description}</p>
                          <p className="text-sm text-muted-foreground">
                            {formatDate(p.due_date)}{alert ? ` · ${alert.label}` : ''} · <b className="text-foreground">{formatCurrency(Number(p.balance_amount ?? 0))}</b>
                          </p>
                          {p.status !== 'paid' && (
                            <div className="mt-3 flex gap-2 [&>*]:min-h-11">
                              <Button className="flex-1" onClick={() => setPaymentTarget({ payable: p })}>{t.financial.registerPayment}</Button>
                              {p.status !== 'cancelled' && (
                                <Button variant="outline" size="icon" className="h-11 w-11" aria-label="Editar" onClick={() => setEditingPayable(p)}>
                                  <Pencil className="h-4 w-4" />
                                </Button>
                              )}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </>
            )}
          </TabsContent>

          {/* ── CONCILIAÇÃO / CAIXA DE ENTRADA / REGRAS / CONTAS / AGING ── */}
          <TabsContent value="reconciliation" className="mt-4"><BankReconciliation /></TabsContent>
          <TabsContent value="inbox" className="mt-4">
            <FinanceReviewInbox onCriarRegra={setSementeRegra} />
          </TabsContent>
          <TabsContent value="ignoradas" className="mt-4"><IgnoradasPanel /></TabsContent>
          <TabsContent value="rules" className="mt-4"><FinanceRulesPanel /></TabsContent>
          <TabsContent value="banks" className="mt-4"><BankSourcesPanel /></TabsContent>
          <TabsContent value="aging" className="mt-4"><AgingReportPanel /></TabsContent>
        </Tabs>

        {/* Saída para a versão anterior enquanto a confiança na nova não se firma. Some
            quando a transição terminar — até lá, ficar preso é pior que ver um link. */}
        <p className="mt-8 text-center text-xs text-muted-foreground">
          Faltou alguma coisa?{' '}
          <a href="/financial?legacy=1" className="underline underline-offset-2 hover:text-foreground">
            Abrir a versão anterior
          </a>
        </p>
      </PageShell>

      {paymentTarget && (
        <PaymentDialog
          open={!!paymentTarget}
          onOpenChange={() => setPaymentTarget(null)}
          receivable={paymentTarget.receivable as never}
          payable={paymentTarget.payable as never}
        />
      )}
      {sementeRegra && (
        <EditorDeRegra
          key={sementeRegra.match_value}
          aberto
          onFechar={() => setSementeRegra(null)}
          regra={sementeRegra}
        />
      )}
      <PayableFormDialog open={showNewPayable} onOpenChange={setShowNewPayable} />
      <PayableFormDialog
        open={!!editingPayable}
        onOpenChange={(v) => { if (!v) setEditingPayable(null); }}
        initialData={editingPayable ?? undefined}
      />
    </V2Shell>
  );
}

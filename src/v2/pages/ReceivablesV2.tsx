import { useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Download, DollarSign, MoreHorizontal, Pencil, Plus, Receipt as ReceiptIcon, Send } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useI18n } from '@/i18n';
import { useReceivables, useFinancialSummary } from '@/hooks/use-financial';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { exportToCSV } from '@/lib/export';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { FinancialFilterPanel, applyFilters, defaultFilters, type FinancialFilters } from '@/components/FinancialFilterPanel';
import { PaymentDialog } from '@/components/PaymentDialog';
import { ReceivableFormDialog } from '@/components/ReceivableFormDialog';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from '@/components/SendViaWhatsAppDialog';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { generateReceivableReceipt, type ReceivableRow } from '@/v2/lib/receipt';
import '@/v2/tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Fase 1 · Recebíveis v2 — paridade com a aba Recebíveis do Financeiro v1
   (vencimento com alerta, origem automático/manual, saldo, recibo, WhatsApp,
   registrar pagamento, editar, filtros, CSV) em DataTable + EntityCard.
   Cobrar via WhatsApp vira 1 clique na linha. Rota /v2/receivables.
──────────────────────────────────────────────────────────────────────────── */

const PAGE_SIZE = 25;

function isOverdue(r: ReceivableRow): boolean {
  return r.status !== 'paid' && r.status !== 'cancelled' && new Date(r.due_date) < new Date();
}

function statusView(r: ReceivableRow): { label: string; tone: StatusTone } {
  if (isOverdue(r)) return { label: 'Em atraso', tone: 'critical' };
  if (r.status === 'paid') return { label: 'Pago', tone: 'success' };
  if (r.status === 'partially_paid') return { label: 'Parcial', tone: 'warning' };
  if (r.status === 'cancelled') return { label: 'Cancelado', tone: 'neutral' };
  return { label: 'Em aberto', tone: 'neutral' };
}

/** Alerta de vencimento (porte do getDueDateAlert v1, tonalizado por token). */
function dueAlert(r: ReceivableRow): { label: string; tone: StatusTone } | null {
  if (r.status === 'paid' || r.status === 'cancelled') return null;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const due = new Date(r.due_date); due.setHours(0, 0, 0, 0);
  const diff = Math.round((due.getTime() - today.getTime()) / 86400000);
  if (diff < 0) return { label: `${Math.abs(diff)}d em atraso`, tone: 'critical' };
  if (diff === 0) return { label: 'Vence hoje', tone: 'critical' };
  if (diff <= 7) return { label: `Vence em ${diff}d`, tone: 'warning' };
  return null;
}

type QuickView = { id: string; label: string; match: (r: ReceivableRow) => boolean };

const QUICK_VIEWS: QuickView[] = [
  { id: 'open', label: 'Em aberto', match: (r) => r.status !== 'paid' && r.status !== 'cancelled' },
  { id: 'overdue', label: 'Vencidos', match: isOverdue },
  { id: 'paid', label: 'Pagos', match: (r) => r.status === 'paid' },
  { id: 'all', label: 'Todos', match: () => true },
];

export default function ReceivablesV2() {
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const { data, isLoading, error } = useReceivables();
  const receivables = useMemo(() => (data ?? []) as unknown as ReceivableRow[], [data]);
  const { data: summary } = useFinancialSummary();

  const initialView = searchParams.get('view');
  const [view, setView] = useState(QUICK_VIEWS.some((v) => v.id === initialView) ? (initialView as string) : 'open');
  const [search, setSearch] = useState('');
  const [filters, setFilters] = useState<FinancialFilters>({ ...defaultFilters });
  const [sort, setSort] = useState<SortState>({ key: 'due_date', dir: 'asc' });
  const [page, setPage] = useState(1);
  const [paymentTarget, setPaymentTarget] = useState<ReceivableRow | null>(null);
  const [editing, setEditing] = useState<ReceivableRow | null>(null);
  const [showNew, setShowNew] = useState(false);
  const [whatsAppTarget, setWhatsAppTarget] = useState<SendViaWhatsAppTarget | null>(null);

  const filtered = useMemo(() => {
    const activeView = QUICK_VIEWS.find((v) => v.id === view) ?? QUICK_VIEWS[0];
    const base = (applyFilters(receivables as never[], filters, 'receivable') as unknown as ReceivableRow[])
      .filter((r) => activeView.match(r))
      .filter((r) => {
        if (!search) return true;
        const hay = `${r.description} ${r.clients?.name ?? ''} ${r.service_orders?.service_order_number ?? ''}`.toLowerCase();
        return hay.includes(search.toLowerCase());
      });
    return [...base].sort((a, b) => {
      const val = (r: ReceivableRow) =>
        sort.key === 'balance' ? Number(r.balance_amount ?? r.amount ?? 0)
        : sort.key === 'amount' ? Number(r.amount ?? 0)
        : r.due_date;
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [receivables, filters, view, search, sort]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const overdueCount = receivables.filter(isOverdue).length;

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const openCharge = (r: ReceivableRow) => {
    const target: SendViaWhatsAppTarget = {
      kind: 'receivable',
      receivableId: r.id,
      description: r.description,
      serviceOrderId: r.service_orders?.id || null,
      shareToken: r.service_orders?.share_token || null,
      clientId: r.clients?.id || r.client_id || null,
      clientName: r.clients?.name || null,
      clientPhone: r.clients?.whatsapp || r.clients?.phone || null,
      amount: Number(r.balance_amount ?? r.amount) || null,
      dueDate: r.due_date || null,
    };
    setWhatsAppTarget(target);
    void writeAuditLog({
      table_name: 'receivables',
      record_id: r.id,
      action: 'whatsapp_send_open' as never,
      new_value: {
        description: r.description,
        amount: Number(r.amount),
        balance: Number(r.balance_amount ?? r.amount),
        due_date: r.due_date,
        client_id: target.clientId,
        service_order_id: target.serviceOrderId,
        has_share_token: !!target.shareToken,
        source: 'v2_receivables',
      },
      reason: 'Abriu envio WhatsApp de recibo/cobrança (v2)',
    });
  };

  const renderMenu = (r: ReceivableRow) => (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Mais ações">
          <MoreHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-52">
        {Number(r.paid_amount || 0) > 0 && (
          <DropdownMenuItem onClick={() => generateReceivableReceipt(r)} className="gap-2">
            <ReceiptIcon className="h-4 w-4" /> Gerar recibo
          </DropdownMenuItem>
        )}
        {r.status !== 'paid' && r.status !== 'cancelled' && (
          <DropdownMenuItem onClick={() => setEditing(r)} className="gap-2">
            <Pencil className="h-4 w-4" /> Editar recebível
          </DropdownMenuItem>
        )}
        <DropdownMenuItem onClick={() => openCharge(r)} className="gap-2">
          <Send className="h-4 w-4" /> Enviar WhatsApp…
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );

  const columns: DataColumn<ReceivableRow>[] = [
    {
      key: 'due_date', header: t.financial.dueDate, minWidth: 128, priority: 0, sortable: true,
      render: (r) => {
        const alert = dueAlert(r);
        return (
          <span className="block leading-tight">
            <span className="block">{formatDate(r.due_date)}</span>
            {alert && <StatusChip tone={alert.tone} className="mt-0.5">{alert.label}</StatusChip>}
          </span>
        );
      },
    },
    {
      key: 'who', header: 'Cliente · Descrição', minWidth: 225, priority: 1, detailLabel: 'Cliente',
      render: (r) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{r.clients?.name || '—'}</span>
          <span className="block truncate text-xs text-muted-foreground">{r.description}</span>
        </span>
      ),
    },
    {
      key: 'status', header: t.common.status, minWidth: 112, priority: 2, detailLabel: 'Status',
      render: (r) => {
        const s = statusView(r);
        return <StatusChip dot tone={s.tone}>{s.label}</StatusChip>;
      },
    },
    {
      key: 'balance', header: t.common.balance, minWidth: 118, priority: 2, align: 'right', sortable: true, detailLabel: 'Saldo',
      render: (r) => <span className="font-semibold">{formatCurrency(Number(r.balance_amount ?? r.amount ?? 0))}</span>,
    },
    {
      key: 'os', header: 'OS', minWidth: 104, priority: 3, detailLabel: 'OS',
      render: (r) =>
        r.service_orders?.service_order_number ? (
          <button
            type="button"
            className="font-semibold text-accent underline-offset-2 hover:underline"
            onClick={(e) => { e.stopPropagation(); if (r.service_orders?.id) navigate(`/service-orders/${r.service_orders.id}`); }}
          >
            {r.service_orders.service_order_number}
          </button>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
    {
      key: 'origin', header: 'Origem', minWidth: 104, priority: 4, detailLabel: 'Origem',
      render: (r) => (
        <StatusChip tone={r.service_order_id ? 'info' : 'neutral'}>
          {r.service_order_id ? 'Automático' : 'Manual'}
        </StatusChip>
      ),
    },
    {
      key: 'amount', header: t.common.amount, minWidth: 112, priority: 5, align: 'right', sortable: true, detailLabel: 'Valor original',
      render: (r) => formatCurrency(Number(r.amount ?? 0)),
    },
  ];

  const csvExport = () =>
    exportToCSV(filtered as never[], 'recebiveis', [
      { key: 'description', label: 'Descrição' },
      { key: 'amount', label: 'Valor', format: (v: number | null) => Number(v || 0).toFixed(2).replace('.', ',') },
      { key: 'due_date', label: 'Vencimento', format: (v: string | null) => (v ? new Date(v).toLocaleDateString('pt-BR') : '') },
      { key: 'status', label: 'Status' },
      { key: 'clients', label: 'Cliente', format: (v: { name?: string } | null) => v?.name || '' },
    ] as never);

  return (
    <div className="themev2 -m-4 min-h-full bg-background p-4 text-foreground lg:-m-6 lg:p-6">
      <PageShell
        breadcrumb={[{ label: 'Financeiro', to: '/financial' }, { label: 'Recebíveis' }]}
        title="Recebíveis"
        count={filtered.length}
        actions={
          <>
            <Button variant="outline" size="sm" onClick={csvExport} className="hidden gap-1.5 sm:inline-flex">
              <Download className="h-4 w-4" /> Exportar CSV
            </Button>
            <Button className="gap-1.5" onClick={() => setShowNew(true)}>
              <Plus className="h-4 w-4" /> Novo recebível
            </Button>
          </>
        }
      >
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <KPIStat label="A receber (aberto)" value={formatCurrency(summary?.total_receivable || 0)} />
          <KPIStat
            label="Vencidos"
            value={formatCurrency(summary?.overdue_receivable || 0)}
            hint={overdueCount > 0 ? `${overdueCount} título${overdueCount > 1 ? 's' : ''}` : 'nenhum'}
            tone={summary?.overdue_receivable ? 'critical' : 'success'}
            onClick={() => { setView('overdue'); setPage(1); }}
          />
          <KPIStat label="Recebido no mês" value={formatCurrency(summary?.collected_this_month || 0)} tone="success" />
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {QUICK_VIEWS.map((v) => (
            <button
              key={v.id}
              type="button"
              onClick={() => { setView(v.id); setPage(1); }}
              className={cn(
                'rounded-full px-3 py-1 text-xs font-semibold transition-colors',
                view === v.id ? 'bg-foreground text-background' : 'bg-muted text-muted-foreground hover:text-foreground',
              )}
            >
              {v.label}{v.id === 'overdue' && overdueCount > 0 ? ` · ${overdueCount}` : ''}
            </button>
          ))}
          <div className="ml-auto w-full sm:w-72">
            <Input
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              placeholder="Buscar por cliente, descrição ou OS…"
              className="h-9"
            />
          </div>
        </div>

        <FinancialFilterPanel type="receivable" filters={filters} onChange={(f) => { setFilters(f); setPage(1); }} />

        {isLoading ? (
          <Skeleton className="h-64 w-full rounded-lg" />
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center">
            <p className="text-destructive">Erro ao carregar recebíveis.</p>
          </div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<ReceivableRow>
                rows={paginated}
                rowKey={(r) => r.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                emptyMessage={t.common.noResults}
                rowClassName={(r) => (isOverdue(r) ? 'bg-destructive/5' : undefined)}
                rowActions={(r) => (
                  <>
                    <Button
                      variant="ghost" size="icon" className="h-8 w-8"
                      aria-label="Cobrar via WhatsApp" title="Cobrar via WhatsApp"
                      onClick={() => openCharge(r)}
                    >
                      <Send className="h-4 w-4" />
                    </Button>
                    {r.status !== 'paid' ? (
                      <Button
                        variant="ghost" size="icon" className="h-8 w-8"
                        aria-label="Registrar pagamento" title="Registrar pagamento"
                        onClick={() => setPaymentTarget(r)}
                      >
                        <DollarSign className="h-4 w-4" />
                      </Button>
                    ) : (
                      <Button
                        variant="ghost" size="icon" className="h-8 w-8"
                        aria-label="Gerar recibo" title="Gerar recibo"
                        onClick={() => generateReceivableReceipt(r)}
                      >
                        <ReceiptIcon className="h-4 w-4" />
                      </Button>
                    )}
                    {renderMenu(r)}
                  </>
                )}
              />
            </div>

            <div className="space-y-2.5 md:hidden">
              {paginated.map((r) => {
                const s = statusView(r);
                const alert = dueAlert(r);
                return (
                  <EntityCard
                    key={r.id}
                    id={r.service_orders?.service_order_number || 'Manual'}
                    severity={s.tone === 'critical' ? 'critical' : s.tone === 'success' ? 'success' : 'neutral'}
                    badge={<StatusChip tone={s.tone}>{s.label}</StatusChip>}
                    title={r.clients?.name || r.description}
                    lines={[
                      r.description,
                      `${formatDate(r.due_date)}${alert ? ` · ${alert.label}` : ''} · ${formatCurrency(Number(r.balance_amount ?? r.amount ?? 0))}`,
                    ]}
                    actions={
                      <>
                        <Button className="flex-1 gap-1.5" onClick={() => openCharge(r)}>
                          <Send className="h-4 w-4" /> Cobrar
                        </Button>
                        {r.status !== 'paid' && (
                          <Button variant="outline" size="icon" className="h-11 w-11" aria-label="Registrar pagamento" onClick={() => setPaymentTarget(r)}>
                            <DollarSign className="h-4 w-4" />
                          </Button>
                        )}
                        {renderMenu(r)}
                      </>
                    }
                  />
                );
              })}
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
                <span className="text-muted-foreground">{filtered.length} títulos · Página {page} de {totalPages}</span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      {paymentTarget && (
        <PaymentDialog
          open={!!paymentTarget}
          onOpenChange={(v) => { if (!v) setPaymentTarget(null); }}
          receivable={paymentTarget as never}
        />
      )}
      <ReceivableFormDialog open={showNew} onOpenChange={setShowNew} />
      <ReceivableFormDialog
        open={!!editing}
        onOpenChange={(v) => { if (!v) setEditing(null); }}
        initialData={editing ?? undefined}
      />
      <SendViaWhatsAppDialog
        open={!!whatsAppTarget}
        onOpenChange={(v) => { if (!v) setWhatsAppTarget(null); }}
        target={whatsAppTarget}
      />
    </div>
  );
}

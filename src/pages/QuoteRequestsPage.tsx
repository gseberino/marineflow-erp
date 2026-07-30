import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  ClipboardList, Clock, MessageSquareWarning, Plus, Search, TrendingDown, Users,
} from 'lucide-react';
import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import {
  useQuoteRequests, QUOTE_STATUS_LABELS,
  type QuoteRequest, type QuoteRequestStatus,
} from '@/hooks/use-quote-requests';
import { agingLevel, businessDaysSince, type AgingLevel } from '@/lib/quote-comparison';
import { NewQuoteRequestDialog } from '@/components/purchasing/NewQuoteRequestDialog';

/**
 * Lista de cotações. O que esta tela tem de diferente de uma lista qualquer é o
 * AGING em dias úteis: a pesquisa de compras trabalha com janela de 3 a 5 dias úteis
 * para o fornecedor responder, e o problema real aqui foi justamente cotação enviada
 * que nunca voltou. Então "há quantos dias está parada" é a informação principal,
 * não um detalhe.
 */

const AGING_STYLE: Record<AgingLevel, { chip: string; label: (d: number) => string }> = {
  fresh: {
    chip: 'bg-muted text-muted-foreground',
    label: d => (d === 0 ? 'hoje' : `há ${d} ${d === 1 ? 'dia útil' : 'dias úteis'}`),
  },
  due: {
    chip: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300',
    label: d => `há ${d} dias úteis — cobrar`,
  },
  late: {
    chip: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300',
    label: d => `há ${d} dias úteis — atrasada`,
  },
};

const STATUS_CHIP: Record<QuoteRequestStatus, string> = {
  open: 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300',
  closed: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300',
  cancelled: 'bg-muted text-muted-foreground',
};

const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

interface QuoteRow {
  quote: QuoteRequest;
  itemCount: number;
  supplierCount: number;
  respondedCount: number;
  bestTotal: number;
  businessDays: number;
  aging: AgingLevel;
  awaiting: boolean;
}

function buildRow(q: QuoteRequest): QuoteRow {
  const items = q.quote_request_items ?? [];
  const responses = q.quote_responses ?? [];
  const priced = responses.filter(r => r.quote_request_item_id && Number(r.unit_price) > 0);
  const responded = new Set(priced.map(r => r.supplier_id));

  // Melhor preço de cada item × quantidade: o piso do que essa compra vai custar.
  const qtyById = new Map(items.map(i => [i.id, Number(i.quantity) || 0]));
  const bestByItem = new Map<string, number>();
  for (const r of priced) {
    const price = Number(r.unit_price);
    const cur = bestByItem.get(r.quote_request_item_id!);
    if (cur === undefined || price < cur) bestByItem.set(r.quote_request_item_id!, price);
  }
  let bestTotal = 0;
  for (const [itemId, price] of bestByItem) bestTotal += price * (qtyById.get(itemId) ?? 0);

  const days = businessDaysSince(q.created_at);
  return {
    quote: q,
    itemCount: items.length,
    supplierCount: (q.sent_supplier_ids ?? []).length,
    respondedCount: responded.size,
    bestTotal,
    businessDays: days,
    aging: agingLevel(days),
    awaiting: q.status === 'open' && responded.size === 0,
  };
}

export default function QuoteRequestsPage() {
  const [statusFilter, setStatusFilter] = useState<'all' | QuoteRequestStatus>('open');
  const [search, setSearch] = useState('');
  const [newOpen, setNewOpen] = useState(false);
  const { data: quotes, isLoading } = useQuoteRequests();

  const rows = useMemo(() => (quotes ?? []).map(buildRow), [quotes]);

  const visible = useMemo(() => {
    let list = rows;
    if (statusFilter !== 'all') list = list.filter(r => r.quote.status === statusFilter);
    const term = search.trim().toLowerCase();
    if (term) {
      list = list.filter(r =>
        r.quote.code.toLowerCase().includes(term) ||
        (r.quote.service_orders?.service_order_number ?? '').toLowerCase().includes(term) ||
        (r.quote.service_orders?.clients?.name ?? '').toLowerCase().includes(term) ||
        (r.quote.notes ?? '').toLowerCase().includes(term) ||
        (r.quote.quote_request_items ?? []).some(i => i.description.toLowerCase().includes(term)),
      );
    }
    return list;
  }, [rows, statusFilter, search]);

  const stats = useMemo(() => {
    const open = rows.filter(r => r.quote.status === 'open');
    return {
      open: open.length,
      silent: open.filter(r => r.awaiting && r.businessDays >= 3).length,
      negotiating: open.reduce((s, r) => s + r.bestTotal, 0),
      answered: open.filter(r => r.respondedCount > 0).length,
    };
  }, [rows]);

  const counts = useMemo(() => ({
    all: rows.length,
    open: rows.filter(r => r.quote.status === 'open').length,
    closed: rows.filter(r => r.quote.status === 'closed').length,
    cancelled: rows.filter(r => r.quote.status === 'cancelled').length,
  }), [rows]);

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Cotações"
        description="Pedidos de preço a fornecedores. O prazo é contado em dias úteis — de 3 a 5 é a janela normal de resposta."
      >
        <Button onClick={() => setNewOpen(true)} className="gap-1">
          <Plus className="h-4 w-4" /> Nova cotação
        </Button>
      </PageHeader>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KPICard title="Cotações abertas" value={String(stats.open)} icon={ClipboardList} />
        <KPICard
          title="Sem resposta há 3+ dias"
          value={String(stats.silent)}
          icon={MessageSquareWarning}
          subtitle={stats.silent ? 'precisam de cobrança' : 'nenhuma parada'}
          className={stats.silent ? 'border-destructive/30 bg-destructive/5' : undefined}
        />
        <KPICard title="Já respondidas" value={String(stats.answered)} icon={Users} subtitle="aguardando sua decisão" />
        <KPICard title="Em negociação" value={fmtBRL(stats.negotiating)} icon={TrendingDown} subtitle="pelo melhor preço de cada item" />
      </div>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-wrap gap-1.5">
          {(['open', 'closed', 'cancelled', 'all'] as const).map(s => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={cn(
                'rounded-full border px-3 py-1 text-xs font-medium transition-colors',
                statusFilter === s
                  ? 'border-primary bg-primary text-primary-foreground'
                  : 'border-border bg-card text-muted-foreground hover:bg-accent',
              )}
            >
              {s === 'all' ? 'Todas' : QUOTE_STATUS_LABELS[s]} ({counts[s]})
            </button>
          ))}
        </div>
        <div className="relative sm:w-72">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Código, OS, cliente ou item…"
            className="pl-8"
          />
        </div>
      </div>

      {isLoading ? (
        <div className="space-y-3">
          {[0, 1, 2].map(i => <Skeleton key={i} className="h-24 w-full" />)}
        </div>
      ) : visible.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
            <ClipboardList className="h-8 w-8 text-muted-foreground" />
            <div>
              <p className="font-medium">Nenhuma cotação {statusFilter === 'open' ? 'aberta' : 'encontrada'}</p>
              <p className="text-sm text-muted-foreground">
                Cotações também nascem sozinhas quando um orçamento aprovado tem item em falta.
              </p>
            </div>
            <Button variant="outline" size="sm" onClick={() => setNewOpen(true)} className="gap-1">
              <Plus className="h-4 w-4" /> Nova cotação
            </Button>
          </CardContent>
        </Card>
      ) : (
        /* Cards em vez de tabela: são 8 informações por cotação, e tabela com 8
           colunas viraria rolagem lateral no celular — o que não é aceitável aqui. */
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
          {visible.map(row => {
            const q = row.quote;
            const aging = AGING_STYLE[row.aging];
            const showAging = q.status === 'open';
            return (
              <Link
                key={q.id}
                to={`/purchasing/quotes/${q.id}`}
                className="block rounded-xl border bg-card p-4 shadow-sm transition-colors hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold tracking-tight">{q.code}</span>
                  <span className={cn('rounded-full px-2 py-0.5 text-[11px] font-medium', STATUS_CHIP[q.status])}>
                    {QUOTE_STATUS_LABELS[q.status]}
                  </span>
                  {showAging && (
                    <span className={cn('inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium', aging.chip)}>
                      <Clock className="h-3 w-3" /> {aging.label(row.businessDays)}
                    </span>
                  )}
                </div>

                {q.service_orders && (
                  <p className="mt-1.5 text-sm text-muted-foreground">
                    {q.service_orders.service_order_number}
                    {q.service_orders.clients?.name ? ` · ${q.service_orders.clients.name}` : ''}
                  </p>
                )}
                {!q.service_orders && q.notes && (
                  <p className="mt-1.5 line-clamp-2 text-sm text-muted-foreground">{q.notes}</p>
                )}

                <div className="mt-3 flex flex-wrap items-end justify-between gap-3">
                  <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                    <span>{row.itemCount} {row.itemCount === 1 ? 'item' : 'itens'}</span>
                    <span className={cn(row.respondedCount === 0 && q.status === 'open' && 'font-medium text-destructive')}>
                      {row.respondedCount} de {row.supplierCount || '—'} responderam
                    </span>
                  </div>
                  {row.bestTotal > 0 && (
                    <div className="text-right">
                      <p className="text-[11px] uppercase tracking-wide text-muted-foreground">melhor preço</p>
                      <p className="font-semibold tabular-nums">{fmtBRL(row.bestTotal)}</p>
                    </div>
                  )}
                </div>
              </Link>
            );
          })}
        </div>
      )}

      <NewQuoteRequestDialog open={newOpen} onOpenChange={setNewOpen} />
    </div>
  );
}

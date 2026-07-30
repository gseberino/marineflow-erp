import { useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  AlertTriangle, ArrowRight, CheckCircle2, ClipboardList, Clock, FileWarning,
  MessageSquareWarning, Package, ShoppingCart, Truck,
} from 'lucide-react';
import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { useQuoteRequests } from '@/hooks/use-quote-requests';
import { usePurchaseOrders, PO_STATUS_LABELS } from '@/hooks/use-purchase-orders';
import { agingLevel, businessDaysSince } from '@/lib/quote-comparison';

/**
 * Central de Compras — a visão ampla da operação.
 *
 * Formato de FILA, não de painel de gráficos: o que importa é "o que precisa de mim
 * agora", com a ação ao lado. É o mesmo desenho já validado no Dashboard v2, e segue
 * a regra dos painéis de compras de mercado — poucos indicadores (5 a 7), porque
 * painel cheio de número deixa de ser usado.
 */

const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

type Severity = 'critical' | 'warning' | 'info';

interface QueueEntry {
  key: string;
  severity: Severity;
  title: string;
  detail: string;
  actionLabel: string;
  to: string;
}

const SEVERITY_STYLE: Record<Severity, { bar: string; chip: string }> = {
  critical: { bar: 'bg-destructive', chip: 'text-destructive' },
  warning: { bar: 'bg-amber-500', chip: 'text-amber-600 dark:text-amber-400' },
  info: { bar: 'bg-primary', chip: 'text-primary' },
};

/** OS comprometidas: as que já podem estar esperando peça para andar. */
const COMMITTED_STATUSES = ['approved', 'scheduled', 'in_progress', 'awaiting_parts'];

export default function PurchasingHubPage() {
  const navigate = useNavigate();
  const { data: quotes, isLoading: loadingQuotes } = useQuoteRequests();
  const { data: pos, isLoading: loadingPOs } = usePurchaseOrders();

  // OS comprometidas com peça faltando. Calculado em uma consulta agregada em vez de
  // uma por OS — a Central não pode custar N requisições.
  const { data: shortageOrders, isLoading: loadingShortages } = useQuery({
    queryKey: ['purchasing-hub', 'shortages'],
    queryFn: async () => {
      const { data: orders, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, clients(name)')
        .in('status', COMMITTED_STATUSES)
        .order('created_at', { ascending: false })
        .limit(60);
      if (error) throw error;
      const list = (orders ?? []) as any[];
      if (!list.length) return [];

      const ids = list.map(o => o.id);
      const [partsRes, availRes, poItemsRes] = await Promise.all([
        supabase
          .from('service_order_parts')
          .select('service_order_id, product_id, quantity')
          .in('service_order_id', ids),
        supabase.from('product_availability').select('id, stock_quantity, reserved_quantity'),
        supabase
          .from('purchase_order_items')
          .select('product_id, quantity, received_qty, purchase_orders!inner(status)')
          .in('purchase_orders.status', ['draft', 'sent', 'partial']),
      ]);
      if (partsRes.error) throw partsRes.error;

      const availById = new Map<string, number>();
      for (const a of (availRes.data ?? []) as any[]) {
        availById.set(a.id, Number(a.stock_quantity ?? 0) - Number(a.reserved_quantity ?? 0));
      }
      const onOrderById = new Map<string, number>();
      for (const i of (poItemsRes.data ?? []) as any[]) {
        const pending = Math.max(0, Number(i.quantity ?? 0) - Number(i.received_qty ?? 0));
        onOrderById.set(i.product_id, (onOrderById.get(i.product_id) ?? 0) + pending);
      }

      const shortageByOrder = new Map<string, number>();
      for (const p of (partsRes.data ?? []) as any[]) {
        const need = Number(p.quantity ?? 0);
        const available = Math.max(0, availById.get(p.product_id) ?? 0);
        const onOrder = onOrderById.get(p.product_id) ?? 0;
        const shortage = Math.max(0, need - available - onOrder);
        if (shortage > 0) {
          shortageByOrder.set(p.service_order_id, (shortageByOrder.get(p.service_order_id) ?? 0) + 1);
        }
      }

      return list
        .filter(o => shortageByOrder.has(o.id))
        .map(o => ({
          id: o.id,
          number: o.service_order_number as string,
          client: o.clients?.name as string | undefined,
          status: o.status as string,
          shortageCount: shortageByOrder.get(o.id) ?? 0,
        }));
    },
    staleTime: 60_000,
  });

  const { data: pendingNotes } = useQuery({
    queryKey: ['purchasing-hub', 'fiscal-pending'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('fiscal_notes')
        .select('id, nfe_number, issuer_name, purchase_order_id, created_at')
        .is('purchase_order_id', null)
        .order('created_at', { ascending: false })
        .limit(5);
      if (error) throw error;
      return (data ?? []) as any[];
    },
    staleTime: 60_000,
  });

  const isLoading = loadingQuotes || loadingPOs || loadingShortages;

  const quoteRows = useMemo(() => {
    return (quotes ?? [])
      .filter(q => q.status === 'open')
      .map(q => {
        const priced = (q.quote_responses ?? []).filter(
          r => r.quote_request_item_id && Number(r.unit_price) > 0,
        );
        const days = businessDaysSince(q.created_at);
        return {
          quote: q,
          days,
          aging: agingLevel(days),
          responded: new Set(priced.map(r => r.supplier_id)).size,
          hasAnswer: priced.length > 0,
        };
      });
  }, [quotes]);

  const queue = useMemo<QueueEntry[]>(() => {
    const out: QueueEntry[] = [];

    // 1. Cotação respondida sem decisão: o dinheiro está parado esperando uma escolha.
    for (const r of quoteRows.filter(r => r.hasAnswer)) {
      out.push({
        key: `decide-${r.quote.id}`,
        severity: 'info',
        title: `Decidir a ${r.quote.code}`,
        detail: `${r.responded} ${r.responded === 1 ? 'fornecedor respondeu' : 'fornecedores responderam'}` +
          (r.quote.service_orders ? ` · ${r.quote.service_orders.service_order_number}` : ''),
        actionLabel: 'Comparar',
        to: `/purchasing/quotes/${r.quote.id}`,
      });
    }

    // 2. Cotação parada: fora da janela de 3-5 dias úteis do mercado.
    for (const r of quoteRows.filter(r => !r.hasAnswer && r.aging !== 'fresh')) {
      out.push({
        key: `chase-${r.quote.id}`,
        severity: r.aging === 'late' ? 'critical' : 'warning',
        title: `Cobrar resposta da ${r.quote.code}`,
        detail: `enviada há ${r.days} dias úteis sem nenhum preço` +
          (r.quote.service_orders ? ` · ${r.quote.service_orders.service_order_number}` : ''),
        actionLabel: 'Abrir',
        to: `/purchasing/quotes/${r.quote.id}`,
      });
    }

    // 3. OS comprometida sem peça: alguém vai chegar na embarcação e faltar material.
    for (const o of shortageOrders ?? []) {
      out.push({
        key: `buy-${o.id}`,
        severity: o.status === 'awaiting_parts' ? 'critical' : 'warning',
        title: `Comprar ${o.shortageCount} ${o.shortageCount === 1 ? 'item' : 'itens'} da ${o.number}`,
        detail: o.client ? `${o.client} · OS ${o.status === 'awaiting_parts' ? 'aguardando peças' : 'comprometida'}` : 'sem cliente',
        actionLabel: 'Abrir OS',
        to: `/service-orders/${o.id}`,
      });
    }

    // 4. OC em rascunho: pedido montado que ninguém mandou para o fornecedor.
    for (const po of (pos ?? []).filter(p => p.status === 'draft')) {
      out.push({
        key: `send-${po.id}`,
        severity: 'warning',
        title: `Enviar a ${po.po_number} ao fornecedor`,
        detail: `${po.suppliers?.name ?? 'sem fornecedor'} · ${fmtBRL(Number(po.total_amount) || 0)}`,
        actionLabel: 'Abrir',
        to: '/purchase-orders',
      });
    }

    // 5. Entrega vencida.
    const today = new Date().toISOString().slice(0, 10);
    for (const po of (pos ?? []).filter(
      p => (p.status === 'sent' || p.status === 'partial') && p.expected_date && p.expected_date < today,
    )) {
      out.push({
        key: `late-${po.id}`,
        severity: 'critical',
        title: `Cobrar entrega da ${po.po_number}`,
        detail: `${po.suppliers?.name ?? 'fornecedor'} · prometida para ${new Date(po.expected_date!).toLocaleDateString('pt-BR')}`,
        actionLabel: 'Abrir',
        to: '/purchase-orders',
      });
    }

    // 6. Nota recebida sem pedido: não houve confronto pedido × nota.
    for (const n of pendingNotes ?? []) {
      out.push({
        key: `unlinked-${n.id}`,
        severity: 'info',
        title: `NF ${n.nfe_number ?? ''} entrou sem ordem de compra`.trim(),
        detail: `${n.issuer_name ?? 'fornecedor'} · sem confronto pedido × nota`,
        actionLabel: 'Entrada',
        to: '/inventory/import-xml',
      });
    }

    const rank: Record<Severity, number> = { critical: 0, warning: 1, info: 2 };
    return out.sort((a, b) => rank[a.severity] - rank[b.severity]);
  }, [quoteRows, shortageOrders, pos, pendingNotes]);

  const stats = useMemo(() => {
    const open = quoteRows.length;
    const silent = quoteRows.filter(r => !r.hasAnswer && r.aging !== 'fresh').length;
    const awaitingDelivery = (pos ?? []).filter(p => p.status === 'sent' || p.status === 'partial');
    return {
      open,
      silent,
      toDecide: quoteRows.filter(r => r.hasAnswer).length,
      awaitingDelivery: awaitingDelivery.length,
      committedValue: awaitingDelivery.reduce((s, p) => s + (Number(p.total_amount) || 0), 0),
      shortageOrders: (shortageOrders ?? []).length,
    };
  }, [quoteRows, pos, shortageOrders]);

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader
        title="Central de Compras"
        description="O que precisa de você, na ordem. Cotações, pedidos, entregas e notas em um lugar."
      >
        <Button variant="outline" size="sm" className="gap-1" onClick={() => navigate('/purchasing/quotes')}>
          <ClipboardList className="h-4 w-4" /> Cotações
        </Button>
        <Button variant="outline" size="sm" className="gap-1" onClick={() => navigate('/purchase-orders')}>
          <Truck className="h-4 w-4" /> Ordens de compra
        </Button>
      </PageHeader>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KPICard
          title="Cotações abertas"
          value={String(stats.open)}
          icon={ClipboardList}
          subtitle={stats.toDecide ? `${stats.toDecide} aguardando sua decisão` : 'nenhuma respondida'}
        />
        <KPICard
          title="Cotações paradas"
          value={String(stats.silent)}
          icon={MessageSquareWarning}
          subtitle="sem resposta há 3+ dias úteis"
          className={stats.silent ? 'border-destructive/30 bg-destructive/5' : undefined}
        />
        <KPICard
          title="OS esperando peça"
          value={String(stats.shortageOrders)}
          icon={Package}
          subtitle="comprometidas com item em falta"
          className={stats.shortageOrders ? 'border-amber-500/30 bg-amber-500/5' : undefined}
        />
        <KPICard
          title="Aguardando entrega"
          value={fmtBRL(stats.committedValue)}
          icon={Truck}
          subtitle={`${stats.awaitingDelivery} ${stats.awaitingDelivery === 1 ? 'pedido' : 'pedidos'} em trânsito`}
        />
      </div>

      <section className="space-y-2">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Precisa de você
        </h2>

        {isLoading ? (
          <div className="space-y-2">
            {[0, 1, 2, 3].map(i => <Skeleton key={i} className="h-16 w-full" />)}
          </div>
        ) : queue.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
              <CheckCircle2 className="h-8 w-8 text-emerald-500" />
              <p className="font-medium">Nada pendente em compras</p>
              <p className="text-sm text-muted-foreground">
                Sem cotação parada, pedido a enviar, entrega atrasada ou OS esperando peça.
              </p>
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-2">
            {queue.map(entry => {
              const style = SEVERITY_STYLE[entry.severity];
              return (
                <div key={entry.key} className="flex items-stretch overflow-hidden rounded-lg border bg-card shadow-sm">
                  <div className={cn('w-1 shrink-0', style.bar)} aria-hidden="true" />
                  <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-1 p-3">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{entry.title}</p>
                      <p className="truncate text-xs text-muted-foreground">{entry.detail}</p>
                    </div>
                    <Button asChild size="sm" variant="outline" className="h-7 shrink-0 gap-1 px-2 text-xs">
                      <Link to={entry.to}>
                        {entry.actionLabel} <ArrowRight className="h-3 w-3" />
                      </Link>
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>

      <section className="grid grid-cols-1 gap-3 lg:grid-cols-3">
        <ShortcutCard
          to="/purchasing/quotes"
          icon={ClipboardList}
          title="Cotações"
          detail="Comparar ofertas e decidir"
        />
        <ShortcutCard
          to="/purchase-orders"
          icon={ShoppingCart}
          title="Ordens de compra"
          detail={`${(pos ?? []).length} no total · ${(pos ?? []).filter(p => p.status === 'draft').length} em rascunho`}
        />
        <ShortcutCard
          to="/inventory/import-xml"
          icon={FileWarning}
          title="Entrada de mercadoria"
          detail="Receber pelo XML da nota"
        />
      </section>
    </div>
  );
}

function ShortcutCard({
  to, icon: Icon, title, detail,
}: {
  to: string;
  icon: typeof ClipboardList;
  title: string;
  detail: string;
}) {
  return (
    <Link
      to={to}
      className="flex items-center gap-3 rounded-xl border bg-card p-4 shadow-sm transition-colors hover:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <div className="rounded-lg bg-primary/10 p-2.5">
        <Icon className="h-5 w-5 text-primary" />
      </div>
      <div className="min-w-0">
        <p className="font-medium leading-tight">{title}</p>
        <p className="truncate text-xs text-muted-foreground">{detail}</p>
      </div>
    </Link>
  );
}

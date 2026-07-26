import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowRight, Calendar, MessageCircle, Pencil, Plus } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useServiceOrders, useUpdateServiceOrderStatus } from '@/hooks/use-service-orders';
import type { ServiceOrderStatus } from '@/types/domain';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from '@/components/SendViaWhatsAppDialog';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda C · CRM & Funil v2 — reescrita do Kanban sob o Princípio 0:
   no desktop as 5 colunas dividem a largura em grid (nada rola de lado);
   abaixo de lg, as colunas empilham como seções. Cores por token. */

type SORow = {
  id: string;
  service_order_number: string;
  status?: string | null;
  grand_total?: number | null;
  scheduled_start_at?: string | null;
  created_at: string;
  share_token?: string | null;
  clients?: { id?: string; name?: string; phone?: string | null; whatsapp?: string | null } | null;
  vessels?: { name?: string } | null;
};

const COLUMNS: { id: string; title: string; tone: StatusTone; isQuote: boolean; next?: { to: ServiceOrderStatus; label: string } }[] = [
  { id: 'draft', title: 'Orçamentos', tone: 'warning', isQuote: true, next: { to: 'approved', label: 'Converter em OS' } },
  { id: 'approved', title: 'Aprovado', tone: 'info', isQuote: false, next: { to: 'scheduled', label: 'Agendar' } },
  { id: 'scheduled', title: 'Agendado', tone: 'info', isQuote: false, next: { to: 'in_progress', label: 'Iniciar' } },
  { id: 'in_progress', title: 'Em Execução', tone: 'warning', isQuote: false, next: { to: 'completed', label: 'Concluir' } },
  { id: 'completed', title: 'Concluído', tone: 'success', isQuote: false, next: { to: 'invoiced', label: 'Faturar' } },
];

const toneBorder: Record<StatusTone, string> = {
  info: 'border-t-info',
  success: 'border-t-success',
  warning: 'border-t-warning',
  critical: 'border-t-destructive',
  neutral: 'border-t-border',
};

export default function CRMKanbanV2() {
  const { formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const { data, isLoading } = useServiceOrders();
  const updateStatus = useUpdateServiceOrderStatus();
  const [whatsAppTarget, setWhatsAppTarget] = useState<SendViaWhatsAppTarget | null>(null);
  const [search, setSearch] = useState('');

  const orders = (data ?? []) as unknown as SORow[];
  const activeOrders = orders.filter((o) => {
    if (!COLUMNS.some((c) => c.id === o.status)) return false;
    if (!search.trim()) return true;
    const q = search.toLowerCase();
    return (
      (o.service_order_number || '').toLowerCase().includes(q) ||
      (o.clients?.name || '').toLowerCase().includes(q) ||
      (o.vessels?.name || '').toLowerCase().includes(q)
    );
  });

  const moveOrder = async (orderId: string, newStatus: ServiceOrderStatus) => {
    await updateStatus.mutateAsync({ id: orderId, status: newStatus });
  };

  const renderCard = (order: SORow, col: (typeof COLUMNS)[number]) => (
    <div key={order.id} className="rounded-lg border bg-card p-3 shadow-sm transition-colors hover:border-primary/40">
      <div className="mb-1.5 flex items-start justify-between gap-2">
        <span className="flex min-w-0 items-center gap-1.5">
          <StatusChip tone={col.isQuote ? 'warning' : 'info'}>{col.isQuote ? 'ORÇ' : 'OS'}</StatusChip>
          <span className="truncate text-xs font-medium text-muted-foreground">#{order.service_order_number}</span>
        </span>
        <span className="shrink-0 text-xs font-semibold tabular-nums">{formatCurrency(order.grand_total || 0)}</span>
      </div>
      <p className="truncate text-sm font-bold leading-tight">{order.clients?.name || '—'}</p>
      <p className="mb-2 truncate text-xs text-muted-foreground">{order.vessels?.name || 'Sem unidade'}</p>
      <div className="mb-2 flex items-center gap-1.5">
        <Button
          size="icon" variant="ghost" className="h-7 w-7 text-success"
          aria-label="Enviar por WhatsApp" title="Enviar por WhatsApp"
          onClick={() => setWhatsAppTarget({
            kind: 'service_order',
            serviceOrderId: order.id,
            serviceOrderNumber: order.service_order_number,
            clientPhone: order.clients?.whatsapp || order.clients?.phone || null,
            clientName: order.clients?.name || null,
            clientId: order.clients?.id || null,
            documentType: order.status === 'draft' ? 'quote' : 'service_order',
            shareToken: order.share_token,
          })}
        >
          <MessageCircle className="h-4 w-4" />
        </Button>
        <Button size="icon" variant="ghost" className="h-7 w-7" aria-label="Abrir" title="Abrir" onClick={() => navigate(`/v2/service-orders/${order.id}`)}>
          <Pencil className="h-4 w-4" />
        </Button>
        {order.scheduled_start_at && (
          <span className="ml-auto flex items-center text-xs text-muted-foreground">
            <Calendar className="mr-1 h-3 w-3" /> {formatDate(order.scheduled_start_at)}
          </span>
        )}
      </div>
      {col.next && (
        <div className="flex justify-end border-t pt-1.5">
          <Button size="sm" variant="ghost" className="h-6 gap-1 px-2 text-xs text-accent" onClick={() => moveOrder(order.id, col.next!.to)}>
            {col.next.label} <ArrowRight className="h-3 w-3" />
          </Button>
        </div>
      )}
    </div>
  );

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Operacional' }, { label: 'CRM & Funil' }]}
        title="CRM & Funil de Vendas"
        description="Acompanhe oportunidades, orçamentos e serviços em andamento."
        actions={
          <>
            <Input
              placeholder="Buscar OS, cliente, barco…"
              className="h-9 w-full sm:w-56"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <Button className="gap-1.5" onClick={() => navigate('/v2/service-orders/new')}>
              <Plus className="h-4 w-4" /> Novo Negócio
            </Button>
          </>
        }
      >
        {isLoading ? (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-5">
            {[1, 2, 3, 4, 5].map((i) => <Skeleton key={i} className="h-96 rounded-lg" />)}
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-5">
            {COLUMNS.map((col) => {
              const colOrders = activeOrders
                .filter((o) => o.status === col.id)
                .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
              const colTotal = colOrders.reduce((sum, o) => sum + (o.grand_total || 0), 0);
              return (
                <section key={col.id} className={`flex min-w-0 flex-col rounded-lg border border-t-[3px] bg-muted/30 ${toneBorder[col.tone]}`}>
                  <header className="border-b bg-card/60 p-3">
                    <div className="mb-0.5 flex items-center justify-between gap-2">
                      <h3 className="truncate text-sm font-bold">{col.title}</h3>
                      <StatusChip tone={col.tone}>{colOrders.length}</StatusChip>
                    </div>
                    <p className="text-xs font-medium text-muted-foreground tabular-nums">{formatCurrency(colTotal)}</p>
                  </header>
                  <div className="flex-1 space-y-2.5 p-2.5 lg:max-h-[62vh] lg:overflow-y-auto">
                    {colOrders.map((o) => renderCard(o, col))}
                    {colOrders.length === 0 && (
                      <p className="rounded-lg border-2 border-dashed p-4 text-center text-xs text-muted-foreground opacity-60">
                        Nenhuma OS aqui
                      </p>
                    )}
                  </div>
                </section>
              );
            })}
          </div>
        )}
      </PageShell>

      {whatsAppTarget && (
        <SendViaWhatsAppDialog
          open={!!whatsAppTarget}
          onOpenChange={(op) => !op && setWhatsAppTarget(null)}
          target={whatsAppTarget}
        />
      )}
    </V2Shell>
  );
}

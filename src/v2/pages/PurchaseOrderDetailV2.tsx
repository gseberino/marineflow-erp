import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { History, ListChecks, PackageCheck, Pencil } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useRecordHistory } from '@/hooks/use-audit-log';
import {
  usePurchaseOrder, PO_STATUS_LABELS,
  type POStatus, type PurchaseOrderItem,
} from '@/hooks/use-purchase-orders';
import { ReceivePODialog } from '@/components/ReceivePODialog';
import { RecordHistory } from '@/components/RecordHistory';
import { EntityTasksPanel } from '@/components/agenda/EntityTasksPanel';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Detalhe da Ordem de Compra.
   Existia lista e formulário, nunca uma página da OC — o que deixava as tarefas de
   compra (r7, r16) sem onde aparecer e o recebimento escondido dentro da tela de OS.
   Aqui o recebimento é o da RPC (estoque + conta a pagar), nunca uma troca de status. */

const PO_TONE: Record<POStatus, StatusTone> = {
  draft: 'neutral', sent: 'info', partial: 'warning', received: 'success', cancelled: 'critical',
};

const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v || 0);

const fmtData = (d?: string | null) =>
  d ? new Date(d + (d.length === 10 ? 'T12:00:00' : '')).toLocaleDateString('pt-BR') : '—';

/** O contador do histórico vive aqui porque nenhum hook pode ficar depois dos
 *  returns antecipados da página (React #310 — já derrubou a tela de cotação). */
function AbaHistorico({ id }: { id: string }) {
  const { data: history } = useRecordHistory('purchase_orders', id);
  const total = history?.length ?? 0;
  return (
    <TabsTrigger value="history" className="flex items-center gap-1.5">
      <History className="h-3.5 w-3.5" /> Histórico
      {total > 0 && (
        <Badge variant="secondary" className="h-4 min-w-4 px-1 text-[10px] leading-none">{total}</Badge>
      )}
    </TabsTrigger>
  );
}

export default function PurchaseOrderDetailV2() {
  const { id } = useParams<{ id: string }>();
  const { data: po, isLoading } = usePurchaseOrder(id);
  const [receberAberto, setReceberAberto] = useState(false);

  if (isLoading) {
    return (
      <V2Shell>
        <div className="space-y-4">
          <Skeleton className="h-9 w-56" />
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-4">
            {[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-24 rounded-lg" />)}
          </div>
          <Skeleton className="h-64 w-full rounded-lg" />
        </div>
      </V2Shell>
    );
  }

  if (!po) {
    return (
      <V2Shell>
        <p className="py-20 text-center text-muted-foreground">
          Ordem de compra não encontrada.{' '}
          <Link to="/v2/purchase-orders" className="text-accent hover:underline">Voltar para a lista</Link>
        </p>
      </V2Shell>
    );
  }

  const itens = po.purchase_order_items ?? [];
  const pedido = itens.reduce((s, i) => s + Number(i.quantity || 0), 0);
  const recebido = itens.reduce((s, i) => s + Number(i.received_qty || 0), 0);
  const faltando = Math.max(0, pedido - recebido);
  const podeReceber = itens.length > 0 && faltando > 0 && po.status !== 'cancelled';

  // O status pode dizer "recebido" sem nenhum item recebido: até 29/08/2026 o menu da
  // lista gravava o status direto, sem passar pela rotina que dá entrada no estoque.
  const statusMente = po.status === 'received' && recebido === 0 && pedido > 0;

  const colunas: DataColumn<PurchaseOrderItem>[] = [
    {
      key: 'item', header: 'Item', minWidth: 220, priority: 0,
      render: (i) => (
        <div className="min-w-0">
          <div className="truncate font-medium">{i.products?.name ?? i.description}</div>
          {i.products?.name && i.description !== i.products.name && (
            <div className="truncate text-xs text-muted-foreground">{i.description}</div>
          )}
        </div>
      ),
    },
    {
      key: 'qtd', header: 'Qtd', minWidth: 74, priority: 1, align: 'right',
      render: (i) => <span className="tabular-nums">{Number(i.quantity)}</span>,
    },
    {
      key: 'unit', header: 'Custo un.', minWidth: 108, priority: 1, align: 'right',
      detailLabel: 'Custo unitário',
      render: (i) => <span className="tabular-nums">{fmtBRL(Number(i.unit_cost))}</span>,
    },
    {
      key: 'total', header: 'Total', minWidth: 112, priority: 1, align: 'right',
      render: (i) => (
        <span className="font-semibold tabular-nums">
          {fmtBRL(Number(i.quantity) * Number(i.unit_cost))}
        </span>
      ),
    },
    {
      key: 'recebido', header: 'Recebido', minWidth: 96, priority: 2, align: 'right',
      detailLabel: 'Recebido',
      render: (i) => {
        const r = Number(i.received_qty || 0);
        const completo = r >= Number(i.quantity);
        return (
          <span className={completo ? 'tabular-nums text-success' : 'tabular-nums text-muted-foreground'}>
            {r} / {Number(i.quantity)}
          </span>
        );
      },
    },
    {
      key: 'sku', header: 'SKU', minWidth: 110, priority: 3, detailLabel: 'SKU',
      render: (i) => <span className="text-muted-foreground">{i.products?.sku ?? '—'}</span>,
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[
          { label: 'Operacional' },
          { label: 'Ordens de compra', to: '/v2/purchase-orders' },
          { label: po.po_number },
        ]}
        title={po.po_number}
        description={
          [po.suppliers?.name ?? 'Sem fornecedor',
           po.service_orders?.service_order_number && `OS ${po.service_orders.service_order_number}`]
            .filter(Boolean).join(' · ')
        }
        actions={
          <>
            <StatusChip dot tone={PO_TONE[po.status]}>{PO_STATUS_LABELS[po.status]}</StatusChip>
            {podeReceber && (
              <Button size="sm" className="gap-1.5" onClick={() => setReceberAberto(true)}>
                <PackageCheck className="h-4 w-4" /> Receber
              </Button>
            )}
            <Button variant="outline" size="sm" className="gap-1.5" asChild>
              <Link to="/v2/purchase-orders"><Pencil className="h-4 w-4" /> Editar na lista</Link>
            </Button>
          </>
        }
      >
        {statusMente && (
          <div className="rounded-lg border border-warning/40 bg-warning/10 p-3 text-sm">
            <strong>Marcada como recebida, mas nada foi dado como entrada.</strong> Nenhum item tem
            quantidade recebida, então o estoque não subiu e não há conta a pagar. Use{' '}
            <span className="font-medium">Receber</span> para registrar a entrada de verdade.
          </div>
        )}

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KPIStat label="Total da OC" value={fmtBRL(Number(po.total_amount))} />
          <KPIStat label="Itens" value={String(itens.length)} />
          <KPIStat
            label="Recebido"
            value={pedido > 0 ? `${recebido} de ${pedido}` : '—'}
            hint={faltando > 0 && pedido > 0 ? `faltam ${faltando}` : pedido > 0 ? 'completo' : undefined}
            tone={faltando > 0 ? 'warning' : 'success'}
          />
          <KPIStat label="Previsão de entrega" value={fmtData(po.expected_date)} />
        </div>

        <Tabs defaultValue="items">
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            <TabsTrigger value="items">Itens</TabsTrigger>
            <TabsTrigger value="tasks" className="flex items-center gap-1.5">
              <ListChecks className="h-3.5 w-3.5" /> Tarefas
            </TabsTrigger>
            {id && <AbaHistorico id={id} />}
          </TabsList>

          <TabsContent value="items" className="mt-4 space-y-2.5">
            <div className="hidden md:block">
              <DataTable<PurchaseOrderItem>
                rows={itens}
                rowKey={(i) => i.id}
                columns={colunas}
                density="compact"
                emptyMessage="Nenhum item nesta ordem de compra."
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {itens.length === 0 && (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  Nenhum item nesta ordem de compra.
                </p>
              )}
              {itens.map((i) => (
                <EntityCard
                  key={i.id}
                  title={i.products?.name ?? i.description}
                  lines={[
                    `${Number(i.quantity)} × ${fmtBRL(Number(i.unit_cost))}`,
                    `Recebido: ${Number(i.received_qty || 0)} de ${Number(i.quantity)}`,
                  ]}
                  badge={
                    <span className="text-sm font-semibold tabular-nums">
                      {fmtBRL(Number(i.quantity) * Number(i.unit_cost))}
                    </span>
                  }
                />
              ))}
            </div>
            {po.notes && (
              <div className="rounded-lg border bg-card p-3 text-sm">
                <div className="mb-1 text-xs font-medium text-muted-foreground">Observações</div>
                <p className="whitespace-pre-wrap">{po.notes}</p>
              </div>
            )}
          </TabsContent>

          <TabsContent value="tasks" className="mt-4">
            <div className="max-w-2xl">
              <EntityTasksPanel entityType="purchase_order" entityId={id} title="Tarefas desta OC" />
            </div>
          </TabsContent>

          <TabsContent value="history" className="mt-4">
            <div className="rounded-lg border bg-card p-4">
              <RecordHistory tableName="purchase_orders" recordId={id} />
            </div>
          </TabsContent>
        </Tabs>
      </PageShell>

      {receberAberto && (
        <ReceivePODialog open={receberAberto} onOpenChange={setReceberAberto} po={po} />
      )}
    </V2Shell>
  );
}

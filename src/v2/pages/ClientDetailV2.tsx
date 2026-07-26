import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Mail, MapPin, Pencil, Phone, Ship } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useClient } from '@/hooks/use-clients';
import { useVesselsForClient } from '@/hooks/use-vessels';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { RecordHistory } from '@/components/RecordHistory';
import { EntityTasksPanel } from '@/components/agenda/EntityTasksPanel';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import { serviceOrderStatusTone } from '@/v2/status-map';
import '@/v2/tokens.css';

/* Onda A/C · Detalhe do Cliente v2 — paridade com ClientDetail v1
   (contato, embarcações, OS, financeiro, tarefas, histórico) com
   breadcrumb, DataTable (as tabelas v1 tinham min-w-[600px] + scroll
   lateral) e totais preservados. */

type SORow = { id: string; service_order_number: string; service_type?: string | null; status: string; grand_total?: number | null };
type RecRow = { id: string; description: string; due_date: string; status?: string | null; amount: number };

export default function ClientDetailV2() {
  const { id } = useParams<{ id: string }>();
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();
  const { data: client, isLoading } = useClient(id);
  const { data: vessels } = useVesselsForClient(id);
  const [editOpen, setEditOpen] = useState(false);

  const { data: orders } = useQuery({
    queryKey: ['service-orders', 'client', id],
    queryFn: async () => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('service_orders').select('*').eq('client_id', id)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data as unknown as SORow[];
    },
    enabled: !!id,
  });

  const { data: clientReceivables } = useQuery({
    queryKey: ['receivables', 'client', id],
    queryFn: async () => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('receivables').select('*').eq('client_id', id)
        .order('due_date', { ascending: false });
      if (error) throw error;
      return data as unknown as RecRow[];
    },
    enabled: !!id,
  });

  if (isLoading) {
    return (
      <V2Shell>
        <div className="space-y-4">
          <Skeleton className="h-10 w-64" />
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-28 rounded-lg" />)}</div>
        </div>
      </V2Shell>
    );
  }

  if (!client) {
    return (
      <V2Shell>
        <p className="py-20 text-center text-muted-foreground">
          {t.common.noResults} <Link to="/v2/clients" className="text-accent hover:underline">← {t.common.back}</Link>
        </p>
      </V2Shell>
    );
  }

  const osColumns: DataColumn<SORow>[] = [
    {
      key: 'number', header: t.serviceOrders.orderNumber, minWidth: 120, priority: 0,
      render: (o) => <span className="font-bold text-accent">{o.service_order_number}</span>,
    },
    {
      key: 'status', header: t.common.status, minWidth: 140, priority: 1,
      render: (o) => (
        <StatusChip dot tone={serviceOrderStatusTone[o.status] ?? 'neutral'}>
          {(t.status as Record<string, string>)[o.status] ?? o.status}
        </StatusChip>
      ),
    },
    {
      key: 'total', header: t.common.total, minWidth: 116, priority: 1, align: 'right',
      render: (o) => <span className="font-semibold">{formatCurrency(o.grand_total ?? 0)}</span>,
    },
    {
      key: 'type', header: t.common.type, minWidth: 120, priority: 2, detailLabel: 'Tipo',
      render: (o) => (
        <span className="text-muted-foreground">
          {o.service_type ? (t.serviceType as Record<string, string>)[o.service_type] ?? o.service_type : '—'}
        </span>
      ),
    },
  ];

  const recTone = (status?: string | null): StatusTone =>
    status === 'paid' ? 'success' : status === 'overdue' ? 'critical' : 'warning';

  const recColumns: DataColumn<RecRow>[] = [
    {
      key: 'description', header: t.common.description, minWidth: 200, priority: 0,
      render: (r) => <span className="truncate font-medium">{r.description}</span>,
    },
    {
      key: 'due', header: t.financial.dueDate, minWidth: 110, priority: 1,
      render: (r) => <span className="text-muted-foreground tabular-nums">{formatDate(r.due_date)}</span>,
    },
    {
      key: 'status', header: t.common.status, minWidth: 110, priority: 1,
      render: (r) => (
        <StatusChip dot tone={recTone(r.status)}>
          {(t.paymentStatus as Record<string, string>)[r.status ?? 'pending'] ?? r.status}
        </StatusChip>
      ),
    },
    {
      key: 'amount', header: t.common.amount, minWidth: 116, priority: 1, align: 'right',
      render: (r) => <span className="font-semibold">{formatCurrency(r.amount)}</span>,
    },
  ];

  const recTotal = (clientReceivables ?? []).reduce((s, r) => s + Number(r.amount), 0);
  const recPaid = (clientReceivables ?? []).filter((r) => r.status === 'paid').reduce((s, r) => s + Number(r.amount), 0);

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Cadastros' }, { label: t.clients.title, to: '/v2/clients' }, { label: client.name }]}
        title={client.name}
        description={`${client.type === 'company' ? t.common.company : t.common.individual}${client.city ? ` · ${client.city}${client.state ? `/${client.state}` : ''}` : ''}`}
        actions={
          <Button variant="outline" size="sm" className="gap-1.5" onClick={() => setEditOpen(true)}>
            <Pencil className="h-4 w-4" /> {t.common.edit}
          </Button>
        }
      >
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
          <div className="space-y-2.5 rounded-lg border bg-card p-4 text-sm">
            {client.email && <p className="flex items-center gap-2"><Mail className="h-4 w-4 shrink-0 text-muted-foreground" /> <span className="truncate">{client.email}</span></p>}
            {client.phone && <p className="flex items-center gap-2"><Phone className="h-4 w-4 shrink-0 text-muted-foreground" /> {client.phone}</p>}
            {client.address_line_1 && <p className="flex items-center gap-2"><MapPin className="h-4 w-4 shrink-0 text-muted-foreground" /> <span className="truncate">{client.address_line_1}, {client.city}</span></p>}
            {client.cpf_cnpj && <p className="text-muted-foreground">{t.clients.doc}: {client.cpf_cnpj}</p>}
            {!client.email && !client.phone && !client.address_line_1 && !client.cpf_cnpj && <p className="text-muted-foreground">Sem dados de contato.</p>}
          </div>
          <KPIStat label={t.clients.vessels} value={String(vessels?.length ?? 0)} />
          <KPIStat label={t.clients.serviceOrders} value={String(orders?.length ?? 0)} />
        </div>

        <Tabs defaultValue="vessels">
          <TabsList className="flex h-auto w-full flex-wrap justify-start">
            <TabsTrigger value="vessels">{t.clients.vessels}</TabsTrigger>
            <TabsTrigger value="orders">{t.clients.serviceOrders}</TabsTrigger>
            <TabsTrigger value="financial">{t.clients.financial}</TabsTrigger>
            <TabsTrigger value="tasks">Tarefas</TabsTrigger>
            <TabsTrigger value="history">Histórico</TabsTrigger>
          </TabsList>

          <TabsContent value="vessels" className="mt-4">
            {(!vessels || vessels.length === 0) ? (
              <p className="rounded-lg border bg-card py-8 text-center text-muted-foreground">{t.vessels.noVessels}</p>
            ) : (
              <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                {vessels.map((v) => (
                  <Link key={v.id} to={`/v2/vessels/${v.id}`} className="rounded-lg border bg-card p-4 transition-colors hover:border-primary/50">
                    <div className="mb-1 flex items-start justify-between gap-2">
                      <span className="min-w-0">
                        <span className="flex items-center gap-2 truncate font-semibold"><Ship className="h-4 w-4 shrink-0 text-accent" />{v.name}</span>
                        <span className="block truncate text-sm text-muted-foreground">{v.manufacturer} {v.model} {v.year ? `(${v.year})` : ''}</span>
                      </span>
                      {v.length_feet && <span className="shrink-0 text-sm font-medium tabular-nums">{v.length_feet} ft</span>}
                    </div>
                    <p className="truncate text-xs text-muted-foreground">
                      {(v as { marinas?: { name?: string } }).marinas?.name || t.vessels.noMarina}
                      {(v as { current_dock_position?: string }).current_dock_position ? ` · ${(v as { current_dock_position?: string }).current_dock_position}` : ''}
                    </p>
                  </Link>
                ))}
              </div>
            )}
          </TabsContent>

          <TabsContent value="orders" className="mt-4 space-y-2">
            <DataTable<SORow>
              rows={orders ?? []}
              rowKey={(o) => o.id}
              columns={osColumns}
              density="compact"
              onRowClick={(o) => navigate(`/v2/service-orders/${o.id}`)}
              emptyMessage={t.common.noResults}
            />
            {orders && orders.length > 0 && (
              <p className="rounded-lg border bg-muted/40 px-4 py-2 text-sm">
                Total ({orders.length} OS): <b className="tabular-nums">{formatCurrency(orders.reduce((s, o) => s + (o.grand_total ?? 0), 0))}</b>
              </p>
            )}
          </TabsContent>

          <TabsContent value="financial" className="mt-4 space-y-2">
            <DataTable<RecRow>
              rows={clientReceivables ?? []}
              rowKey={(r) => r.id}
              columns={recColumns}
              density="compact"
              emptyMessage={t.clients.noFinancialRecords}
            />
            {clientReceivables && clientReceivables.length > 0 && (
              <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border bg-muted/40 px-4 py-2 text-sm">
                <span>Total ({clientReceivables.length} lançamentos): <b className="tabular-nums">{formatCurrency(recTotal)}</b></span>
                <span className="flex gap-4 text-xs">
                  <span className="text-success">Pago: <b className="tabular-nums">{formatCurrency(recPaid)}</b></span>
                  <span className="text-warning">Em aberto: <b className="tabular-nums">{formatCurrency(recTotal - recPaid)}</b></span>
                </span>
              </div>
            )}
          </TabsContent>

          <TabsContent value="tasks" className="mt-4">
            <EntityTasksPanel entityType="client" entityId={id} title="Tarefas deste cliente" />
          </TabsContent>

          <TabsContent value="history" className="mt-4">
            <div className="rounded-lg border bg-card p-4">
              <RecordHistory tableName="clients" recordId={id} />
            </div>
          </TabsContent>
        </Tabs>
      </PageShell>

      <ClientFormDialog open={editOpen} onOpenChange={setEditOpen} client={client} />
    </V2Shell>
  );
}

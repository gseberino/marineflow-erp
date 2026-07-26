import { useEffect, useMemo, useState } from 'react';
import {
  CheckCircle, ClipboardList, Download, FileText, History, MessageCircle,
  MoreHorizontal, Pencil, Plus, SlidersHorizontal, X,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import {
  useCollections, useMarkOverdueCollections, useCancelCollection, useSendCollectionWhatsApp,
  type CollectionFilters, type Collection, type CollectionStatus,
} from '@/hooks/use-collections';
import { useClients } from '@/hooks/use-clients';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { CollectionStatusBadge, COLLECTION_STATUS_OPTIONS } from '@/components/collections/CollectionStatusBadge';
import { CreateCollectionDialog } from '@/components/collections/CreateCollectionDialog';
import { PaymentConfirmDialog } from '@/components/collections/PaymentConfirmDialog';
import { AddContactDialog } from '@/components/collections/AddContactDialog';
import { EditContactDialog } from '@/components/collections/EditContactDialog';
import { AutoRuleDialog } from '@/components/collections/AutoRuleDialog';
import { CollectionDetailSheet } from '@/components/collections/CollectionDetailSheet';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda B · Cobranças v2 — paridade com CollectionsPage v1 (KPIs clicáveis,
   filtros completos, régua automática, dialogs e sheet reutilizados) com
   ações em 2 níveis: WhatsApp na linha, resto no menu. */

const fmtBRL = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const todayISO = () => new Date().toISOString().slice(0, 10);

export default function CollectionsV2() {
  const [filters, setFilters] = useState<CollectionFilters>({ sort_by: 'due_date', sort_dir: 'asc' });
  const [createOpen, setCreateOpen] = useState(false);
  const [ruleOpen, setRuleOpen] = useState(false);
  const [payTarget, setPayTarget] = useState<Collection | null>(null);
  const [contactTarget, setContactTarget] = useState<Collection | null>(null);
  const [editContactTarget, setEditContactTarget] = useState<Collection | null>(null);
  const [cancelTarget, setCancelTarget] = useState<Collection | null>(null);
  const [detailId, setDetailId] = useState<string | null>(null);

  const { data: collections = [], isLoading } = useCollections(filters);
  const { data: clients } = useClients();
  const cancel = useCancelCollection();
  const send = useSendCollectionWhatsApp();
  const markOverdue = useMarkOverdueCollections();

  // Igual à v1: marca vencidas ao montar
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { markOverdue.mutate(); }, []);

  const kpis = useMemo(() => {
    const open = collections.filter((c) => ['pending', 'sent', 'viewed'].includes(c.status));
    const overdue = collections.filter((c) => c.status === 'overdue');
    const totalOpen = open.reduce((s, c) => s + Number(c.amount), 0);
    const totalOverdue = overdue.reduce((s, c) => s + Number(c.amount), 0);
    const since = new Date(); since.setDate(since.getDate() - 30);
    const last30 = collections.filter((c) => new Date(c.created_at) >= since);
    const paid30 = last30.filter((c) => c.status === 'paid').length;
    const overdue30 = last30.filter((c) => c.status === 'overdue').length;
    const recovery = paid30 + overdue30 > 0 ? (paid30 / (paid30 + overdue30)) * 100 : 0;
    const now = new Date();
    const avgDays = overdue.length === 0 ? 0 :
      Math.round(overdue.reduce((s, c) => s + Math.max(0, (now.getTime() - new Date(c.due_date).getTime()) / 86400000), 0) / overdue.length);
    return { totalOpen, totalOverdue, recovery, avgDays };
  }, [collections]);

  const dueClass = (date: string, status: CollectionStatus) => {
    if (status === 'paid' || status === 'cancelled') return '';
    const t = todayISO();
    if (date < t) return 'font-medium text-destructive';
    if (date === t) return 'font-medium text-warning';
    return '';
  };

  const update = (patch: Partial<CollectionFilters>) => setFilters((f) => ({ ...f, ...patch }));
  const clearFilters = () => setFilters({ sort_by: 'due_date', sort_dir: 'asc' });

  const exportCsv = () => {
    const rows = collections.map((c) => ({
      Cliente: c.client?.name || '—',
      'OS / Ref': c.service_order?.service_order_number || 'Avulso',
      Valor: Number(c.amount).toFixed(2),
      Vencimento: new Date(c.due_date).toLocaleDateString('pt-BR'),
      Status: c.status,
      Telefone: c.phone || c.client?.phone || '',
      'Último Contato': c.last_contact_at ? new Date(c.last_contact_at).toLocaleDateString('pt-BR') : '',
    }));
    if (!rows.length) return;
    const csv = [Object.keys(rows[0]).join(','), ...rows.map((r) => Object.values(r).map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }));
    a.download = 'cobrancas.csv';
    a.click();
  };

  const renderMenu = (c: Collection) => (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Mais ações">
          <MoreHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-52">
        <DropdownMenuItem onClick={() => setPayTarget(c)} className="gap-2">
          <CheckCircle className="h-4 w-4" /> Marcar como paga
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => setContactTarget(c)} className="gap-2">
          <ClipboardList className="h-4 w-4" /> Registrar contato
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => setDetailId(c.id)} className="gap-2">
          <History className="h-4 w-4" /> Ver histórico
        </DropdownMenuItem>
        {c.service_order_id && (
          <DropdownMenuItem onClick={() => window.open(`/v2/service-orders/${c.service_order_id}`, '_blank')} className="gap-2">
            <FileText className="h-4 w-4" /> Ver OS
          </DropdownMenuItem>
        )}
        <DropdownMenuItem onClick={() => setEditContactTarget(c)} className="gap-2">
          <Pencil className="h-4 w-4" /> Alterar contato
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={() => setCancelTarget(c)} className="gap-2 text-destructive focus:text-destructive">
          <X className="h-4 w-4" /> Cancelar
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );

  const columns: DataColumn<Collection>[] = [
    {
      key: 'client', header: 'Cliente', minWidth: 180, priority: 0,
      render: (c) => <span className="block truncate font-semibold">{c.client?.name || '—'}</span>,
    },
    {
      key: 'due_date', header: 'Vencimento', minWidth: 116, priority: 1,
      render: (c) => (
        <span className={cn('tabular-nums', dueClass(c.due_date, c.status))}>
          {new Date(c.due_date).toLocaleDateString('pt-BR')}
        </span>
      ),
    },
    {
      key: 'amount', header: 'Valor', minWidth: 116, priority: 1, align: 'right',
      render: (c) => <span className="font-semibold">{fmtBRL(Number(c.amount))}</span>,
    },
    {
      key: 'status', header: 'Status', minWidth: 118, priority: 2, detailLabel: 'Status',
      render: (c) => <CollectionStatusBadge status={c.status} />,
    },
    {
      key: 'os', header: 'OS / Ref', minWidth: 110, priority: 3, detailLabel: 'OS/Ref',
      render: (c) => c.service_order?.service_order_number
        ? <span className="font-medium text-accent">{c.service_order.service_order_number}</span>
        : <span className="text-muted-foreground">Avulso</span>,
    },
    {
      key: 'phone', header: 'Contato', minWidth: 140, priority: 4, detailLabel: 'Contato',
      render: (c) => {
        const phone = c.contact_whatsapp || c.phone || c.client?.whatsapp || c.client?.phone || '';
        return phone ? <span className="truncate text-muted-foreground tabular-nums">{phone}</span> : <span className="text-muted-foreground">—</span>;
      },
    },
    {
      key: 'last_contact', header: 'Últ. contato', minWidth: 110, priority: 5, detailLabel: 'Último contato',
      render: (c) => (
        <span className="text-muted-foreground tabular-nums">
          {c.last_contact_at ? new Date(c.last_contact_at).toLocaleDateString('pt-BR') : '—'}
        </span>
      ),
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Operacional' }, { label: 'Cobranças' }]}
        title="Cobranças"
        count={collections.length}
        description="Gerencie cobranças e a régua automática"
        actions={
          <>
            <Button variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex" onClick={exportCsv}>
              <Download className="h-4 w-4" /> Exportar CSV
            </Button>
            <Button variant="outline" size="sm" className="gap-1.5" onClick={() => setRuleOpen(true)}>
              <SlidersHorizontal className="h-4 w-4" /> Régua
            </Button>
            <Button className="gap-1.5" onClick={() => setCreateOpen(true)}>
              <Plus className="h-4 w-4" /> Nova Cobrança
            </Button>
          </>
        }
      >
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <KPIStat label="Total em aberto" value={fmtBRL(kpis.totalOpen)} hint="pendentes/enviadas/vistas" tone="warning" onClick={() => update({ status: 'pending' })} />
          <KPIStat label="Total vencido" value={fmtBRL(kpis.totalOverdue)} hint="em atraso" tone={kpis.totalOverdue > 0 ? 'critical' : 'success'} onClick={() => update({ status: 'overdue' })} />
          <KPIStat label="Taxa de recuperação" value={`${kpis.recovery.toFixed(0)}%`} hint="últimos 30 dias" tone="success" />
          <KPIStat label="Média em atraso" value={`${kpis.avgDays} dias`} hint="cobranças vencidas" />
        </div>

        <div className="grid grid-cols-1 gap-3 rounded-lg border bg-card p-4 md:grid-cols-2 lg:grid-cols-4">
          <div className="space-y-1">
            <Label className="text-xs">Buscar</Label>
            <Input placeholder="Cliente ou OS…" className="h-9" value={filters.search || ''} onChange={(e) => update({ search: e.target.value || undefined })} />
          </div>
          <div className="space-y-1 md:col-span-2 lg:col-span-3">
            <Label className="text-xs">Status</Label>
            <div className="flex flex-wrap gap-1.5">
              {[{ value: 'all', label: 'Todos' }, ...COLLECTION_STATUS_OPTIONS].map((opt) => {
                const isActive = opt.value === 'all' ? !filters.status || filters.status === 'all' : filters.status === opt.value;
                return (
                  <button
                    key={opt.value}
                    type="button"
                    onClick={() => update({ status: opt.value === 'all' || isActive ? undefined : (opt.value as CollectionStatus) })}
                    className={cn(
                      'rounded-full border px-2.5 py-0.5 text-xs transition-colors',
                      isActive
                        ? 'border-primary/50 bg-primary/10 font-medium text-primary'
                        : 'border-border bg-background text-muted-foreground hover:border-primary/50',
                    )}
                  >
                    {opt.label}
                  </button>
                );
              })}
            </div>
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Cliente</Label>
            <Select value={filters.client_id || 'all'} onValueChange={(v) => update({ client_id: v === 'all' ? undefined : v })}>
              <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos</SelectItem>
                {(clients || []).map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Vence de</Label>
            <Input type="date" className="h-9" value={filters.date_from || ''} onChange={(e) => update({ date_from: e.target.value || undefined })} />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Vence até</Label>
            <Input type="date" className="h-9" value={filters.date_to || ''} onChange={(e) => update({ date_to: e.target.value || undefined })} />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Valor mín / máx</Label>
            <div className="flex gap-2">
              <Input type="number" className="h-9" value={filters.amount_min ?? ''} onChange={(e) => update({ amount_min: e.target.value ? Number(e.target.value) : undefined })} />
              <Input type="number" className="h-9" value={filters.amount_max ?? ''} onChange={(e) => update({ amount_max: e.target.value ? Number(e.target.value) : undefined })} />
              <Button variant="outline" size="sm" className="h-9 shrink-0" onClick={clearFilters}>Limpar</Button>
            </div>
          </div>
        </div>

        <div className="hidden md:block">
          <DataTable<Collection>
            rows={collections}
            rowKey={(c) => c.id}
            columns={columns}
            isLoading={isLoading}
            onRowClick={(c) => setDetailId(c.id)}
            emptyMessage="Nenhuma cobrança encontrada."
            rowClassName={(c) => (c.status === 'overdue' ? 'bg-destructive/5' : undefined)}
            rowActions={(c) => (
              <>
                <Button
                  variant="ghost" size="icon" className="h-8 w-8"
                  aria-label="Enviar WhatsApp" title="Enviar WhatsApp"
                  onClick={() => send.mutate({ collection: c })}
                >
                  <MessageCircle className="h-4 w-4" />
                </Button>
                {renderMenu(c)}
              </>
            )}
          />
        </div>

        <div className="space-y-2.5 md:hidden">
          {collections.map((c) => (
            <EntityCard
              key={c.id}
              severity={c.status === 'overdue' ? 'critical' : c.status === 'paid' ? 'success' : 'neutral'}
              badge={<CollectionStatusBadge status={c.status} />}
              title={c.client?.name || '—'}
              lines={[
                c.service_order?.service_order_number || 'Avulso',
                `${new Date(c.due_date).toLocaleDateString('pt-BR')} · ${fmtBRL(Number(c.amount))}`,
              ]}
              onClick={() => setDetailId(c.id)}
              actions={
                <>
                  <Button className="flex-1 gap-1.5" onClick={() => send.mutate({ collection: c })}>
                    <MessageCircle className="h-4 w-4" /> Cobrar
                  </Button>
                  {renderMenu(c)}
                </>
              }
            />
          ))}
          <button
            type="button"
            aria-label="Nova Cobrança"
            onClick={() => setCreateOpen(true)}
            className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
          >
            <Plus className="h-6 w-6" />
          </button>
        </div>
      </PageShell>

      <CreateCollectionDialog open={createOpen} onOpenChange={setCreateOpen} />
      <AutoRuleDialog open={ruleOpen} onOpenChange={setRuleOpen} />
      <PaymentConfirmDialog open={!!payTarget} onOpenChange={(v) => !v && setPayTarget(null)} collection={payTarget} />
      {contactTarget && (
        <AddContactDialog open={!!contactTarget} onOpenChange={(v) => !v && setContactTarget(null)} collectionId={contactTarget.id} />
      )}
      <EditContactDialog open={!!editContactTarget} onOpenChange={(v) => !v && setEditContactTarget(null)} collection={editContactTarget} />
      <CollectionDetailSheet collectionId={detailId} onClose={() => setDetailId(null)} />

      <AlertDialog open={!!cancelTarget} onOpenChange={(v) => !v && setCancelTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancelar cobrança?</AlertDialogTitle>
            <AlertDialogDescription>
              A cobrança de {cancelTarget?.client?.name} no valor de{' '}
              {cancelTarget && fmtBRL(Number(cancelTarget.amount))} será marcada como cancelada.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Voltar</AlertDialogCancel>
            <AlertDialogAction
              onClick={async () => {
                if (cancelTarget) await cancel.mutateAsync(cancelTarget.id);
                setCancelTarget(null);
              }}
            >
              Cancelar cobrança
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </V2Shell>
  );
}

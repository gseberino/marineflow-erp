import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { ChevronDown, Download, PackageCheck, Pencil, Plus, Trash2, Truck } from 'lucide-react';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import {
  usePurchaseOrders, useCreatePurchaseOrder, useUpdatePurchaseOrder, useDeletePurchaseOrder,
  useAddPOItem, useRemovePOItem, PO_STATUS_LABELS,
  type PurchaseOrder, type POStatus,
} from '@/hooks/use-purchase-orders';
import { useSuppliers } from '@/hooks/use-suppliers';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Skeleton } from '@/components/ui/skeleton';
import { Separator } from '@/components/ui/separator';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda B · Ordens de Compra v2 — paridade com PurchaseOrdersPage v1 (form com
   itens, troca rápida de status, exclusão, CSV). O dialog é cópia tokenizada
   do embutido na v1 (a v1 morre inteira na aposentadoria). */

const ALL_STATUSES: POStatus[] = ['draft', 'sent', 'partial', 'received', 'cancelled'];

const PO_TONE: Record<POStatus, StatusTone> = {
  draft: 'neutral', sent: 'info', partial: 'warning', received: 'success', cancelled: 'critical',
};

const fmtBRL = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

function POFormDialog({ open, onOpenChange, editing }: {
  open: boolean; onOpenChange: (v: boolean) => void; editing?: PurchaseOrder | null;
}) {
  const isEdit = !!editing;
  const { data: suppliers } = useSuppliers();
  const createPO = useCreatePurchaseOrder();
  const updatePO = useUpdatePurchaseOrder();
  const addItem = useAddPOItem();
  const removeItem = useRemovePOItem();

  const [supplierId, setSupplierId] = useState(editing?.supplier_id ?? '');
  const [expectedDate, setExpectedDate] = useState(editing?.expected_date ?? '');
  const [notes, setNotes] = useState(editing?.notes ?? '');
  const [status, setStatus] = useState<POStatus>(editing?.status ?? 'draft');
  const existingItems = editing?.purchase_order_items ?? [];
  const [newItems, setNewItems] = useState<Array<{ description: string; quantity: string; unit_cost: string }>>([]);

  const updateNewItem = (idx: number, field: string, val: string) =>
    setNewItems((prev) => prev.map((it, i) => (i === idx ? { ...it, [field]: val } : it)));

  const handleSave = async () => {
    if (!supplierId) { toast.error('Selecione um fornecedor'); return; }
    try {
      if (isEdit && editing) {
        await updatePO.mutateAsync({ id: editing.id, supplier_id: supplierId || null, expected_date: expectedDate || null, notes: notes || null, status });
        for (const ni of newItems) {
          if (!ni.description.trim()) continue;
          await addItem.mutateAsync({
            purchase_order_id: editing.id, product_id: null, description: ni.description,
            quantity: parseFloat(ni.quantity) || 1, unit_cost: parseFloat(ni.unit_cost) || 0, received_qty: 0,
          });
        }
      } else {
        const validItems = newItems
          .filter((i) => i.description.trim())
          .map((i) => ({
            description: i.description, quantity: parseFloat(i.quantity) || 1,
            unit_cost: parseFloat(i.unit_cost) || 0, received_qty: 0, product_id: null,
          }));
        await createPO.mutateAsync({
          supplier_id: supplierId || null, expected_date: expectedDate || null,
          notes: notes || null, status, items: validItems,
        } as never);
      }
      onOpenChange(false);
    } catch { /* toast tratado no hook */ }
  };

  const isPending = createPO.isPending || updatePO.isPending || addItem.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="themev2 max-h-[90vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? `Editar ${editing?.po_number}` : 'Nova Ordem de Compra'}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Fornecedor *</Label>
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger><SelectValue placeholder="Selecionar fornecedor" /></SelectTrigger>
                <SelectContent>
                  {(suppliers ?? []).map((s) => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Status</Label>
              <Select value={status} onValueChange={(v) => setStatus(v as POStatus)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ALL_STATUSES.map((s) => <SelectItem key={s} value={s}>{PO_STATUS_LABELS[s]}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Previsão de recebimento</Label>
              <Input type="date" value={expectedDate} onChange={(e) => setExpectedDate(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Observações</Label>
            <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} />
          </div>
          <Separator />
          <div>
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-semibold">Itens da PO</p>
              <Button type="button" size="sm" variant="outline" className="gap-1" onClick={() => setNewItems((p) => [...p, { description: '', quantity: '1', unit_cost: '0' }])}>
                <Plus className="h-3.5 w-3.5" /> Adicionar item
              </Button>
            </div>
            {existingItems.length > 0 && (
              <div className="mb-2 divide-y rounded-lg border">
                {existingItems.map((item) => (
                  <div key={item.id} className="flex items-center gap-2 px-3 py-2 text-sm">
                    <span className="min-w-0 flex-1 truncate">{item.description}</span>
                    <span className="w-14 text-right text-muted-foreground tabular-nums">x{item.quantity}</span>
                    <span className="w-20 text-right text-muted-foreground tabular-nums">{fmtBRL(Number(item.unit_cost))}</span>
                    <button
                      type="button"
                      aria-label="Remover item"
                      onClick={() => removeItem.mutate({ itemId: item.id, poId: editing!.id })}
                      className="ml-1 text-destructive hover:opacity-70"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            )}
            {newItems.map((ni, idx) => (
              <div key={idx} className="mb-2 grid grid-cols-[1fr_72px_88px_32px] items-center gap-2">
                <Input placeholder="Descrição do item" value={ni.description} onChange={(e) => updateNewItem(idx, 'description', e.target.value)} />
                <Input type="number" placeholder="Qtd" min="0" value={ni.quantity} onChange={(e) => updateNewItem(idx, 'quantity', e.target.value)} />
                <Input type="number" placeholder="Custo" min="0" step="0.01" value={ni.unit_cost} onChange={(e) => updateNewItem(idx, 'unit_cost', e.target.value)} />
                <button type="button" aria-label="Remover linha" onClick={() => setNewItems((p) => p.filter((_, i) => i !== idx))} className="text-destructive hover:opacity-70">
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
            ))}
            {newItems.length === 0 && existingItems.length === 0 && (
              <p className="py-2 text-xs text-muted-foreground">Nenhum item adicionado. Clique em "Adicionar item" para começar.</p>
            )}
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={isPending}>
            {isPending ? 'Salvando…' : isEdit ? 'Salvar alterações' : 'Criar PO'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default function PurchaseOrdersV2() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<PurchaseOrder | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);
  const [sort, setSort] = useState<SortState>({ key: 'po_number', dir: 'asc' });

  const { data: orders, isLoading, error } = usePurchaseOrders();
  const deletePO = useDeletePurchaseOrder();
  const updatePO = useUpdatePurchaseOrder();

  const filtered = useMemo(() => {
    let list = orders ?? [];
    if (statusFilter !== 'all') list = list.filter((o) => o.status === statusFilter);
    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter((o) =>
        o.po_number.toLowerCase().includes(q) ||
        (o.suppliers?.name ?? '').toLowerCase().includes(q) ||
        (o.service_orders?.service_order_number ?? '').toLowerCase().includes(q),
      );
    }
    return [...list].sort((a, b) => {
      const val = (o: PurchaseOrder): string | number => {
        if (sort.key === 'supplier') return o.suppliers?.name ?? '';
        if (sort.key === 'total_amount') return o.total_amount ?? 0;
        if (sort.key === 'expected_date') return o.expected_date ?? '';
        return String((o as unknown as Record<string, unknown>)[sort.key] ?? '');
      };
      const av = val(a);
      const bv = val(b);
      if (typeof av === 'string' && typeof bv === 'string') {
        return sort.dir === 'asc' ? av.localeCompare(bv, 'pt-BR') : bv.localeCompare(av, 'pt-BR');
      }
      return sort.dir === 'asc' ? Number(av) - Number(bv) : Number(bv) - Number(av);
    });
  }, [orders, statusFilter, search, sort]);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
  };

  const handleEdit = (po: PurchaseOrder) => { setEditing(po); setFormOpen(true); };
  const handleNew = () => { setEditing(null); setFormOpen(true); };

  const statusMenu = (po: PurchaseOrder) => (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button size="icon" variant="ghost" className="h-8 w-8" aria-label="Mudar status">
          <ChevronDown className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {ALL_STATUSES.filter((s) => s !== po.status).map((s) => (
          <DropdownMenuItem key={s} onClick={() => updatePO.mutate({ id: po.id, status: s })} className="gap-2">
            {s === 'received' && <PackageCheck className="h-3.5 w-3.5 text-success" />}
            {PO_STATUS_LABELS[s]}
          </DropdownMenuItem>
        ))}
        <DropdownMenuItem className="gap-2 text-destructive focus:text-destructive" onClick={() => setDeleteId(po.id)}>
          <Trash2 className="h-3.5 w-3.5" /> Excluir
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );

  const columns: DataColumn<PurchaseOrder>[] = [
    {
      key: 'po_number', header: 'Número', minWidth: 120, priority: 0, sortable: true,
      render: (po) => <span className="font-bold text-accent">{po.po_number}</span>,
    },
    {
      key: 'supplier', header: 'Fornecedor', minWidth: 180, priority: 1, sortable: true,
      render: (po) => <span className="truncate font-medium">{po.suppliers?.name ?? '—'}</span>,
    },
    {
      key: 'status', header: 'Status', minWidth: 118, priority: 2,
      render: (po) => <StatusChip dot tone={PO_TONE[po.status]}>{PO_STATUS_LABELS[po.status]}</StatusChip>,
    },
    {
      key: 'total_amount', header: 'Total', minWidth: 116, priority: 1, align: 'right', sortable: true,
      render: (po) => <span className="font-semibold">{fmtBRL(po.total_amount ?? 0)}</span>,
    },
    {
      key: 'expected_date', header: 'Previsão', minWidth: 108, priority: 3, sortable: true, detailLabel: 'Previsão',
      render: (po) => (
        <span className="text-muted-foreground tabular-nums">
          {po.expected_date ? format(new Date(po.expected_date), 'dd/MM/yyyy', { locale: ptBR }) : '—'}
        </span>
      ),
    },
    {
      key: 'os', header: 'OS vinculada', minWidth: 116, priority: 4, detailLabel: 'OS vinculada',
      render: (po) =>
        po.service_order_id && po.service_orders?.service_order_number ? (
          <Link to={`/v2/service-orders/${po.service_order_id}`} className="font-medium text-accent hover:underline" onClick={(e) => e.stopPropagation()}>
            {po.service_orders.service_order_number}
          </Link>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
  ];

  const exportCsv = () => {
    if (!filtered.length) return;
    const rows = filtered.map((po) => ({
      Número: po.po_number,
      Fornecedor: po.suppliers?.name || '',
      'OS Vinculada': po.service_orders?.service_order_number || '',
      Status: PO_STATUS_LABELS[po.status] || po.status,
      'Previsão Entrega': po.expected_date ? format(new Date(po.expected_date), 'dd/MM/yyyy', { locale: ptBR }) : '',
      Total: Number(po.total_amount || 0).toFixed(2),
    }));
    const csv = [Object.keys(rows[0]).join(','), ...rows.map((r) => Object.values(r).map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }));
    a.download = 'ordens_compra.csv';
    a.click();
  };

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Estoque & Compras' }, { label: 'Ordens de Compra' }]}
        title="Ordens de Compra"
        count={(orders ?? []).length}
        description="Gerencie pedidos de compra para fornecedores"
        actions={
          <>
            <Button variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex" onClick={exportCsv}>
              <Download className="h-4 w-4" /> CSV
            </Button>
            <Button className="gap-1.5" onClick={handleNew}>
              <Plus className="h-4 w-4" /> Nova PO
            </Button>
          </>
        }
      >
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {(['draft', 'sent', 'partial', 'received'] as POStatus[]).map((s) => (
            <KPIStat
              key={s}
              label={PO_STATUS_LABELS[s]}
              value={String((orders ?? []).filter((o) => o.status === s).length)}
              tone={PO_TONE[s]}
              onClick={() => setStatusFilter(statusFilter === s ? 'all' : s)}
            />
          ))}
        </div>

        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <Input
            placeholder="Buscar por número, fornecedor…"
            className="h-9 flex-1"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <div className="flex flex-wrap gap-1.5">
            {(['all', ...ALL_STATUSES] as const).map((s) => {
              const isActive = statusFilter === s;
              return (
                <button
                  key={s}
                  type="button"
                  onClick={() => setStatusFilter(s)}
                  className={cn(
                    'rounded-full border px-3 py-1 text-xs font-medium transition-colors',
                    isActive
                      ? 'border-primary bg-primary text-primary-foreground'
                      : 'border-border bg-background text-muted-foreground hover:border-primary/40',
                  )}
                >
                  {s === 'all' ? 'Todos' : PO_STATUS_LABELS[s]}
                </button>
              );
            })}
          </div>
        </div>

        {isLoading ? (
          <div className="space-y-2">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center">
            <p className="text-sm text-destructive">Erro ao carregar ordens de compra.</p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="space-y-3 rounded-lg border bg-card p-12 text-center">
            <Truck className="mx-auto h-10 w-10 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">Nenhuma ordem de compra encontrada.</p>
            <Button className="gap-1.5" onClick={handleNew}>
              <Plus className="h-4 w-4" /> Criar primeira PO
            </Button>
          </div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<PurchaseOrder>
                rows={filtered}
                rowKey={(po) => po.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                onRowClick={handleEdit}
                emptyMessage="Nenhuma ordem de compra encontrada."
                rowActions={(po) => (
                  <>
                    <Button size="icon" variant="ghost" className="h-8 w-8" aria-label="Editar" title="Editar" onClick={() => handleEdit(po)}>
                      <Pencil className="h-4 w-4" />
                    </Button>
                    {statusMenu(po)}
                  </>
                )}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {filtered.map((po) => (
                <EntityCard
                  key={po.id}
                  id={po.po_number}
                  severity={PO_TONE[po.status]}
                  badge={<StatusChip tone={PO_TONE[po.status]}>{PO_STATUS_LABELS[po.status]}</StatusChip>}
                  title={po.suppliers?.name ?? '—'}
                  lines={[
                    po.service_orders?.service_order_number ? `OS ${po.service_orders.service_order_number}` : 'Sem OS vinculada',
                    `${po.expected_date ? format(new Date(po.expected_date), 'dd/MM/yyyy', { locale: ptBR }) + ' · ' : ''}${fmtBRL(po.total_amount ?? 0)}`,
                  ]}
                  onClick={() => handleEdit(po)}
                  actions={
                    <>
                      <Button className="flex-1" onClick={() => handleEdit(po)}>Editar</Button>
                      {statusMenu(po)}
                    </>
                  }
                />
              ))}
              <button
                type="button"
                aria-label="Nova PO"
                onClick={handleNew}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </button>
            </div>
          </>
        )}
      </PageShell>

      {formOpen && (
        <POFormDialog
          key={editing?.id ?? 'new'}
          open={formOpen}
          onOpenChange={(v) => { setFormOpen(v); if (!v) setEditing(null); }}
          editing={editing}
        />
      )}

      <AlertDialog open={!!deleteId} onOpenChange={(v) => !v && setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Excluir ordem de compra?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta ação não pode ser desfeita. Todos os itens desta PO serão removidos.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={async () => { if (deleteId) await deletePO.mutateAsync(deleteId); setDeleteId(null); }}
            >
              Excluir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </V2Shell>
  );
}

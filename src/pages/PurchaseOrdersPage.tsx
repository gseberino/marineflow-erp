import { useState, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import {
  usePurchaseOrders,
  useCreatePurchaseOrder,
  useUpdatePurchaseOrder,
  useDeletePurchaseOrder,
  useAddPOItem,
  useRemovePOItem,
  PO_STATUS_LABELS,
  PO_STATUS_COLORS,
  type PurchaseOrder,
  type PurchaseOrderItem,
  type POStatus,
} from '@/hooks/use-purchase-orders';
import { useSuppliers } from '@/hooks/use-suppliers';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel,
  AlertDialogContent, AlertDialogDescription, AlertDialogFooter,
  AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils';
import { Plus, Search, Truck, Trash2, Pencil, PackageCheck, ChevronDown, ArrowUpDown, ArrowUp, ArrowDown, Download } from 'lucide-react';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { toast } from 'sonner';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

const ALL_STATUSES: POStatus[] = ['draft', 'sent', 'partial', 'received', 'cancelled'];

// ── PO Form Dialog ─────────────────────────────────────────────────────────────
function POFormDialog({
  open,
  onOpenChange,
  editing,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  editing?: PurchaseOrder | null;
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

  // Line items state
  const existingItems = editing?.purchase_order_items ?? [];
  const [newItems, setNewItems] = useState<Array<{ description: string; quantity: string; unit_cost: string }>>([]);

  const addNewItemRow = () =>
    setNewItems(prev => [...prev, { description: '', quantity: '1', unit_cost: '0' }]);

  const updateNewItem = (idx: number, field: string, val: string) =>
    setNewItems(prev => prev.map((it, i) => (i === idx ? { ...it, [field]: val } : it)));

  const removeNewItemRow = (idx: number) =>
    setNewItems(prev => prev.filter((_, i) => i !== idx));

  const handleSave = async () => {
    if (!supplierId) { toast.error('Selecione um fornecedor'); return; }
    try {
      if (isEdit && editing) {
        await updatePO.mutateAsync({ id: editing.id, supplier_id: supplierId || null, expected_date: expectedDate || null, notes: notes || null, status });
        // Add new items
        for (const ni of newItems) {
          if (!ni.description.trim()) continue;
          await addItem.mutateAsync({
            purchase_order_id: editing.id,
            product_id: null,
            description: ni.description,
            quantity: parseFloat(ni.quantity) || 1,
            unit_cost: parseFloat(ni.unit_cost) || 0,
            received_qty: 0,
          });
        }
      } else {
        const validItems = newItems
          .filter(i => i.description.trim())
          .map(i => ({
            description: i.description,
            quantity: parseFloat(i.quantity) || 1,
            unit_cost: parseFloat(i.unit_cost) || 0,
            received_qty: 0,
            product_id: null,
          }));
        await createPO.mutateAsync({
          supplier_id: supplierId || null,
          expected_date: expectedDate || null,
          notes: notes || null,
          status,
          items: validItems,
        } as any);
      }
      onOpenChange(false);
    } catch { /* toast handled in hook */ }
  };

  const isPending = createPO.isPending || updatePO.isPending || addItem.isPending;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? `Editar ${editing?.po_number}` : 'Nova Ordem de Compra'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {/* Supplier */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label>Fornecedor *</Label>
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecionar fornecedor" />
                </SelectTrigger>
                <SelectContent>
                  {(suppliers ?? []).map((s: any) => (
                    <SelectItem key={s.id} value={s.id}>{s.company_name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Status</Label>
              <Select value={status} onValueChange={v => setStatus(v as POStatus)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ALL_STATUSES.map(s => (
                    <SelectItem key={s} value={s}>{PO_STATUS_LABELS[s]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label>Previsão de recebimento</Label>
              <Input type="date" value={expectedDate} onChange={e => setExpectedDate(e.target.value)} />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label>Observações</Label>
            <Textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} />
          </div>

          <Separator />

          {/* Items */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <p className="text-sm font-semibold">Itens da PO</p>
              <Button type="button" size="sm" variant="outline" onClick={addNewItemRow}>
                <Plus className="h-3.5 w-3.5 mr-1" /> Adicionar item
              </Button>
            </div>

            {/* Existing items (edit mode) */}
            {existingItems.length > 0 && (
              <div className="rounded-lg border divide-y mb-2">
                {existingItems.map(item => (
                  <div key={item.id} className="flex items-center gap-2 px-3 py-2 text-sm">
                    <span className="flex-1">{item.description}</span>
                    <span className="text-muted-foreground w-16 text-right">x{item.quantity}</span>
                    <span className="text-muted-foreground w-20 text-right">
                      R$ {Number(item.unit_cost).toFixed(2)}
                    </span>
                    <button
                      type="button"
                      onClick={() => removeItem.mutate({ itemId: item.id, poId: editing!.id })}
                      className="text-destructive hover:opacity-70 ml-1"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* New items rows */}
            {newItems.map((ni, idx) => (
              <div key={idx} className="grid grid-cols-[1fr_80px_90px_32px] gap-2 mb-2 items-center">
                <Input
                  placeholder="Descrição do item"
                  value={ni.description}
                  onChange={e => updateNewItem(idx, 'description', e.target.value)}
                />
                <Input
                  type="number"
                  placeholder="Qtd"
                  min="0"
                  value={ni.quantity}
                  onChange={e => updateNewItem(idx, 'quantity', e.target.value)}
                />
                <Input
                  type="number"
                  placeholder="Custo unit."
                  min="0"
                  step="0.01"
                  value={ni.unit_cost}
                  onChange={e => updateNewItem(idx, 'unit_cost', e.target.value)}
                />
                <button
                  type="button"
                  onClick={() => removeNewItemRow(idx)}
                  className="text-destructive hover:opacity-70"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
            ))}

            {newItems.length === 0 && existingItems.length === 0 && (
              <p className="text-xs text-muted-foreground py-2">
                Nenhum item adicionado. Clique em "Adicionar item" para começar.
              </p>
            )}
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={handleSave} disabled={isPending}>
            {isPending ? 'Salvando...' : isEdit ? 'Salvar alterações' : 'Criar PO'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ── Main Page ─────────────────────────────────────────────────────────────────
export default function PurchaseOrdersPage() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<PurchaseOrder | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);

  const { data: orders, isLoading, error } = usePurchaseOrders();
  const deletePO = useDeletePurchaseOrder();
  const updatePO = useUpdatePurchaseOrder();

  const [sortKey, setSortKey] = useState<'po_number' | 'supplier' | 'status' | 'expected_date' | 'total_amount'>('po_number');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const handleSort = (key: typeof sortKey) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
  };
  const SortIcon = ({ col }: { col: typeof sortKey }) => {
    if (sortKey !== col) return <ArrowUpDown className="h-3 w-3 ml-1 opacity-40" />;
    return sortDir === 'desc' ? <ArrowDown className="h-3 w-3 ml-1" /> : <ArrowUp className="h-3 w-3 ml-1" />;
  };

  const filtered = useMemo(() => {
    let list = orders ?? [];
    if (statusFilter !== 'all') list = list.filter(o => o.status === statusFilter);
    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter(o =>
        o.po_number.toLowerCase().includes(q) ||
        (o.suppliers?.supplier_name ?? '').toLowerCase().includes(q) ||
        (o.service_orders?.service_order_number ?? '').toLowerCase().includes(q)
      );
    }
    return [...list].sort((a, b) => {
      let av: any, bv: any;
      if (sortKey === 'supplier') { av = a.suppliers?.supplier_name ?? ''; bv = b.suppliers?.supplier_name ?? ''; }
      else if (sortKey === 'total_amount') { av = a.total_amount ?? 0; bv = b.total_amount ?? 0; }
      else if (sortKey === 'expected_date') { av = a.expected_date ?? ''; bv = b.expected_date ?? ''; }
      else { av = (a as any)[sortKey] ?? ''; bv = (b as any)[sortKey] ?? ''; }
      if (typeof av === 'string') return sortDir === 'asc' ? av.localeCompare(bv, 'pt-BR') : bv.localeCompare(av, 'pt-BR');
      return sortDir === 'asc' ? av - bv : bv - av;
    });
  }, [orders, statusFilter, search, sortKey, sortDir]);

  const handleEdit = (po: PurchaseOrder) => { setEditing(po); setFormOpen(true); };
  const handleNew = () => { setEditing(null); setFormOpen(true); };
  const handleDelete = async () => {
    if (!deleteId) return;
    await deletePO.mutateAsync(deleteId);
    setDeleteId(null);
  };

  const handleStatusChange = (id: string, newStatus: POStatus) => {
    updatePO.mutate({ id, status: newStatus });
  };

  const formatCurrency = (v: number) =>
    new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

  return (
    <div className="flex flex-col gap-6 p-4 lg:p-6">
      <PageHeader
        title="Ordens de Compra"
        description="Gerencie pedidos de compra para fornecedores"
        icon={<Truck className="h-5 w-5" />}
        actions={
          <>
          <Button variant="outline" size="sm" className="gap-1" onClick={() => {
            if (!filtered.length) return;
            const rows = filtered.map(po => ({
              'Número': po.po_number,
              'Fornecedor': po.suppliers?.supplier_name || '',
              'OS Vinculada': po.service_orders?.service_order_number || '',
              'Status': PO_STATUS_LABELS[po.status] || po.status,
              'Previsão Entrega': po.expected_date ? format(new Date(po.expected_date), 'dd/MM/yyyy', { locale: ptBR }) : '',
              'Total': (po.items || []).reduce((s: number, it: any) => s + Number(it.total_price || 0), 0).toFixed(2),
            }));
            const csv = [Object.keys(rows[0]).join(','), ...rows.map(r => Object.values(r).map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
            const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' })); a.download = 'ordens_compra.csv'; a.click();
          }}>
            <Download className="h-3.5 w-3.5" /> CSV
          </Button>
          <Button onClick={handleNew}>
            <Plus className="h-4 w-4 mr-2" /> Nova PO
          </Button>
          </>
        }
      />

      {/* Filters */}
      <div className="flex flex-wrap gap-3 items-center">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Buscar por número, fornecedor..."
            className="pl-9"
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        <div className="flex gap-2 flex-wrap">
          {(['all', ...ALL_STATUSES] as const).map(s => {
            const isActive = statusFilter === s;
            const label = s === 'all' ? 'Todos' : PO_STATUS_LABELS[s];
            return (
              <button
                key={s}
                onClick={() => setStatusFilter(s)}
                className={cn(
                  'px-3 py-1 rounded-full text-xs font-medium border transition-colors',
                  isActive
                    ? 'bg-primary text-primary-foreground border-primary'
                    : 'bg-background border-border text-muted-foreground hover:border-primary/40'
                )}
              >
                {label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Stats row */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {(['draft', 'sent', 'partial', 'received'] as POStatus[]).map(s => {
          const count = (orders ?? []).filter(o => o.status === s).length;
          return (
            <div key={s} className="rounded-xl border bg-card p-3 shadow-sm">
              <p className="text-xs text-muted-foreground">{PO_STATUS_LABELS[s]}</p>
              <p className="text-2xl font-bold">{count}</p>
            </div>
          );
        })}
      </div>

      {/* Table */}
      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        {isLoading ? (
          <div className="p-4 space-y-3">
            {[1,2,3].map(i => <Skeleton key={i} className="h-10 w-full" />)}
          </div>
        ) : error ? (
          <div className="p-8 text-center">
            <p className="text-destructive text-sm">Erro ao carregar ordens de compra.</p>
            <p className="text-xs text-muted-foreground mt-1">
              Execute a migration SQL no Lovable para criar as tabelas necessárias.
            </p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="p-12 text-center">
            <Truck className="h-10 w-10 text-muted-foreground/30 mx-auto mb-3" />
            <p className="text-sm text-muted-foreground">Nenhuma ordem de compra encontrada.</p>
            <Button variant="outline" size="sm" className="mt-3" onClick={handleNew}>
              <Plus className="h-3.5 w-3.5 mr-1" /> Criar primeira PO
            </Button>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="cursor-pointer select-none" onClick={() => handleSort('po_number')}>
                  <span className="inline-flex items-center">Número <SortIcon col="po_number" /></span>
                </TableHead>
                <TableHead className="cursor-pointer select-none" onClick={() => handleSort('supplier')}>
                  <span className="inline-flex items-center">Fornecedor <SortIcon col="supplier" /></span>
                </TableHead>
                <TableHead className="hidden md:table-cell">OS vinculada</TableHead>
                <TableHead className="cursor-pointer select-none" onClick={() => handleSort('status')}>
                  <span className="inline-flex items-center">Status <SortIcon col="status" /></span>
                </TableHead>
                <TableHead className="hidden sm:table-cell cursor-pointer select-none" onClick={() => handleSort('expected_date')}>
                  <span className="inline-flex items-center">Previsão <SortIcon col="expected_date" /></span>
                </TableHead>
                <TableHead className="text-right hidden sm:table-cell cursor-pointer select-none" onClick={() => handleSort('total_amount')}>
                  <span className="inline-flex items-center justify-end w-full">Total <SortIcon col="total_amount" /></span>
                </TableHead>
                <TableHead className="w-24" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map(po => (
                <TableRow key={po.id} className="cursor-pointer hover:bg-muted/30">
                  <TableCell className="font-medium">{po.po_number}</TableCell>
                  <TableCell>{po.suppliers?.supplier_name ?? '—'}</TableCell>
                  <TableCell className="text-sm hidden md:table-cell">
                    {po.service_order_id && po.service_orders?.service_order_number
                      ? <Link to={`/service-orders/${po.service_order_id}`} className="text-primary hover:underline" onClick={e => e.stopPropagation()}>
                          {po.service_orders.service_order_number}
                        </Link>
                      : <span className="text-muted-foreground">—</span>}
                  </TableCell>
                  <TableCell>
                    <span className={cn('px-2 py-0.5 rounded-full text-xs font-medium', PO_STATUS_COLORS[po.status])}>
                      {PO_STATUS_LABELS[po.status]}
                    </span>
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground hidden sm:table-cell">
                    {po.expected_date
                      ? format(new Date(po.expected_date), 'dd/MM/yyyy', { locale: ptBR })
                      : '—'}
                  </TableCell>
                  <TableCell className="text-right font-medium hidden sm:table-cell">
                    {formatCurrency(po.total_amount ?? 0)}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center justify-end gap-1">
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7"
                        onClick={() => handleEdit(po)}
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>

                      {/* Status quick-change */}
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button size="icon" variant="ghost" className="h-7 w-7">
                            <ChevronDown className="h-3.5 w-3.5" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          {ALL_STATUSES.filter(s => s !== po.status).map(s => (
                            <DropdownMenuItem
                              key={s}
                              onClick={() => handleStatusChange(po.id, s)}
                            >
                              {s === 'received' && <PackageCheck className="h-3.5 w-3.5 mr-2 text-green-600" />}
                              {PO_STATUS_LABELS[s]}
                            </DropdownMenuItem>
                          ))}
                          <DropdownMenuItem
                            className="text-destructive focus:text-destructive"
                            onClick={() => setDeleteId(po.id)}
                          >
                            <Trash2 className="h-3.5 w-3.5 mr-2" /> Excluir
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>

      <POFormDialog
        open={formOpen}
        onOpenChange={v => { setFormOpen(v); if (!v) setEditing(null); }}
        editing={editing}
      />

      <AlertDialog open={!!deleteId} onOpenChange={v => !v && setDeleteId(null)}>
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
              onClick={handleDelete}
            >
              Excluir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

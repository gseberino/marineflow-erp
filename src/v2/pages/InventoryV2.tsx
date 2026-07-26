import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Download, Plus, ScanBarcode } from 'lucide-react';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import { useI18n } from '@/i18n';
import {
  useInventoryOverview, useInventoryProducts, useInventoryMovements,
  useAdjustStock, useAddStockEntry,
  type InventoryProductFilters, type MovementFilters,
} from '@/hooks/use-inventory';
import { useProducts } from '@/hooks/use-products';
import { useMultiFilter } from '@/hooks/use-multi-filter';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { MultiFilterBar } from '@/components/MultiFilterBar';
import { PriceSuggestionAlert } from '@/components/PriceSuggestionAlert';
import { BarcodeScannerModal } from '@/components/BarcodeScannerModal';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda B · Estoque v2 — paridade com InventoryPage v1 (visão geral +
   movimentos, KPIs-filtro, scanner, ajuste e entrada de estoque, CSVs).
   Dialogs são cópias tokenizadas dos embutidos na v1. */

const MOVEMENT_LABELS: Record<string, string> = {
  purchase: 'Compra', service_usage: 'Uso em OS', manual_add: 'Entrada manual',
  manual_remove: 'Saída manual', return: 'Devolução', adjustment: 'Ajuste',
  import: 'Importação', manual_adjustment: 'Ajuste',
};
const POSITIVE_TYPES = new Set(['purchase', 'manual_add', 'return', 'import']);
const NEGATIVE_TYPES = new Set(['service_usage', 'manual_remove']);
const REF_LABELS: Record<string, string> = {
  service_order: 'OS', manual_entry: 'Entrada manual',
  manual_adjustment: 'Ajuste manual', import: 'Importação',
  service_order_cancel: 'Cancel. OS',
};
const REASONS = [
  'Acerto de inventário físico', 'Perda ou dano',
  'Produto vencido', 'Correção de erro de lançamento', 'Outro',
];

type ProductRow = {
  id: string;
  name: string;
  sku?: string | null;
  unit?: string | null;
  category?: string | null;
  location_bin?: string | null;
  cost_price?: number | null;
  stock_quantity?: number | null;
  minimum_stock?: number | null;
};

type MovementRow = {
  id: string;
  created_at: string;
  movement_type: string;
  quantity_delta: number;
  unit_cost_snapshot?: number | null;
  reference_type?: string | null;
  notes?: string | null;
  products?: { name?: string } | null;
};

const stockView = (p: ProductRow): { label: string; tone: StatusTone } => {
  const qty = p.stock_quantity ?? 0;
  const min = p.minimum_stock ?? 0;
  if (qty === 0) return { label: 'Esgotado', tone: 'critical' };
  if (min > 0 && qty < min) return { label: 'Baixo', tone: 'warning' };
  return { label: 'OK', tone: 'success' };
};

function AdjustStockDialog({ product, onClose }: { product: ProductRow | null; onClose: () => void }) {
  const adjust = useAdjustStock();
  const [newQty, setNewQty] = useState(0);
  const [reason, setReason] = useState('');
  const [notes, setNotes] = useState('');
  const current = product?.stock_quantity ?? 0;
  const delta = newQty - current;

  useEffect(() => {
    if (product) { setNewQty(product.stock_quantity ?? 0); setReason(''); setNotes(''); }
  }, [product]);

  const handleSubmit = async () => {
    if (delta === 0) { toast.error('A quantidade não foi alterada. Modifique o valor antes de confirmar.'); return; }
    if (!reason) { toast.error('Selecione o motivo do ajuste antes de confirmar.'); return; }
    try {
      await adjust.mutateAsync({ product_id: product!.id, new_quantity: newQty, reason, notes: notes || undefined });
      toast.success('Estoque ajustado com sucesso');
      onClose();
    } catch (err) {
      toast.error('Erro ao ajustar estoque: ' + (err instanceof Error ? err.message : 'Tente novamente'));
    }
  };

  return (
    <Dialog open={!!product} onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="themev2 max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>Ajustar Estoque</DialogTitle></DialogHeader>
        <div className="space-y-4">
          <div>
            <p className="font-semibold">{product?.name}</p>
            <p className="text-sm text-muted-foreground">Estoque atual: {current} {product?.unit || 'un'}</p>
          </div>
          <div className="space-y-2">
            <Label>Nova quantidade</Label>
            <Input type="number" min={0} value={newQty} onChange={(e) => setNewQty(Number(e.target.value))} />
            <p className={cn('text-xs font-medium', delta > 0 ? 'text-success' : delta < 0 ? 'text-destructive' : 'text-muted-foreground')}>
              Variação: {delta > 0 ? '+' : ''}{delta} unidades
            </p>
          </div>
          <div className="space-y-2">
            <Label>Motivo *</Label>
            <Select value={reason} onValueChange={setReason}>
              <SelectTrigger><SelectValue placeholder="Selecione o motivo" /></SelectTrigger>
              <SelectContent>{REASONS.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>Observações</Label>
            <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Detalhes adicionais…" />
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={onClose}>Cancelar</Button>
            <Button onClick={handleSubmit} disabled={adjust.isPending}>
              {adjust.isPending ? 'Salvando…' : 'Confirmar Ajuste'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function AddEntryDialog({ open, onClose, product, allProducts }: {
  open: boolean; onClose: () => void; product: ProductRow | null; allProducts: ProductRow[];
}) {
  const addEntry = useAddStockEntry();
  const [selectedId, setSelectedId] = useState('');
  const [qty, setQty] = useState(1);
  const [unitCost, setUnitCost] = useState('');
  const [entryNotes, setEntryNotes] = useState('');
  const productId = product?.id || selectedId;

  const handleOpenChange = (v: boolean) => {
    if (!v) { setSelectedId(''); setQty(1); setUnitCost(''); setEntryNotes(''); onClose(); }
  };

  const handleSubmit = async () => {
    if (!productId || qty < 1) return;
    try {
      await addEntry.mutateAsync({
        product_id: productId, quantity: qty,
        unit_cost: unitCost ? Number(unitCost) : undefined,
        notes: entryNotes || undefined,
      });
      toast.success('Entrada registrada com sucesso');
      handleOpenChange(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Erro ao registrar entrada. Verifique os dados e tente novamente.');
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="themev2 max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>Entrada de Estoque</DialogTitle></DialogHeader>
        <div className="space-y-4">
          {product ? (
            <div>
              <p className="font-semibold">{product.name}</p>
              <p className="text-xs text-muted-foreground">Estoque atual: {product.stock_quantity ?? 0}</p>
            </div>
          ) : (
            <div className="space-y-2">
              <Label>Produto *</Label>
              <Select value={selectedId} onValueChange={setSelectedId}>
                <SelectTrigger><SelectValue placeholder="Selecione o produto" /></SelectTrigger>
                <SelectContent>
                  {allProducts.filter((p) => (p as ProductRow & { active?: boolean }).active).map((p) => (
                    <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <div className="space-y-2">
            <Label>Quantidade a adicionar *</Label>
            <Input type="number" min={1} value={qty} onChange={(e) => setQty(Number(e.target.value))} />
          </div>
          <div className="space-y-2">
            <Label>Custo unitário (opcional)</Label>
            <Input type="number" min={0} step={0.01} value={unitCost} onChange={(e) => setUnitCost(e.target.value)} placeholder="0.00" />
            <p className="text-xs text-muted-foreground">Informe o custo de compra desta entrada</p>
          </div>
          <div className="space-y-2">
            <Label>Notas</Label>
            <Input value={entryNotes} onChange={(e) => setEntryNotes(e.target.value)} placeholder="Ex: NF 12345, Fornecedor XYZ" />
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => handleOpenChange(false)}>Cancelar</Button>
            <Button onClick={handleSubmit} disabled={!productId || qty < 1 || addEntry.isPending}>
              {addEntry.isPending ? 'Salvando…' : 'Confirmar Entrada'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

export default function InventoryV2() {
  const { t, formatCurrency } = useI18n();
  const [searchParams, setSearchParams] = useSearchParams();
  const tab = searchParams.get('tab') || 'overview';
  const setTab = (v: string) => setSearchParams((prev) => { prev.set('tab', v); return prev; }, { replace: true });

  const [activeKpi, setActiveKpi] = useState<string>('all');
  const [prodFilters, setProdFilters] = useState<InventoryProductFilters>({ stockStatus: 'all' });
  const [movFilters, setMovFilters] = useState<MovementFilters>({});
  const [movTypeFilter, setMovTypeFilter] = useState<string[]>([]);
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' });
  const PAGE_SIZE = 20;
  const [page, setPage] = useState(1);
  const MOV_PAGE_SIZE = 30;
  const [movPage, setMovPage] = useState(1);

  const { filters: invFilters, toggle: invToggle, setField: invSetField, clearAll: invClearAll, activeCount: invActiveCount } =
    useMultiFilter({ search: '', category: [] as string[] });

  const { data: overview, isLoading: loadingOverview } = useInventoryOverview();
  const { data: products, isLoading: loadingProducts } = useInventoryProducts(prodFilters);
  const { data: movements, isLoading: loadingMovements } = useInventoryMovements(movFilters);
  const { data: allProducts } = useProducts();

  const [adjustProduct, setAdjustProduct] = useState<ProductRow | null>(null);
  const [addEntryProduct, setAddEntryProduct] = useState<ProductRow | null>(null);
  const [showAddEntry, setShowAddEntry] = useState(false);
  const [scannerOpen, setScannerOpen] = useState(false);

  const categories = useMemo(() => {
    if (!allProducts) return [];
    return Array.from(new Set(allProducts.filter((p) => p.category).map((p) => p.category!))).sort();
  }, [allProducts]);

  const sortedProducts = useMemo(() => {
    let list = ((products || []) as unknown as ProductRow[]);
    const cats = invFilters.category as string[];
    if (cats.length > 0) list = list.filter((p) => cats.includes(p.category || ''));
    return [...list].sort((a, b) => {
      const val = (p: ProductRow): string | number => {
        if (sort.key === 'status') {
          const qty = p.stock_quantity ?? 0;
          return qty === 0 ? 0 : qty < (p.minimum_stock ?? 0) ? 1 : 2;
        }
        const v = (p as Record<string, unknown>)[sort.key];
        return typeof v === 'number' ? v : String(v ?? '');
      };
      const av = val(a);
      const bv = val(b);
      if (typeof av === 'string' && typeof bv === 'string') {
        return sort.dir === 'asc' ? av.localeCompare(bv, 'pt-BR') : bv.localeCompare(av, 'pt-BR');
      }
      return sort.dir === 'asc' ? Number(av) - Number(bv) : Number(bv) - Number(av);
    });
  }, [products, invFilters.category, sort]);

  const totalPages = Math.max(1, Math.ceil(sortedProducts.length / PAGE_SIZE));
  const pagedProducts = sortedProducts.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const filteredValue = useMemo(
    () => ((products || []) as unknown as ProductRow[]).reduce((s, p) => s + (p.stock_quantity ?? 0) * (p.cost_price ?? 0), 0),
    [products],
  );

  const filteredMovements = useMemo(() => {
    let list = (movements || []) as unknown as MovementRow[];
    if (movTypeFilter.length > 0) list = list.filter((m) => movTypeFilter.includes(m.movement_type));
    return list;
  }, [movements, movTypeFilter]);
  const movTotalPages = Math.max(1, Math.ceil(filteredMovements.length / MOV_PAGE_SIZE));
  const pagedMovements = filteredMovements.slice((movPage - 1) * MOV_PAGE_SIZE, movPage * MOV_PAGE_SIZE);
  const movTotals = useMemo(() => ({
    entries: filteredMovements.filter((x) => x.quantity_delta > 0).reduce((s, x) => s + x.quantity_delta, 0),
    exits: filteredMovements.filter((x) => x.quantity_delta < 0).reduce((s, x) => s + x.quantity_delta, 0),
  }), [filteredMovements]);

  const formatDateTime = (iso: string) => {
    const d = new Date(iso);
    return d.toLocaleDateString('pt-BR') + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  };

  const handleKpiClick = (kpi: string) => {
    if (kpi === activeKpi) {
      setActiveKpi('all');
      setProdFilters((p) => ({ ...p, stockStatus: 'all' }));
    } else {
      setActiveKpi(kpi);
      setProdFilters((p) => ({ ...p, stockStatus: kpi as InventoryProductFilters['stockStatus'] }));
    }
    setTab('overview');
    setPage(1);
  };

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const productColumns: DataColumn<ProductRow>[] = [
    {
      key: 'name', header: 'Produto', minWidth: 220, priority: 0, sortable: true,
      render: (p) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{p.name}</span>
          <span className="block truncate text-xs text-muted-foreground">{p.sku || '—'}</span>
        </span>
      ),
    },
    {
      key: 'stock_quantity', header: 'Estoque', minWidth: 92, priority: 1, align: 'right', sortable: true,
      render: (p) => {
        const s = stockView(p);
        return (
          <span className={cn('font-semibold tabular-nums', s.tone === 'critical' ? 'text-destructive' : s.tone === 'warning' ? 'text-warning' : 'text-success')}>
            {p.stock_quantity ?? 0}
          </span>
        );
      },
    },
    {
      key: 'status', header: 'Status', minWidth: 96, priority: 2, sortable: true, detailLabel: 'Status',
      render: (p) => {
        const s = stockView(p);
        return <StatusChip dot tone={s.tone}>{s.label}</StatusChip>;
      },
    },
    {
      key: 'cost_price', header: 'Custo', minWidth: 108, priority: 3, align: 'right', sortable: true, detailLabel: 'Custo',
      render: (p) => <span className="text-muted-foreground">{formatCurrency(p.cost_price ?? 0)}</span>,
    },
    {
      key: 'category', header: 'Categoria', minWidth: 120, priority: 4, sortable: true, detailLabel: 'Categoria',
      render: (p) => (p.category ? <StatusChip tone="neutral">{p.category}</StatusChip> : <span className="text-muted-foreground">—</span>),
    },
    {
      key: 'location_bin', header: 'Local', minWidth: 96, priority: 5, sortable: true, detailLabel: 'Local',
      render: (p) => <span className="truncate text-muted-foreground">{p.location_bin || '—'}</span>,
    },
    {
      key: 'minimum_stock', header: 'Mín.', minWidth: 72, priority: 5, align: 'right', sortable: true, detailLabel: 'Mínimo',
      render: (p) => <span className="text-muted-foreground tabular-nums">{p.minimum_stock ?? 0}</span>,
    },
  ];

  const movementColumns: DataColumn<MovementRow>[] = [
    {
      key: 'created_at', header: 'Data/Hora', minWidth: 128, priority: 0,
      render: (m) => <span className="text-xs text-muted-foreground tabular-nums">{formatDateTime(m.created_at)}</span>,
    },
    {
      key: 'product', header: 'Produto', minWidth: 200, priority: 1,
      render: (m) => <span className="truncate font-semibold">{m.products?.name || '—'}</span>,
    },
    {
      key: 'type', header: t.common.type, minWidth: 128, priority: 2, detailLabel: 'Tipo',
      render: (m) => {
        const tone: StatusTone = POSITIVE_TYPES.has(m.movement_type) ? 'success' : NEGATIVE_TYPES.has(m.movement_type) ? 'critical' : 'info';
        return <StatusChip tone={tone}>{MOVEMENT_LABELS[m.movement_type] || m.movement_type}</StatusChip>;
      },
    },
    {
      key: 'qty', header: 'Qtd', minWidth: 76, priority: 1, align: 'right',
      render: (m) => (
        <span className={cn('font-semibold tabular-nums', m.quantity_delta > 0 ? 'text-success' : 'text-destructive')}>
          {m.quantity_delta > 0 ? '+' : ''}{m.quantity_delta}
        </span>
      ),
    },
    {
      key: 'cost', header: 'Custo Unit.', minWidth: 104, priority: 3, align: 'right', detailLabel: 'Custo unit.',
      render: (m) => <span className="text-muted-foreground">{m.unit_cost_snapshot ? formatCurrency(m.unit_cost_snapshot) : '—'}</span>,
    },
    {
      key: 'ref', header: t.inventory.reference, minWidth: 110, priority: 4, detailLabel: 'Referência',
      render: (m) => <span className="text-xs text-muted-foreground">{REF_LABELS[m.reference_type || ''] || m.reference_type || '—'}</span>,
    },
    {
      key: 'notes', header: t.common.notes, minWidth: 160, priority: 5, detailLabel: 'Notas',
      render: (m) => <span className="truncate text-xs text-muted-foreground">{m.notes || '—'}</span>,
    },
  ];

  const exportProductsCsv = () => {
    const rows = sortedProducts.map((p) => ({
      Produto: p.name, SKU: p.sku || '', Categoria: p.category || '', Local: p.location_bin || '',
      Custo: Number(p.cost_price ?? 0).toFixed(2), Estoque: p.stock_quantity ?? 0, 'Mínimo': p.minimum_stock ?? 0,
    }));
    if (!rows.length) return;
    const csv = [Object.keys(rows[0]).join(','), ...rows.map((r) => Object.values(r).map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }));
    a.download = 'estoque.csv';
    a.click();
  };

  const exportMovementsCsv = () => {
    if (!filteredMovements.length) return;
    const rows = filteredMovements.map((m) => ({
      'Data/Hora': formatDateTime(m.created_at),
      Produto: m.products?.name || '',
      Tipo: MOVEMENT_LABELS[m.movement_type] || m.movement_type,
      Quantidade: m.quantity_delta,
      'Custo Unit.': m.unit_cost_snapshot ?? '',
      Notas: m.notes || '',
    }));
    const csv = [Object.keys(rows[0]).join(','), ...rows.map((r) => Object.values(r).map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }));
    a.download = 'movimentos_estoque.csv';
    a.click();
  };

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Estoque & Compras' }, { label: t.inventory.title }]}
        title={t.inventory.title}
        description={t.inventory.description}
        actions={
          <>
            <Button variant="outline" size="sm" className="gap-1.5" onClick={() => setScannerOpen(true)}>
              <ScanBarcode className="h-4 w-4" /> Scanner
            </Button>
            <Button className="gap-1.5" onClick={() => { setAddEntryProduct(null); setShowAddEntry(true); }}>
              <Plus className="h-4 w-4" /> {t.inventory.addEntry}
            </Button>
          </>
        }
      >
        <PriceSuggestionAlert />

        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          {loadingOverview ? (
            Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-lg" />)
          ) : (
            <>
              <KPIStat
                label={t.inventory.totalProducts}
                value={String(overview?.total_products ?? 0)}
                hint={activeKpi === 'all' ? 'todos visíveis' : 'clique para ver todos'}
                onClick={() => handleKpiClick('all')}
                className={activeKpi === 'all' ? 'ring-2 ring-ring' : undefined}
              />
              <KPIStat
                label={t.inventory.lowStockCount}
                value={String(overview?.low_stock_count ?? 0)}
                tone={(overview?.low_stock_count ?? 0) > 0 ? 'warning' : 'success'}
                hint={activeKpi === 'low' ? 'filtro ativo' : 'clique para filtrar'}
                onClick={() => handleKpiClick('low')}
                className={activeKpi === 'low' ? 'ring-2 ring-ring' : undefined}
              />
              <KPIStat
                label={t.inventory.outOfStock}
                value={String(overview?.out_of_stock_count ?? 0)}
                tone={(overview?.out_of_stock_count ?? 0) > 0 ? 'critical' : 'success'}
                hint={activeKpi === 'out' ? 'filtro ativo' : 'clique para filtrar'}
                onClick={() => handleKpiClick('out')}
                className={activeKpi === 'out' ? 'ring-2 ring-ring' : undefined}
              />
              <KPIStat label={t.inventory.totalValue} value={formatCurrency(overview?.total_stock_value ?? 0)} hint={t.inventory.costTotal} />
            </>
          )}
        </div>

        <Tabs value={tab} onValueChange={setTab}>
          <TabsList>
            <TabsTrigger value="overview">{t.inventory.overview}</TabsTrigger>
            <TabsTrigger value="movements">{t.inventory.movements}</TabsTrigger>
          </TabsList>

          <TabsContent value="overview" className="mt-4 space-y-4">
            <MultiFilterBar
              search={String(invFilters.search || '')}
              onSearchChange={(v) => { invSetField('search', v); setProdFilters((p) => ({ ...p, search: v })); setPage(1); }}
              searchPlaceholder="Buscar produto, SKU…"
              filters={invFilters}
              activeCount={invActiveCount}
              onToggle={(f, v) => { invToggle(f, v); setPage(1); }}
              onSetField={invSetField}
              onClearAll={() => { invClearAll(); setProdFilters((p) => ({ ...p, search: '', category: undefined })); setPage(1); }}
              presetType="inventory"
              groups={categories.length > 0 ? [{
                type: 'multi' as const,
                field: 'category',
                label: 'Categoria',
                options: categories.map((c) => ({ value: c, label: c })),
              }] : []}
              extra={
                <Button variant="outline" size="sm" className="gap-1" onClick={exportProductsCsv}>
                  <Download className="h-4 w-4" /> CSV
                </Button>
              }
            />

            <div className="hidden md:block">
              <DataTable<ProductRow>
                rows={pagedProducts}
                rowKey={(p) => p.id}
                columns={productColumns}
                sort={sort}
                onSort={handleSort}
                isLoading={loadingProducts}
                emptyMessage={t.common.noResults}
                rowClassName={(p) => {
                  const s = stockView(p);
                  return s.tone === 'critical' ? 'bg-destructive/5' : s.tone === 'warning' ? 'bg-warning/5' : undefined;
                }}
                rowActions={(p) => (
                  <>
                    <Button size="sm" variant="outline" onClick={() => setAdjustProduct(p)}>Ajustar</Button>
                    <Button size="icon" variant="ghost" className="h-8 w-8" aria-label="Entrada de estoque" title="Entrada de estoque" onClick={() => { setAddEntryProduct(p); setShowAddEntry(true); }}>
                      <Plus className="h-4 w-4" />
                    </Button>
                  </>
                )}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {pagedProducts.map((p) => {
                const s = stockView(p);
                return (
                  <EntityCard
                    key={p.id}
                    severity={s.tone}
                    badge={<StatusChip tone={s.tone}>{s.label}</StatusChip>}
                    title={p.name}
                    lines={[
                      [p.sku, p.category].filter(Boolean).join(' · ') || '—',
                      `Estoque ${p.stock_quantity ?? 0} · mín ${p.minimum_stock ?? 0} · ${formatCurrency(p.cost_price ?? 0)}`,
                    ]}
                    actions={
                      <>
                        <Button className="flex-1" onClick={() => setAdjustProduct(p)}>Ajustar</Button>
                        <Button variant="outline" size="icon" className="h-11 w-11" aria-label="Entrada" onClick={() => { setAddEntryProduct(p); setShowAddEntry(true); }}>
                          <Plus className="h-4 w-4" />
                        </Button>
                      </>
                    }
                  />
                );
              })}
            </div>

            <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-muted-foreground">
              <span>{sortedProducts.length} produtos · Página {page} de {totalPages} · {t.inventory.filteredValue}: <b className="text-foreground">{formatCurrency(filteredValue)}</b></span>
              {totalPages > 1 && (
                <span className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </span>
              )}
            </div>
          </TabsContent>

          <TabsContent value="movements" className="mt-4 space-y-4">
            <div className="flex flex-wrap items-center gap-3">
              <Select
                value={movFilters.product_id || '__all'}
                onValueChange={(v) => { setMovFilters((p) => ({ ...p, product_id: v === '__all' ? undefined : v })); setMovPage(1); }}
              >
                <SelectTrigger className="h-9 w-full sm:w-56"><SelectValue placeholder={t.inventory.allProducts} /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__all">{t.inventory.allProducts}</SelectItem>
                  {(allProducts || []).map((p) => <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
              <div className="flex flex-wrap items-center gap-1.5">
                <span className="shrink-0 text-xs text-muted-foreground">Tipo:</span>
                <button
                  type="button"
                  onClick={() => { setMovTypeFilter([]); setMovPage(1); }}
                  className={cn(
                    'rounded-full border px-2.5 py-0.5 text-xs transition-colors',
                    movTypeFilter.length === 0
                      ? 'border-primary/50 bg-primary/10 font-medium text-primary'
                      : 'border-border bg-background text-muted-foreground hover:border-primary/50',
                  )}
                >
                  Todos
                </button>
                {Object.entries(MOVEMENT_LABELS).map(([k, v]) => (
                  <button
                    key={k}
                    type="button"
                    onClick={() => { setMovTypeFilter((prev) => prev.includes(k) ? prev.filter((x) => x !== k) : [...prev, k]); setMovPage(1); }}
                    className={cn(
                      'rounded-full border px-2.5 py-0.5 text-xs transition-colors',
                      movTypeFilter.includes(k)
                        ? 'border-primary/50 bg-primary/10 font-medium text-primary'
                        : 'border-border bg-background text-muted-foreground hover:border-primary/50',
                    )}
                  >
                    {v}
                  </button>
                ))}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <Label className="text-xs">De</Label>
                <Input type="date" className="h-9 w-36" value={movFilters.dateFrom || ''} onChange={(e) => { setMovFilters((p) => ({ ...p, dateFrom: e.target.value || undefined })); setMovPage(1); }} />
                <Label className="text-xs">Até</Label>
                <Input type="date" className="h-9 w-36" value={movFilters.dateTo || ''} onChange={(e) => { setMovFilters((p) => ({ ...p, dateTo: e.target.value || undefined })); setMovPage(1); }} />
              </div>
              {(movFilters.product_id || movTypeFilter.length > 0 || movFilters.dateFrom || movFilters.dateTo) && (
                <Button size="sm" variant="ghost" onClick={() => { setMovFilters({}); setMovTypeFilter([]); setMovPage(1); }}>Limpar filtros</Button>
              )}
              <Button variant="outline" size="sm" className="ml-auto gap-1" onClick={exportMovementsCsv}>
                <Download className="h-4 w-4" /> Exportar
              </Button>
            </div>

            <div className="hidden md:block">
              <DataTable<MovementRow>
                rows={pagedMovements}
                rowKey={(m) => m.id}
                columns={movementColumns}
                density="compact"
                isLoading={loadingMovements}
                emptyMessage={t.common.noResults}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {pagedMovements.map((m) => {
                const tone: StatusTone = POSITIVE_TYPES.has(m.movement_type) ? 'success' : NEGATIVE_TYPES.has(m.movement_type) ? 'critical' : 'info';
                return (
                  <EntityCard
                    key={m.id}
                    severity={tone}
                    badge={<StatusChip tone={tone}>{MOVEMENT_LABELS[m.movement_type] || m.movement_type}</StatusChip>}
                    title={m.products?.name || '—'}
                    lines={[
                      `${m.quantity_delta > 0 ? '+' : ''}${m.quantity_delta} un · ${m.unit_cost_snapshot ? formatCurrency(m.unit_cost_snapshot) : 'sem custo'}`,
                      formatDateTime(m.created_at),
                    ]}
                  />
                );
              })}
            </div>

            <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-muted-foreground">
              <span>
                {t.inventory.totalEntries}: <b className="text-success">+{movTotals.entries}</b>
                {' · '}
                {t.inventory.totalExits}: <b className="text-destructive">{movTotals.exits}</b>
                {movTotalPages > 1 && ` · Página ${movPage} de ${movTotalPages}`}
              </span>
              {movTotalPages > 1 && (
                <span className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setMovPage((p) => Math.max(1, p - 1))} disabled={movPage === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setMovPage((p) => Math.min(movTotalPages, p + 1))} disabled={movPage === movTotalPages}>Próxima</Button>
                </span>
              )}
            </div>
          </TabsContent>
        </Tabs>
      </PageShell>

      <AdjustStockDialog product={adjustProduct} onClose={() => setAdjustProduct(null)} />
      <AddEntryDialog
        open={showAddEntry}
        onClose={() => { setShowAddEntry(false); setAddEntryProduct(null); }}
        product={addEntryProduct}
        allProducts={(allProducts || []) as unknown as ProductRow[]}
      />
      <BarcodeScannerModal
        open={scannerOpen}
        onOpenChange={setScannerOpen}
        onProductScanned={(p) => {
          setScannerOpen(false);
          setTimeout(() => setAdjustProduct(p as unknown as ProductRow), 100);
        }}
      />
    </V2Shell>
  );
}

import { useState, useMemo, useEffect } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { KPICard } from '@/components/KPICard';
import {
  useInventoryOverview,
  useInventoryProducts,
  useInventoryMovements,
  useAdjustStock,
  useAddStockEntry,
  type InventoryProductFilters,
  type MovementFilters,
} from '@/hooks/use-inventory';
import { useProducts } from '@/hooks/use-products';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Package, TrendingDown, AlertTriangle, Plus, DollarSign, ChevronUp, ChevronDown, ScanBarcode, ChevronLeft, ChevronRight
} from 'lucide-react';
import { toast } from 'sonner';
import { PriceSuggestionAlert } from '@/components/PriceSuggestionAlert';
import { BarcodeScannerModal } from '@/components/BarcodeScannerModal';
import { useMultiFilter } from '@/hooks/use-multi-filter';
import { MultiFilterBar } from '@/components/MultiFilterBar';

// ── Movement labels & colors ──────────────────────────────
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

// ── Sort Icon ─────────────────────────────────────────────
function SortIcon({ field, sortField, sortDir }: { field: string; sortField: string; sortDir: 'asc' | 'desc' }) {
  if (sortField !== field) return <span className="text-muted-foreground/40 text-xs">↕</span>;
  return sortDir === 'asc'
    ? <ChevronUp className="h-3 w-3 text-primary" />
    : <ChevronDown className="h-3 w-3 text-primary" />;
}

// ── Main Page ─────────────────────────────────────────────
export default function InventoryPage() {
  const { t, formatCurrency } = useI18n();
  const [tab, setTab] = useState('overview');

  // ── Filters ──
  const [activeKpi, setActiveKpi] = useState<string>('all');
  const [prodFilters, setProdFilters] = useState<InventoryProductFilters>({ stockStatus: 'all' });
  const [movFilters, setMovFilters] = useState<MovementFilters>({});

  // ── Sort ──
  const [sortField, setSortField] = useState<string>('product_name');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');

  // ── Pagination ──
  const PAGE_SIZE = 20;
  const [page, setPage] = useState(1);

  // ── Multi-filters (overview tab) ──
  const { filters: invFilters, toggle: invToggle, setField: invSetField, clearAll: invClearAll, activeCount: invActiveCount } = useMultiFilter({ search: '', category: [] as string[] });
  // ── Movement type multi-filter ──
  const [movTypeFilter, setMovTypeFilter] = useState<string[]>([]);
  const MOV_PAGE_SIZE = 30;
  const [movPage, setMovPage] = useState(1);
  const toggleSort = (field: string) => {
    if (sortField === field) {
      setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDir('asc');
    }
  };

  // ── Data ──
  const { data: overview, isLoading: loadingOverview } = useInventoryOverview();
  const { data: products, isLoading: loadingProducts } = useInventoryProducts(prodFilters);
  const { data: movements, isLoading: loadingMovements } = useInventoryMovements(movFilters);
  const { data: allProducts } = useProducts();

  // ── Dialogs ──
  const [adjustProduct, setAdjustProduct] = useState<any>(null);
  const [addEntryProduct, setAddEntryProduct] = useState<any>(null);
  const [showAddEntry, setShowAddEntry] = useState(false);
  const [scannerOpen, setScannerOpen] = useState(false);

  // ── Categories list ──
  const categories = useMemo(() => {
    if (!allProducts) return [];
    const set = new Set(allProducts.filter(p => p.category).map(p => p.category!));
    return Array.from(set).sort();
  }, [allProducts]);

  // ── Sorted products (with client-side category filter) ──
  const sortedProducts = useMemo(() => {
    let list = products || [];
    const cats = invFilters.category as string[];
    if (cats.length > 0) {
      list = list.filter(p => cats.includes(p.category || ''));
    }
    if (!list.length) return [];
    return [...list].sort((a, b) => {
      let aVal: any, bVal: any;
      if (sortField === 'status') {
        const getStatus = (p: any) => {
          if ((p.stock_quantity ?? 0) === 0) return 0;
          if ((p.stock_quantity ?? 0) < (p.minimum_stock ?? 0)) return 1;
          return 2;
        };
        aVal = getStatus(a); bVal = getStatus(b);
      } else {
        aVal = (a as any)[sortField] ?? '';
        bVal = (b as any)[sortField] ?? '';
      }
      if (typeof aVal === 'string') {
        return sortDir === 'asc'
          ? aVal.localeCompare(bVal, 'pt-BR')
          : bVal.localeCompare(aVal, 'pt-BR');
      }
      return sortDir === 'asc' ? aVal - bVal : bVal - aVal;
    });
  }, [products, invFilters.category, sortField, sortDir]);

  // Reset to page 1 when filters or sort change
  const sortedKey = `${sortField}-${sortDir}-${(invFilters.category as string[]).join(',')}`;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useMemo(() => setPage(1), [sortedKey]);

  const totalPages = Math.ceil(sortedProducts.length / PAGE_SIZE);
  const pagedProducts = sortedProducts.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  // ── Filtered totals ──
  const filteredValue = useMemo(() =>
    (products || []).reduce((s, p) => s + (p.stock_quantity ?? 0) * (p.cost_price ?? 0), 0)
  , [products]);

  // ── Filtered movements (client-side type filter) ──
  const filteredMovements = useMemo(() => {
    let list = movements || [];
    if (movTypeFilter.length > 0) {
      list = list.filter(m => movTypeFilter.includes(m.movement_type));
    }
    return list;
  }, [movements, movTypeFilter]);

  const movTotalPages = Math.ceil(filteredMovements.length / MOV_PAGE_SIZE);
  const pagedMovements = filteredMovements.slice((movPage - 1) * MOV_PAGE_SIZE, movPage * MOV_PAGE_SIZE);

  // ── Movement totals ──
  const movTotals = useMemo(() => {
    const m = filteredMovements;
    return {
      entries: m.filter(x => x.quantity_delta > 0).reduce((s, x) => s + x.quantity_delta, 0),
      exits: m.filter(x => x.quantity_delta < 0).reduce((s, x) => s + x.quantity_delta, 0),
    };
  }, [filteredMovements]);

  const formatDateTime = (iso: string) => {
    const d = new Date(iso);
    return d.toLocaleDateString('pt-BR') + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  };

  // ── KPI click handler ──
  const handleKpiClick = (kpi: string) => {
    if (kpi === activeKpi) {
      setActiveKpi('all');
      setProdFilters(p => ({ ...p, stockStatus: 'all' }));
    } else {
      setActiveKpi(kpi);
      setProdFilters(p => ({ ...p, stockStatus: kpi as any }));
    }
    setTab('overview');
  };

  const kpiRing = (kpi: string) =>
    activeKpi === kpi ? 'ring-2 ring-primary ring-offset-2' : '';

  const kpiHint = (kpi: string, filterLabel: string) =>
    activeKpi === kpi ? 'Filtro ativo — clique para limpar' : filterLabel;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.inventory.title} description={t.inventory.description}>
        <div className="flex items-center gap-2">
          <Button variant="outline" onClick={() => setScannerOpen(true)}>
            <ScanBarcode className="h-4 w-4 mr-2" /> Scanner
          </Button>
          <Button onClick={() => { setAddEntryProduct(null); setShowAddEntry(true); }}>
            <Plus className="h-4 w-4 mr-1" /> {t.inventory.addEntry}
          </Button>
        </div>
      </PageHeader>

      <PriceSuggestionAlert />

      {/* KPI Cards — clickable filters */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {loadingOverview ? (
          Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-28 rounded-xl" />)
        ) : (
          <>
            <div
              className={`cursor-pointer transition-all ${kpiRing('all')}`}
              onClick={() => handleKpiClick('all')}
            >
              <KPICard
                title={t.inventory.totalProducts}
                value={String(overview?.total_products ?? 0)}
                subtitle={kpiHint('all', 'Clique para ver todos')}
                icon={Package}
              />
            </div>
            <div
              className={`cursor-pointer transition-all ${kpiRing('low')}`}
              onClick={() => handleKpiClick('low')}
            >
              <KPICard
                title={t.inventory.lowStockCount}
                value={String(overview?.low_stock_count ?? 0)}
                subtitle={kpiHint('low', 'Clique para filtrar')}
                icon={AlertTriangle}
                className={(overview?.low_stock_count ?? 0) > 0 ? 'border-amber-300 bg-amber-50/50 dark:bg-amber-950/20' : ''}
              />
            </div>
            <div
              className={`cursor-pointer transition-all ${kpiRing('out')}`}
              onClick={() => handleKpiClick('out')}
            >
              <KPICard
                title={t.inventory.outOfStock}
                value={String(overview?.out_of_stock_count ?? 0)}
                subtitle={kpiHint('out', 'Clique para filtrar')}
                icon={TrendingDown}
                className={(overview?.out_of_stock_count ?? 0) > 0 ? 'border-destructive/50 bg-destructive/5' : ''}
              />
            </div>
            <div>
              <KPICard
                title={t.inventory.totalValue}
                value={formatCurrency(overview?.total_stock_value ?? 0)}
                subtitle={t.inventory.costTotal}
                icon={DollarSign}
              />
            </div>
          </>
        )}
      </div>

      {/* Tabs */}
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="overview">{t.inventory.overview}</TabsTrigger>
          <TabsTrigger value="movements">{t.inventory.movements}</TabsTrigger>
        </TabsList>

        {/* ── Tab 1: Overview ── */}
        <TabsContent value="overview" className="space-y-4">
          {/* Filters — search + category multi-select */}
          <MultiFilterBar
            search={invFilters.search as string}
            onSearchChange={v => { invSetField('search', v); setProdFilters(p => ({ ...p, search: v })); }}
            searchPlaceholder="Buscar produto, SKU..."
            filters={invFilters}
            activeCount={invActiveCount}
            onToggle={invToggle}
            onSetField={invSetField}
            onClearAll={() => { invClearAll(); setProdFilters(p => ({ ...p, search: '', category: undefined })); }}
            groups={categories.length > 0 ? [
              {
                type: 'multi' as const,
                field: 'category',
                label: 'Categoria',
                options: categories.map(c => ({ value: c, label: c })),
              },
            ] : []}
          />

          {/* Products table with sortable headers */}
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[900px]">
              <thead>
                <tr className="border-b bg-muted/50">
                  {([
                    { label: 'Produto', field: 'product_name', align: 'text-left', hide: '' },
                    { label: 'SKU', field: 'sku', align: 'text-left', hide: 'hidden md:table-cell' },
                    { label: 'Categoria', field: 'category', align: 'text-left', hide: 'hidden lg:table-cell' },
                    { label: 'Local', field: 'location_bin', align: 'text-left', hide: 'hidden lg:table-cell' },
                    { label: 'Custo', field: 'cost_price', align: 'text-right', hide: 'hidden md:table-cell' },
                    { label: 'Estoque', field: 'stock_quantity', align: 'text-center', hide: '' },
                    { label: 'Mín.', field: 'minimum_stock', align: 'text-center', hide: 'hidden sm:table-cell' },
                    { label: 'Status', field: 'status', align: 'text-center', hide: '' },
                  ] as const).map(col => (
                    <th
                      key={col.field}
                      onClick={() => toggleSort(col.field)}
                      className={`px-4 py-3 ${col.align} font-medium text-muted-foreground cursor-pointer select-none hover:bg-muted/50 transition-colors ${col.hide}`}
                    >
                      <div className={`flex items-center gap-1 ${col.align === 'text-right' ? 'justify-end' : col.align === 'text-center' ? 'justify-center' : ''}`}>
                        {col.label}
                        <SortIcon field={col.field} sortField={sortField} sortDir={sortDir} />
                      </div>
                    </th>
                  ))}
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.actions}</th>
                </tr>
              </thead>
              <tbody>
                {loadingProducts ? (
                  Array.from({ length: 5 }).map((_, i) => (
                    <tr key={i} className="border-b"><td colSpan={9} className="p-3"><Skeleton className="h-8 w-full" /></td></tr>
                  ))
                ) : !sortedProducts.length ? (
                  <tr><td colSpan={9} className="text-center py-10 text-muted-foreground">{t.common.noResults}</td></tr>
                ) : (
                  pagedProducts.map(p => {
                    const qty = p.stock_quantity ?? 0;
                    const min = p.minimum_stock ?? 0;
                    const isOut = qty === 0;
                    const isLow = !isOut && min > 0 && qty < min;
                    return (
                      <tr key={p.id} className="border-b last:border-0 hover:bg-muted/30">
                        <td className="px-4 py-3 font-medium">{p.product_name}</td>
                        <td className="px-4 py-3 text-muted-foreground hidden md:table-cell">{p.sku || '—'}</td>
                        <td className="px-4 py-3 hidden lg:table-cell">{p.category || '—'}</td>
                        <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{p.location_bin || '—'}</td>
                        <td className="px-4 py-3 text-right hidden md:table-cell">{formatCurrency(p.cost_price ?? 0)}</td>
                        <td className="px-4 py-3 text-center">
                          <span className={`font-semibold ${isOut ? 'text-destructive' : isLow ? 'text-amber-600' : 'text-success'}`}>{qty}</span>
                        </td>
                        <td className="px-4 py-3 text-center hidden sm:table-cell text-muted-foreground">{min}</td>
                        <td className="px-4 py-3 text-center">
                          {isOut ? (
                            <Badge variant="destructive" className="text-[10px]">{t.inventory.stockOut}</Badge>
                          ) : isLow ? (
                            <Badge className="bg-amber-100 text-amber-800 border-amber-300 text-[10px]">{t.inventory.stockLow}</Badge>
                          ) : (
                            <Badge variant="secondary" className="text-[10px]">{t.inventory.stockOk}</Badge>
                          )}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <div className="flex justify-end gap-1">
                            <Button size="sm" variant="outline" onClick={() => setAdjustProduct(p)}>Ajustar</Button>
                            <Button size="icon" variant="ghost" className="h-8 w-8" onClick={() => { setAddEntryProduct(p); setShowAddEntry(true); }}>
                              <Plus className="h-4 w-4" />
                            </Button>
                          </div>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
            {sortedProducts.length > 0 && (
              <div className="flex items-center justify-between px-4 py-3 border-t bg-muted/30 text-xs text-muted-foreground">
                <span>{sortedProducts.length} produtos · Página {page} de {totalPages}</span>
                <div className="flex items-center gap-3">
                  <span>{t.inventory.filteredValue}: {formatCurrency(filteredValue)}</span>
                  {totalPages > 1 && (
                    <div className="flex gap-1">
                      <Button variant="outline" size="sm" className="h-7 px-2" onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}>
                        <ChevronLeft className="h-3 w-3" />
                      </Button>
                      <Button variant="outline" size="sm" className="h-7 px-2" onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}>
                        <ChevronRight className="h-3 w-3" />
                      </Button>
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        </TabsContent>

        {/* ── Tab 2: Movements ── */}
        <TabsContent value="movements" className="space-y-4">
          <div className="flex flex-wrap gap-3 items-center">
            <Select
              value={movFilters.product_id || '__all'}
              onValueChange={v => setMovFilters(p => ({ ...p, product_id: v === '__all' ? undefined : v }))}
            >
              <SelectTrigger className="w-[220px]"><SelectValue placeholder={t.inventory.allProducts} /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__all">{t.inventory.allProducts}</SelectItem>
                {(allProducts || []).map(p => <SelectItem key={p.id} value={p.id}>{p.product_name}</SelectItem>)}
              </SelectContent>
            </Select>

            {/* Tipo — chips multi-select */}
            <div className="flex flex-wrap gap-1.5 items-center">
              <span className="text-xs text-muted-foreground shrink-0">Tipo:</span>
              <button
                type="button"
                onClick={() => setMovTypeFilter([])}
                className={`px-2.5 py-0.5 rounded-full text-xs border transition-colors ${movTypeFilter.length === 0 ? 'bg-primary/10 text-primary border-primary/50 font-medium' : 'bg-background text-muted-foreground border-border hover:border-primary/50'}`}
              >
                Todos
              </button>
              {Object.entries(MOVEMENT_LABELS).map(([k, v]) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setMovTypeFilter(prev => prev.includes(k) ? prev.filter(x => x !== k) : [...prev, k])}
                  className={`px-2.5 py-0.5 rounded-full text-xs border transition-colors ${movTypeFilter.includes(k) ? 'bg-primary/10 text-primary border-primary/50 font-medium' : 'bg-background text-muted-foreground border-border hover:border-primary/50'}`}
                >
                  {v}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-2">
              <Label className="text-xs">De</Label>
              <Input type="date" className="w-[150px]" value={movFilters.dateFrom || ''} onChange={e => setMovFilters(p => ({ ...p, dateFrom: e.target.value || undefined }))} />
              <Label className="text-xs">Até</Label>
              <Input type="date" className="w-[150px]" value={movFilters.dateTo || ''} onChange={e => setMovFilters(p => ({ ...p, dateTo: e.target.value || undefined }))} />
            </div>

            {(movFilters.product_id || movTypeFilter.length > 0 || movFilters.dateFrom || movFilters.dateTo) && (
              <Button size="sm" variant="ghost" onClick={() => { setMovFilters({}); setMovTypeFilter([]); }}>Limpar filtros</Button>
            )}
          </div>

          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[900px]">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">Data/Hora</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">Produto</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.type}</th>
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground">Qtd</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">Custo Unit.</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.inventory.reference}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.common.notes}</th>
                </tr>
              </thead>
              <tbody>
                {loadingMovements ? (
                  Array.from({ length: 5 }).map((_, i) => (
                    <tr key={i} className="border-b"><td colSpan={7} className="p-3"><Skeleton className="h-8 w-full" /></td></tr>
                  ))
                ) : !filteredMovements.length ? (
                  <tr><td colSpan={7} className="text-center py-10 text-muted-foreground">{t.common.noResults}</td></tr>
                ) : (
                  pagedMovements.map(m => {
                    const isPositive = m.quantity_delta > 0;
                    const typeLabel = MOVEMENT_LABELS[m.movement_type] || m.movement_type;
                    const badgeClass = POSITIVE_TYPES.has(m.movement_type)
                      ? 'bg-success/15 text-success'
                      : NEGATIVE_TYPES.has(m.movement_type)
                        ? 'bg-destructive/15 text-destructive'
                        : 'bg-info/15 text-info';
                    const refLabel = REF_LABELS[m.reference_type || ''] || m.reference_type || '—';
                    const prod = m.products as any;
                    return (
                      <tr key={m.id} className="border-b last:border-0 hover:bg-muted/30">
                        <td className="px-4 py-3 text-muted-foreground text-xs">{formatDateTime(m.created_at)}</td>
                        <td className="px-4 py-3 font-medium">{prod?.product_name || '—'}</td>
                        <td className="px-4 py-3">
                          <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold ${badgeClass}`}>{typeLabel}</span>
                        </td>
                        <td className="px-4 py-3 text-center font-semibold">
                          <span className={isPositive ? 'text-success' : 'text-destructive'}>
                            {isPositive ? '+' : ''}{m.quantity_delta}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-right hidden md:table-cell text-muted-foreground">
                          {m.unit_cost_snapshot ? formatCurrency(m.unit_cost_snapshot) : '—'}
                        </td>
                        <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground text-xs">{refLabel}</td>
                        <td className="px-4 py-3 hidden md:table-cell text-muted-foreground text-xs">{m.notes || '—'}</td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
            {filteredMovements.length > 0 && (
              <div className="flex items-center justify-between px-4 py-3 border-t bg-muted/30 text-xs text-muted-foreground">
                <span>
                  {t.inventory.totalEntries}: <span className="text-success font-semibold">+{movTotals.entries}</span>
                  {' · '}
                  {t.inventory.totalExits}: <span className="text-destructive font-semibold">{movTotals.exits}</span>
                  {movTotalPages > 1 && ` · Página ${movPage} de ${movTotalPages}`}
                </span>
                {movTotalPages > 1 && (
                  <div className="flex gap-1">
                    <Button variant="outline" size="sm" className="h-7 px-2" onClick={() => setMovPage(p => Math.max(1, p - 1))} disabled={movPage === 1}>
                      <ChevronLeft className="h-3 w-3" />
                    </Button>
                    <Button variant="outline" size="sm" className="h-7 px-2" onClick={() => setMovPage(p => Math.min(movTotalPages, p + 1))} disabled={movPage === movTotalPages}>
                      <ChevronRight className="h-3 w-3" />
                    </Button>
                  </div>
                )}
              </div>
            )}
          </div>
        </TabsContent>
      </Tabs>

      {/* ── AdjustStockDialog ── */}
      <AdjustStockDialog
        product={adjustProduct}
        onClose={() => setAdjustProduct(null)}
        formatCurrency={formatCurrency}
      />

      <AddEntryDialog
        open={showAddEntry}
        onClose={() => { setShowAddEntry(false); setAddEntryProduct(null); }}
        product={addEntryProduct}
        allProducts={allProducts || []}
        formatCurrency={formatCurrency}
      />

      <BarcodeScannerModal 
        open={scannerOpen} 
        onOpenChange={setScannerOpen} 
        onProductScanned={(p) => {
          setScannerOpen(false);
          // Set timeout to avoid dialog unmount conflicts
          setTimeout(() => setAdjustProduct(p), 100);
        }} 
      />
    </div>
  );
}

// ── AdjustStockDialog ─────────────────────────────────────
function AdjustStockDialog({ product, onClose, formatCurrency }: {
  product: any; onClose: () => void; formatCurrency: (v: number) => string;
}) {
  const adjust = useAdjustStock();
  const [newQty, setNewQty] = useState(0);
  const [reason, setReason] = useState('');
  const [notes, setNotes] = useState('');

  const open = !!product;
  const current = product?.stock_quantity ?? 0;
  const delta = newQty - current;

  // Reset on product change
  useEffect(() => {
    if (product) {
      setNewQty(product.stock_quantity ?? 0);
      setReason('');
      setNotes('');
    }
  }, [product]);

  const handleSubmit = async () => {
    if (delta === 0) {
      toast.error('A quantidade não foi alterada. Modifique o valor antes de confirmar.');
      return;
    }
    if (!reason) {
      toast.error('Selecione o motivo do ajuste antes de confirmar.');
      return;
    }
    try {
      await adjust.mutateAsync({
        product_id: product.id,
        new_quantity: newQty,
        reason,
        notes: notes || undefined,
      });
      toast.success('Estoque ajustado com sucesso');
      onClose();
    } catch (err: any) {
      const msg = err?.message || err?.details || 'Tente novamente';
      toast.error('Erro ao ajustar estoque: ' + msg);
      console.error('Adjust stock error:', err);
    }
  };

  return (
    <Dialog open={open} onOpenChange={v => { if (!v) onClose(); }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Ajustar Estoque</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div>
            <p className="font-semibold">{product?.product_name}</p>
            <p className="text-sm text-muted-foreground">Estoque atual: {current} {product?.unit || 'un'}</p>
          </div>
          <div className="space-y-2">
            <Label>Nova quantidade</Label>
            <Input type="number" min={0} value={newQty} onChange={e => setNewQty(Number(e.target.value))} />
            <p className={`text-xs font-medium ${delta > 0 ? 'text-success' : delta < 0 ? 'text-destructive' : 'text-muted-foreground'}`}>
              Variação: {delta > 0 ? '+' : ''}{delta} unidades
            </p>
          </div>
          <div className="space-y-2">
            <Label>Motivo *</Label>
            <Select value={reason} onValueChange={setReason}>
              <SelectTrigger><SelectValue placeholder="Selecione o motivo" /></SelectTrigger>
              <SelectContent>
                {REASONS.map(r => <SelectItem key={r} value={r}>{r}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>Observações</Label>
            <Textarea value={notes} onChange={e => setNotes(e.target.value)} placeholder="Detalhes adicionais..." />
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={onClose}>Cancelar</Button>
            <Button onClick={handleSubmit} disabled={adjust.isPending}>
              {adjust.isPending ? 'Salvando...' : 'Confirmar Ajuste'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ── AddEntryDialog ────────────────────────────────────────
function AddEntryDialog({ open, onClose, product, allProducts, formatCurrency }: {
  open: boolean; onClose: () => void; product: any; allProducts: any[]; formatCurrency: (v: number) => string;
}) {
  const addEntry = useAddStockEntry();
  const [selectedId, setSelectedId] = useState('');
  const [qty, setQty] = useState(1);
  const [unitCost, setUnitCost] = useState('');
  const [entryNotes, setEntryNotes] = useState('');

  const productId = product?.id || selectedId;

  const handleOpenChange = (v: boolean) => {
    if (!v) {
      setSelectedId('');
      setQty(1);
      setUnitCost('');
      setEntryNotes('');
      onClose();
    }
  };

  const handleSubmit = async () => {
    if (!productId || qty < 1) return;
    try {
      await addEntry.mutateAsync({
        product_id: productId,
        quantity: qty,
        unit_cost: unitCost ? Number(unitCost) : undefined,
        notes: entryNotes || undefined,
      });
      toast.success('Entrada registrada com sucesso');
      handleOpenChange(false);
    } catch (err: any) {
      const msg = err?.message || err?.details
        || 'Erro ao registrar entrada. Verifique os dados e tente novamente.';
      toast.error(msg);
      console.error('Stock entry error:', err);
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Entrada de Estoque</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          {product ? (
            <div>
              <p className="font-semibold">{product.product_name}</p>
              <p className="text-xs text-muted-foreground">Estoque atual: {product.stock_quantity ?? 0}</p>
            </div>
          ) : (
            <div className="space-y-2">
              <Label>Produto *</Label>
              <Select value={selectedId} onValueChange={setSelectedId}>
                <SelectTrigger><SelectValue placeholder="Selecione o produto" /></SelectTrigger>
                <SelectContent>
                  {allProducts.filter(p => p.active).map(p => (
                    <SelectItem key={p.id} value={p.id}>{p.product_name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <div className="space-y-2">
            <Label>Quantidade a adicionar *</Label>
            <Input type="number" min={1} value={qty} onChange={e => setQty(Number(e.target.value))} />
          </div>
          <div className="space-y-2">
            <Label>Custo unitário (opcional)</Label>
            <Input type="number" min={0} step={0.01} value={unitCost} onChange={e => setUnitCost(e.target.value)} placeholder="0.00" />
            <p className="text-xs text-muted-foreground">Informe o custo de compra desta entrada</p>
          </div>
          <div className="space-y-2">
            <Label>Notas</Label>
            <Input value={entryNotes} onChange={e => setEntryNotes(e.target.value)} placeholder="Ex: NF 12345, Fornecedor XYZ" />
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => handleOpenChange(false)}>Cancelar</Button>
            <Button onClick={handleSubmit} disabled={!productId || qty < 1 || addEntry.isPending}>
              {addEntry.isPending ? 'Salvando...' : 'Confirmar Entrada'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

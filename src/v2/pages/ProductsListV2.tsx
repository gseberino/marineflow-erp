import { useMemo, useState } from 'react';
import { AlertTriangle, Download, Package, Pencil, Plus, Table2, Upload } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useProducts, type Product } from '@/hooks/use-products';
import { useMultiFilter } from '@/hooks/use-multi-filter';
import { exportToCSV, PRODUCTS_COLUMNS } from '@/lib/export-utils';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { MultiFilterBar } from '@/components/MultiFilterBar';
import { ProductFormDialog } from '@/components/ProductFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { BulkEditor } from '@/components/BulkEditor';
import { PriceSuggestionAlert } from '@/components/PriceSuggestionAlert';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda A · Produtos v2 — paridade com ProductList v1: filtros compostos com
   presets, toggle "Incompletos" (fiscal), import/CSV/edição em massa, imagem,
   estoque com mínimo + reservado/disponível (modelo v2), alerta de preço. */

const PAGE_SIZE = 20;

type ProductRow = Product & {
  product_categories?: { name?: string } | null;
  image_url?: string | null;
  fiscal_complete?: boolean | null;
  reserved_quantity?: number | null;
  active?: boolean | null;
};

const isLowStock = (p: ProductRow) => (p.minimum_stock ?? 0) > 0 && (p.stock_quantity ?? 0) <= (p.minimum_stock ?? 0);

export default function ProductsListV2() {
  const { t, formatCurrency } = useI18n();
  const { data, isLoading, error } = useProducts();
  const products = useMemo(() => (data ?? []) as unknown as ProductRow[], [data]);

  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<ProductRow | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [bulkOpen, setBulkOpen] = useState(false);
  const [incompleteFilter, setIncompleteFilter] = useState(false);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' });
  const { filters, toggle, setField, clearAll, activeCount } = useMultiFilter({
    search: '',
    active: [] as string[],
    category: [] as string[],
  });

  const categories = useMemo(
    () => [...new Set(products.map((p) => p.category).filter(Boolean))].sort() as string[],
    [products],
  );

  const filtered = useMemo(() => {
    const f = filters as { search: string; active: string[]; category: string[] };
    const list = products.filter((p) => {
      const pName = p.name || '';
      const pCategory = p.product_categories?.name || '';
      if (f.search && !(
        pName.toLowerCase().includes(f.search.toLowerCase()) ||
        (p.sku ?? '').toLowerCase().includes(f.search.toLowerCase()) ||
        pCategory.toLowerCase().includes(f.search.toLowerCase())
      )) return false;
      if (f.active.length) {
        if (f.active.includes('active') && !f.active.includes('inactive') && !p.active) return false;
        if (f.active.includes('inactive') && !f.active.includes('active') && p.active) return false;
      }
      if (f.category.length && !f.category.includes(p.category ?? '')) return false;
      if (incompleteFilter && p.fiscal_complete !== false) return false;
      return true;
    });
    return [...list].sort((a, b) => {
      const val = (p: ProductRow) => {
        if (['stock_quantity', 'cost_price', 'sale_price'].includes(sort.key)) return Number((p as Record<string, unknown>)[sort.key] ?? 0);
        return String((p as Record<string, unknown>)[sort.key] ?? '').toLowerCase();
      };
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [products, filters, incompleteFilter, sort]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const openEdit = (p: ProductRow) => { setEditing(p); setFormOpen(true); };

  const stockCell = (p: ProductRow) => {
    const low = isLowStock(p);
    const reserved = Number(p.reserved_quantity) || 0;
    const available = (p.stock_quantity ?? 0) - reserved;
    return (
      <span className="block leading-tight tabular-nums">
        <span className={low ? 'font-semibold text-destructive' : ''}>
          {p.stock_quantity ?? 0}
          {low && <AlertTriangle className="ml-1 inline h-3 w-3" />}
        </span>
        <span className="block text-xs text-muted-foreground">{t.products.min}: {p.minimum_stock ?? 0}</span>
        {reserved > 0 && (
          <span
            title={`${reserved} reservados · ${available} disponíveis`}
            className={`block truncate text-xs ${available < 0 ? 'font-medium text-destructive' : 'text-muted-foreground'}`}
          >
            {reserved} res. · {available} disp.
          </span>
        )}
      </span>
    );
  };

  const columns: DataColumn<ProductRow>[] = [
    {
      key: 'name', header: t.serviceOrders.product, minWidth: 250, priority: 0, sortable: true,
      render: (p) => (
        <span className="flex items-center gap-3">
          {p.image_url ? (
            <img src={p.image_url} alt={p.name} loading="lazy" className="h-9 w-9 shrink-0 rounded border bg-muted object-cover" />
          ) : (
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded border bg-muted/40 text-muted-foreground">
              <Package className="h-4 w-4" />
            </span>
          )}
          <span className="min-w-0 leading-tight">
            <span className="flex items-center gap-1.5 truncate font-semibold">
              <span className="truncate">{p.name}</span>
              {p.fiscal_complete === false && <StatusChip tone="warning">Incompleto</StatusChip>}
            </span>
            <span className="block truncate text-xs text-muted-foreground">{p.sku}</span>
          </span>
        </span>
      ),
    },
    {
      key: 'stock_quantity', header: t.products.stock, minWidth: 150, priority: 1, sortable: true, detailLabel: 'Estoque',
      render: stockCell,
    },
    {
      key: 'sale_price', header: t.products.salePrice, minWidth: 116, priority: 1, align: 'right', sortable: true, detailLabel: 'Venda',
      render: (p) => <span className="font-semibold">{formatCurrency(p.sale_price ?? 0, p.sale_currency ?? 'BRL')}</span>,
    },
    {
      key: 'category', header: t.products.category, minWidth: 130, priority: 3, sortable: true, detailLabel: 'Categoria',
      render: (p) => (p.category ? <StatusChip tone="neutral">{p.category}</StatusChip> : <span className="text-muted-foreground">—</span>),
    },
    {
      key: 'cost_price', header: t.products.cost, minWidth: 110, priority: 4, align: 'right', sortable: true, detailLabel: 'Custo',
      render: (p) => <span className="text-muted-foreground">{formatCurrency(p.cost_price ?? 0, p.cost_currency ?? 'BRL')}</span>,
    },
    {
      key: 'brand', header: t.products.brand, minWidth: 110, priority: 5, sortable: true, detailLabel: 'Marca',
      render: (p) => <span className="truncate text-muted-foreground">{p.brand || '—'}</span>,
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Cadastros' }, { label: t.products.title }]}
        title={t.products.title}
        count={products.length}
        actions={
          <>
            <Button variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex" onClick={() => setImportOpen(true)}>
              <Upload className="h-4 w-4" /> {t.imports.importData}
            </Button>
            <Button variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex" onClick={() => setBulkOpen(true)}>
              <Table2 className="h-4 w-4" /> {t.imports.bulkEdit}
            </Button>
            <Button
              variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex"
              onClick={() => products.length && exportToCSV(products as never[], 'produtos.csv', PRODUCTS_COLUMNS as never)}
            >
              <Download className="h-4 w-4" /> {t.imports.exportCSV}
            </Button>
            <Button className="gap-1.5" onClick={() => { setEditing(null); setFormOpen(true); }}>
              <Plus className="h-4 w-4" /> {t.products.newProduct}
            </Button>
          </>
        }
      >
        <PriceSuggestionAlert />

        <MultiFilterBar
          search={String((filters as Record<string, unknown>).search || '')}
          onSearchChange={(v) => { setField('search', v); setPage(1); }}
          searchPlaceholder={t.products.searchPlaceholder}
          filters={filters}
          activeCount={activeCount + (incompleteFilter ? 1 : 0)}
          onToggle={(f, v) => { toggle(f, v); setPage(1); }}
          onSetField={(f, v) => { setField(f, v); setPage(1); }}
          onClearAll={() => { clearAll(); setIncompleteFilter(false); setPage(1); }}
          presetType="products"
          groups={[
            {
              type: 'multi',
              field: 'active',
              label: 'Status',
              options: [
                { value: 'active', label: 'Ativos' },
                { value: 'inactive', label: 'Inativos' },
              ],
            },
            ...(categories.length > 0 ? [{
              type: 'multi' as const,
              field: 'category',
              label: 'Categoria',
              options: categories.map((c) => ({ value: c, label: c })),
            }] : []),
          ]}
          extra={
            <Button
              variant={incompleteFilter ? 'default' : 'outline'}
              size="sm"
              onClick={() => { setIncompleteFilter((v) => !v); setPage(1); }}
              className="gap-1"
            >
              <AlertTriangle className="h-3 w-3" /> Incompletos
            </Button>
          }
        />

        {isLoading ? (
          <div className="space-y-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center"><p className="text-destructive">{(error as Error).message}</p></div>
        ) : filtered.length === 0 ? (
          <div className="space-y-3 rounded-lg border bg-card p-12 text-center">
            <Package className="mx-auto h-12 w-12 text-muted-foreground" />
            <p className="text-muted-foreground">{products.length === 0 ? t.products.noProducts : t.common.noResults}</p>
            {products.length === 0 && (
              <Button className="gap-1.5" onClick={() => setFormOpen(true)}>
                <Plus className="h-4 w-4" /> {t.products.createFirst}
              </Button>
            )}
          </div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<ProductRow>
                rows={paginated}
                rowKey={(p) => p.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                onRowClick={openEdit}
                emptyMessage={t.common.noResults}
                rowClassName={(p) => (isLowStock(p) ? 'bg-warning/5' : undefined)}
                rowActions={(p) => (
                  <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Editar produto" title="Editar" onClick={() => openEdit(p)}>
                    <Pencil className="h-4 w-4" />
                  </Button>
                )}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {paginated.map((p) => {
                const low = isLowStock(p);
                const reserved = Number(p.reserved_quantity) || 0;
                return (
                  <EntityCard
                    key={p.id}
                    severity={low ? 'warning' : 'neutral'}
                    badge={
                      <>
                        {low && <StatusChip tone="critical">Estoque baixo</StatusChip>}
                        {p.fiscal_complete === false && <StatusChip tone="warning">Incompleto</StatusChip>}
                      </>
                    }
                    title={p.name}
                    lines={[
                      [p.sku, p.category].filter(Boolean).join(' · ') || '—',
                      `Estoque ${p.stock_quantity ?? 0}${reserved > 0 ? ` (${reserved} reserv.)` : ''} · ${formatCurrency(p.sale_price ?? 0, p.sale_currency ?? 'BRL')}`,
                    ]}
                    onClick={() => openEdit(p)}
                  />
                );
              })}
              <button
                type="button"
                aria-label={t.products.newProduct}
                onClick={() => { setEditing(null); setFormOpen(true); }}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </button>
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 pb-16 text-sm md:pb-0">
                <span className="text-muted-foreground">{filtered.length} produtos · Página {page} de {totalPages}</span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      <ProductFormDialog open={formOpen} onOpenChange={setFormOpen} product={editing} />
      <ImportWizard entityType="products" open={importOpen} onOpenChange={setImportOpen} />
      <BulkEditor entityType="products" open={bulkOpen} onOpenChange={setBulkOpen} />
    </V2Shell>
  );
}

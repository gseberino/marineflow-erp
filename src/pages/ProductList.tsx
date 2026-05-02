import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useProducts, type Product } from '@/hooks/use-products';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, AlertTriangle, Edit, Upload, Download, Table2, Package } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { ProductFormDialog } from '@/components/ProductFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { BulkEditor } from '@/components/BulkEditor';
import { exportToCSV, PRODUCTS_COLUMNS } from '@/lib/export-utils';
import { FilterPresets } from '@/components/FilterPresets';
import { PriceSuggestionAlert } from '@/components/PriceSuggestionAlert';

export default function ProductList() {
  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const [editProduct, setEditProduct] = useState<Product | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [bulkOpen, setBulkOpen] = useState(false);
  const [activeFilter, setActiveFilter] = useState<'all'|'active'|'inactive'>('all');
  const [categoryFilter, setCategoryFilter] = useState('all');
  const [incompleteFilter, setIncompleteFilter] = useState(false);
  const { t, formatCurrency } = useI18n();
  const { data: products, isLoading, error } = useProducts();

  const categories = useMemo(() =>
    [...new Set((products ?? []).map(p => p.category).filter(Boolean))].sort() as string[],
  [products]);

  const filtered = (products ?? []).filter(p => {
    const matchesSearch = !search ||
      p.product_name.toLowerCase().includes(search.toLowerCase()) ||
      (p.sku ?? '').toLowerCase().includes(search.toLowerCase()) ||
      (p.category ?? '').toLowerCase().includes(search.toLowerCase());
    const matchesActive = activeFilter === 'all' ||
      (activeFilter === 'active' ? (p as any).active : !(p as any).active);
    const matchesCategory = categoryFilter === 'all' || p.category === categoryFilter;
    const matchesIncomplete = !incompleteFilter || (p as any).fiscal_complete === false;
    return matchesSearch && matchesActive && matchesCategory && matchesIncomplete;
  });

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.products.title} description={`${t.products.description} (${products?.length ?? 0})`}>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" className="gap-1" onClick={() => setImportOpen(true)}>
            <Upload className="h-3.5 w-3.5" /> {t.imports.importData}
          </Button>
          <Button variant="outline" size="sm" className="gap-1" onClick={() => setBulkOpen(true)}>
            <Table2 className="h-3.5 w-3.5" /> {t.imports.bulkEdit}
          </Button>
          <Button variant="outline" size="sm" className="gap-1" onClick={() => products && exportToCSV(products, 'produtos.csv', PRODUCTS_COLUMNS)}>
            <Download className="h-3.5 w-3.5" /> {t.imports.exportCSV}
          </Button>
          <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => { setEditProduct(null); setFormOpen(true); }}>
            <Plus className="h-4 w-4" /> {t.products.newProduct}
          </Button>
        </div>
      </PageHeader>

      <PriceSuggestionAlert />

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder={t.products.searchPlaceholder} value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
        </div>
        <Select value={activeFilter} onValueChange={(v) => setActiveFilter(v as any)}>
          <SelectTrigger className="w-full sm:w-[130px]">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos</SelectItem>
            <SelectItem value="active">Ativos</SelectItem>
            <SelectItem value="inactive">Inativos</SelectItem>
          </SelectContent>
        </Select>
        {categories.length > 0 && (
          <Select value={categoryFilter} onValueChange={setCategoryFilter}>
            <SelectTrigger className="w-full sm:w-[170px]">
              <SelectValue placeholder="Categoria" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todas categorias</SelectItem>
              {categories.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}
            </SelectContent>
          </Select>
        )}
        <Button
          variant={incompleteFilter ? 'default' : 'outline'}
          size="sm"
          onClick={() => setIncompleteFilter(v => !v)}
          className="gap-1"
        >
          <AlertTriangle className="h-3 w-3" />
          Incompletos
        </Button>
        <FilterPresets
          filterType="products"
          currentConfig={{ search, activeFilter, categoryFilter, incompleteFilter }}
          hasActiveFilters={!!search || activeFilter !== 'all' || categoryFilter !== 'all' || incompleteFilter}
          onApply={(c: any) => {
            setSearch(c.search ?? '');
            setActiveFilter(c.activeFilter ?? 'all');
            setCategoryFilter(c.categoryFilter ?? 'all');
            setIncompleteFilter(!!c.incompleteFilter);
          }}
        />
      </div>

      {isLoading ? (
        <div className="space-y-2">{[1,2,3,4].map(i => <Skeleton key={i} className="h-14 rounded-lg" />)}</div>
      ) : filtered.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-muted-foreground">{products?.length === 0 ? t.products.noProducts : t.common.noResults}</p>
          {products?.length === 0 && (
            <Button variant="outline" className="mt-4" onClick={() => setFormOpen(true)}>
              <Plus className="h-4 w-4 mr-2" /> {t.products.createFirst}
            </Button>
          )}
        </div>
      ) : (
        <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
          <table className="w-full text-sm min-w-[800px]">
            <thead><tr className="border-b bg-muted/50">
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.product}</th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.products.category}</th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.products.brand}</th>
              <th className="px-4 py-3 text-center font-medium text-muted-foreground">{t.products.stock}</th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">{t.products.cost}</th>
              <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.products.salePrice}</th>
              <th className="px-4 py-3 text-center font-medium text-muted-foreground w-12"></th>
            </tr></thead>
            <tbody>
              {filtered.map(p => {
                const lowStock = (p.stock_quantity ?? 0) <= (p.minimum_stock ?? 0);
                return (
                  <tr key={p.id} className={`border-b last:border-0 hover:bg-muted/30 transition-colors ${lowStock ? 'bg-warning/5' : ''}`}>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        {(p as any).image_url ? (
                          <img
                            src={(p as any).image_url}
                            alt={p.product_name}
                            className="h-10 w-10 rounded object-cover border bg-muted shrink-0"
                            loading="lazy"
                          />
                        ) : (
                          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded border bg-muted/40 text-muted-foreground">
                            <Package className="h-5 w-5" />
                          </div>
                        )}
                        <div className="min-w-0">
                          <p className="font-medium truncate">
                            {p.product_name}
                            {(p as any).fiscal_complete === false && (
                              <span className="ml-2 inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-medium text-amber-700">
                                Incompleto
                              </span>
                            )}
                            {(p.minimum_stock ?? 0) > 0 && (p.stock_quantity ?? 0) <= (p.minimum_stock ?? 0) && (
                              <span className="inline-flex items-center gap-1 rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-medium text-red-700 ml-2">
                                <AlertTriangle className="h-3 w-3" />
                                Estoque baixo
                              </span>
                            )}
                          </p>
                          <p className="text-xs text-muted-foreground truncate">{p.sku}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 hidden md:table-cell">
                      {p.category && <StatusBadge className="bg-secondary text-secondary-foreground">{p.category}</StatusBadge>}
                    </td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{p.brand}</td>
                    <td className="px-4 py-3 text-center">
                      <span className={lowStock ? 'text-destructive font-semibold' : ''}>{p.stock_quantity ?? 0}</span>
                      {lowStock && <AlertTriangle className="h-3 w-3 text-destructive inline ml-1" />}
                      <span className="text-xs text-muted-foreground block">{t.products.min}: {p.minimum_stock ?? 0}</span>
                    </td>
                    <td className="px-4 py-3 text-right hidden md:table-cell text-muted-foreground">{formatCurrency(p.cost_price ?? 0, p.cost_currency ?? 'BRL')}</td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(p.sale_price ?? 0, p.sale_currency ?? 'BRL')}</td>
                    <td className="px-4 py-3 text-center">
                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => { setEditProduct(p); setFormOpen(true); }}>
                        <Edit className="h-3.5 w-3.5" />
                      </Button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <ProductFormDialog open={formOpen} onOpenChange={setFormOpen} product={editProduct} />
      <ImportWizard entityType="products" open={importOpen} onOpenChange={setImportOpen} />
      <BulkEditor entityType="products" open={bulkOpen} onOpenChange={setBulkOpen} />
    </div>
  );
}

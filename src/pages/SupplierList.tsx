import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useSuppliers, type Supplier } from '@/hooks/use-suppliers';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Building2, Upload, Download, ChevronLeft, ChevronRight, ArrowUpDown, ArrowUp, ArrowDown } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/StatusBadge';
import { SupplierFormDialog } from '@/components/SupplierFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { exportToCSV, SUPPLIERS_COLUMNS } from '@/lib/export-utils';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import { FilterPresets } from '@/components/FilterPresets';
import { getDefaultFilterCache } from '@/hooks/use-saved-filters';

type SortDir = 'asc' | 'desc';
const PAGE_SIZE = 20;

function useSupplierProductCounts() {
  return useQuery({
    queryKey: ['supplier-product-counts'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('product_suppliers')
        .select('supplier_id');
      if (error) throw error;
      const counts: Record<string, number> = {};
      (data ?? []).forEach(r => {
        counts[r.supplier_id] = (counts[r.supplier_id] ?? 0) + 1;
      });
      return counts;
    },
  });
}

export default function SupplierList() {
  const [search, setSearch] = useState(() => {
    const c = getDefaultFilterCache('suppliers');
    return (c?.search as string) ?? '';
  });
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Supplier | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [sortKey, setSortKey] = useState('name');
  const [sortDir, setSortDir] = useState<SortDir>('asc');
  const { t } = useI18n();
  const { data: suppliers, isLoading, error } = useSuppliers();
  const { data: productCounts } = useSupplierProductCounts();

  const handleSort = (key: string) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
    setPage(1);
  };

  function SortIcon({ col }: { col: string }) {
    if (sortKey !== col) return <ArrowUpDown className="h-3 w-3 ml-1 opacity-40 shrink-0" />;
    return sortDir === 'asc' ? <ArrowUp className="h-3 w-3 ml-1 shrink-0" /> : <ArrowDown className="h-3 w-3 ml-1 shrink-0" />;
  }

  const filtered = useMemo(() => {
    const list = (suppliers ?? []).filter(s =>
      !search ||
      s.name.toLowerCase().includes(search.toLowerCase()) ||
      (s.cnpj_cpf ?? '').toLowerCase().includes(search.toLowerCase()) ||
      (s.trade_name ?? '').toLowerCase().includes(search.toLowerCase())
    );
    return [...list].sort((a, b) => {
      let av: any = (a as any)[sortKey] ?? '';
      let bv: any = (b as any)[sortKey] ?? '';
      if (typeof av === 'string') av = av.toLowerCase();
      if (typeof bv === 'string') bv = bv.toLowerCase();
      if (av < bv) return sortDir === 'asc' ? -1 : 1;
      if (av > bv) return sortDir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [suppliers, search, sortKey, sortDir]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.suppliers.title} description={`${t.suppliers.description} (${suppliers?.length ?? 0})`}>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" className="gap-1" onClick={() => setImportOpen(true)}>
            <Upload className="h-3.5 w-3.5" /> {t.imports.importData}
          </Button>
          <Button variant="outline" size="sm" className="gap-1" onClick={() => suppliers && exportToCSV(suppliers, 'fornecedores.csv', SUPPLIERS_COLUMNS)}>
            <Download className="h-3.5 w-3.5" /> {t.imports.exportCSV}
          </Button>
          <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => { setEditing(null); setFormOpen(true); }}>
            <Plus className="h-4 w-4" /> {t.suppliers.newSupplier}
          </Button>
        </div>
      </PageHeader>
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder={t.suppliers.searchPlaceholder} value={search} onChange={e => { setSearch(e.target.value); setPage(1); }} className="pl-9" />
        </div>
        <FilterPresets
          filterType="suppliers"
          currentConfig={{ search }}
          hasActiveFilters={!!search}
          onApply={(c: any) => {
            setSearch(c.search ?? '');
            setPage(1);
          }}
        />
      </div>

      {isLoading ? (
        <div className="space-y-2">{[1,2,3].map(i => <Skeleton key={i} className="h-14 rounded-lg" />)}</div>
      ) : filtered.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-muted-foreground">{suppliers?.length === 0 ? t.suppliers.noSuppliers : t.common.noResults}</p>
          {suppliers?.length === 0 && (
            <Button variant="outline" className="mt-4" onClick={() => { setEditing(null); setFormOpen(true); }}>
              <Plus className="h-4 w-4 mr-2" /> {t.suppliers.createFirst}
            </Button>
          )}
        </div>
      ) : (
        <>
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[700px]">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                  <button onClick={() => handleSort('name')} className="flex items-center hover:text-foreground transition-colors">
                    {t.suppliers.supplierName}<SortIcon col="name" />
                  </button>
                </th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                  <button onClick={() => handleSort('trade_name')} className="flex items-center hover:text-foreground transition-colors">
                    {t.suppliers.tradeName}<SortIcon col="trade_name" />
                  </button>
                </th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">
                  <button onClick={() => handleSort('cnpj_cpf')} className="flex items-center hover:text-foreground transition-colors">
                    {t.suppliers.cnpj}<SortIcon col="cnpj_cpf" />
                  </button>
                </th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                  <button onClick={() => handleSort('contact_name')} className="flex items-center hover:text-foreground transition-colors">
                    {t.suppliers.contactName}<SortIcon col="contact_name" />
                  </button>
                </th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">
                  <button onClick={() => handleSort('city')} className="flex items-center hover:text-foreground transition-colors">
                    {t.address.city}/{t.address.state}<SortIcon col="city" />
                  </button>
                </th>
                <th className="px-4 py-3 text-center font-medium text-muted-foreground">{t.suppliers.linkedProducts}</th>
                <th className="px-4 py-3 text-center font-medium text-muted-foreground">
                  <button onClick={() => handleSort('active')} className="flex items-center justify-center w-full hover:text-foreground transition-colors">
                    {t.common.status}<SortIcon col="active" />
                  </button>
                </th>
                <th className="px-4 py-3 text-center font-medium text-muted-foreground">{t.common.actions}</th>
              </tr></thead>
              <tbody>
                {paginated.map(s => (
                  <tr key={s.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <Building2 className="h-4 w-4 text-accent shrink-0" />
                        <span className="font-medium">{s.name}</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{s.trade_name ?? '—'}</td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{s.cnpj_cpf ?? '—'}</td>
                    <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{s.contact_name ?? '—'}</td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">
                      {[s.city, s.state].filter(Boolean).join('/') || '—'}
                    </td>
                    <td className="px-4 py-3 text-center font-medium">{productCounts?.[s.id] ?? 0}</td>
                    <td className="px-4 py-3 text-center">
                      <StatusBadge className={s.active ? 'bg-emerald-100 text-emerald-700' : 'bg-muted text-muted-foreground'}>
                        {s.active ? t.common.active : t.common.inactive}
                      </StatusBadge>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <Button variant="ghost" size="sm" onClick={() => { setEditing(s); setFormOpen(true); }}>{t.common.edit}</Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} fornecedores · Página {page} de {totalPages}
              </span>
              <div className="flex gap-2">
                <Button variant="outline" size="sm" onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}>
                  <ChevronLeft className="h-4 w-4" /> Anterior
                </Button>
                <Button variant="outline" size="sm" onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}>
                  Próxima <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            </div>
          )}
        </>
      )}

      <SupplierFormDialog open={formOpen} onOpenChange={setFormOpen} supplier={editing} />
      <ImportWizard entityType="suppliers" open={importOpen} onOpenChange={setImportOpen} />
    </div>
  );
}

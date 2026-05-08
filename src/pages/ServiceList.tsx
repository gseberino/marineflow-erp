import { useMemo, useState } from 'react';
import { useI18n } from '@/i18n';
import { useServices } from '@/hooks/use-services';
import { PageHeader } from '@/components/PageHeader';
import { ServiceFormDialog } from '@/components/ServiceFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { BulkEditor } from '@/components/BulkEditor';
import { exportToCSV, SERVICES_COLUMNS } from '@/lib/export-utils';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/StatusBadge';
import { Plus, Search, Wrench, Pencil, Upload, Download, Table2, ChevronLeft, ChevronRight, ArrowUpDown, ArrowUp, ArrowDown } from 'lucide-react';

type SortDir = 'asc' | 'desc';
const PAGE_SIZE = 20;

export default function ServiceList() {
  const { t, formatCurrency } = useI18n();
  const { data: services, isLoading, error } = useServices();
  const [search, setSearch] = useState('');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editData, setEditData] = useState<any>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [bulkOpen, setBulkOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [sortKey, setSortKey] = useState('service_name');
  const [sortDir, setSortDir] = useState<SortDir>('asc');

  const billingUnitLabel: Record<string, string> = {
    hour: t.services.unitHour,
    visit: t.services.unitVisit,
    day: t.services.unitDay,
    unit: t.services.unitUnit,
  };

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
    const q = search.toLowerCase();
    const list = (services ?? []).filter((s) =>
      s.service_name.toLowerCase().includes(q) || (s.category || '').toLowerCase().includes(q)
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
  }, [services, search, sortKey, sortDir]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.services.title} description={t.services.description}>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" className="gap-1" onClick={() => setImportOpen(true)}>
            <Upload className="h-3.5 w-3.5" /> {t.imports.importData}
          </Button>
          <Button variant="outline" size="sm" className="gap-1" onClick={() => setBulkOpen(true)}>
            <Table2 className="h-3.5 w-3.5" /> {t.imports.bulkEdit}
          </Button>
          <Button variant="outline" size="sm" className="gap-1" onClick={() => services && exportToCSV(services, 'servicos.csv', SERVICES_COLUMNS)}>
            <Download className="h-3.5 w-3.5" /> {t.imports.exportCSV}
          </Button>
          <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"
            onClick={() => { setEditData(null); setDialogOpen(true); }}>
            <Plus className="h-4 w-4" /> {t.services.newService}
          </Button>
        </div>
      </PageHeader>

      <div className="relative max-w-sm">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input placeholder={t.services.searchPlaceholder} value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="pl-9" />
      </div>

      {error ? (
        <div className="py-20 text-center text-destructive">
          Erro ao carregar serviços. Tente recarregar a página.
        </div>
      ) : isLoading ? (
        <div className="space-y-3">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}</div>
      ) : !filtered?.length ? (
        <div className="flex flex-col items-center gap-3 py-16 text-center">
          <Wrench className="h-12 w-12 text-muted-foreground/40" />
          <p className="text-muted-foreground">{search ? t.common.noResults : t.services.noServices}</p>
          {!search && (
            <Button variant="outline" onClick={() => { setEditData(null); setDialogOpen(true); }}>
              {t.services.createFirst}
            </Button>
          )}
        </div>
      ) : (
        <>
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[800px]">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('service_name')} className="flex items-center hover:text-foreground transition-colors">
                      {t.services.serviceName}<SortIcon col="service_name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('category')} className="flex items-center hover:text-foreground transition-colors">
                      {t.services.category}<SortIcon col="category" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('billing_unit')} className="flex items-center hover:text-foreground transition-colors">
                      {t.services.billingUnit}<SortIcon col="billing_unit" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">
                    <button onClick={() => handleSort('default_price')} className="flex items-center justify-end w-full hover:text-foreground transition-colors">
                      {t.services.defaultPrice}<SortIcon col="default_price" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground">
                    <button onClick={() => handleSort('active')} className="flex items-center justify-center w-full hover:text-foreground transition-colors">
                      {t.common.status}<SortIcon col="active" />
                    </button>
                  </th>
                  <th className="px-4 py-3 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {paginated.map((s) => (
                  <tr key={s.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                    <td className="px-4 py-3 font-medium">{s.service_name}</td>
                    <td className="px-4 py-3 text-muted-foreground">{s.category || '—'}</td>
                    <td className="px-4 py-3">{billingUnitLabel[s.billing_unit] || s.billing_unit}</td>
                    <td className="px-4 py-3 text-right">{formatCurrency(s.default_price || 0)}</td>
                    <td className="px-4 py-3 text-center">
                      <StatusBadge className={s.active ? 'bg-success/15 text-success' : 'bg-muted text-muted-foreground'}>
                        {s.active ? t.common.active : t.common.inactive}
                      </StatusBadge>
                    </td>
                    <td className="px-4 py-3">
                      <Button variant="ghost" size="icon" className="h-7 w-7"
                        onClick={() => { setEditData(s); setDialogOpen(true); }}>
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} serviços · Página {page} de {totalPages}
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

      <ServiceFormDialog open={dialogOpen} onOpenChange={setDialogOpen} editData={editData} />
      <ImportWizard entityType="services" open={importOpen} onOpenChange={setImportOpen} />
      <BulkEditor entityType="services" open={bulkOpen} onOpenChange={setBulkOpen} />
    </div>
  );
}

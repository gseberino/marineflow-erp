import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useVessels } from '@/hooks/use-vessels';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Anchor, Ship, ChevronLeft, ChevronRight, ArrowUpDown, ArrowUp, ArrowDown, Download } from 'lucide-react';
import { exportToCSV, VESSELS_COLUMNS } from '@/lib/export-utils';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import { FilterPresets } from '@/components/FilterPresets';

type SortDir = 'asc' | 'desc';
const PAGE_SIZE = 20;

export default function VesselList() {
  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const [typeFilter, setTypeFilter] = useState('all');
  const [page, setPage] = useState(1);
  const [sortKey, setSortKey] = useState('boat_name');
  const [sortDir, setSortDir] = useState<SortDir>('asc');
  const { t } = useI18n();
  const { data: vessels, isLoading, error } = useVessels();

  const types = useMemo(() =>
    [...new Set((vessels ?? []).map((v: any) => v.asset_type).filter(Boolean))].sort() as string[],
  [vessels]);

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
    const list = (vessels ?? []).filter((v: any) =>
      (!search ||
        v.boat_name.toLowerCase().includes(search.toLowerCase()) ||
        (v.manufacturer ?? '').toLowerCase().includes(search.toLowerCase()) ||
        (v.model ?? '').toLowerCase().includes(search.toLowerCase()) ||
        (v.clients?.full_name_or_company_name ?? '').toLowerCase().includes(search.toLowerCase())
      ) && (typeFilter === 'all' || v.asset_type === typeFilter)
    );
    return [...list].sort((a: any, b: any) => {
      let av: any;
      let bv: any;
      if (sortKey === 'owner') {
        av = a.clients?.full_name_or_company_name ?? '';
        bv = b.clients?.full_name_or_company_name ?? '';
      } else {
        av = a[sortKey] ?? '';
        bv = b[sortKey] ?? '';
      }
      if (typeof av === 'string') av = av.toLowerCase();
      if (typeof bv === 'string') bv = bv.toLowerCase();
      if (av < bv) return sortDir === 'asc' ? -1 : 1;
      if (av > bv) return sortDir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [vessels, search, typeFilter, sortKey, sortDir]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.vessels.title} description={`${t.vessels.description} (${vessels?.length ?? 0})`}>
        <Button variant="outline" size="sm" className="gap-1" onClick={() => vessels && exportToCSV(vessels, 'embarcacoes.csv', VESSELS_COLUMNS)}>
          <Download className="h-3.5 w-3.5" /> Exportar CSV
        </Button>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => setFormOpen(true)}>
          <Plus className="h-4 w-4" /> Nova Unidade
        </Button>
      </PageHeader>
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder={t.vessels.searchPlaceholder} value={search} onChange={e => { setSearch(e.target.value); setPage(1); }} className="pl-9" />
        </div>
        {types.length > 0 && (
          <Select value={typeFilter} onValueChange={v => { setTypeFilter(v); setPage(1); }}>
            <SelectTrigger className="w-full sm:w-[170px]">
              <SelectValue placeholder="Tipo" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos os tipos</SelectItem>
              {types.map(tp => <SelectItem key={tp} value={tp}>{tp}</SelectItem>)}
            </SelectContent>
          </Select>
        )}
        <FilterPresets
          filterType="vessels"
          currentConfig={{ search, typeFilter }}
          hasActiveFilters={!!search || typeFilter !== 'all'}
          onApply={(c: any) => {
            setSearch(c.search ?? '');
            setTypeFilter(c.typeFilter ?? 'all');
            setPage(1);
          }}
        />
      </div>

      {isLoading ? (
        <div className="space-y-2">{[1,2,3,4].map(i => <Skeleton key={i} className="h-14 rounded-lg" />)}</div>
      ) : filtered.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-muted-foreground">{vessels?.length === 0 ? t.vessels.noVessels : t.common.noResults}</p>
          {vessels?.length === 0 && (
            <Button variant="outline" className="mt-4" onClick={() => setFormOpen(true)}>
              <Plus className="h-4 w-4 mr-2" /> {t.vessels.createFirst}
            </Button>
          )}
        </div>
      ) : (
        <>
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[800px]">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                  <button onClick={() => handleSort('boat_name')} className="flex items-center hover:text-foreground transition-colors">
                    Unidade / Tipo<SortIcon col="boat_name" />
                  </button>
                </th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                  <button onClick={() => handleSort('owner')} className="flex items-center hover:text-foreground transition-colors">
                    {t.vessels.owner}<SortIcon col="owner" />
                  </button>
                </th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.serviceOrders.marina}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.vessels.engine}</th>
                <th className="px-4 py-3 text-center font-medium text-muted-foreground">
                  <button onClick={() => handleSort('length_feet')} className="flex items-center justify-center w-full hover:text-foreground transition-colors">
                    {t.vessels.length}<SortIcon col="length_feet" />
                  </button>
                </th>
                <th className="px-4 py-3 text-center font-medium text-muted-foreground hidden lg:table-cell">
                  <button onClick={() => handleSort('year')} className="flex items-center justify-center w-full hover:text-foreground transition-colors">
                    {t.vessels.year}<SortIcon col="year" />
                  </button>
                </th>
              </tr></thead>
              <tbody>
                {paginated.map((v: any) => (
                  <tr key={v.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                    <td className="px-4 py-3">
                      <Link to={`/vessels/${v.id}`} className="flex items-center gap-2">
                        <Ship className="h-4 w-4 text-accent shrink-0" />
                        <div>
                          <p className="font-medium text-accent hover:underline">{v.boat_name}</p>
                          <p className="text-xs text-muted-foreground">{v.asset_type || 'Lancha'} • {v.manufacturer} {v.model}</p>
                        </div>
                      </Link>
                    </td>
                    <td className="px-4 py-3 hidden md:table-cell">
                      <Link to={`/clients/${v.client_id}`} className="text-muted-foreground hover:text-foreground">
                        {v.clients?.full_name_or_company_name ?? '—'}
                      </Link>
                    </td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">
                      {v.marinas?.marina_name ? (
                        <span className="flex items-center gap-1"><Anchor className="h-3 w-3" />{v.marinas.marina_name}</span>
                      ) : '—'}
                    </td>
                    <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">
                      {v.engine_quantity ?? 1}× {v.engine_brand} {v.engine_model}
                    </td>
                    <td className="px-4 py-3 text-center font-medium">{v.length_feet ? `${v.length_feet} ft` : '—'}</td>
                    <td className="px-4 py-3 text-center text-muted-foreground hidden lg:table-cell">{v.year ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} unidades · Página {page} de {totalPages}
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

      <VesselFormDialog open={formOpen} onOpenChange={setFormOpen} />
    </div>
  );
}

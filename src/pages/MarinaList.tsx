import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useMarinas } from '@/hooks/use-marinas';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, MapPin, Phone, Mail, Ship, Edit, ChevronLeft, ChevronRight, ArrowUpDown, ArrowUp, ArrowDown, Download } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { MarinaFormDialog } from '@/components/MarinaFormDialog';
import { exportToCSV, MARINAS_COLUMNS } from '@/lib/export-utils';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import type { Marina } from '@/hooks/use-marinas';
import { FilterPresets } from '@/components/FilterPresets';
import { getDefaultFilterCache } from '@/hooks/use-saved-filters';

type SortDir = 'asc' | 'desc';

export default function MarinaList() {
  const [search, setSearch] = useState(() => {
    const c = getDefaultFilterCache('marinas');
    return (c?.search as string) ?? '';
  });
  const [formOpen, setFormOpen] = useState(false);
  const [editMarina, setEditMarina] = useState<Marina | null>(null);
  const [page, setPage] = useState(1);
  const [sortKey, setSortKey] = useState('name');
  const [sortDir, setSortDir] = useState<SortDir>('asc');
  const PAGE_SIZE = 20;
  const { t } = useI18n();
  const { data: marinas, isLoading, error } = useMarinas();

  const { data: vesselCounts } = useQuery({
    queryKey: ['vessel-counts-by-marina'],
    queryFn: async () => {
      const { data, error } = await supabase.from('vessels').select('marina_id').not('marina_id', 'is', null);
      if (error) throw error;
      const counts: Record<string, number> = {};
      data.forEach(v => { if (v.marina_id) counts[v.marina_id] = (counts[v.marina_id] || 0) + 1; });
      return counts;
    },
  });

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
    const list = (marinas ?? []).filter(m =>
      !search || m.name.toLowerCase().includes(search.toLowerCase()) || (m.city ?? '').toLowerCase().includes(search.toLowerCase())
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
  }, [marinas, search, sortKey, sortDir]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.marinas.title} description={`${t.marinas.description} (${marinas?.length ?? 0})`}>
        <Button variant="outline" size="sm" className="gap-1" onClick={() => exportToCSV(filtered, 'marinas.csv', MARINAS_COLUMNS)}>
          <Download className="h-3.5 w-3.5" /> CSV
        </Button>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => { setEditMarina(null); setFormOpen(true); }}>
          <Plus className="h-4 w-4" /> {t.marinas.newMarina}
        </Button>
      </PageHeader>
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder={t.marinas.searchPlaceholder}
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
            className="pl-9"
          />
        </div>
        <FilterPresets
          filterType="marinas"
          currentConfig={{ search }}
          hasActiveFilters={!!search}
          onApply={(c: any) => {
            setSearch(c.search ?? '');
            setPage(1);
          }}
        />
      </div>

      {isLoading ? (
        <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-4 space-y-3">
            {[1,2,3,4].map(i => <Skeleton key={i} className="h-10 rounded-lg" />)}
          </div>
        </div>
      ) : (
        <>
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[700px]">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('name')} className="flex items-center hover:text-foreground transition-colors">
                      {(t.marinas as any).name || 'Marina'}<SortIcon col="name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                    <button onClick={() => handleSort('contact_name')} className="flex items-center hover:text-foreground transition-colors">
                      {(t.common as any).contact || 'Contato'}<SortIcon col="contact_name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground hidden sm:table-cell w-24">
                    {t.clients.vessels || 'Embarcações'}
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground w-20">
                    <button onClick={() => handleSort('active')} className="flex items-center justify-center w-full hover:text-foreground transition-colors">
                      {(t.common as any).status || 'Status'}<SortIcon col="active" />
                    </button>
                  </th>
                  <th className="px-4 py-3 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {paginated.map(m => {
                  const vesselCount = vesselCounts?.[m.id] ?? 0;
                  return (
                    <tr key={m.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                      <td className="px-4 py-3">
                        <p className="font-medium">{m.name}</p>
                        {m.address_line_1 && (
                          <p className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
                            <MapPin className="h-3 w-3 shrink-0" />
                            {m.city}{m.state ? `/${m.state}` : ''}
                          </p>
                        )}
                      </td>
                      <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">
                        {m.contact_name && (
                          <div className="flex items-center gap-1.5">
                            <Phone className="h-3 w-3 shrink-0" />
                            {m.contact_name}{m.contact_phone ? ` · ${m.contact_phone}` : ''}
                          </div>
                        )}
                        {m.contact_email && (
                          <div className="flex items-center gap-1.5 text-xs mt-0.5">
                            <Mail className="h-3 w-3 shrink-0" />
                            {m.contact_email}
                          </div>
                        )}
                      </td>
                      <td className="px-4 py-3 text-center hidden sm:table-cell text-muted-foreground">
                        <div className="flex items-center justify-center gap-1">
                          <Ship className="h-3.5 w-3.5" />
                          {vesselCount}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-center">
                        <StatusBadge className={m.active ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                          {m.active ? t.common.active : t.common.inactive}
                        </StatusBadge>
                      </td>
                      <td className="px-4 py-3">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7"
                          onClick={() => { setEditMarina(m); setFormOpen(true); }}
                        >
                          <Edit className="h-3.5 w-3.5" />
                        </Button>
                      </td>
                    </tr>
                  );
                })}
                {paginated.length === 0 && (
                  <tr>
                    <td colSpan={5} className="px-4 py-12 text-center text-muted-foreground">
                      {marinas?.length === 0 ? t.marinas.noMarinas : t.common.noResults}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} marinas · Página {page} de {totalPages}
              </span>
              <div className="flex gap-2">
                <Button variant="outline" size="sm" onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}>
                  <ChevronLeft className="h-4 w-4" />
                  Anterior
                </Button>
                <Button variant="outline" size="sm" onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}>
                  Próxima
                  <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            </div>
          )}
        </>
      )}

      <MarinaFormDialog open={formOpen} onOpenChange={setFormOpen} marina={editMarina} />
    </div>
  );
}

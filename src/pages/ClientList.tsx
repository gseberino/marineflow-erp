import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Phone, Mail, Ship, Upload, Download, ChevronLeft, ChevronRight, ArrowUpDown, ArrowUp, ArrowDown } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { exportToCSV, CLIENTS_COLUMNS } from '@/lib/export-utils';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import { FilterPresets } from '@/components/FilterPresets';
import { getDefaultFilterCache } from '@/hooks/use-saved-filters';

type SortDir = 'asc' | 'desc';

export default function ClientList() {
  const [search, setSearch] = useState(() => {
    const c = getDefaultFilterCache('clients');
    return (c?.search as string) ?? '';
  });
  const [formOpen, setFormOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [sortKey, setSortKey] = useState('name');
  const [sortDir, setSortDir] = useState<SortDir>('asc');
  const PAGE_SIZE = 20;
  const { t } = useI18n();
  const { data: clients, isLoading, error } = useClients();

  const { data: vesselCounts } = useQuery({
    queryKey: ['vessel-counts'],
    queryFn: async () => {
      const { data, error } = await supabase.from('vessels').select('client_id');
      if (error) throw error;
      const counts: Record<string, number> = {};
      data.forEach(v => { counts[v.client_id] = (counts[v.client_id] || 0) + 1; });
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
    const list = (clients ?? []).filter(c =>
      !search || c.name.toLowerCase().includes(search.toLowerCase()) ||
      (c.email ?? '').toLowerCase().includes(search.toLowerCase()) ||
      (c.cpf_cnpj ?? '').includes(search)
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
  }, [clients, search, sortKey, sortDir]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.clients.title} description={`${t.clients.description} (${clients?.length ?? 0})`}>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" className="gap-1" onClick={() => setImportOpen(true)}>
            <Upload className="h-3.5 w-3.5" /> {t.imports.importData}
          </Button>
          <Button variant="outline" size="sm" className="gap-1" onClick={() => clients && exportToCSV(clients, 'clientes.csv', CLIENTS_COLUMNS)}>
            <Download className="h-3.5 w-3.5" /> {t.imports.exportCSV}
          </Button>
          <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => setFormOpen(true)}>
            <Plus className="h-4 w-4" /> {t.clients.newClient}
          </Button>
        </div>
      </PageHeader>

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder={t.clients.searchPlaceholder}
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
            className="pl-9"
          />
        </div>
        <FilterPresets
          filterType="clients"
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
            {[1,2,3,4,5].map(i => <Skeleton key={i} className="h-10 rounded-lg" />)}
          </div>
        </div>
      ) : (
        <>
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[600px]">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('name')} className="flex items-center hover:text-foreground transition-colors">
                      {(t.clients as any).name || 'Nome'}<SortIcon col="name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                    <button onClick={() => handleSort('email')} className="flex items-center hover:text-foreground transition-colors">
                      {(t.common as any).contact || 'Contato'}<SortIcon col="email" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground hidden sm:table-cell w-20">
                    {t.clients.vessels || 'Embarcações'}
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground w-20">
                    <button onClick={() => handleSort('active')} className="flex items-center justify-center w-full hover:text-foreground transition-colors">
                      {(t.common as any).status || 'Status'}<SortIcon col="active" />
                    </button>
                  </th>
                </tr>
              </thead>
              <tbody>
                {paginated.map(client => {
                  const vc = vesselCounts?.[client.id] ?? 0;
                  return (
                    <tr key={client.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                      <td className="px-4 py-3">
                        <Link to={`/clients/${client.id}`} className="font-medium text-accent hover:underline block truncate max-w-[160px]">
                          {client.name}
                        </Link>
                        <span className="text-xs text-muted-foreground">
                          {client.type === 'company' ? t.common.company : t.common.individual}
                          {client.city ? ` · ${client.city}${client.state ? `/${client.state}` : ''}` : ''}
                        </span>
                      </td>
                      <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">
                        {client.email && (
                          <div className="flex items-center gap-1.5 truncate max-w-[200px]">
                            <Mail className="h-3 w-3 shrink-0" />
                            {client.email}
                          </div>
                        )}
                        {client.phone && (
                          <div className="flex items-center gap-1.5 text-xs mt-0.5">
                            <Phone className="h-3 w-3 shrink-0" />
                            {client.phone}
                          </div>
                        )}
                      </td>
                      <td className="px-4 py-3 text-center hidden sm:table-cell text-muted-foreground">
                        <div className="flex items-center justify-center gap-1">
                          <Ship className="h-3.5 w-3.5" />
                          {vc}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-center">
                        <StatusBadge className={client.active ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                          {client.active ? t.common.active : t.common.inactive}
                        </StatusBadge>
                      </td>
                    </tr>
                  );
                })}
                {paginated.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-12 text-center text-muted-foreground">
                      {clients?.length === 0 ? t.clients.noClients : t.common.noResults}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} {t.clients.title?.toLowerCase() || 'clientes'} · Página {page} de {totalPages}
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

      <ClientFormDialog open={formOpen} onOpenChange={setFormOpen} />
      <ImportWizard entityType="auto" open={importOpen} onOpenChange={setImportOpen} />
    </div>
  );
}

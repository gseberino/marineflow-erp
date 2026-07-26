import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Download, Mail, Phone, Plus, Ship, Upload } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { supabase } from '@/integrations/supabase/client';
import { exportToCSV, CLIENTS_COLUMNS } from '@/lib/export-utils';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { FilterPresets } from '@/components/FilterPresets';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda A · Clientes v2 — paridade com ClientList v1 (busca, presets, import,
   CSV, contagem de embarcações, dialog de cadastro) em DataTable + EntityCard. */

const PAGE_SIZE = 20;

type ClientRow = {
  id: string;
  name: string;
  type?: string | null;
  email?: string | null;
  phone?: string | null;
  cpf_cnpj?: string | null;
  city?: string | null;
  state?: string | null;
  active?: boolean | null;
};

export default function ClientsListV2() {
  const { t } = useI18n();
  const navigate = useNavigate();
  const { data, isLoading, error } = useClients();
  const clients = useMemo(() => (data ?? []) as unknown as ClientRow[], [data]);

  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' });

  const { data: vesselCounts } = useQuery({
    queryKey: ['vessel-counts'],
    queryFn: async () => {
      const { data: rows, error: err } = await supabase.from('vessels').select('client_id');
      if (err) throw err;
      const counts: Record<string, number> = {};
      rows.forEach((v) => { counts[v.client_id] = (counts[v.client_id] || 0) + 1; });
      return counts;
    },
  });

  const filtered = useMemo(() => {
    const list = clients.filter((c) =>
      !search ||
      c.name.toLowerCase().includes(search.toLowerCase()) ||
      (c.email ?? '').toLowerCase().includes(search.toLowerCase()) ||
      (c.cpf_cnpj ?? '').includes(search),
    );
    return [...list].sort((a, b) => {
      const val = (c: ClientRow) => {
        if (sort.key === 'active') return c.active ? 1 : 0;
        const v = (c as Record<string, unknown>)[sort.key];
        return String(v ?? '').toLowerCase();
      };
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [clients, search, sort]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const columns: DataColumn<ClientRow>[] = [
    {
      key: 'name', header: 'Nome', minWidth: 210, priority: 0, sortable: true,
      render: (c) => (
        <span className="block leading-tight">
          <Link to={`/v2/clients/${c.id}`} className="block truncate font-semibold text-accent hover:underline" onClick={(e) => e.stopPropagation()}>
            {c.name}
          </Link>
          <span className="block truncate text-xs text-muted-foreground">
            {c.type === 'company' ? t.common.company : t.common.individual}
            {c.city ? ` · ${c.city}${c.state ? `/${c.state}` : ''}` : ''}
          </span>
        </span>
      ),
    },
    {
      key: 'email', header: 'Contato', minWidth: 220, priority: 1, sortable: true, detailLabel: 'Contato',
      render: (c) => (
        <span className="block leading-tight text-muted-foreground">
          {c.email && (
            <span className="flex items-center gap-1.5 truncate"><Mail className="h-3 w-3 shrink-0" />{c.email}</span>
          )}
          {c.phone && (
            <span className="mt-0.5 flex items-center gap-1.5 text-xs"><Phone className="h-3 w-3 shrink-0" />{c.phone}</span>
          )}
          {!c.email && !c.phone && '—'}
        </span>
      ),
    },
    {
      key: 'vessels', header: 'Embarcações', minWidth: 110, priority: 3, detailLabel: 'Embarcações',
      render: (c) => (
        <span className="inline-flex items-center gap-1 text-muted-foreground tabular-nums">
          <Ship className="h-3.5 w-3.5" /> {vesselCounts?.[c.id] ?? 0}
        </span>
      ),
    },
    {
      key: 'active', header: 'Status', minWidth: 96, priority: 2, sortable: true, detailLabel: 'Status',
      render: (c) => (
        <StatusChip dot tone={c.active ? 'success' : 'critical'}>
          {c.active ? t.common.active : t.common.inactive}
        </StatusChip>
      ),
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Cadastros' }, { label: t.clients.title }]}
        title={t.clients.title}
        count={clients.length}
        actions={
          <>
            <Button variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex" onClick={() => setImportOpen(true)}>
              <Upload className="h-4 w-4" /> {t.imports.importData}
            </Button>
            <Button
              variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex"
              onClick={() => clients.length && exportToCSV(clients as never[], 'clientes.csv', CLIENTS_COLUMNS as never)}
            >
              <Download className="h-4 w-4" /> {t.imports.exportCSV}
            </Button>
            <Button className="gap-1.5" onClick={() => setFormOpen(true)}>
              <Plus className="h-4 w-4" /> {t.clients.newClient}
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-3 sm:flex-row">
          <Input
            placeholder={t.clients.searchPlaceholder}
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
            className="h-9 flex-1"
          />
          <FilterPresets
            filterType="clients"
            currentConfig={{ search }}
            hasActiveFilters={!!search}
            onApply={(c: { search?: string }) => { setSearch(c.search ?? ''); setPage(1); }}
          />
        </div>

        {isLoading ? (
          <div className="space-y-2">{[1, 2, 3, 4, 5].map((i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center">
            <p className="text-destructive">{(error as Error).message}</p>
          </div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<ClientRow>
                rows={paginated}
                rowKey={(c) => c.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                onRowClick={(c) => navigate(`/v2/clients/${c.id}`)}
                emptyMessage={clients.length === 0 ? t.clients.noClients : t.common.noResults}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {paginated.map((c) => (
                <EntityCard
                  key={c.id}
                  severity={c.active ? 'neutral' : 'critical'}
                  badge={<StatusChip tone={c.active ? 'success' : 'critical'}>{c.active ? t.common.active : t.common.inactive}</StatusChip>}
                  title={c.name}
                  lines={[
                    [c.email, c.phone].filter(Boolean).join(' · ') || '—',
                    `${c.type === 'company' ? t.common.company : t.common.individual}${c.city ? ` · ${c.city}` : ''} · ${vesselCounts?.[c.id] ?? 0} emb.`,
                  ]}
                  onClick={() => navigate(`/v2/clients/${c.id}`)}
                />
              ))}
              <button
                type="button"
                aria-label={t.clients.newClient}
                onClick={() => setFormOpen(true)}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </button>
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 pb-16 text-sm md:pb-0">
                <span className="text-muted-foreground">{filtered.length} clientes · Página {page} de {totalPages}</span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      <ClientFormDialog open={formOpen} onOpenChange={setFormOpen} />
      <ImportWizard entityType="auto" open={importOpen} onOpenChange={setImportOpen} />
    </V2Shell>
  );
}

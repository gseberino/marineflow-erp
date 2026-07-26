import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Anchor, Download, Mail, Pencil, Phone, Plus, Ship } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useMarinas, type Marina } from '@/hooks/use-marinas';
import { supabase } from '@/integrations/supabase/client';
import { exportToCSV, MARINAS_COLUMNS } from '@/lib/export-utils';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { MarinaFormDialog } from '@/components/MarinaFormDialog';
import { FilterPresets } from '@/components/FilterPresets';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda A · Marinas v2 — paridade com MarinaList v1 (busca, presets, CSV,
   contagem de embarcações, edição inline via dialog). */

const PAGE_SIZE = 20;

export default function MarinasListV2() {
  const { t } = useI18n();
  const { data, isLoading, error } = useMarinas();
  const marinas = useMemo(() => (data ?? []) as Marina[], [data]);

  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Marina | null>(null);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' });

  const { data: vesselCounts } = useQuery({
    queryKey: ['vessel-counts-by-marina'],
    queryFn: async () => {
      const { data: rows, error: err } = await supabase.from('vessels').select('marina_id').not('marina_id', 'is', null);
      if (err) throw err;
      const counts: Record<string, number> = {};
      rows.forEach((v) => { if (v.marina_id) counts[v.marina_id] = (counts[v.marina_id] || 0) + 1; });
      return counts;
    },
  });

  const filtered = useMemo(() => {
    const list = marinas.filter((m) =>
      !search || m.name.toLowerCase().includes(search.toLowerCase()) || (m.city ?? '').toLowerCase().includes(search.toLowerCase()),
    );
    return [...list].sort((a, b) => {
      const val = (m: Marina) =>
        sort.key === 'active' ? (m.active ? 1 : 0) : String((m as Record<string, unknown>)[sort.key] ?? '').toLowerCase();
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [marinas, search, sort]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const openEdit = (m: Marina) => { setEditing(m); setFormOpen(true); };

  const columns: DataColumn<Marina>[] = [
    {
      key: 'name', header: 'Marina', minWidth: 200, priority: 0, sortable: true,
      render: (m) => (
        <span className="flex items-center gap-2">
          <Anchor className="h-4 w-4 shrink-0 text-accent" />
          <span className="min-w-0 leading-tight">
            <span className="block truncate font-semibold">{m.name}</span>
            {(m.city || m.state) && (
              <span className="block truncate text-xs text-muted-foreground">{m.city}{m.state ? `/${m.state}` : ''}</span>
            )}
          </span>
        </span>
      ),
    },
    {
      key: 'contact_name', header: 'Contato', minWidth: 210, priority: 1, sortable: true, detailLabel: 'Contato',
      render: (m) => (
        <span className="block leading-tight text-muted-foreground">
          {(m.contact_name || m.phone) && (
            <span className="flex items-center gap-1.5 truncate"><Phone className="h-3 w-3 shrink-0" />{[m.contact_name, m.phone].filter(Boolean).join(' · ')}</span>
          )}
          {m.email && (
            <span className="mt-0.5 flex items-center gap-1.5 truncate text-xs"><Mail className="h-3 w-3 shrink-0" />{m.email}</span>
          )}
          {!m.contact_name && !m.phone && !m.email && '—'}
        </span>
      ),
    },
    {
      key: 'vessels', header: 'Embarcações', minWidth: 110, priority: 3, detailLabel: 'Embarcações',
      render: (m) => (
        <span className="inline-flex items-center gap-1 text-muted-foreground tabular-nums">
          <Ship className="h-3.5 w-3.5" /> {vesselCounts?.[m.id] ?? 0}
        </span>
      ),
    },
    {
      key: 'active', header: 'Status', minWidth: 96, priority: 2, sortable: true, detailLabel: 'Status',
      render: (m) => (
        <StatusChip dot tone={m.active ? 'success' : 'critical'}>{m.active ? t.common.active : t.common.inactive}</StatusChip>
      ),
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Cadastros' }, { label: t.marinas.title }]}
        title={t.marinas.title}
        count={marinas.length}
        actions={
          <>
            <Button
              variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex"
              onClick={() => exportToCSV(filtered as never[], 'marinas.csv', MARINAS_COLUMNS as never)}
            >
              <Download className="h-4 w-4" /> CSV
            </Button>
            <Button className="gap-1.5" onClick={() => { setEditing(null); setFormOpen(true); }}>
              <Plus className="h-4 w-4" /> {t.marinas.newMarina}
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-3 sm:flex-row">
          <Input
            placeholder={t.marinas.searchPlaceholder}
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
            className="h-9 flex-1"
          />
          <FilterPresets
            filterType="marinas"
            currentConfig={{ search }}
            hasActiveFilters={!!search}
            onApply={(c: { search?: string }) => { setSearch(c.search ?? ''); setPage(1); }}
          />
        </div>

        {isLoading ? (
          <div className="space-y-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center"><p className="text-destructive">{(error as Error).message}</p></div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<Marina>
                rows={paginated}
                rowKey={(m) => m.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                onRowClick={openEdit}
                emptyMessage={marinas.length === 0 ? t.marinas.noMarinas : t.common.noResults}
                rowActions={(m) => (
                  <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Editar marina" title="Editar" onClick={() => openEdit(m)}>
                    <Pencil className="h-4 w-4" />
                  </Button>
                )}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {paginated.map((m) => (
                <EntityCard
                  key={m.id}
                  severity={m.active ? 'neutral' : 'critical'}
                  badge={<StatusChip tone={m.active ? 'success' : 'critical'}>{m.active ? t.common.active : t.common.inactive}</StatusChip>}
                  title={m.name}
                  lines={[
                    [m.contact_name, m.phone].filter(Boolean).join(' · ') || '—',
                    `${m.city ?? '—'}${m.state ? `/${m.state}` : ''} · ${vesselCounts?.[m.id] ?? 0} emb.`,
                  ]}
                  onClick={() => openEdit(m)}
                />
              ))}
              <button
                type="button"
                aria-label={t.marinas.newMarina}
                onClick={() => { setEditing(null); setFormOpen(true); }}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </button>
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 pb-16 text-sm md:pb-0">
                <span className="text-muted-foreground">{filtered.length} marinas · Página {page} de {totalPages}</span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      <MarinaFormDialog open={formOpen} onOpenChange={setFormOpen} marina={editing} />
    </V2Shell>
  );
}

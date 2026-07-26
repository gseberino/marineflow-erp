import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Anchor, Download, Plus, Ship } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useVessels } from '@/hooks/use-vessels';
import { exportToCSV, VESSELS_COLUMNS } from '@/lib/export-utils';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { VesselFormDialog } from '@/components/VesselFormDialog';
import { FilterPresets } from '@/components/FilterPresets';
import { PageShell } from '@/v2/components/PageShell';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda A · Embarcações v2 — paridade com VesselList v1 (busca, filtro por tipo,
   presets, CSV, dialog de cadastro) em DataTable + EntityCard. */

const PAGE_SIZE = 20;

type VesselRow = {
  id: string;
  name: string;
  asset_type?: string | null;
  manufacturer?: string | null;
  model?: string | null;
  engine_brand?: string | null;
  engine_model?: string | null;
  engine_quantity?: number | null;
  length_feet?: number | null;
  year?: number | null;
  client_id?: string | null;
  clients?: { name?: string } | null;
  marinas?: { name?: string } | null;
};

export default function VesselsListV2() {
  const { t } = useI18n();
  const navigate = useNavigate();
  const { data, isLoading, error } = useVessels();
  const vessels = useMemo(() => (data ?? []) as unknown as VesselRow[], [data]);

  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [formOpen, setFormOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' });

  const types = useMemo(
    () => [...new Set(vessels.map((v) => v.asset_type).filter(Boolean))].sort() as string[],
    [vessels],
  );

  const filtered = useMemo(() => {
    const list = vessels.filter((v) =>
      (!search ||
        v.name.toLowerCase().includes(search.toLowerCase()) ||
        (v.manufacturer ?? '').toLowerCase().includes(search.toLowerCase()) ||
        (v.model ?? '').toLowerCase().includes(search.toLowerCase()) ||
        (v.clients?.name ?? '').toLowerCase().includes(search.toLowerCase())) &&
      (typeFilter === 'all' || v.asset_type === typeFilter),
    );
    return [...list].sort((a, b) => {
      const val = (v: VesselRow) => {
        if (sort.key === 'owner') return (v.clients?.name ?? '').toLowerCase();
        if (sort.key === 'length_feet' || sort.key === 'year') return Number((v as Record<string, unknown>)[sort.key] ?? 0);
        return String((v as Record<string, unknown>)[sort.key] ?? '').toLowerCase();
      };
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [vessels, search, typeFilter, sort]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const columns: DataColumn<VesselRow>[] = [
    {
      key: 'name', header: 'Unidade / Tipo', minWidth: 210, priority: 0, sortable: true,
      render: (v) => (
        <span className="flex items-center gap-2">
          <Ship className="h-4 w-4 shrink-0 text-accent" />
          <span className="min-w-0 leading-tight">
            <Link to={`/v2/vessels/${v.id}`} className="block truncate font-semibold text-accent hover:underline" onClick={(e) => e.stopPropagation()}>
              {v.name}
            </Link>
            <span className="block truncate text-xs text-muted-foreground">
              {v.asset_type || 'Lancha'} · {[v.manufacturer, v.model].filter(Boolean).join(' ') || '—'}
            </span>
          </span>
        </span>
      ),
    },
    {
      key: 'owner', header: t.vessels.owner, minWidth: 170, priority: 1, sortable: true, detailLabel: 'Proprietário',
      render: (v) => (
        v.client_id ? (
          <Link to={`/v2/clients/${v.client_id}`} className="truncate text-muted-foreground hover:text-foreground hover:underline" onClick={(e) => e.stopPropagation()}>
            {v.clients?.name ?? '—'}
          </Link>
        ) : (
          <span className="text-muted-foreground">—</span>
        )
      ),
    },
    {
      key: 'marina', header: t.serviceOrders.marina, minWidth: 140, priority: 3, detailLabel: 'Marina',
      render: (v) =>
        v.marinas?.name ? (
          <span className="flex items-center gap-1 truncate text-muted-foreground"><Anchor className="h-3 w-3 shrink-0" />{v.marinas.name}</span>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
    {
      key: 'engine', header: t.vessels.engine, minWidth: 160, priority: 4, detailLabel: 'Motorização',
      render: (v) => (
        <span className="truncate text-muted-foreground">
          {v.engine_brand || v.engine_model ? `${v.engine_quantity ?? 1}× ${[v.engine_brand, v.engine_model].filter(Boolean).join(' ')}` : '—'}
        </span>
      ),
    },
    {
      key: 'length_feet', header: t.vessels.length, minWidth: 84, priority: 2, sortable: true, detailLabel: 'Pés',
      render: (v) => <span className="font-medium tabular-nums">{v.length_feet ? `${v.length_feet} ft` : '—'}</span>,
    },
    {
      key: 'year', header: t.vessels.year, minWidth: 78, priority: 5, sortable: true, detailLabel: 'Ano',
      render: (v) => <span className="text-muted-foreground tabular-nums">{v.year ?? '—'}</span>,
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Cadastros' }, { label: t.vessels.title }]}
        title={t.vessels.title}
        count={vessels.length}
        actions={
          <>
            <Button
              variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex"
              onClick={() => vessels.length && exportToCSV(vessels as never[], 'embarcacoes.csv', VESSELS_COLUMNS as never)}
            >
              <Download className="h-4 w-4" /> Exportar CSV
            </Button>
            <Button className="gap-1.5" onClick={() => setFormOpen(true)}>
              <Plus className="h-4 w-4" /> Nova Unidade
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-3 sm:flex-row">
          <Input
            placeholder={t.vessels.searchPlaceholder}
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
            className="h-9 flex-1"
          />
          {types.length > 0 && (
            <Select value={typeFilter} onValueChange={(v) => { setTypeFilter(v); setPage(1); }}>
              <SelectTrigger className="h-9 w-full sm:w-[170px]">
                <SelectValue placeholder="Tipo" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Todos os tipos</SelectItem>
                {types.map((tp) => <SelectItem key={tp} value={tp}>{tp}</SelectItem>)}
              </SelectContent>
            </Select>
          )}
          <FilterPresets
            filterType="vessels"
            currentConfig={{ search, typeFilter }}
            hasActiveFilters={!!search || typeFilter !== 'all'}
            onApply={(c: { search?: string; typeFilter?: string }) => {
              setSearch(c.search ?? '');
              setTypeFilter(c.typeFilter ?? 'all');
              setPage(1);
            }}
          />
        </div>

        {isLoading ? (
          <div className="space-y-2">{[1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center">
            <p className="text-destructive">{(error as Error).message}</p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="space-y-3 rounded-lg border bg-card p-12 text-center">
            <Ship className="mx-auto h-12 w-12 text-muted-foreground" />
            <p className="text-muted-foreground">{vessels.length === 0 ? t.vessels.noVessels : t.common.noResults}</p>
            {vessels.length === 0 && (
              <Button className="gap-1.5" onClick={() => setFormOpen(true)}>
                <Plus className="h-4 w-4" /> {t.vessels.createFirst}
              </Button>
            )}
          </div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<VesselRow>
                rows={paginated}
                rowKey={(v) => v.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                onRowClick={(v) => navigate(`/v2/vessels/${v.id}`)}
                emptyMessage={t.common.noResults}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {paginated.map((v) => (
                <EntityCard
                  key={v.id}
                  title={v.name}
                  lines={[
                    `${v.asset_type || 'Lancha'} · ${[v.manufacturer, v.model].filter(Boolean).join(' ') || '—'}`,
                    [v.clients?.name, v.marinas?.name, v.length_feet ? `${v.length_feet} ft` : null, v.year].filter(Boolean).join(' · ') || '—',
                  ]}
                  onClick={() => navigate(`/v2/vessels/${v.id}`)}
                />
              ))}
              <button
                type="button"
                aria-label="Nova Unidade"
                onClick={() => setFormOpen(true)}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </button>
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 pb-16 text-sm md:pb-0">
                <span className="text-muted-foreground">{filtered.length} unidades · Página {page} de {totalPages}</span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      <VesselFormDialog open={formOpen} onOpenChange={setFormOpen} />
    </V2Shell>
  );
}

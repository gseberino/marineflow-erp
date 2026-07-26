import { useMemo, useState } from 'react';
import { Download, Pencil, Plus, Table2, Upload, Wrench } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useServices } from '@/hooks/use-services';
import { exportToCSV, SERVICES_COLUMNS } from '@/lib/export-utils';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { ServiceFormDialog } from '@/components/ServiceFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { BulkEditor } from '@/components/BulkEditor';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda A · Serviços v2 — paridade com ServiceList v1 (busca, import, edição
   em massa, CSV, unidade de cobrança, edição via dialog). */

const PAGE_SIZE = 20;

type ServiceRow = {
  id: string;
  name: string;
  category?: string | null;
  billing_unit: string;
  default_price?: number | null;
  active?: boolean | null;
};

export default function ServicesListV2() {
  const { t, formatCurrency } = useI18n();
  const { data, isLoading, error } = useServices();
  const services = useMemo(() => (data ?? []) as unknown as ServiceRow[], [data]);

  const [search, setSearch] = useState('');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editData, setEditData] = useState<ServiceRow | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [bulkOpen, setBulkOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' });

  const billingUnitLabel: Record<string, string> = {
    hour: t.services.unitHour,
    visit: t.services.unitVisit,
    day: t.services.unitDay,
    unit: t.services.unitUnit,
  };

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    const list = services.filter((s) => s.name.toLowerCase().includes(q) || (s.category || '').toLowerCase().includes(q));
    return [...list].sort((a, b) => {
      const val = (s: ServiceRow) => {
        if (sort.key === 'default_price') return Number(s.default_price ?? 0);
        if (sort.key === 'active') return s.active ? 1 : 0;
        return String((s as Record<string, unknown>)[sort.key] ?? '').toLowerCase();
      };
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [services, search, sort]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const openEdit = (s: ServiceRow) => { setEditData(s); setDialogOpen(true); };

  const columns: DataColumn<ServiceRow>[] = [
    {
      key: 'name', header: t.services.serviceName, minWidth: 220, priority: 0, sortable: true,
      render: (s) => <span className="block truncate font-semibold">{s.name}</span>,
    },
    {
      key: 'category', header: t.services.category, minWidth: 140, priority: 2, sortable: true, detailLabel: 'Categoria',
      render: (s) => (s.category ? <StatusChip tone="neutral">{s.category}</StatusChip> : <span className="text-muted-foreground">—</span>),
    },
    {
      key: 'billing_unit', header: t.services.billingUnit, minWidth: 110, priority: 3, sortable: true, detailLabel: 'Unidade',
      render: (s) => <span className="text-muted-foreground">{billingUnitLabel[s.billing_unit] || s.billing_unit}</span>,
    },
    {
      key: 'default_price', header: t.services.defaultPrice, minWidth: 120, priority: 1, align: 'right', sortable: true, detailLabel: 'Preço padrão',
      render: (s) => <span className="font-semibold">{formatCurrency(s.default_price || 0)}</span>,
    },
    {
      key: 'active', header: t.common.status, minWidth: 96, priority: 2, sortable: true, detailLabel: 'Status',
      render: (s) => (
        <StatusChip dot tone={s.active ? 'success' : 'neutral'}>{s.active ? t.common.active : t.common.inactive}</StatusChip>
      ),
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Cadastros' }, { label: t.services.title }]}
        title={t.services.title}
        count={services.length}
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
              onClick={() => services.length && exportToCSV(services as never[], 'servicos.csv', SERVICES_COLUMNS as never)}
            >
              <Download className="h-4 w-4" /> {t.imports.exportCSV}
            </Button>
            <Button className="gap-1.5" onClick={() => { setEditData(null); setDialogOpen(true); }}>
              <Plus className="h-4 w-4" /> {t.services.newService}
            </Button>
          </>
        }
      >
        <Input
          placeholder={t.services.searchPlaceholder}
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }}
          className="h-9 sm:max-w-sm"
        />

        {error ? (
          <div className="rounded-lg border bg-card p-8 text-center">
            <p className="text-destructive">Erro ao carregar serviços. Tente recarregar a página.</p>
          </div>
        ) : isLoading ? (
          <div className="space-y-2">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : filtered.length === 0 ? (
          <div className="space-y-3 rounded-lg border bg-card p-12 text-center">
            <Wrench className="mx-auto h-12 w-12 text-muted-foreground" />
            <p className="text-muted-foreground">{search ? t.common.noResults : t.services.noServices}</p>
            {!search && (
              <Button className="gap-1.5" onClick={() => { setEditData(null); setDialogOpen(true); }}>
                <Plus className="h-4 w-4" /> {t.services.createFirst}
              </Button>
            )}
          </div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<ServiceRow>
                rows={paginated}
                rowKey={(s) => s.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                onRowClick={openEdit}
                emptyMessage={t.common.noResults}
                rowActions={(s) => (
                  <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Editar serviço" title="Editar" onClick={() => openEdit(s)}>
                    <Pencil className="h-4 w-4" />
                  </Button>
                )}
              />
            </div>
            <div className="space-y-2.5 md:hidden">
              {paginated.map((s) => (
                <EntityCard
                  key={s.id}
                  badge={<StatusChip tone={s.active ? 'success' : 'neutral'}>{s.active ? t.common.active : t.common.inactive}</StatusChip>}
                  title={s.name}
                  lines={[
                    [s.category, billingUnitLabel[s.billing_unit] || s.billing_unit].filter(Boolean).join(' · '),
                    formatCurrency(s.default_price || 0),
                  ]}
                  onClick={() => openEdit(s)}
                />
              ))}
              <button
                type="button"
                aria-label={t.services.newService}
                onClick={() => { setEditData(null); setDialogOpen(true); }}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </button>
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 pb-16 text-sm md:pb-0">
                <span className="text-muted-foreground">{filtered.length} serviços · Página {page} de {totalPages}</span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      <ServiceFormDialog open={dialogOpen} onOpenChange={setDialogOpen} editData={editData} />
      <ImportWizard entityType="services" open={importOpen} onOpenChange={setImportOpen} />
      <BulkEditor entityType="services" open={bulkOpen} onOpenChange={setBulkOpen} />
    </V2Shell>
  );
}

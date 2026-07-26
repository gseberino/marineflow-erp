import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Building2, Download, Pencil, Plus, Upload } from 'lucide-react';
import { useI18n } from '@/i18n';
import { useSuppliers, type Supplier } from '@/hooks/use-suppliers';
import { supabase } from '@/integrations/supabase/client';
import { exportToCSV, SUPPLIERS_COLUMNS } from '@/lib/export-utils';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { SupplierFormDialog } from '@/components/SupplierFormDialog';
import { ImportWizard } from '@/components/ImportWizard';
import { FilterPresets } from '@/components/FilterPresets';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda A · Fornecedores v2 — paridade com SupplierList v1 (busca, presets,
   import, CSV, produtos vinculados, edição via dialog). */

const PAGE_SIZE = 20;

export default function SuppliersListV2() {
  const { t } = useI18n();
  const { data, isLoading, error } = useSuppliers();
  const suppliers = useMemo(() => (data ?? []) as Supplier[], [data]);

  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Supplier | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortState>({ key: 'name', dir: 'asc' });

  const { data: productCounts } = useQuery({
    queryKey: ['supplier-product-counts'],
    queryFn: async () => {
      const { data: rows, error: err } = await supabase.from('product_suppliers').select('supplier_id');
      if (err) throw err;
      const counts: Record<string, number> = {};
      (rows ?? []).forEach((r) => { counts[r.supplier_id] = (counts[r.supplier_id] ?? 0) + 1; });
      return counts;
    },
  });

  const filtered = useMemo(() => {
    const list = suppliers.filter((s) =>
      !search ||
      s.name.toLowerCase().includes(search.toLowerCase()) ||
      (s.cnpj_cpf ?? '').toLowerCase().includes(search.toLowerCase()) ||
      (s.trade_name ?? '').toLowerCase().includes(search.toLowerCase()),
    );
    return [...list].sort((a, b) => {
      const val = (s: Supplier) =>
        sort.key === 'active' ? (s.active ? 1 : 0) : String((s as Record<string, unknown>)[sort.key] ?? '').toLowerCase();
      const av = val(a);
      const bv = val(b);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [suppliers, search, sort]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  const openEdit = (s: Supplier) => { setEditing(s); setFormOpen(true); };

  const columns: DataColumn<Supplier>[] = [
    {
      key: 'name', header: t.suppliers.supplierName, minWidth: 210, priority: 0, sortable: true,
      render: (s) => (
        <span className="flex items-center gap-2">
          <Building2 className="h-4 w-4 shrink-0 text-accent" />
          <span className="min-w-0 leading-tight">
            <span className="block truncate font-semibold">{s.name}</span>
            {s.trade_name && <span className="block truncate text-xs text-muted-foreground">{s.trade_name}</span>}
          </span>
        </span>
      ),
    },
    {
      key: 'cnpj_cpf', header: t.suppliers.cnpj, minWidth: 150, priority: 3, sortable: true, detailLabel: 'CNPJ/CPF',
      render: (s) => <span className="text-muted-foreground tabular-nums">{s.cnpj_cpf ?? '—'}</span>,
    },
    {
      key: 'contact_name', header: t.suppliers.contactName, minWidth: 150, priority: 2, sortable: true, detailLabel: 'Contato',
      render: (s) => <span className="truncate text-muted-foreground">{s.contact_name ?? '—'}</span>,
    },
    {
      key: 'city', header: `${t.address.city}/${t.address.state}`, minWidth: 130, priority: 4, sortable: true, detailLabel: 'Cidade/UF',
      render: (s) => <span className="truncate text-muted-foreground">{[s.city, s.state].filter(Boolean).join('/') || '—'}</span>,
    },
    {
      key: 'products', header: t.suppliers.linkedProducts, minWidth: 100, priority: 5, detailLabel: 'Produtos',
      render: (s) => <span className="font-medium tabular-nums">{productCounts?.[s.id] ?? 0}</span>,
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
        breadcrumb={[{ label: 'Cadastros' }, { label: t.suppliers.title }]}
        title={t.suppliers.title}
        count={suppliers.length}
        actions={
          <>
            <Button variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex" onClick={() => setImportOpen(true)}>
              <Upload className="h-4 w-4" /> {t.imports.importData}
            </Button>
            <Button
              variant="outline" size="sm" className="hidden gap-1.5 sm:inline-flex"
              onClick={() => suppliers.length && exportToCSV(suppliers as never[], 'fornecedores.csv', SUPPLIERS_COLUMNS as never)}
            >
              <Download className="h-4 w-4" /> {t.imports.exportCSV}
            </Button>
            <Button className="gap-1.5" onClick={() => { setEditing(null); setFormOpen(true); }}>
              <Plus className="h-4 w-4" /> {t.suppliers.newSupplier}
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-3 sm:flex-row">
          <Input
            placeholder={t.suppliers.searchPlaceholder}
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
            className="h-9 flex-1"
          />
          <FilterPresets
            filterType="suppliers"
            currentConfig={{ search }}
            hasActiveFilters={!!search}
            onApply={(c: { search?: string }) => { setSearch(c.search ?? ''); setPage(1); }}
          />
        </div>

        {isLoading ? (
          <div className="space-y-2">{[1, 2, 3].map((i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center"><p className="text-destructive">{(error as Error).message}</p></div>
        ) : filtered.length === 0 ? (
          <div className="space-y-3 rounded-lg border bg-card p-12 text-center">
            <Building2 className="mx-auto h-12 w-12 text-muted-foreground" />
            <p className="text-muted-foreground">{suppliers.length === 0 ? t.suppliers.noSuppliers : t.common.noResults}</p>
            {suppliers.length === 0 && (
              <Button className="gap-1.5" onClick={() => { setEditing(null); setFormOpen(true); }}>
                <Plus className="h-4 w-4" /> {t.suppliers.createFirst}
              </Button>
            )}
          </div>
        ) : (
          <>
            <div className="hidden md:block">
              <DataTable<Supplier>
                rows={paginated}
                rowKey={(s) => s.id}
                columns={columns}
                sort={sort}
                onSort={handleSort}
                onRowClick={openEdit}
                emptyMessage={t.common.noResults}
                rowActions={(s) => (
                  <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Editar fornecedor" title="Editar" onClick={() => openEdit(s)}>
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
                    [s.trade_name, s.cnpj_cpf].filter(Boolean).join(' · ') || '—',
                    [s.contact_name, [s.city, s.state].filter(Boolean).join('/'), `${productCounts?.[s.id] ?? 0} produto(s)`].filter(Boolean).join(' · '),
                  ]}
                  onClick={() => openEdit(s)}
                />
              ))}
              <button
                type="button"
                aria-label={t.suppliers.newSupplier}
                onClick={() => { setEditing(null); setFormOpen(true); }}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </button>
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 pb-16 text-sm md:pb-0">
                <span className="text-muted-foreground">{filtered.length} fornecedores · Página {page} de {totalPages}</span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Anterior</Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Próxima</Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      <SupplierFormDialog open={formOpen} onOpenChange={setFormOpen} supplier={editing} />
      <ImportWizard entityType="suppliers" open={importOpen} onOpenChange={setImportOpen} />
    </V2Shell>
  );
}

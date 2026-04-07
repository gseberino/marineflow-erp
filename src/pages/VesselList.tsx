import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useVessels } from '@/hooks/use-vessels';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Anchor, Ship } from 'lucide-react';
import { Skeleton } from '@/components/ui/skeleton';
import { VesselFormDialog } from '@/components/VesselFormDialog';

export default function VesselList() {
  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const { t } = useI18n();
  const { data: vessels, isLoading, error } = useVessels();

  const filtered = (vessels ?? []).filter((v: any) =>
    !search ||
    v.boat_name.toLowerCase().includes(search.toLowerCase()) ||
    (v.manufacturer ?? '').toLowerCase().includes(search.toLowerCase()) ||
    (v.model ?? '').toLowerCase().includes(search.toLowerCase()) ||
    (v.clients?.full_name_or_company_name ?? '').toLowerCase().includes(search.toLowerCase())
  );

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.vessels.title} description={`${t.vessels.description} (${vessels?.length ?? 0})`}>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => setFormOpen(true)}>
          <Plus className="h-4 w-4" /> {t.vessels.newVessel}
        </Button>
      </PageHeader>
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder={t.vessels.searchPlaceholder} value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
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
        <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead><tr className="border-b bg-muted/50">
              <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.vessels.vessel}</th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.vessels.owner}</th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.serviceOrders.marina}</th>
              <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.vessels.engine}</th>
              <th className="px-4 py-3 text-center font-medium text-muted-foreground">{t.vessels.length}</th>
              <th className="px-4 py-3 text-center font-medium text-muted-foreground hidden lg:table-cell">{t.vessels.year}</th>
            </tr></thead>
            <tbody>
              {filtered.map((v: any) => (
                <tr key={v.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                  <td className="px-4 py-3">
                    <Link to={`/vessels/${v.id}`} className="flex items-center gap-2">
                      <Ship className="h-4 w-4 text-accent shrink-0" />
                      <div>
                        <p className="font-medium text-accent hover:underline">{v.boat_name}</p>
                        <p className="text-xs text-muted-foreground">{v.manufacturer} {v.model}</p>
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
      )}

      <VesselFormDialog open={formOpen} onOpenChange={setFormOpen} />
    </div>
  );
}

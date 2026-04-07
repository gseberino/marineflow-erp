import { useState } from 'react';
import { useI18n } from '@/i18n';
import { useServices } from '@/hooks/use-services';
import { PageHeader } from '@/components/PageHeader';
import { ServiceFormDialog } from '@/components/ServiceFormDialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/StatusBadge';
import { Plus, Search, Wrench, Pencil } from 'lucide-react';

export default function ServiceList() {
  const { t, formatCurrency } = useI18n();
  const { data: services, isLoading } = useServices();
  const [search, setSearch] = useState('');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editData, setEditData] = useState<any>(null);

  const filtered = services?.filter((s) => {
    const q = search.toLowerCase();
    return s.service_name.toLowerCase().includes(q) || (s.category || '').toLowerCase().includes(q);
  });

  const billingUnitLabel: Record<string, string> = {
    hour: t.services.unitHour,
    visit: t.services.unitVisit,
    day: t.services.unitDay,
    unit: t.services.unitUnit,
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.services.title} description={t.services.description}>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"
          onClick={() => { setEditData(null); setDialogOpen(true); }}>
          <Plus className="h-4 w-4" /> {t.services.newService}
        </Button>
      </PageHeader>

      <div className="relative max-w-sm">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input placeholder={t.services.searchPlaceholder} value={search}
          onChange={(e) => setSearch(e.target.value)} className="pl-9" />
      </div>

      {isLoading ? (
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
        <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.services.serviceName}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.services.category}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.services.billingUnit}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.services.defaultPrice}</th>
                <th className="px-4 py-3 text-center font-medium text-muted-foreground">{t.common.status}</th>
                <th className="px-4 py-3 w-10"></th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((s) => (
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
      )}

      <ServiceFormDialog open={dialogOpen} onOpenChange={setDialogOpen} editData={editData} />
    </div>
  );
}

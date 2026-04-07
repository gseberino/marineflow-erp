import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useMarinas } from '@/hooks/use-marinas';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, MapPin, Phone, Mail, Ship, Edit } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { MarinaFormDialog } from '@/components/MarinaFormDialog';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
import type { Marina } from '@/hooks/use-marinas';

export default function MarinaList() {
  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const [editMarina, setEditMarina] = useState<Marina | null>(null);
  const { t } = useI18n();
  const { data: marinas, isLoading, error } = useMarinas();

  // Vessel counts per marina
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

  const filtered = (marinas ?? []).filter(m =>
    !search || m.marina_name.toLowerCase().includes(search.toLowerCase()) || (m.city ?? '').toLowerCase().includes(search.toLowerCase())
  );

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.marinas.title} description={`${t.marinas.description} (${marinas?.length ?? 0})`}>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => { setEditMarina(null); setFormOpen(true); }}>
          <Plus className="h-4 w-4" /> {t.marinas.newMarina}
        </Button>
      </PageHeader>
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder={t.marinas.searchPlaceholder} value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {[1,2,3,4].map(i => <Skeleton key={i} className="h-40 rounded-xl" />)}
        </div>
      ) : filtered.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-muted-foreground">{marinas?.length === 0 ? t.marinas.noMarinas : t.common.noResults}</p>
          {marinas?.length === 0 && (
            <Button variant="outline" className="mt-4" onClick={() => setFormOpen(true)}>
              <Plus className="h-4 w-4 mr-2" /> {t.marinas.createFirst}
            </Button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {filtered.map(m => {
            const vesselCount = vesselCounts?.[m.id] ?? 0;
            return (
              <div key={m.id} className="rounded-xl border bg-card p-5 shadow-sm hover:shadow-md transition-all">
                <div className="flex items-start justify-between mb-3">
                  <h3 className="font-semibold text-lg">{m.marina_name}</h3>
                  <div className="flex items-center gap-2">
                    <StatusBadge className={m.active ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                      {m.active ? t.common.active : t.common.inactive}
                    </StatusBadge>
                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => { setEditMarina(m); setFormOpen(true); }}>
                      <Edit className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
                <div className="space-y-1.5 text-sm text-muted-foreground">
                  {m.address_line_1 && <div className="flex items-center gap-2"><MapPin className="h-3.5 w-3.5" /> {m.address_line_1}, {m.city}, {m.state}</div>}
                  {m.contact_name && <div className="flex items-center gap-2"><Phone className="h-3.5 w-3.5" /> {m.contact_name}{m.contact_phone ? ` - ${m.contact_phone}` : ''}</div>}
                  {m.contact_email && <div className="flex items-center gap-2"><Mail className="h-3.5 w-3.5" /> {m.contact_email}</div>}
                  <div className="flex items-center gap-2"><Ship className="h-3.5 w-3.5" /> {t.marinas.vesselsDocked.replace('{count}', String(vesselCount))}</div>
                </div>
                {m.access_notes && <p className="text-xs text-muted-foreground mt-3 p-2 bg-muted/50 rounded">{m.access_notes}</p>}
                {m.latitude && <p className="text-xs text-muted-foreground mt-2">📍 {Number(m.latitude).toFixed(4)}, {Number(m.longitude).toFixed(4)}</p>}
              </div>
            );
          })}
        </div>
      )}

      <MarinaFormDialog open={formOpen} onOpenChange={setFormOpen} marina={editMarina} />
    </div>
  );
}

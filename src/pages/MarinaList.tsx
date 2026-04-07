import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { marinas, vessels } from '@/data/mock-data';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, MapPin, Phone, Mail, Ship } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';

export default function MarinaList() {
  const [search, setSearch] = useState('');
  const { t } = useI18n();
  const filtered = marinas.filter(m =>
    !search || m.marina_name.toLowerCase().includes(search.toLowerCase()) || m.city.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.marinas.title} description={t.marinas.description}>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"><Plus className="h-4 w-4" /> {t.marinas.newMarina}</Button>
      </PageHeader>
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder={t.marinas.searchPlaceholder} value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {filtered.map(m => {
          const vesselCount = vessels.filter(v => v.marina_id === m.id).length;
          return (
            <div key={m.id} className="rounded-xl border bg-card p-5 shadow-sm hover:shadow-md transition-all">
              <div className="flex items-start justify-between mb-3">
                <h3 className="font-semibold text-lg">{m.marina_name}</h3>
                <StatusBadge className={m.active ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                  {m.active ? t.common.active : t.common.inactive}
                </StatusBadge>
              </div>
              <div className="space-y-1.5 text-sm text-muted-foreground">
                <div className="flex items-center gap-2"><MapPin className="h-3.5 w-3.5" /> {m.address_line_1}, {m.city}, {m.state}</div>
                <div className="flex items-center gap-2"><Phone className="h-3.5 w-3.5" /> {m.contact_name} - {m.contact_phone}</div>
                <div className="flex items-center gap-2"><Mail className="h-3.5 w-3.5" /> {m.contact_email}</div>
                <div className="flex items-center gap-2"><Ship className="h-3.5 w-3.5" /> {t.marinas.vesselsDocked.replace('{count}', String(vesselCount))}</div>
              </div>
              {m.access_notes && <p className="text-xs text-muted-foreground mt-3 p-2 bg-muted/50 rounded">{m.access_notes}</p>}
              {m.latitude && <p className="text-xs text-muted-foreground mt-2">📍 {m.latitude.toFixed(4)}, {m.longitude?.toFixed(4)}</p>}
            </div>
          );
        })}
      </div>
    </div>
  );
}

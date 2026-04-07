import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Phone, Mail, Ship } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';

export default function ClientList() {
  const [search, setSearch] = useState('');
  const [formOpen, setFormOpen] = useState(false);
  const { t } = useI18n();
  const { data: clients, isLoading, error } = useClients();

  // Get vessel counts per client
  const { data: vesselCounts } = useQuery({
    queryKey: ['vessel-counts'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('vessels')
        .select('client_id');
      if (error) throw error;
      const counts: Record<string, number> = {};
      data.forEach(v => { counts[v.client_id] = (counts[v.client_id] || 0) + 1; });
      return counts;
    },
  });

  const filtered = (clients ?? []).filter(c =>
    !search || c.full_name_or_company_name.toLowerCase().includes(search.toLowerCase()) ||
    (c.email ?? '').toLowerCase().includes(search.toLowerCase()) ||
    (c.cpf_cnpj ?? '').includes(search)
  );

  if (error) return <div className="py-20 text-center text-destructive">{(error as Error).message}</div>;

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.clients.title} description={`${t.clients.description} (${clients?.length ?? 0})`}>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90" onClick={() => setFormOpen(true)}>
          <Plus className="h-4 w-4" /> {t.clients.newClient}
        </Button>
      </PageHeader>

      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder={t.clients.searchPlaceholder} value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1,2,3,4,5,6].map(i => <Skeleton key={i} className="h-40 rounded-xl" />)}
        </div>
      ) : filtered.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-muted-foreground">{clients?.length === 0 ? t.clients.noClients : t.common.noResults}</p>
          {clients?.length === 0 && (
            <Button variant="outline" className="mt-4" onClick={() => setFormOpen(true)}>
              <Plus className="h-4 w-4 mr-2" /> {t.clients.createFirst}
            </Button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map(client => {
            const vc = vesselCounts?.[client.id] ?? 0;
            return (
              <Link key={client.id} to={`/clients/${client.id}`} className="rounded-xl border bg-card p-5 shadow-sm hover:shadow-md hover:border-accent/30 transition-all">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <h3 className="font-semibold">{client.full_name_or_company_name}</h3>
                    <StatusBadge className={client.type === 'company' ? 'bg-primary/10 text-primary mt-1' : 'bg-muted text-muted-foreground mt-1'}>
                      {client.type === 'company' ? t.common.company : t.common.individual}
                    </StatusBadge>
                  </div>
                  <StatusBadge className={client.active ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                    {client.active ? t.common.active : t.common.inactive}
                  </StatusBadge>
                </div>
                <div className="space-y-1.5 text-sm text-muted-foreground">
                  {client.email && <div className="flex items-center gap-2"><Mail className="h-3.5 w-3.5" /> {client.email}</div>}
                  {client.phone && <div className="flex items-center gap-2"><Phone className="h-3.5 w-3.5" /> {client.phone}</div>}
                  <div className="flex items-center gap-2"><Ship className="h-3.5 w-3.5" /> {vc} {t.clients.vessels.toLowerCase()}</div>
                </div>
                <div className="flex items-center gap-3 mt-4 pt-3 border-t text-xs">
                  <span className="text-muted-foreground ml-auto">{client.city}{client.state ? `, ${client.state}` : ''}</span>
                </div>
              </Link>
            );
          })}
        </div>
      )}

      <ClientFormDialog open={formOpen} onOpenChange={setFormOpen} />
    </div>
  );
}

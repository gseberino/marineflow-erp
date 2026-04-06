import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { clients, getVesselsForClient, getServiceOrdersForClient } from '@/data/mock-data';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Phone, Mail, Ship } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';

export default function ClientList() {
  const [search, setSearch] = useState('');

  const filtered = clients.filter(c =>
    !search || c.full_name_or_company_name.toLowerCase().includes(search.toLowerCase()) ||
    c.email.toLowerCase().includes(search.toLowerCase()) ||
    c.cpf_cnpj.includes(search)
  );

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title="Clients" description="Manage your client database">
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
          <Plus className="h-4 w-4" /> New Client
        </Button>
      </PageHeader>

      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder="Search clients by name, email, or document..." value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filtered.map(client => {
          const vessels = getVesselsForClient(client.id);
          const orders = getServiceOrdersForClient(client.id);
          const openOrders = orders.filter(o => !['completed', 'invoiced', 'cancelled'].includes(o.status)).length;
          return (
            <Link key={client.id} to={`/clients/${client.id}`} className="rounded-xl border bg-card p-5 shadow-sm hover:shadow-md hover:border-accent/30 transition-all">
              <div className="flex items-start justify-between mb-3">
                <div>
                  <h3 className="font-semibold">{client.full_name_or_company_name}</h3>
                  <StatusBadge className={client.type === 'company' ? 'bg-primary/10 text-primary mt-1' : 'bg-muted text-muted-foreground mt-1'}>
                    {client.type === 'company' ? 'Company' : 'Individual'}
                  </StatusBadge>
                </div>
                <StatusBadge className={client.active ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                  {client.active ? 'Active' : 'Inactive'}
                </StatusBadge>
              </div>
              <div className="space-y-1.5 text-sm text-muted-foreground">
                <div className="flex items-center gap-2"><Mail className="h-3.5 w-3.5" /> {client.email}</div>
                <div className="flex items-center gap-2"><Phone className="h-3.5 w-3.5" /> {client.phone}</div>
                <div className="flex items-center gap-2"><Ship className="h-3.5 w-3.5" /> {vessels.length} vessel{vessels.length !== 1 ? 's' : ''}</div>
              </div>
              <div className="flex items-center gap-3 mt-4 pt-3 border-t text-xs">
                <span className="text-muted-foreground">{orders.length} orders</span>
                {openOrders > 0 && <span className="text-warning font-medium">{openOrders} open</span>}
                <span className="text-muted-foreground ml-auto">{client.city}, {client.state}</span>
              </div>
            </Link>
          );
        })}
      </div>
    </div>
  );
}

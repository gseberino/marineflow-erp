import { useParams, Link } from 'react-router-dom';
import { clients, getVesselsForClient, getServiceOrdersForClient, receivables, getMarina } from '@/data/mock-data';
import { formatCurrency, formatDate, statusConfig, serviceTypeLabels } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArrowLeft, Mail, Phone, MapPin, Ship } from 'lucide-react';

export default function ClientDetail() {
  const { id } = useParams<{ id: string }>();
  const client = clients.find(c => c.id === id);
  if (!client) return <div className="py-20 text-center text-muted-foreground">Client not found. <Link to="/clients" className="text-accent hover:underline">← Back</Link></div>;

  const vessels = getVesselsForClient(client.id);
  const orders = getServiceOrdersForClient(client.id);
  const clientReceivables = receivables.filter(r => r.client_id === client.id);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center gap-3">
        <Link to="/clients" className="rounded-lg p-1.5 hover:bg-muted transition-colors"><ArrowLeft className="h-5 w-5" /></Link>
        <div>
          <h1 className="text-2xl font-bold">{client.full_name_or_company_name}</h1>
          <div className="flex items-center gap-2 mt-1 text-sm text-muted-foreground">
            <StatusBadge className={client.type === 'company' ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'}>
              {client.type === 'company' ? 'Company' : 'Individual'}
            </StatusBadge>
            <span>{client.city}, {client.state}</span>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="rounded-xl border bg-card p-5 shadow-sm space-y-3">
          <div className="flex items-center gap-2 text-sm"><Mail className="h-4 w-4 text-muted-foreground" /> {client.email}</div>
          <div className="flex items-center gap-2 text-sm"><Phone className="h-4 w-4 text-muted-foreground" /> {client.phone}</div>
          <div className="flex items-center gap-2 text-sm"><MapPin className="h-4 w-4 text-muted-foreground" /> {client.address_line_1}, {client.city}</div>
          <div className="flex items-center gap-2 text-sm text-muted-foreground">Doc: {client.cpf_cnpj}</div>
        </div>
        <div className="rounded-xl border bg-card p-5 shadow-sm text-center">
          <p className="text-3xl font-bold">{vessels.length}</p>
          <p className="text-sm text-muted-foreground">Vessels</p>
        </div>
        <div className="rounded-xl border bg-card p-5 shadow-sm text-center">
          <p className="text-3xl font-bold">{orders.length}</p>
          <p className="text-sm text-muted-foreground">Service Orders</p>
        </div>
      </div>

      <Tabs defaultValue="vessels">
        <TabsList><TabsTrigger value="vessels">Vessels</TabsTrigger><TabsTrigger value="orders">Service Orders</TabsTrigger><TabsTrigger value="financial">Financial</TabsTrigger></TabsList>
        <TabsContent value="vessels" className="mt-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {vessels.map(v => {
              const marina = v.marina_id ? getMarina(v.marina_id) : undefined;
              return (
                <Link key={v.id} to={`/vessels/${v.id}`} className="rounded-xl border bg-card p-5 shadow-sm hover:shadow-md transition-all">
                  <div className="flex items-start justify-between mb-2">
                    <div>
                      <h3 className="font-semibold flex items-center gap-2"><Ship className="h-4 w-4 text-accent" />{v.boat_name}</h3>
                      <p className="text-sm text-muted-foreground">{v.manufacturer} {v.model} ({v.year})</p>
                    </div>
                    <span className="text-sm font-medium">{v.length_feet} ft</span>
                  </div>
                  <p className="text-xs text-muted-foreground">{marina?.marina_name || 'No marina'} {v.current_dock_position ? `• ${v.current_dock_position}` : ''}</p>
                </Link>
              );
            })}
          </div>
        </TabsContent>
        <TabsContent value="orders" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Order #</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Type</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">Total</th>
              </tr></thead>
              <tbody>
                {orders.map(o => (
                  <tr key={o.id} className="border-b last:border-0 hover:bg-muted/30">
                    <td className="px-4 py-3"><Link to={`/service-orders/${o.id}`} className="text-accent hover:underline">{o.service_order_number}</Link></td>
                    <td className="px-4 py-3 text-muted-foreground">{serviceTypeLabels[o.service_type]}</td>
                    <td className="px-4 py-3"><StatusBadge className={statusConfig[o.status].className}>{statusConfig[o.status].label}</StatusBadge></td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(o.grand_total)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </TabsContent>
        <TabsContent value="financial" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Description</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Due</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">Amount</th>
              </tr></thead>
              <tbody>
                {clientReceivables.map(r => (
                  <tr key={r.id} className="border-b last:border-0">
                    <td className="px-4 py-3">{r.description}</td>
                    <td className="px-4 py-3 text-muted-foreground">{formatDate(r.due_date)}</td>
                    <td className="px-4 py-3"><StatusBadge className={r.status === 'paid' ? 'bg-success/15 text-success' : r.status === 'overdue' ? 'bg-destructive/10 text-destructive' : 'bg-warning/15 text-warning'}>{r.status}</StatusBadge></td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(r.amount)}</td>
                  </tr>
                ))}
                {clientReceivables.length === 0 && <tr><td colSpan={4} className="px-4 py-8 text-center text-muted-foreground">No financial records.</td></tr>}
              </tbody>
            </table>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}

import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { useClient, useUpdateClient } from '@/hooks/use-clients';
import { useVesselsForClient } from '@/hooks/use-vessels';
import { statusConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Button } from '@/components/ui/button';
import { ArrowLeft, Mail, Phone, MapPin, Ship, Edit } from 'lucide-react';
import { ClientFormDialog } from '@/components/ClientFormDialog';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';

export default function ClientDetail() {
  const { id } = useParams<{ id: string }>();
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: client, isLoading } = useClient(id);
  const { data: vessels } = useVesselsForClient(id);
  const [editOpen, setEditOpen] = useState(false);

  // Fetch service orders for this client
  const { data: orders } = useQuery({
    queryKey: ['service-orders', 'client', id],
    queryFn: async () => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('service_orders')
        .select('*')
        .eq('client_id', id)
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
    enabled: !!id,
  });

  // Fetch receivables for this client
  const { data: clientReceivables } = useQuery({
    queryKey: ['receivables', 'client', id],
    queryFn: async () => {
      if (!id) return [];
      const { data, error } = await supabase
        .from('receivables')
        .select('*')
        .eq('client_id', id)
        .order('due_date', { ascending: false });
      if (error) throw error;
      return data;
    },
    enabled: !!id,
  });

  if (isLoading) return (
    <div className="space-y-6">
      <Skeleton className="h-10 w-64" />
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {[1,2,3].map(i => <Skeleton key={i} className="h-32 rounded-xl" />)}
      </div>
    </div>
  );

  if (!client) return (
    <div className="py-20 text-center text-muted-foreground">
      {t.common.noResults} <Link to="/clients" className="text-accent hover:underline">← {t.common.back}</Link>
    </div>
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center gap-3">
        <Link to="/clients" className="rounded-lg p-1.5 hover:bg-muted transition-colors"><ArrowLeft className="h-5 w-5" /></Link>
        <div className="flex-1">
          <h1 className="text-2xl font-bold">{client.full_name_or_company_name}</h1>
          <div className="flex items-center gap-2 mt-1 text-sm text-muted-foreground">
            <StatusBadge className={client.type === 'company' ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'}>
              {client.type === 'company' ? t.common.company : t.common.individual}
            </StatusBadge>
            <span>{client.city}{client.state ? `, ${client.state}` : ''}</span>
          </div>
        </div>
        <Button variant="outline" size="sm" onClick={() => setEditOpen(true)}>
          <Edit className="h-4 w-4 mr-1" /> {t.common.edit}
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="rounded-xl border bg-card p-5 shadow-sm space-y-3">
          {client.email && <div className="flex items-center gap-2 text-sm"><Mail className="h-4 w-4 text-muted-foreground" /> {client.email}</div>}
          {client.phone && <div className="flex items-center gap-2 text-sm"><Phone className="h-4 w-4 text-muted-foreground" /> {client.phone}</div>}
          {client.address_line_1 && <div className="flex items-center gap-2 text-sm"><MapPin className="h-4 w-4 text-muted-foreground" /> {client.address_line_1}, {client.city}</div>}
          {client.cpf_cnpj && <div className="text-sm text-muted-foreground">{t.clients.doc}: {client.cpf_cnpj}</div>}
        </div>
        <div className="rounded-xl border bg-card p-5 shadow-sm text-center">
          <p className="text-3xl font-bold">{vessels?.length ?? 0}</p>
          <p className="text-sm text-muted-foreground">{t.clients.vessels}</p>
        </div>
        <div className="rounded-xl border bg-card p-5 shadow-sm text-center">
          <p className="text-3xl font-bold">{orders?.length ?? 0}</p>
          <p className="text-sm text-muted-foreground">{t.clients.serviceOrders}</p>
        </div>
      </div>

      <Tabs defaultValue="vessels">
        <TabsList>
          <TabsTrigger value="vessels">{t.clients.vessels}</TabsTrigger>
          <TabsTrigger value="orders">{t.clients.serviceOrders}</TabsTrigger>
          <TabsTrigger value="financial">{t.clients.financial}</TabsTrigger>
        </TabsList>
        <TabsContent value="vessels" className="mt-4">
          {(!vessels || vessels.length === 0) ? (
            <p className="py-8 text-center text-muted-foreground">{t.vessels.noVessels}</p>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {vessels.map((v: any) => (
                <Link key={v.id} to={`/vessels/${v.id}`} className="rounded-xl border bg-card p-5 shadow-sm hover:shadow-md transition-all">
                  <div className="flex items-start justify-between mb-2">
                    <div>
                      <h3 className="font-semibold flex items-center gap-2"><Ship className="h-4 w-4 text-accent" />{v.boat_name}</h3>
                      <p className="text-sm text-muted-foreground">{v.manufacturer} {v.model} {v.year ? `(${v.year})` : ''}</p>
                    </div>
                    {v.length_feet && <span className="text-sm font-medium">{v.length_feet} ft</span>}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {v.marinas?.marina_name || t.vessels.noMarina}
                    {v.current_dock_position ? ` • ${v.current_dock_position}` : ''}
                  </p>
                </Link>
              ))}
            </div>
          )}
        </TabsContent>
        <TabsContent value="orders" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[600px]">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.orderNumber}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.type}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.total}</th>
              </tr></thead>
              <tbody>
                {(orders ?? []).map(o => (
                  <tr key={o.id} className="border-b last:border-0 hover:bg-muted/30">
                    <td className="px-4 py-3"><Link to={`/service-orders/${o.id}`} className="text-accent hover:underline">{o.service_order_number}</Link></td>
                    <td className="px-4 py-3 text-muted-foreground">{o.service_type ? (t.serviceType as Record<string, string>)[o.service_type] ?? o.service_type : '—'}</td>
                    <td className="px-4 py-3">
                      <StatusBadge className={statusConfig[o.status as keyof typeof statusConfig]?.className ?? ''}>
                        {(t.status as Record<string, string>)[o.status] ?? o.status}
                      </StatusBadge>
                    </td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(o.grand_total ?? 0)}</td>
                  </tr>
                ))}
                {(!orders || orders.length === 0) && <tr><td colSpan={4} className="px-4 py-8 text-center text-muted-foreground">{t.common.noResults}</td></tr>}
              </tbody>
            </table>
          </div>
        </TabsContent>
        <TabsContent value="financial" className="mt-4">
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[600px]">
              <thead><tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.financial.dueDate}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
              </tr></thead>
              <tbody>
                {(clientReceivables ?? []).map(r => (
                  <tr key={r.id} className="border-b last:border-0">
                    <td className="px-4 py-3">{r.description}</td>
                    <td className="px-4 py-3 text-muted-foreground">{formatDate(r.due_date)}</td>
                    <td className="px-4 py-3">
                      <StatusBadge className={r.status === 'paid' ? 'bg-success/15 text-success' : r.status === 'overdue' ? 'bg-destructive/10 text-destructive' : 'bg-warning/15 text-warning'}>
                        {(t.paymentStatus as Record<string, string>)[r.status ?? 'pending'] ?? r.status}
                      </StatusBadge>
                    </td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(r.amount)}</td>
                  </tr>
                ))}
                {(!clientReceivables || clientReceivables.length === 0) && <tr><td colSpan={4} className="px-4 py-8 text-center text-muted-foreground">{t.clients.noFinancialRecords}</td></tr>}
              </tbody>
            </table>
          </div>
        </TabsContent>
      </Tabs>

      <ClientFormDialog open={editOpen} onOpenChange={setEditOpen} client={client} />
    </div>
  );
}

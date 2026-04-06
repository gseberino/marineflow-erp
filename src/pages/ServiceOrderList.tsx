import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { StatusBadge } from '@/components/StatusBadge';
import { serviceOrders, getClient, getVessel, getMarina } from '@/data/mock-data';
import { formatCurrency, formatDate, statusConfig, priorityConfig, serviceTypeLabels } from '@/lib/constants';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Filter } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

export default function ServiceOrderList() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');

  const filtered = serviceOrders.filter(so => {
    const client = getClient(so.client_id);
    const vessel = getVessel(so.vessel_id);
    const matchesSearch = !search ||
      so.service_order_number.toLowerCase().includes(search.toLowerCase()) ||
      client?.full_name_or_company_name.toLowerCase().includes(search.toLowerCase()) ||
      vessel?.boat_name.toLowerCase().includes(search.toLowerCase());
    const matchesStatus = statusFilter === 'all' || so.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title="Service Orders" description="Manage all service orders and field operations">
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
          <Plus className="h-4 w-4" /> New Order
        </Button>
      </PageHeader>

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder="Search orders, clients, vessels..." value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-full sm:w-[180px]">
            <Filter className="h-4 w-4 mr-2" />
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Statuses</SelectItem>
            {Object.entries(statusConfig).map(([key, val]) => (
              <SelectItem key={key} value={key}>{val.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Order #</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Client</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Vessel</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Marina</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">Status</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Priority</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Type</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Scheduled</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">Total</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(so => {
                const client = getClient(so.client_id);
                const vessel = getVessel(so.vessel_id);
                const marina = so.marina_id ? getMarina(so.marina_id) : undefined;
                const sc = statusConfig[so.status];
                const pc = priorityConfig[so.priority];
                return (
                  <tr key={so.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors cursor-pointer">
                    <td className="px-4 py-3">
                      <Link to={`/service-orders/${so.id}`} className="font-medium text-accent hover:underline">{so.service_order_number}</Link>
                    </td>
                    <td className="px-4 py-3 font-medium">{client?.full_name_or_company_name}</td>
                    <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{vessel?.boat_name}</td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{marina?.marina_name || '—'}</td>
                    <td className="px-4 py-3"><StatusBadge className={sc.className}>{sc.label}</StatusBadge></td>
                    <td className="px-4 py-3 hidden md:table-cell"><span className={pc.className}>{pc.label}</span></td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{serviceTypeLabels[so.service_type]}</td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{so.scheduled_start_at ? formatDate(so.scheduled_start_at) : '—'}</td>
                    <td className="px-4 py-3 text-right font-semibold">{formatCurrency(so.grand_total)}</td>
                  </tr>
                );
              })}
              {filtered.length === 0 && (
                <tr><td colSpan={9} className="px-4 py-12 text-center text-muted-foreground">No service orders found.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

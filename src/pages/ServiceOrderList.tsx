import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { serviceOrders, getClient, getVessel, getMarina } from '@/data/mock-data';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, Filter } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

export default function ServiceOrderList() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const { t, formatCurrency, formatDate } = useI18n();

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
      <PageHeader title={t.serviceOrders.title} description={t.serviceOrders.description}>
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
          <Plus className="h-4 w-4" /> {t.serviceOrders.newOrder}
        </Button>
      </PageHeader>

      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder={t.serviceOrders.searchPlaceholder} value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="w-full sm:w-[180px]">
            <Filter className="h-4 w-4 mr-2" />
            <SelectValue placeholder={t.common.status} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{t.serviceOrders.allStatuses}</SelectItem>
            {Object.keys(statusConfig).map(key => (
              <SelectItem key={key} value={key}>{(t.status as Record<string, string>)[key]}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/50">
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.orderNumber}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.client}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.serviceOrders.vessel}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.serviceOrders.marina}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.serviceOrders.priority}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.common.type}</th>
                <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.serviceOrders.scheduled}</th>
                <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.total}</th>
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
                    <td className="px-4 py-3"><StatusBadge className={sc.className}>{(t.status as Record<string, string>)[so.status]}</StatusBadge></td>
                    <td className="px-4 py-3 hidden md:table-cell"><span className={pc.className}>{(t.priority as Record<string, string>)[so.priority]}</span></td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{(t.serviceType as Record<string, string>)[so.service_type]}</td>
                    <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{so.scheduled_start_at ? formatDate(so.scheduled_start_at) : '—'}</td>
                    <td className="px-4 py-3 text-right font-semibold">{formatCurrency(so.grand_total)}</td>
                  </tr>
                );
              })}
              {filtered.length === 0 && (
                <tr><td colSpan={9} className="px-4 py-12 text-center text-muted-foreground">{t.common.noResults}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

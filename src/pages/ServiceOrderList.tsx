import { useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Plus, Search, Filter, ClipboardList, MoreHorizontal, FileText, Printer } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { PDFOptionsDialog } from '@/components/PDFOptionsDialog';
import { usePDFData } from '@/hooks/use-pdf';
import { generatePDF, type PDFOptions } from '@/lib/pdf-generator';

export default function ServiceOrderList() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: orders, isLoading, error } = useServiceOrders();

  const [pdfTarget, setPdfTarget] = useState<{ id: string; type: 'quote' | 'service_order' } | null>(null);
  const { data: pdfData } = usePDFData(pdfTarget?.id);

  const handleGeneratePDF = (options: PDFOptions, validity?: any) => {
    if (!pdfData || !pdfTarget) return;
    generatePDF({ ...pdfData, documentType: pdfTarget.type }, { ...options, validity });
    setPdfTarget(null);
  };

  const filtered = (orders || []).filter((so: any) => {
    const clientName = so.clients?.full_name_or_company_name || '';
    const vesselName = so.vessels?.boat_name || '';
    const matchesSearch = !search ||
      so.service_order_number.toLowerCase().includes(search.toLowerCase()) ||
      clientName.toLowerCase().includes(search.toLowerCase()) ||
      vesselName.toLowerCase().includes(search.toLowerCase());
    const matchesStatus = statusFilter === 'all' || so.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.serviceOrders.title} description={t.serviceOrders.description}>
        <Link to="/service-orders/new">
          <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
            <Plus className="h-4 w-4" /> {t.serviceOrders.newOrder}
          </Button>
        </Link>
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

      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}
        </div>
      ) : error ? (
        <div className="rounded-xl border bg-card p-8 text-center">
          <p className="text-destructive">Erro ao carregar ordens de serviço</p>
        </div>
      ) : filtered.length === 0 && !search && statusFilter === 'all' ? (
        <div className="rounded-xl border bg-card p-12 text-center space-y-3">
          <ClipboardList className="h-12 w-12 mx-auto text-muted-foreground" />
          <p className="text-muted-foreground">Nenhuma ordem de serviço cadastrada ainda.</p>
          <Link to="/service-orders/new">
            <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
              <Plus className="h-4 w-4" /> {t.serviceOrders.newOrder}
            </Button>
          </Link>
        </div>
      ) : (
        <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.orderNumber}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.client}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.serviceOrders.vessel}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.status}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.serviceOrders.priority}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.common.type}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.serviceOrders.scheduled}</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.total}</th>
                  <th className="px-4 py-3 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((so: any) => {
                  const sc = statusConfig[so.status as keyof typeof statusConfig];
                  const pc = priorityConfig[so.priority as keyof typeof priorityConfig];
                  return (
                    <tr key={so.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                      <td className="px-4 py-3">
                        <Link to={`/service-orders/${so.id}`} className="font-medium text-accent hover:underline">{so.service_order_number}</Link>
                      </td>
                      <td className="px-4 py-3 font-medium">{so.clients?.full_name_or_company_name || '—'}</td>
                      <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{so.vessels?.boat_name || '—'}</td>
                      <td className="px-4 py-3">
                        {sc && <StatusBadge className={sc.className}>{(t.status as Record<string, string>)[so.status]}</StatusBadge>}
                      </td>
                      <td className="px-4 py-3 hidden md:table-cell">
                        {pc && <span className={pc.className}>{(t.priority as Record<string, string>)[so.priority]}</span>}
                      </td>
                      <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">
                        {so.service_type ? (t.serviceType as Record<string, string>)[so.service_type] : '—'}
                      </td>
                      <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">
                        {so.scheduled_start_at ? formatDate(so.scheduled_start_at) : '—'}
                      </td>
                      <td className="px-4 py-3 text-right font-semibold">{formatCurrency(so.grand_total || 0)}</td>
                      <td className="px-4 py-3">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon" className="h-8 w-8">
                              <MoreHorizontal className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem asChild>
                              <Link to={`/service-orders/${so.id}`}>Abrir</Link>
                            </DropdownMenuItem>
                            <DropdownMenuSeparator />
                            <DropdownMenuItem
                              onClick={() => setPdfTarget({ id: so.id, type: 'quote' })}
                              className="gap-2"
                            >
                              <FileText className="h-4 w-4" />
                              Imprimir Orçamento
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => setPdfTarget({ id: so.id, type: 'service_order' })}
                              className="gap-2"
                            >
                              <Printer className="h-4 w-4" />
                              Imprimir OS
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </td>
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
      )}

      <PDFOptionsDialog
        open={!!pdfTarget}
        onOpenChange={v => { if (!v) setPdfTarget(null); }}
        documentType={pdfTarget?.type || 'quote'}
        onGenerate={handleGeneratePDF}
      />
    </div>
  );
}

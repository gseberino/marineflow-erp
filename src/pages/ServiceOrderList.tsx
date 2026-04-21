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
import { Plus, Search, Filter, ClipboardList, MoreHorizontal, FileText, Printer, MessageCircle } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { PDFOptionsDialog } from '@/components/PDFOptionsDialog';
import { usePDFData } from '@/hooks/use-pdf';
import { generatePDF, type PDFOptions } from '@/lib/pdf-generator';
import { normalizePhoneE164 } from '@/lib/masks';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { toast } from 'sonner';
import { recordWhatsAppEvent } from '@/lib/diagnostics';

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

  const handleSendWhatsApp = (so: any) => {
    if (!so?.share_token) {
      toast.error('Esta OS ainda não tem link público gerado.');
      return;
    }
    const url = `${window.location.origin}/view/${so.share_token}`;
    const phoneRaw = so.clients?.whatsapp || so.clients?.phone || '';
    const phone = normalizePhoneE164(phoneRaw);
    const clientName = so.clients?.full_name_or_company_name || '';
    const msg = `Olá${clientName ? ' ' + clientName : ''}, segue o link da Ordem de Serviço ${so.service_order_number}: ${url}`;
    const waUrl = phone
      ? `https://wa.me/${phone}?text=${encodeURIComponent(msg)}`
      : `https://wa.me/?text=${encodeURIComponent(msg)}`;
    const win = window.open(waUrl, '_blank', 'noopener,noreferrer');
    const opened = !!win;
    void writeAuditLog({
      table_name: 'service_orders',
      record_id: so.id,
      action: 'whatsapp_send' as any,
      new_value: {
        share_token: so.share_token,
        public_url: url,
        phone_raw: String(phoneRaw),
        phone_normalized: phone,
        client_name: clientName,
        opened,
        source: 'list_dropdown',
      },
      reason: opened
        ? 'Link do WhatsApp aberto (lista de OS)'
        : 'Falha ao abrir janela do WhatsApp (lista de OS)',
    });
    recordWhatsAppEvent({
      source: 'list_dropdown',
      action: 'send',
      serviceOrderId: so.id,
      serviceOrderNumber: so.service_order_number,
      shareToken: so.share_token,
      phoneRaw: String(phoneRaw),
      phoneNormalized: phone,
      opened,
      popupBlocked: !opened,
      errorMessage: !opened ? 'window.open returned null (likely popup blocker)' : undefined,
    });
    if (!opened) {
      toast.error('Não foi possível abrir o WhatsApp. Verifique o bloqueador de pop-ups.');
    }
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
                            <DropdownMenuSeparator />
                            <DropdownMenuItem
                              onClick={() => handleSendWhatsApp(so)}
                              disabled={!so.share_token}
                              className="gap-2"
                            >
                              <MessageCircle className="h-4 w-4" />
                              Enviar por WhatsApp
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

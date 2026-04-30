import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { useServiceOrders, useDuplicateServiceOrder } from '@/hooks/use-service-orders';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Plus, Search, Filter, ClipboardList, MoreHorizontal, FileText, Printer, MessageCircle, Send, CheckCircle2, XCircle, History, Copy } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { PDFOptionsDialog } from '@/components/PDFOptionsDialog';
import { WhatsAppSendHistoryDialog } from '@/components/WhatsAppSendHistoryDialog';
import { SendViaZAPIDialog, type SendViaZAPITarget } from '@/components/SendViaZAPIDialog';
import { useWhatsAppSendStatusMap } from '@/hooks/use-whatsapp-send-log';
import { usePDFData } from '@/hooks/use-pdf';
import { generatePDF, type PDFOptions } from '@/lib/pdf-generator';
import { normalizePhoneE164 } from '@/lib/masks';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { toast } from 'sonner';
import { recordWhatsAppEvent } from '@/lib/diagnostics';
import { useQueryClient } from '@tanstack/react-query';
import { FilterPresets } from '@/components/FilterPresets';

export default function ServiceOrderList() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [priorityFilter, setPriorityFilter] = useState<string>('all');
  const [periodFilter, setPeriodFilter] = useState<string>('all');
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: orders, isLoading, error } = useServiceOrders();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const duplicate = useDuplicateServiceOrder();

  const handleDuplicate = async (soId: string) => {
    try {
      const newSO = await duplicate.mutateAsync(soId);
      toast.success('OS duplicada com sucesso!');
      navigate(`/service-orders/${(newSO as any).id}`);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao duplicar OS');
    }
  };

  const [pdfTarget, setPdfTarget] = useState<{ id: string; type: 'quote' | 'service_order' } | null>(null);
  const [historyTarget, setHistoryTarget] = useState<{ id: string; number: string } | null>(null);
  const [zapiTarget, setZapiTarget] = useState<SendViaZAPITarget | null>(null);
  const { data: pdfData } = usePDFData(pdfTarget?.id);

  const orderIds = (orders || []).map((o: any) => o.id);
  const { data: sendStatusMap } = useWhatsAppSendStatusMap(orderIds);

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

  const openZapiDialog = (so: any, documentType: 'service_order' | 'quote') => {
    setZapiTarget({
      kind: 'service_order',
      serviceOrderId: so.id,
      serviceOrderNumber: so.service_order_number,
      shareToken: so.share_token,
      clientId: so.client_id || so.clients?.id || null,
      clientName: so.clients?.full_name_or_company_name || null,
      clientPhone: so.clients?.whatsapp || so.clients?.phone || null,
      documentType,
    });
  };

  const filtered = (orders || []).filter((so: any) => {
    const clientName = so.clients?.full_name_or_company_name || '';
    const vesselName = so.vessels?.boat_name || '';
    const matchesSearch = !search ||
      so.service_order_number.toLowerCase().includes(search.toLowerCase()) ||
      clientName.toLowerCase().includes(search.toLowerCase()) ||
      vesselName.toLowerCase().includes(search.toLowerCase());
    const matchesStatus = statusFilter === 'all' || so.status === statusFilter;
    const matchesPriority = priorityFilter === 'all' || so.priority === priorityFilter;
    const now = new Date();
    const soDate = new Date(so.created_at);
    const matchesPeriod = (() => {
      if (periodFilter === 'all') return true;
      if (periodFilter === 'today') return soDate.toDateString() === now.toDateString();
      if (periodFilter === 'week') {
        const weekAgo = new Date(now); weekAgo.setDate(now.getDate() - 7);
        return soDate >= weekAgo;
      }
      if (periodFilter === 'month') return soDate.getMonth() === now.getMonth() && soDate.getFullYear() === now.getFullYear();
      if (periodFilter === 'last_month') {
        const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        return soDate.getMonth() === lm.getMonth() && soDate.getFullYear() === lm.getFullYear();
      }
      return true;
    })();
    return matchesSearch && matchesStatus && matchesPriority && matchesPeriod;
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
        <Select value={priorityFilter} onValueChange={setPriorityFilter}>
          <SelectTrigger className="w-full sm:w-[140px]">
            <SelectValue placeholder="Prioridade" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todas</SelectItem>
            <SelectItem value="low">Baixa</SelectItem>
            <SelectItem value="normal">Normal</SelectItem>
            <SelectItem value="high">Alta</SelectItem>
            <SelectItem value="urgent">Urgente</SelectItem>
          </SelectContent>
        </Select>
        <Select value={periodFilter} onValueChange={setPeriodFilter}>
          <SelectTrigger className="w-full sm:w-[160px]">
            <SelectValue placeholder="Período" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Todos os períodos</SelectItem>
            <SelectItem value="today">Hoje</SelectItem>
            <SelectItem value="week">Esta semana</SelectItem>
            <SelectItem value="month">Este mês</SelectItem>
            <SelectItem value="last_month">Mês passado</SelectItem>
          </SelectContent>
        </Select>
        <FilterPresets
          filterType="service_orders"
          currentConfig={{ search, statusFilter, priorityFilter, periodFilter }}
          hasActiveFilters={statusFilter !== 'all' || priorityFilter !== 'all' || periodFilter !== 'all' || !!search}
          onApply={(c: any) => {
            setSearch(c.search ?? '');
            setStatusFilter(c.statusFilter ?? 'all');
            setPriorityFilter(c.priorityFilter ?? 'all');
            setPeriodFilter(c.periodFilter ?? 'all');
          }}
        />
        {(statusFilter !== 'all' || priorityFilter !== 'all' || periodFilter !== 'all' || search) && (
          <Button variant="ghost" size="sm" onClick={() => {
            setSearch('');
            setStatusFilter('all');
            setPriorityFilter('all');
            setPeriodFilter('all');
          }}>
            Limpar filtros
          </Button>
        )}
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
        <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
          <table className="w-full text-sm min-w-[1000px]">
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
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground hidden md:table-cell">WhatsApp</th>
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
                      <td className="px-4 py-3 font-medium max-w-[150px]">
                        <span className="block truncate">{so.clients?.full_name_or_company_name || '—'}</span>
                      </td>
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
                      <td className="px-4 py-3 hidden md:table-cell text-center">
                        {(() => {
                          const entry = sendStatusMap?.get(so.id);
                          if (!entry) {
                            return <span className="text-xs text-muted-foreground">—</span>;
                          }
                          const nv: any = entry.new_value || {};
                          const reason = nv?.zapi_response?.error || entry.reason || `HTTP ${nv?.http_status ?? '?'}`;
                          const when = new Date(entry.changed_at).toLocaleString('pt-BR');
                          return (
                            <TooltipProvider>
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <button
                                    type="button"
                                    onClick={() => setHistoryTarget({ id: so.id, number: so.service_order_number })}
                                    className="inline-flex items-center"
                                    aria-label="Ver histórico de envios Z-API"
                                  >
                                    {entry.success ? (
                                      <CheckCircle2 className="h-4 w-4 text-success" />
                                    ) : (
                                      <XCircle className="h-4 w-4 text-destructive" />
                                    )}
                                  </button>
                                </TooltipTrigger>
                                <TooltipContent side="left" className="max-w-xs">
                                  <div className="text-xs space-y-1">
                                    <div className="font-medium">
                                      {entry.success ? 'Enviado via Z-API' : 'Falha no envio Z-API'}
                                    </div>
                                    <div className="text-muted-foreground">{when}</div>
                                    {!entry.success && (
                                      <div className="text-destructive">{reason}</div>
                                    )}
                                    <div className="text-muted-foreground italic">Clique para ver histórico</div>
                                  </div>
                                </TooltipContent>
                              </Tooltip>
                            </TooltipProvider>
                          );
                        })()}
                      </td>
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
                            <DropdownMenuItem onClick={() => handleDuplicate(so.id)} className="gap-2">
                              <Copy className="h-4 w-4" />
                              Duplicar OS
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
                              Enviar via wa.me (link)
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => openZapiDialog(so, 'service_order')}
                              disabled={!so.share_token}
                              className="gap-2"
                            >
                              <Send className="h-4 w-4" />
                              Enviar OS via Z-API…
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => openZapiDialog(so, 'quote')}
                              disabled={!so.share_token}
                              className="gap-2"
                            >
                              <Send className="h-4 w-4" />
                              Enviar Orçamento via Z-API…
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => setHistoryTarget({ id: so.id, number: so.service_order_number })}
                              className="gap-2"
                            >
                              <History className="h-4 w-4" />
                              Histórico de envios Z-API
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </td>
                    </tr>
                  );
                })}
                {filtered.length === 0 && (
                  <tr><td colSpan={10} className="px-4 py-12 text-center text-muted-foreground">{t.common.noResults}</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}

      <PDFOptionsDialog
        open={!!pdfTarget}
        onOpenChange={v => { if (!v) setPdfTarget(null); }}
        documentType={pdfTarget?.type || 'quote'}
        hasProductImages={pdfData?.parts?.some((p: any) => !!p.image_url) ?? false}
        onGenerate={handleGeneratePDF}
      />

      <WhatsAppSendHistoryDialog
        open={!!historyTarget}
        onOpenChange={v => { if (!v) setHistoryTarget(null); }}
        serviceOrderId={historyTarget?.id || null}
        serviceOrderNumber={historyTarget?.number}
      />

      <SendViaZAPIDialog
        open={!!zapiTarget}
        onOpenChange={v => { if (!v) setZapiTarget(null); }}
        target={zapiTarget}
      />
    </div>
  );
}

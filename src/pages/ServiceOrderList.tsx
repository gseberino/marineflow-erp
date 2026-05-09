import { useMemo, useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { useServiceOrders, useDuplicateServiceOrder } from '@/hooks/use-service-orders';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Plus, ClipboardList, MoreHorizontal, FileText, Printer, MessageCircle, Send, CheckCircle2, XCircle, History, Copy, Download, ChevronLeft, ChevronRight, ArrowUpDown, ArrowUp, ArrowDown } from 'lucide-react';
import { exportToCSV } from '@/lib/export';
import { supabase } from '@/integrations/supabase/client';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { MultiFilterBar } from '@/components/MultiFilterBar';
import { useMultiFilter } from '@/hooks/use-multi-filter';
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
import { useTechnicians } from '@/hooks/use-agenda';

type SortDir = 'asc' | 'desc';
const PAGE_SIZE = 20;
const PRIORITY_WEIGHT: Record<string, number> = { urgent: 4, high: 3, normal: 2, low: 1 };

export default function ServiceOrderList() {
  const [page, setPage] = useState(1);
  const { filters, toggle, setField, clearAll, activeCount } = useMultiFilter({
    search: '',
    status: [] as string[],
    priority: [] as string[],
    technician: [] as string[],
    dateFrom: '',
    dateTo: '',
  });
  const [sortKey, setSortKey] = useState('created_at');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: orders, isLoading, error } = useServiceOrders();
  const { data: technicians = [] } = useTechnicians();
  const [searchParams] = useSearchParams();

  // Apply ?status= from Dashboard navigation links
  useEffect(() => {
    const statusParam = searchParams.get('status');
    if (statusParam) {
      setField('status', [statusParam]);
      setPage(1);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
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
    const clientName = so.clients?.name || '';
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
      clientName: so.clients?.name || null,
      clientPhone: so.clients?.whatsapp || so.clients?.phone || null,
      documentType,
    });
  };

  const handleSort = (key: string) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
    setPage(1);
  };

  function SortIcon({ col }: { col: string }) {
    if (sortKey !== col) return <ArrowUpDown className="h-3 w-3 ml-1 opacity-40 shrink-0" />;
    return sortDir === 'asc' ? <ArrowUp className="h-3 w-3 ml-1 shrink-0" /> : <ArrowDown className="h-3 w-3 ml-1 shrink-0" />;
  }

  const getSortValue = (so: any, key: string): any => {
    if (key === 'client_name') return so.clients?.name ?? '';
    if (key === 'vessel_name') return so.vessels?.name ?? '';
    if (key === 'priority') return PRIORITY_WEIGHT[so.priority] ?? 0;
    return so[key] ?? '';
  };

  const filtered = useMemo(() => {
    const { search, status, priority, technician, dateFrom, dateTo } = filters as {
      search: string; status: string[]; priority: string[]; technician: string[]; dateFrom: string; dateTo: string;
    };
    const list = (orders || []).filter((so: any) => {
      const clientName = so.clients?.name || '';
      const vesselName = so.vessels?.name || '';
      if (search && !(
        so.service_order_number.toLowerCase().includes(search.toLowerCase()) ||
        clientName.toLowerCase().includes(search.toLowerCase()) ||
        vesselName.toLowerCase().includes(search.toLowerCase())
      )) return false;
      if (status.length && !status.includes(so.status)) return false;
      if (priority.length && !priority.includes(so.priority)) return false;
      if (technician.length) {
        const soTechs: string[] = (so.service_order_technicians || []).map((t: any) => t.user_id);
        if (!technician.some(tid => soTechs.includes(tid))) return false;
      }
      if (dateFrom || dateTo) {
        const soDate = so.created_at ? so.created_at.split('T')[0] : '';
        if (dateFrom && soDate < dateFrom) return false;
        if (dateTo && soDate > dateTo) return false;
      }
      return true;
    });
    return [...list].sort((a, b) => {
      let av = getSortValue(a, sortKey);
      let bv = getSortValue(b, sortKey);
      if (typeof av === 'string') av = av.toLowerCase();
      if (typeof bv === 'string') bv = bv.toLowerCase();
      if (av < bv) return sortDir === 'asc' ? -1 : 1;
      if (av > bv) return sortDir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [orders, filters, sortKey, sortDir]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.serviceOrders.title} description={t.serviceOrders.description}>
        <Link to="/service-orders/new">
          <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
            <Plus className="h-4 w-4" /> {t.serviceOrders.newOrder}
          </Button>
        </Link>
      </PageHeader>

      <MultiFilterBar
        search={filters.search as string}
        onSearchChange={v => { setField('search', v); setPage(1); }}
        searchPlaceholder={t.serviceOrders.searchPlaceholder}
        filters={filters}
        activeCount={activeCount}
        onToggle={(f, v) => { toggle(f, v); setPage(1); }}
        onSetField={(f, v) => { setField(f, v); setPage(1); }}
        onClearAll={() => { clearAll(); setPage(1); }}
        groups={[
          {
            type: 'multi',
            field: 'status',
            label: 'Status',
            options: Object.keys(statusConfig).map(key => ({
              value: key,
              label: (t.status as Record<string, string>)[key] ?? key,
            })),
          },
          {
            type: 'multi',
            field: 'priority',
            label: 'Prioridade',
            options: [
              { value: 'low', label: 'Baixa' },
              { value: 'normal', label: 'Normal' },
              { value: 'high', label: 'Alta' },
              { value: 'urgent', label: 'Urgente' },
            ],
          },
          {
            type: 'multi',
            field: 'technician',
            label: 'Técnico',
            options: technicians.map((t: any) => ({ value: t.id, label: t.full_name })),
          },
          { type: 'daterange', fromField: 'dateFrom', toField: 'dateTo', label: 'Período' },
        ]}
        extra={
          <Button
            variant="outline"
            size="sm"
            onClick={() =>
              exportToCSV(filtered, 'ordens_servico', [
                { key: 'service_order_number', label: 'Número' },
                { key: 'status', label: 'Status' },
                { key: 'clients', label: 'Cliente', format: (v) => v?.name || '' },
                { key: 'vessels', label: 'Embarcação', format: (v) => v?.name || '' },
                { key: 'grand_total', label: 'Valor Total', format: (v) => Number(v || 0).toFixed(2).replace('.', ',') },
                { key: 'created_at', label: 'Data Criação', format: (v) => v ? new Date(v).toLocaleDateString('pt-BR') : '' },
                { key: 'scheduled_start_at', label: 'Agendado Para', format: (v) => v ? new Date(v).toLocaleDateString('pt-BR') : '' },
              ])
            }
            className="gap-1"
          >
            <Download className="h-4 w-4" />
            Exportar CSV
          </Button>
        }
      />

      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}
        </div>
      ) : error ? (
        <div className="rounded-xl border bg-card p-8 text-center">
          <p className="text-destructive">Erro ao carregar ordens de serviço</p>
        </div>
      ) : filtered.length === 0 && activeCount === 0 ? (
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
        <>
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[1000px]">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('service_order_number')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.orderNumber}<SortIcon col="service_order_number" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('client_name')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.client}<SortIcon col="client_name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                    <button onClick={() => handleSort('vessel_name')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.vessel}<SortIcon col="vessel_name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('status')} className="flex items-center hover:text-foreground transition-colors">
                      {t.common.status}<SortIcon col="status" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                    <button onClick={() => handleSort('priority')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.priority}<SortIcon col="priority" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.common.type}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">
                    <button onClick={() => handleSort('scheduled_start_at')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.scheduled}<SortIcon col="scheduled_start_at" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">
                    <button onClick={() => handleSort('grand_total')} className="flex items-center justify-end w-full hover:text-foreground transition-colors">
                      {t.common.total}<SortIcon col="grand_total" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-center font-medium text-muted-foreground hidden md:table-cell">WhatsApp</th>
                  <th className="px-4 py-3 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {paginated.map((so: any) => {
                  const sc = statusConfig[so.status as keyof typeof statusConfig];
                  const pc = priorityConfig[so.priority as keyof typeof priorityConfig];
                  return (
                    <tr key={so.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                      <td className="px-4 py-3">
                        <Link to={`/service-orders/${so.id}`} className="font-medium text-accent hover:underline">{so.service_order_number}</Link>
                      </td>
                      <td className="px-4 py-3 font-medium max-w-[150px]">
                        <span className="block truncate">{so.clients?.name || '—'}</span>
                      </td>
                      <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">{so.vessels?.name || '—'}</td>
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

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} ordens · Página {page} de {totalPages}
              </span>
              <div className="flex gap-2">
                <Button variant="outline" size="sm" onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}>
                  <ChevronLeft className="h-4 w-4" /> Anterior
                </Button>
                <Button variant="outline" size="sm" onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}>
                  Próxima <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            </div>
          )}
        </>
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

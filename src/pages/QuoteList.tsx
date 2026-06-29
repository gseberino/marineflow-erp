import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { QuoteStatusQuickChange } from '@/components/QuoteStatusQuickChange';
import { StockConfirmationDialog } from '@/components/StockConfirmationDialog';
import { useI18n } from '@/i18n';
import { useServiceOrders, useDuplicateServiceOrder, useUpdateServiceOrderStatus } from '@/hooks/use-service-orders';
import { priorityConfig } from '@/lib/constants';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Plus, FileText, MoreHorizontal, Printer, MessageCircle, Send,
  Copy, Download, ChevronLeft, ChevronRight, ArrowUpDown, ArrowUp,
  ArrowDown, Loader2, ArrowRightCircle, History, Wrench,
} from 'lucide-react';
import { exportToCSV } from '@/lib/export';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { MultiFilterBar } from '@/components/MultiFilterBar';
import { useMultiFilter } from '@/hooks/use-multi-filter';
import { PDFOptionsDialog } from '@/components/PDFOptionsDialog';
import { WhatsAppSendHistoryDialog } from '@/components/WhatsAppSendHistoryDialog';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from '@/components/SendViaWhatsAppDialog';
import { usePDFData, fetchPDFData } from '@/hooks/use-pdf';
import { generatePDF, downloadPDF, DEFAULT_PDF_OPTIONS, type PDFOptions } from '@/lib/pdf-generator';
import type { PDFAction } from '@/components/PDFOptionsDialog';
import { normalizePhoneE164 } from '@/lib/masks';
import { toast } from 'sonner';

type SortDir = 'asc' | 'desc';
const PAGE_SIZE = 20;

export default function QuoteList() {
  const { t, formatCurrency, formatDate } = useI18n();
  const navigate = useNavigate();

  const { data: orders, isLoading, error } = useServiceOrders();
  const duplicate = useDuplicateServiceOrder();
  const convertToOS = useUpdateServiceOrderStatus();

  const [page, setPage] = useState(1);
  const [sortKey, setSortKey] = useState('created_at');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [stockConfirm, setStockConfirm] = useState<{ id: string; number: string } | null>(null);
  const [pdfTarget, setPdfTarget] = useState<{ id: string; type: 'quote' | 'service_order' } | null>(null);
  const [historyTarget, setHistoryTarget] = useState<{ id: string; number: string } | null>(null);
  const [whatsAppTarget, setWhatsAppTarget] = useState<SendViaWhatsAppTarget | null>(null);

  const { filters, toggle, setField, clearAll, activeCount } = useMultiFilter({
    search: '',
    quoteStatus: [] as string[],
    priority: [] as string[],
    dateFrom: '',
    dateTo: '',
  });

  const { data: pdfData } = usePDFData(pdfTarget?.id);

  // ── Sorting ────────────────────────────────────────────────────────────────
  const handleSort = (key: string) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
    setPage(1);
  };

  function SortIcon({ col }: { col: string }) {
    if (sortKey !== col) return <ArrowUpDown className="h-3 w-3 ml-1 opacity-40 shrink-0" />;
    return sortDir === 'asc' ? <ArrowUp className="h-3 w-3 ml-1 shrink-0" /> : <ArrowDown className="h-3 w-3 ml-1 shrink-0" />;
  }

  // ── Filtered & sorted quotes ────────────────────────────────────────────────
  const filtered = useMemo(() => {
    const { search, quoteStatus, priority, dateFrom, dateTo } = filters as {
      search: string; quoteStatus: string[]; priority: string[]; dateFrom: string; dateTo: string;
    };
    const list = (orders || []).filter((so: any) => {
      if (so.status !== 'draft') return false;
      const clientName = so.clients?.name || '';
      const vesselName = so.vessels?.name || '';
      if (search && !(
        so.service_order_number.toLowerCase().includes(search.toLowerCase()) ||
        clientName.toLowerCase().includes(search.toLowerCase()) ||
        vesselName.toLowerCase().includes(search.toLowerCase())
      )) return false;
      if (quoteStatus.length && !quoteStatus.includes(so.quote_status ?? 'draft')) return false;
      if (priority.length && !priority.includes(so.priority)) return false;
      if (dateFrom || dateTo) {
        const soDate = so.created_at ? so.created_at.split('T')[0] : '';
        if (dateFrom && soDate < dateFrom) return false;
        if (dateTo && soDate > dateTo) return false;
      }
      return true;
    });
    return [...list].sort((a: any, b: any) => {
      let av: any = a[sortKey] ?? '';
      let bv: any = b[sortKey] ?? '';
      if (sortKey === 'client_name') { av = a.clients?.name ?? ''; bv = b.clients?.name ?? ''; }
      if (sortKey === 'vessel_name') { av = a.vessels?.name ?? ''; bv = b.vessels?.name ?? ''; }
      if (typeof av === 'string') av = av.toLowerCase();
      if (typeof bv === 'string') bv = bv.toLowerCase();
      if (av < bv) return sortDir === 'asc' ? -1 : 1;
      if (av > bv) return sortDir === 'asc' ? 1 : -1;
      return 0;
    });
  }, [orders, filters, sortKey, sortDir]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const totalCount = (orders || []).filter((o: any) => o.status === 'draft').length;
  const osCount = (orders || []).filter((o: any) => o.status !== 'draft').length;

  // ── Actions ────────────────────────────────────────────────────────────────
  const handleConvertToOS = async (so: any) => {
    try {
      await convertToOS.mutateAsync({ id: so.id, status: 'approved' });
      toast.success(`${so.service_order_number} convertido em OS`);
      setStockConfirm({ id: so.id, number: so.service_order_number });
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao converter em OS');
    }
  };

  const handleDuplicate = async (soId: string) => {
    try {
      const newSO = await duplicate.mutateAsync({ sourceId: soId, mode: 'quote' });
      toast.success('Orçamento duplicado!');
      navigate(`/service-orders/${(newSO as any).id}`);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao duplicar');
    }
  };

  const handleGeneratePDF = (action: PDFAction, options: PDFOptions, validity?: any, dueDate?: string) => {
    if (!pdfData || !pdfTarget) return;
    if (action === 'download') {
      downloadPDF({ ...pdfData, documentType: pdfTarget.type }, { ...options, validity, dueDate })
        .then(() => toast.success('PDF baixado com sucesso'))
        .catch(() => toast.error('Erro ao gerar o PDF'));
    } else {
      generatePDF({ ...pdfData, documentType: pdfTarget.type }, { ...options, validity, dueDate })
        .then(doc => { doc.output('dataurlnewwindow'); })
        .catch(() => toast.error('Erro ao gerar o PDF'));
    }
    setPdfTarget(null);
  };

  const handleDirectDownload = async (soId: string, type: 'quote' | 'service_order') => {
    try {
      const data = await fetchPDFData(soId);
      if (!data) throw new Error('Dados não encontrados');
      await downloadPDF({ ...data, documentType: type }, DEFAULT_PDF_OPTIONS);
      toast.success('PDF baixado');
    } catch {
      toast.error('Erro ao gerar o PDF');
    }
  };

  const handleSendWhatsApp = (so: any) => {
    if (!so.share_token) { toast.error('Este orçamento ainda não tem link público gerado.'); return; }
    const url = `${window.location.origin}/public/service-order/${so.share_token}`;
    const clientName = so.clients?.name;
    const phone = normalizePhoneE164(so.clients?.whatsapp || so.clients?.phone || '');
    const msg = `Olá${clientName ? ' ' + clientName : ''}, segue o link do seu Orçamento ${so.service_order_number}: ${url}`;
    const waUrl = phone
      ? `https://wa.me/${phone}?text=${encodeURIComponent(msg)}`
      : `https://wa.me/?text=${encodeURIComponent(msg)}`;
    window.open(waUrl, '_blank', 'noopener,noreferrer');
  };

  const openWhatsAppDialog = (so: any, documentType: 'service_order' | 'quote') => {
    if (!so.share_token) { toast.error('Este orçamento ainda não tem link público gerado.'); return; }
    setWhatsAppTarget({
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

  // ── Render ─────────────────────────────────────────────────────────────────
  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title="Orçamentos" description="Gerencie seus orçamentos e propostas comerciais">
        <Link to="/service-orders/new">
          <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
            <Plus className="h-4 w-4" /> Novo Orçamento
          </Button>
        </Link>
      </PageHeader>

      {/* Tab navigation — links between the two list pages */}
      <div className="flex gap-1 border-b">
        <span className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 border-amber-500 text-amber-700">
          <FileText className="h-4 w-4" />
          Orçamentos
          <span className="rounded-full px-1.5 py-0.5 text-xs font-bold bg-amber-100 text-amber-700">
            {totalCount}
          </span>
        </span>
        <Link
          to="/service-orders"
          className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 border-transparent text-muted-foreground hover:text-foreground transition-colors"
        >
          <Wrench className="h-4 w-4" />
          Ordens de Serviço
          <span className="rounded-full px-1.5 py-0.5 text-xs font-bold bg-muted text-muted-foreground">
            {osCount}
          </span>
        </Link>
      </div>

      {/* Filter bar */}
      <MultiFilterBar
        search={filters.search as string}
        onSearchChange={v => { setField('search', v); setPage(1); }}
        searchPlaceholder="Buscar por número, cliente ou embarcação…"
        filters={filters}
        activeCount={activeCount}
        onToggle={(f, v) => { toggle(f, v); setPage(1); }}
        onSetField={(f, v) => { setField(f, v); setPage(1); }}
        onClearAll={() => { clearAll(); setPage(1); }}
        presetType="quotes"
        groups={[
          {
            type: 'multi',
            field: 'quoteStatus',
            label: 'Status do orçamento',
            options: [
              { value: 'draft',             label: 'Em elaboração' },
              { value: 'sent',              label: 'Enviado' },
              { value: 'awaiting_approval', label: 'Aguard. aprovação' },
              { value: 'approved',          label: 'Aprovado' },
              { value: 'awaiting_deposit',  label: 'Aguard. sinal' },
              { value: 'rejected',          label: 'Reprovado' },
            ],
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
          { type: 'daterange', fromField: 'dateFrom', toField: 'dateTo', label: 'Período' },
        ]}
        extra={
          <Button
            variant="outline"
            size="sm"
            onClick={() =>
              exportToCSV(filtered, 'orcamentos', [
                { key: 'service_order_number', label: 'Número' },
                { key: 'quote_status', label: 'Status' },
                { key: 'clients', label: 'Cliente', format: (v: any) => v?.name || '' },
                { key: 'vessels', label: 'Embarcação', format: (v: any) => v?.name || '' },
                { key: 'grand_total', label: 'Valor Total', format: (v: any) => Number(v || 0).toFixed(2).replace('.', ',') },
                { key: 'created_at', label: 'Data Criação', format: (v: any) => v ? new Date(v).toLocaleDateString('pt-BR') : '' },
              ])
            }
            className="gap-1"
          >
            <Download className="h-4 w-4" />
            Exportar CSV
          </Button>
        }
      />

      {/* Content */}
      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}
        </div>
      ) : error ? (
        <div className="rounded-xl border bg-card p-8 text-center">
          <p className="text-destructive">Erro ao carregar orçamentos</p>
        </div>
      ) : filtered.length === 0 && activeCount === 0 ? (
        <div className="rounded-xl border bg-card p-12 text-center space-y-3">
          <FileText className="h-12 w-12 mx-auto text-muted-foreground" />
          <p className="text-muted-foreground">Nenhum orçamento cadastrado ainda.</p>
          <Link to="/service-orders/new">
            <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
              <Plus className="h-4 w-4" /> Novo Orçamento
            </Button>
          </Link>
        </div>
      ) : (
        <>
          <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[900px]">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('service_order_number')} className="flex items-center hover:text-foreground transition-colors">
                      Número <SortIcon col="service_order_number" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    <button onClick={() => handleSort('client_name')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.client} <SortIcon col="client_name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                    <button onClick={() => handleSort('vessel_name')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.vessel} <SortIcon col="vessel_name" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">
                    Status
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">
                    <button onClick={() => handleSort('priority')} className="flex items-center hover:text-foreground transition-colors">
                      {t.serviceOrders.priority} <SortIcon col="priority" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">
                    <button onClick={() => handleSort('created_at')} className="flex items-center hover:text-foreground transition-colors">
                      Criado em <SortIcon col="created_at" />
                    </button>
                  </th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">
                    <button onClick={() => handleSort('grand_total')} className="flex items-center justify-end w-full hover:text-foreground transition-colors">
                      {t.common.total} <SortIcon col="grand_total" />
                    </button>
                  </th>
                  <th className="px-4 py-3 w-10" />
                </tr>
              </thead>
              <tbody>
                {paginated.map((so: any) => {
                  const pc = priorityConfig[so.priority as keyof typeof priorityConfig];
                  return (
                    <tr key={so.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                      <td className="px-4 py-3">
                        <Link to={`/service-orders/${so.id}`} className="font-medium text-accent hover:underline">
                          {so.service_order_number}
                        </Link>
                      </td>
                      <td className="px-4 py-3 font-medium max-w-[150px]">
                        <span className="block truncate">{so.clients?.name || '—'}</span>
                      </td>
                      <td className="px-4 py-3 hidden md:table-cell text-muted-foreground">
                        {so.vessels?.name || '—'}
                      </td>
                      <td className="px-4 py-3">
                        <QuoteStatusQuickChange
                          orderId={so.id}
                          currentQuoteStatus={so.quote_status ?? 'draft'}
                          serviceOrderNumber={so.service_order_number}
                          grandTotal={so.grand_total || 0}
                          laborCost={so.labor_cost_total || 0}
                          partsCost={so.parts_cost_total || 0}
                        />
                      </td>
                      <td className="px-4 py-3 hidden md:table-cell">
                        {pc && <span className={pc.className}>{(t.priority as Record<string, string>)[so.priority]}</span>}
                      </td>
                      <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">
                        {so.created_at ? formatDate(so.created_at) : '—'}
                      </td>
                      <td className="px-4 py-3 text-right font-semibold">
                        {formatCurrency(so.grand_total || 0)}
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
                            <DropdownMenuSeparator />
                            <DropdownMenuItem
                              onClick={() => handleConvertToOS(so)}
                              className="gap-2 text-blue-700 font-medium focus:text-blue-700 focus:bg-blue-50"
                            >
                              <ArrowRightCircle className="h-4 w-4" />
                              Converter em OS
                            </DropdownMenuItem>
                            <DropdownMenuSeparator />
                            <DropdownMenuItem onClick={() => handleDuplicate(so.id)} className="gap-2">
                              <Copy className="h-4 w-4" />
                              Duplicar orçamento
                            </DropdownMenuItem>
                            <DropdownMenuSeparator />
                            <DropdownMenuItem onClick={() => setPdfTarget({ id: so.id, type: 'quote' })} className="gap-2">
                              <FileText className="h-4 w-4" />
                              Imprimir Orçamento
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => setPdfTarget({ id: so.id, type: 'service_order' })} className="gap-2">
                              <Printer className="h-4 w-4" />
                              Imprimir OS
                            </DropdownMenuItem>
                            <DropdownMenuSeparator />
                            <DropdownMenuItem onClick={() => handleDirectDownload(so.id, 'quote')} className="gap-2">
                              <Download className="h-4 w-4" />
                              Baixar Orçamento
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
                              onClick={() => openWhatsAppDialog(so, 'quote')}
                              disabled={!so.share_token}
                              className="gap-2"
                            >
                              <Send className="h-4 w-4" />
                              Enviar Orçamento via WhatsApp…
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => setHistoryTarget({ id: so.id, number: so.service_order_number })}
                              className="gap-2"
                            >
                              <History className="h-4 w-4" />
                              Histórico de envios WhatsApp
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </td>
                    </tr>
                  );
                })}
                {filtered.length === 0 && (
                  <tr>
                    <td colSpan={8} className="px-4 py-12 text-center text-muted-foreground">
                      {t.common.noResults}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} orçamentos · Página {page} de {totalPages}
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

      {/* Dialogs */}
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
      <SendViaWhatsAppDialog
        open={!!whatsAppTarget}
        onOpenChange={v => { if (!v) setWhatsAppTarget(null); }}
        target={whatsAppTarget}
      />
      {stockConfirm && (
        <StockConfirmationDialog
          open={!!stockConfirm}
          onOpenChange={v => { if (!v) setStockConfirm(null); }}
          serviceOrderId={stockConfirm.id}
          serviceOrderNumber={stockConfirm.number}
        />
      )}
    </div>
  );
}

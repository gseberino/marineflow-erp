import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import {
  ArrowRightCircle, Copy, Download, ExternalLink, FileDown, FileText, History, Loader2,
  MessageCircle, MoreHorizontal, Plus, Printer, Receipt, Send, Wrench,
} from 'lucide-react';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import { useI18n } from '@/i18n';
import { supabase } from '@/integrations/supabase/client';
import { useServiceOrders, useDuplicateServiceOrder, useUpdateServiceOrderStatus } from '@/hooks/use-service-orders';
import { useWhatsAppSendStatusMap } from '@/hooks/use-whatsapp-send-log';
import { useMultiFilter } from '@/hooks/use-multi-filter';
import { usePDFData, fetchPDFData } from '@/hooks/use-pdf';
import { generatePDF, downloadPDF, DEFAULT_PDF_OPTIONS, type PDFOptions } from '@/lib/pdf-generator';
import { normalizePhoneE164 } from '@/lib/masks';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { recordWhatsAppEvent } from '@/lib/diagnostics';
import { statusConfig } from '@/lib/constants';
import type { ServiceOrderStatus } from '@/types/domain';
import { useTechnicians } from '@/hooks/use-agenda';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator,
  DropdownMenuSub, DropdownMenuSubContent, DropdownMenuSubTrigger, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { MultiFilterBar } from '@/components/MultiFilterBar';
import { StatusQuickChange } from '@/components/StatusQuickChange';
import { QuoteStatusQuickChange } from '@/components/QuoteStatusQuickChange';
import { PurchaseNeedsDialog } from '@/components/purchasing/PurchaseNeedsDialog';
import { PDFOptionsDialog, type PDFAction } from '@/components/PDFOptionsDialog';
import { WhatsAppSendHistoryDialog } from '@/components/WhatsAppSendHistoryDialog';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from '@/components/SendViaWhatsAppDialog';
import { exportToCSV } from '@/lib/export';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { DataTable, type DataColumn, type SortState } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import { priorityTone, serviceOrderStatusTone, quoteStatusTone, paymentTone } from '@/v2/status-map';
import '@/v2/tokens.css';

/* ─────────────────────────────────────────────────────────────────────────────
   Fase 1 · Telas gêmeas v2 — Ordens de Serviço + Orçamentos
   Paridade total com ServiceOrderList/QuoteList v1, rearranjada em 3 níveis:
   nível 1 = WhatsApp + Abrir no hover; nível 2 = menu curto; nível 3 = submenus
   Documentos/WhatsApp. Desktop = DataTable (orçamento de colunas, Princípio 0);
   mobile = EntityCard + FAB. Rotas /v2/* — as telas v1 permanecem intactas.
   Correção embutida: o link wa.me de orçamentos usava /public/service-order/
   (rota inexistente); aqui ambos usam /view/:token, a rota real.
──────────────────────────────────────────────────────────────────────────── */

type Mode = 'orders' | 'quotes';
const PAGE_SIZE = 20;
const PRIORITY_WEIGHT: Record<string, number> = { urgent: 4, high: 3, normal: 2, low: 1 };

type SORow = {
  id: string;
  service_order_number: string;
  status: string;
  quote_status?: string | null;
  priority?: string | null;
  service_type?: string | null;
  grand_total?: number | null;
  labor_cost_total?: number | null;
  parts_cost_total?: number | null;
  scheduled_start_at?: string | null;
  created_at?: string | null;
  payment_status?: string | null;
  share_token?: string | null;
  client_id?: string | null;
  customer_po_number?: string | null;
  customer_buyer_name?: string | null;
  requested_by_name?: string | null;
  clients?: { id?: string; name?: string; phone?: string | null; whatsapp?: string | null } | null;
  vessels?: { name?: string } | null;
  service_order_technicians?: { user_id: string }[] | null;
};

const QUOTE_STATUS_LABELS: Record<string, string> = {
  draft: 'Em elaboração',
  sent: 'Enviado',
  awaiting_approval: 'Aguard. aprovação',
  approved: 'Aprovado',
  awaiting_deposit: 'Aguard. sinal',
  rejected: 'Reprovado',
};

const PAYMENT_LABELS: Record<string, string> = {
  unpaid: 'Em aberto',
  pending: 'Pendente',
  partial: 'Parcial',
  paid: 'Pago',
  overdue: 'Vencido',
  refunded: 'Reembolsado',
};

type QuickView = { id: string; label: string; match: (so: SORow) => boolean };

export default function OrdersListV2({ mode }: { mode: Mode }) {
  const isOrders = mode === 'orders';
  const { t, formatCurrency, formatDate } = useI18n();
  const statusLabels = t.status as Record<string, string>;
  const priorityLabels = t.priority as Record<string, string>;
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const { data, isLoading, error } = useServiceOrders();
  const orders = (data ?? []) as unknown as SORow[];
  const { data: technicians = [] } = useTechnicians();
  const duplicate = useDuplicateServiceOrder();
  const convertToOS = useUpdateServiceOrderStatus();

  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortState>({ key: 'created_at', dir: 'desc' });
  const [view, setView] = useState('all');
  const [pdfTarget, setPdfTarget] = useState<{ id: string; type: 'quote' | 'service_order' } | null>(null);
  const [historyTarget, setHistoryTarget] = useState<{ id: string; number: string } | null>(null);
  const [whatsAppTarget, setWhatsAppTarget] = useState<SendViaWhatsAppTarget | null>(null);
  const [duplicateDialogId, setDuplicateDialogId] = useState<string | null>(null);
  const [stockConfirm, setStockConfirm] = useState<{ id: string; number: string } | null>(null);
  const [bulkDownloading, setBulkDownloading] = useState(false);
  const pdfGenCountRef = useRef(0);
  const { data: pdfData } = usePDFData(pdfTarget?.id);

  const { filters, toggle, setField, clearAll, activeCount } = useMultiFilter(
    isOrders
      ? { search: '', status: [] as string[], priority: [] as string[], technician: [] as string[], dateFrom: '', dateTo: '' }
      : { search: '', quoteStatus: [] as string[], priority: [] as string[], dateFrom: '', dateTo: '' },
  );

  // ?status= vindo do Dashboard continua funcionando (paridade v1)
  useEffect(() => {
    const statusParam = searchParams.get('status');
    if (statusParam && isOrders) {
      setField('status', [statusParam]);
      setPage(1);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => () => {
    if (pdfGenCountRef.current > 0) document.body.style.overflow = '';
  }, []);

  const belongsToMode = (so: SORow) => (isOrders ? so.status !== 'draft' : so.status === 'draft');

  const quickViews: QuickView[] = isOrders
    ? [
        { id: 'all', label: 'Todas', match: () => true },
        { id: 'urgent', label: 'Urgentes', match: (so) => so.priority === 'urgent' || so.priority === 'high' },
        {
          id: 'late',
          label: 'Atrasadas',
          match: (so) =>
            !!so.scheduled_start_at &&
            new Date(so.scheduled_start_at) < new Date() &&
            !['completed', 'invoiced', 'cancelled'].includes(so.status),
        },
        { id: 'unpaid', label: 'Não pagas', match: (so) => so.payment_status === 'unpaid' || so.payment_status === 'partial' },
      ]
    : [
        { id: 'all', label: 'Todos', match: () => true },
        { id: 'waiting', label: 'Aguardando cliente', match: (so) => ['sent', 'awaiting_approval', 'awaiting_deposit'].includes(so.quote_status ?? 'draft') },
        { id: 'approved', label: 'Aprovados', match: (so) => so.quote_status === 'approved' },
      ];

  const getSortValue = (so: SORow, key: string): string | number => {
    if (key === 'client') return (so.clients?.name ?? '').toLowerCase();
    if (key === 'priority') return PRIORITY_WEIGHT[so.priority ?? ''] ?? 0;
    if (key === 'total') return so.grand_total ?? 0;
    if (key === 'scheduled') return so.scheduled_start_at ?? '';
    if (key === 'created_at') return so.created_at ?? '';
    if (key === 'number') return so.service_order_number;
    const v = (so as Record<string, unknown>)[key];
    return typeof v === 'number' ? v : String(v ?? '').toLowerCase();
  };

  const filtered = useMemo(() => {
    const f = filters as Record<string, string | string[]>;
    const search = String(f.search || '').toLowerCase();
    const activeView = quickViews.find((v) => v.id === view) ?? quickViews[0];
    const list = orders.filter((so) => {
      if (!belongsToMode(so)) return false;
      if (!activeView.match(so)) return false;
      if (search) {
        const hay = `${so.service_order_number} ${so.clients?.name ?? ''} ${so.vessels?.name ?? ''}`.toLowerCase();
        if (!hay.includes(search)) return false;
      }
      const statusF = (isOrders ? f.status : f.quoteStatus) as string[] | undefined;
      if (statusF?.length) {
        const value = isOrders ? so.status : (so.quote_status ?? 'draft');
        if (!statusF.includes(value)) return false;
      }
      const priorityF = f.priority as string[] | undefined;
      if (priorityF?.length && !priorityF.includes(so.priority ?? '')) return false;
      if (isOrders) {
        const techF = f.technician as string[] | undefined;
        if (techF?.length) {
          const soTechs = (so.service_order_technicians ?? []).map((x) => x.user_id);
          if (!techF.some((id) => soTechs.includes(id))) return false;
        }
      }
      const dateFrom = String(f.dateFrom || '');
      const dateTo = String(f.dateTo || '');
      if (dateFrom || dateTo) {
        const soDate = so.created_at ? so.created_at.split('T')[0] : '';
        if (dateFrom && soDate < dateFrom) return false;
        if (dateTo && soDate > dateTo) return false;
      }
      return true;
    });
    return [...list].sort((a, b) => {
      const av = getSortValue(a, sort.key);
      const bv = getSortValue(b, sort.key);
      if (av < bv) return sort.dir === 'asc' ? -1 : 1;
      if (av > bv) return sort.dir === 'asc' ? 1 : -1;
      return 0;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [orders, filters, sort, view, mode]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const quoteCount = orders.filter((o) => o.status === 'draft').length;
  const orderCount = orders.filter((o) => o.status !== 'draft').length;

  const orderIds = useMemo(() => (isOrders ? filtered.map((o) => o.id) : []), [filtered, isOrders]);
  const { data: sendStatusMap } = useWhatsAppSendStatusMap(orderIds);

  const handleSort = (key: string) => {
    setSort((prev) => (prev.key === key ? { key, dir: prev.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' }));
    setPage(1);
  };

  // ── Ações (paridade v1, mesmos handlers) ─────────────────────────────────
  const handleInvoice = async (so: SORow) => {
    try {
      const { data: parts, error: err } = await supabase
        .from('service_order_parts')
        .select('product_id, quantity, unit_sale_snapshot')
        .eq('service_order_id', so.id);
      if (err) throw err;
      const items = (parts ?? [])
        .filter((p) => p.product_id)
        .map((p) => ({ productId: p.product_id, quantity: Number(p.quantity) || 0, unitPrice: Number(p.unit_sale_snapshot) || 0 }));
      if (!items.length) {
        toast.error(isOrders
          ? 'Esta OS não tem produtos para faturar (só serviços/mão de obra).'
          : 'Este orçamento não tem produtos para faturar (só serviços/mão de obra).');
        return;
      }
      navigate('/fiscal/emissao', {
        state: { invoiceFrom: {
          serviceOrderId: so.id,
          clientId: so.client_id || so.clients?.id || null,
          items,
          purchaseOrder: so.customer_po_number || '',
          buyerName: so.customer_buyer_name || so.requested_by_name || '',
          orderNumber: so.service_order_number || null,
        } },
      });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Erro ao preparar o faturamento');
    }
  };

  const executeDuplicate = async (soId: string, dupMode: 'quote' | 'order') => {
    setDuplicateDialogId(null);
    try {
      const newSO = await duplicate.mutateAsync({ sourceId: soId, mode: dupMode });
      toast.success(dupMode === 'quote' ? 'Duplicado como Orçamento!' : 'Duplicado como nova OS!');
      navigate(`/v2/service-orders/${(newSO as { id: string }).id}`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Erro ao duplicar');
    }
  };

  const handleConvertToOS = async (so: SORow) => {
    try {
      await convertToOS.mutateAsync({ id: so.id, status: 'approved' });
      toast.success(`${so.service_order_number} convertido em OS`);
      setStockConfirm({ id: so.id, number: so.service_order_number });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Erro ao converter em OS');
    }
  };

  const handleGeneratePDF = (action: PDFAction, options: PDFOptions, validity?: unknown, dueDate?: string) => {
    if (!pdfData || !pdfTarget) return;
    const payload = { ...pdfData, documentType: pdfTarget.type };
    if (action === 'download') {
      downloadPDF(payload, { ...options, validity, dueDate } as PDFOptions)
        .then(() => toast.success('PDF baixado com sucesso'))
        .catch(() => toast.error('Erro ao gerar o PDF'));
    } else {
      generatePDF(payload, { ...options, validity } as PDFOptions);
    }
    setPdfTarget(null);
  };

  const handleDirectDownload = async (soId: string, type: 'quote' | 'service_order') => {
    try {
      const d = await fetchPDFData(soId);
      if (!d) throw new Error('Dados não encontrados');
      await downloadPDF({ ...d, documentType: type }, DEFAULT_PDF_OPTIONS);
      toast.success('PDF baixado com sucesso');
    } catch {
      toast.error('Erro ao gerar o PDF');
    }
  };

  const handleBulkDownload = async (ids: string[], clear: () => void) => {
    if (!ids.length) return;
    setBulkDownloading(true);
    pdfGenCountRef.current = ids.length;
    let ok = 0;
    let failed = 0;
    for (let i = 0; i < ids.length; i++) {
      try {
        const d = await fetchPDFData(ids[i]);
        if (!d) throw new Error('Dados não encontrados');
        await downloadPDF({ ...d, documentType: isOrders ? 'service_order' : 'quote' }, DEFAULT_PDF_OPTIONS);
        ok++;
        if (i < ids.length - 1) await new Promise((r) => setTimeout(r, 800));
      } catch {
        failed++;
      } finally {
        pdfGenCountRef.current = Math.max(0, pdfGenCountRef.current - 1);
        if (pdfGenCountRef.current === 0) document.body.style.overflow = '';
      }
    }
    setBulkDownloading(false);
    clear();
    if (failed === 0) toast.success(`${ok} PDF${ok > 1 ? 's' : ''} baixado${ok > 1 ? 's' : ''} com sucesso`);
    else toast.error(`${failed} falhou. ${ok} baixado${ok > 1 ? 's' : ''} com sucesso.`);
  };

  // wa.me com link público — SEMPRE /view/:token (rota real; corrige o link
  // quebrado /public/service-order/ que a QuoteList v1 enviava ao cliente).
  const handleSendWaMe = (so: SORow) => {
    if (!so.share_token) {
      toast.error(isOrders ? 'Esta OS ainda não tem link público gerado.' : 'Este orçamento ainda não tem link público gerado.');
      return;
    }
    const url = `${window.location.origin}/view/${so.share_token}`;
    const phoneRaw = so.clients?.whatsapp || so.clients?.phone || '';
    const phone = normalizePhoneE164(phoneRaw);
    const clientName = so.clients?.name || '';
    const docLabel = isOrders ? 'da Ordem de Serviço' : 'do seu Orçamento';
    const msg = `Olá${clientName ? ' ' + clientName : ''}, segue o link ${docLabel} ${so.service_order_number}: ${url}`;
    const waUrl = phone
      ? `https://wa.me/${phone}?text=${encodeURIComponent(msg)}`
      : `https://wa.me/?text=${encodeURIComponent(msg)}`;
    const win = window.open(waUrl, '_blank', 'noopener,noreferrer');
    const opened = !!win;
    void writeAuditLog({
      table_name: 'service_orders',
      record_id: so.id,
      action: 'whatsapp_send' as never,
      new_value: {
        share_token: so.share_token, public_url: url, phone_raw: String(phoneRaw),
        phone_normalized: phone, client_name: clientName, opened, source: 'v2_list',
      },
      reason: opened ? 'Link do WhatsApp aberto (lista v2)' : 'Falha ao abrir janela do WhatsApp (lista v2)',
    });
    recordWhatsAppEvent({
      source: 'v2_list', action: 'send', serviceOrderId: so.id,
      serviceOrderNumber: so.service_order_number, shareToken: so.share_token,
      phoneRaw: String(phoneRaw), phoneNormalized: phone, opened, popupBlocked: !opened,
      errorMessage: !opened ? 'window.open returned null (likely popup blocker)' : undefined,
    });
    if (!opened) toast.error('Não foi possível abrir o WhatsApp. Verifique o bloqueador de pop-ups.');
  };

  const openWhatsAppDialog = (so: SORow, documentType: 'service_order' | 'quote') => {
    if (!so.share_token) {
      toast.error(isOrders ? 'Esta OS ainda não tem link público gerado.' : 'Este orçamento ainda não tem link público gerado.');
      return;
    }
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

  // ── Colunas (orçamento de colunas decide o que cabe; resto vai p/ linha ▾) ──
  const columns: DataColumn<SORow>[] = [
    {
      key: 'number', header: isOrders ? 'OS' : 'Número', minWidth: 116, priority: 0, sortable: true,
      render: (so) => (
        <Link to={`/v2/service-orders/${so.id}`} className="font-bold text-accent hover:underline" onClick={(e) => e.stopPropagation()}>
          {so.service_order_number}
        </Link>
      ),
    },
    {
      key: 'client', header: 'Cliente · Embarcação', minWidth: 215, priority: 1, sortable: true, detailLabel: 'Cliente',
      render: (so) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{so.clients?.name || '—'}</span>
          <span className="block truncate text-xs text-muted-foreground">
            {[so.vessels?.name, so.service_type ? (t.serviceType as Record<string, string>)[so.service_type] : null].filter(Boolean).join(' · ') || '—'}
          </span>
        </span>
      ),
    },
    {
      key: 'status', header: 'Status', minWidth: 200, priority: 2, detailLabel: 'Status',
      render: (so) => (
        <span className="inline-flex flex-wrap items-center gap-1" onClick={(e) => e.stopPropagation()}>
          {isOrders ? (
            <StatusQuickChange orderId={so.id} currentStatus={so.status as ServiceOrderStatus} />
          ) : (
            <QuoteStatusQuickChange
              orderId={so.id}
              currentQuoteStatus={so.quote_status ?? 'draft'}
              serviceOrderNumber={so.service_order_number}
              grandTotal={so.grand_total || 0}
              laborCost={so.labor_cost_total || 0}
              partsCost={so.parts_cost_total || 0}
            />
          )}
          {(so.priority === 'urgent' || so.priority === 'high') && (
            <StatusChip tone={priorityTone[so.priority]}>{priorityLabels[so.priority] ?? so.priority}</StatusChip>
          )}
        </span>
      ),
    },
    {
      key: 'total', header: 'Total', minWidth: 118, priority: 2, align: 'right', sortable: true, detailLabel: 'Total',
      render: (so) => <span className="font-semibold">{formatCurrency(so.grand_total || 0)}</span>,
    },
    isOrders
      ? {
          key: 'scheduled', header: 'Agendada', minWidth: 106, priority: 3, sortable: true, detailLabel: 'Agendada',
          render: (so) => (so.scheduled_start_at ? formatDate(so.scheduled_start_at) : '—'),
        }
      : {
          key: 'created_at', header: 'Criado em', minWidth: 106, priority: 3, sortable: true, detailLabel: 'Criado em',
          render: (so) => (so.created_at ? formatDate(so.created_at) : '—'),
        },
    ...(isOrders
      ? [
          {
            key: 'payment', header: 'Pgto', minWidth: 104, priority: 4, detailLabel: 'Pagamento',
            render: (so) => so.payment_status
              ? <StatusChip tone={paymentTone[so.payment_status] ?? 'neutral'}>{PAYMENT_LABELS[so.payment_status] ?? so.payment_status}</StatusChip>
              : <span className="text-xs text-muted-foreground">—</span>,
          } satisfies DataColumn<SORow>,
          {
            key: 'whatsapp', header: 'WhatsApp', minWidth: 96, priority: 5, detailLabel: 'WhatsApp',
            render: (so) => {
              const entry = sendStatusMap?.get(so.id);
              if (!entry) return <span className="text-xs text-muted-foreground">—</span>;
              return (
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); setHistoryTarget({ id: so.id, number: so.service_order_number }); }}
                  className="inline-flex items-center gap-1 text-xs font-medium underline-offset-2 hover:underline"
                  title="Ver histórico de envios WhatsApp"
                >
                  {entry.success
                    ? <StatusChip dot tone="success">Enviado</StatusChip>
                    : <StatusChip dot tone="critical">Falhou</StatusChip>}
                </button>
              );
            },
          } satisfies DataColumn<SORow>,
        ]
      : []),
  ];

  // ── Menu ⋯ (nível 2 + submenus nível 3) ──────────────────────────────────
  const renderMenu = (so: SORow) => (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="Mais ações">
          <MoreHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        {!isOrders && (
          <DropdownMenuItem onClick={() => handleConvertToOS(so)} className="gap-2 font-medium text-info focus:text-info">
            <ArrowRightCircle className="h-4 w-4" /> Converter em OS
          </DropdownMenuItem>
        )}
        <DropdownMenuItem onClick={() => handleInvoice(so)} className="gap-2 font-medium text-success focus:text-success">
          <Receipt className="h-4 w-4" /> Emitir NF-e / Faturar
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => (isOrders ? setDuplicateDialogId(so.id) : executeDuplicate(so.id, 'quote'))}
          className="gap-2"
        >
          <Copy className="h-4 w-4" /> {isOrders ? 'Duplicar' : 'Duplicar orçamento'}
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuSub>
          <DropdownMenuSubTrigger className="gap-2">
            <FileDown className="h-4 w-4" /> Documentos
          </DropdownMenuSubTrigger>
          <DropdownMenuSubContent>
            <DropdownMenuItem onClick={() => setPdfTarget({ id: so.id, type: 'quote' })} className="gap-2">
              <FileText className="h-4 w-4" /> Imprimir Orçamento
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setPdfTarget({ id: so.id, type: 'service_order' })} className="gap-2">
              <Printer className="h-4 w-4" /> Imprimir OS
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={() => handleDirectDownload(so.id, 'quote')} className="gap-2">
              <Download className="h-4 w-4" /> Baixar Orçamento
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => handleDirectDownload(so.id, 'service_order')} className="gap-2">
              <Download className="h-4 w-4" /> Baixar OS
            </DropdownMenuItem>
          </DropdownMenuSubContent>
        </DropdownMenuSub>
        <DropdownMenuSub>
          <DropdownMenuSubTrigger className="gap-2">
            <MessageCircle className="h-4 w-4" /> WhatsApp
          </DropdownMenuSubTrigger>
          <DropdownMenuSubContent>
            {isOrders && (
              <DropdownMenuItem onClick={() => openWhatsAppDialog(so, 'service_order')} disabled={!so.share_token} className="gap-2">
                <Send className="h-4 w-4" /> Enviar OS…
              </DropdownMenuItem>
            )}
            <DropdownMenuItem onClick={() => openWhatsAppDialog(so, 'quote')} disabled={!so.share_token} className="gap-2">
              <Send className="h-4 w-4" /> Enviar Orçamento…
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => handleSendWaMe(so)} disabled={!so.share_token} className="gap-2">
              <MessageCircle className="h-4 w-4" /> Abrir no wa.me (link)
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={() => setHistoryTarget({ id: so.id, number: so.service_order_number })} className="gap-2">
              <History className="h-4 w-4" /> Histórico de envios
            </DropdownMenuItem>
          </DropdownMenuSubContent>
        </DropdownMenuSub>
      </DropdownMenuContent>
    </DropdownMenu>
  );

  const csvExport = () =>
    exportToCSV(filtered as never[], isOrders ? 'ordens_servico' : 'orcamentos', [
      { key: 'service_order_number', label: 'Número' },
      { key: isOrders ? 'status' : 'quote_status', label: 'Status' },
      { key: 'clients', label: 'Cliente', format: (v: { name?: string } | null) => v?.name || '' },
      { key: 'vessels', label: 'Embarcação', format: (v: { name?: string } | null) => v?.name || '' },
      { key: 'grand_total', label: 'Valor Total', format: (v: number | null) => Number(v || 0).toFixed(2).replace('.', ',') },
      { key: 'created_at', label: 'Data Criação', format: (v: string | null) => (v ? new Date(v).toLocaleDateString('pt-BR') : '') },
    ] as never);

  const filterGroups = isOrders
    ? [
        {
          type: 'multi' as const, field: 'status', label: 'Status',
          options: Object.keys(statusConfig).filter((k) => k !== 'draft').map((k) => ({ value: k, label: statusLabels[k] ?? k })),
        },
        {
          type: 'multi' as const, field: 'priority', label: 'Prioridade',
          options: [
            { value: 'low', label: 'Baixa' }, { value: 'normal', label: 'Normal' },
            { value: 'high', label: 'Alta' }, { value: 'urgent', label: 'Urgente' },
          ],
        },
        {
          type: 'multi' as const, field: 'technician', label: 'Técnico',
          options: (technicians as { id: string; full_name: string }[]).map((x) => ({ value: x.id, label: x.full_name })),
        },
        { type: 'daterange' as const, fromField: 'dateFrom', toField: 'dateTo', label: 'Período' },
      ]
    : [
        {
          type: 'multi' as const, field: 'quoteStatus', label: 'Status do orçamento',
          options: Object.entries(QUOTE_STATUS_LABELS).map(([value, label]) => ({ value, label })),
        },
        {
          type: 'multi' as const, field: 'priority', label: 'Prioridade',
          options: [
            { value: 'low', label: 'Baixa' }, { value: 'normal', label: 'Normal' },
            { value: 'high', label: 'Alta' }, { value: 'urgent', label: 'Urgente' },
          ],
        },
        { type: 'daterange' as const, fromField: 'dateFrom', toField: 'dateTo', label: 'Período' },
      ];

  const cardSeverity = (so: SORow) =>
    so.priority === 'urgent'
      ? 'critical'
      : isOrders
        ? (serviceOrderStatusTone[so.status] ?? 'neutral')
        : (quoteStatusTone[so.quote_status ?? 'draft'] ?? 'neutral');

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Operacional', to: '/' }, { label: isOrders ? 'Ordens de Serviço' : 'Orçamentos' }]}
        title={isOrders ? 'Ordens de Serviço' : 'Orçamentos'}
        count={isOrders ? orderCount : quoteCount}
        actions={
          <>
            <Button variant="outline" size="sm" onClick={csvExport} className="hidden gap-1.5 sm:inline-flex">
              <Download className="h-4 w-4" /> Exportar CSV
            </Button>
            <Link to="/v2/service-orders/new">
              <Button className="gap-1.5">
                <Plus className="h-4 w-4" /> {isOrders ? 'Nova OS' : 'Novo Orçamento'}
              </Button>
            </Link>
          </>
        }
      >
        {/* Tabs gêmeas — tokenizadas (sem azul/âmbar cru da v1) */}
        <div className="flex gap-1 border-b">
          <TwinTab to="/v2/quotes" active={!isOrders} icon={<FileText className="h-4 w-4" />} label="Orçamentos" count={quoteCount} />
          <TwinTab to="/v2/service-orders" active={isOrders} icon={<Wrench className="h-4 w-4" />} label="Ordens de Serviço" count={orderCount} />
        </div>

        {/* Views rápidas + barra de filtros completa (presets preservados) */}
        <div className="flex flex-wrap items-center gap-1.5">
          {quickViews.map((v) => (
            <button
              key={v.id}
              type="button"
              onClick={() => { setView(v.id); setPage(1); }}
              className={cn(
                'rounded-full px-3 py-1 text-xs font-semibold transition-colors',
                view === v.id
                  ? 'bg-foreground text-background'
                  : 'bg-muted text-muted-foreground hover:text-foreground',
              )}
            >
              {v.label}
            </button>
          ))}
        </div>
        <MultiFilterBar
          search={String((filters as Record<string, unknown>).search || '')}
          onSearchChange={(v) => { setField('search', v); setPage(1); }}
          searchPlaceholder="Buscar por número, cliente ou embarcação…"
          filters={filters}
          activeCount={activeCount}
          onToggle={(f, v) => { toggle(f, v); setPage(1); }}
          onSetField={(f, v) => { setField(f, v); setPage(1); }}
          onClearAll={() => { clearAll(); setPage(1); }}
          presetType={isOrders ? 'service_orders' : 'quotes'}
          groups={filterGroups}
        />

        {isLoading ? (
          <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-14 w-full" />)}
          </div>
        ) : error ? (
          <div className="rounded-lg border bg-card p-8 text-center">
            <p className="text-destructive">Erro ao carregar {isOrders ? 'ordens de serviço' : 'orçamentos'}.</p>
          </div>
        ) : filtered.length === 0 && activeCount === 0 && view === 'all' ? (
          <div className="space-y-3 rounded-lg border bg-card p-12 text-center">
            {isOrders
              ? <Wrench className="mx-auto h-12 w-12 text-muted-foreground" />
              : <FileText className="mx-auto h-12 w-12 text-muted-foreground" />}
            <p className="text-muted-foreground">
              {isOrders ? 'Nenhuma ordem de serviço cadastrada ainda.' : 'Nenhum orçamento cadastrado ainda.'}
            </p>
            <Link to="/v2/service-orders/new">
              <Button className="gap-1.5"><Plus className="h-4 w-4" /> {isOrders ? 'Nova OS' : 'Novo Orçamento'}</Button>
            </Link>
          </div>
        ) : (
          <>
            {/* Desktop: DataTable universal */}
            <div className="hidden md:block">
              <DataTable<SORow>
                rows={paginated}
                rowKey={(so) => so.id}
                columns={columns}
                selectable
                sort={sort}
                onSort={handleSort}
                onRowClick={(so) => navigate(`/v2/service-orders/${so.id}`)}
                emptyMessage={t.common.noResults}
                rowActions={(so) => (
                  <>
                    <Button
                      variant="ghost" size="icon" className="h-8 w-8"
                      aria-label="Enviar por WhatsApp" title="Enviar por WhatsApp"
                      disabled={!so.share_token}
                      onClick={() => openWhatsAppDialog(so, isOrders ? 'service_order' : 'quote')}
                    >
                      <MessageCircle className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost" size="icon" className="h-8 w-8"
                      aria-label="Abrir" title="Abrir"
                      onClick={() => navigate(`/v2/service-orders/${so.id}`)}
                    >
                      <ExternalLink className="h-4 w-4" />
                    </Button>
                    {renderMenu(so)}
                  </>
                )}
                bulkBar={(keys, clear) => (
                  <>
                    <span className="font-semibold">{keys.length} selecionada{keys.length > 1 ? 's' : ''}</span>
                    <Button size="sm" variant="secondary" disabled={bulkDownloading} onClick={() => handleBulkDownload(keys, clear)} className="gap-1.5">
                      {bulkDownloading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                      {bulkDownloading ? 'Baixando…' : `Baixar ${keys.length} PDF${keys.length > 1 ? 's' : ''}`}
                    </Button>
                    <button type="button" className="ml-auto text-xs underline-offset-2 hover:underline" onClick={clear} disabled={bulkDownloading}>
                      Cancelar seleção
                    </button>
                  </>
                )}
              />
            </div>

            {/* Mobile: EntityCard + FAB */}
            <div className="space-y-2.5 md:hidden">
              {paginated.map((so) => (
                <EntityCard
                  key={so.id}
                  id={so.service_order_number}
                  severity={cardSeverity(so)}
                  badge={
                    <>
                      <StatusChip tone={isOrders ? (serviceOrderStatusTone[so.status] ?? 'neutral') : (quoteStatusTone[so.quote_status ?? 'draft'] ?? 'neutral')}>
                        {isOrders ? (statusLabels[so.status] ?? so.status) : (QUOTE_STATUS_LABELS[so.quote_status ?? 'draft'] ?? so.quote_status)}
                      </StatusChip>
                      {so.priority === 'urgent' && <StatusChip tone="critical">{priorityLabels.urgent}</StatusChip>}
                    </>
                  }
                  title={so.clients?.name || '—'}
                  lines={[
                    [so.vessels?.name, so.service_type ? (t.serviceType as Record<string, string>)[so.service_type] : null].filter(Boolean).join(' · ') || '—',
                    `${isOrders && so.scheduled_start_at ? formatDate(so.scheduled_start_at) + ' · ' : ''}${formatCurrency(so.grand_total || 0)}`,
                  ]}
                  onClick={() => navigate(`/v2/service-orders/${so.id}`)}
                  actions={
                    <>
                      <Button className="flex-1" onClick={() => navigate(`/v2/service-orders/${so.id}`)}>
                        Abrir {isOrders ? 'OS' : 'Orçamento'}
                      </Button>
                      <Button
                        variant="outline" size="icon" className="h-11 w-11"
                        aria-label="Enviar por WhatsApp" disabled={!so.share_token}
                        onClick={() => openWhatsAppDialog(so, isOrders ? 'service_order' : 'quote')}
                      >
                        <MessageCircle className="h-4 w-4" />
                      </Button>
                      {renderMenu(so)}
                    </>
                  }
                />
              ))}
              <Link
                to="/v2/service-orders/new"
                aria-label={isOrders ? 'Nova OS' : 'Novo Orçamento'}
                className="fixed bottom-24 right-5 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-transform active:scale-95"
              >
                <Plus className="h-6 w-6" />
              </Link>
            </div>

            {totalPages > 1 && (
              <div className="flex flex-wrap items-center justify-between gap-2 pb-16 text-sm md:pb-0">
                <span className="text-muted-foreground">
                  {filtered.length} {isOrders ? 'ordens de serviço' : 'orçamentos'} · Página {page} de {totalPages}
                </span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>
                    Anterior
                  </Button>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>
                    Próxima
                  </Button>
                </div>
              </div>
            )}
          </>
        )}
      </PageShell>

      {/* Diálogos (paridade v1) */}
      <PDFOptionsDialog
        open={!!pdfTarget}
        onOpenChange={(v) => { if (!v) setPdfTarget(null); }}
        documentType={pdfTarget?.type || 'quote'}
        hasProductImages={pdfData?.parts?.some((p: { image_url?: string | null }) => !!p.image_url) ?? false}
        onGenerate={handleGeneratePDF}
      />
      <WhatsAppSendHistoryDialog
        open={!!historyTarget}
        onOpenChange={(v) => { if (!v) setHistoryTarget(null); }}
        serviceOrderId={historyTarget?.id || null}
        serviceOrderNumber={historyTarget?.number}
      />
      <SendViaWhatsAppDialog
        open={!!whatsAppTarget}
        onOpenChange={(v) => { if (!v) setWhatsAppTarget(null); }}
        target={whatsAppTarget}
      />
      {stockConfirm && (
        <PurchaseNeedsDialog
          open={!!stockConfirm}
          onOpenChange={(v) => { if (!v) setStockConfirm(null); }}
          serviceOrderId={stockConfirm.id}
          serviceOrderNumber={stockConfirm.number}
        />
      )}
      <Dialog open={!!duplicateDialogId} onOpenChange={(v) => { if (!v) setDuplicateDialogId(null); }}>
        <DialogContent className="themev2 max-w-sm">
          <DialogHeader>
            <DialogTitle>Como deseja duplicar?</DialogTitle>
            <DialogDescription>
              Escolha se a cópia será um novo Orçamento (para ajustar e enviar ao cliente) ou uma nova Ordem de Serviço já aberta.
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-3 pt-2">
            <button
              type="button"
              onClick={() => duplicateDialogId && executeDuplicate(duplicateDialogId, 'quote')}
              disabled={duplicate.isPending}
              className="flex flex-col items-center gap-2 rounded-lg border-2 border-border p-4 text-sm font-medium transition-colors hover:border-primary hover:bg-primary/5"
            >
              <FileText className="h-7 w-7 text-warning" />
              Orçamento
              <span className="text-center text-xs font-normal text-muted-foreground">Rascunho editável, pode mudar o cliente</span>
            </button>
            <button
              type="button"
              onClick={() => duplicateDialogId && executeDuplicate(duplicateDialogId, 'order')}
              disabled={duplicate.isPending}
              className="flex flex-col items-center gap-2 rounded-lg border-2 border-border p-4 text-sm font-medium transition-colors hover:border-primary hover:bg-primary/5"
            >
              <Wrench className="h-7 w-7 text-info" />
              Nova OS
              <span className="text-center text-xs font-normal text-muted-foreground">Já entra como OS aberta, sem etapa de orçamento</span>
            </button>
          </div>
        </DialogContent>
      </Dialog>
    </V2Shell>
  );
}

function TwinTab({ to, active, icon, label, count }: { to: string; active: boolean; icon: ReactNode; label: string; count: number }) {
  const inner = (
    <>
      {icon}
      {label}
      <span className={cn(
        'rounded-full px-1.5 py-0.5 text-xs font-bold',
        active ? 'bg-primary/15 text-primary' : 'bg-muted text-muted-foreground',
      )}>
        {count}
      </span>
    </>
  );
  if (active) {
    return (
      <span className="flex items-center gap-2 border-b-2 border-primary px-4 py-2.5 text-sm font-semibold text-foreground">
        {inner}
      </span>
    );
  }
  return (
    <Link
      to={to}
      className="flex items-center gap-2 border-b-2 border-transparent px-4 py-2.5 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
    >
      {inner}
    </Link>
  );
}

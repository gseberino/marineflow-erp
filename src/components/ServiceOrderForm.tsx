import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import {
  computeOsFinancials, normalizeInstallmentRows,
  calcInstallmentAmount as calcInstallmentAmountPure,
  findSignalRow, simulateCardReceipt, computeItemDiscountTotal,
  computePartsProfit, computeReceivablesStatus,
} from '@/lib/os-financials';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { useVessels } from '@/hooks/use-vessels';
import { useMarinas } from '@/hooks/use-marinas';
import { useProducts } from '@/hooks/use-products';
import { useServices } from '@/hooks/use-services';
import { useCardFees } from '@/hooks/use-card-fees';
import { useAppSettings } from '@/hooks/use-app-settings';
import { useSOLinkedPOs, useUpdatePurchaseOrder } from '@/hooks/use-purchase-orders';
import {
  useCreateServiceOrder,
  useUpdateServiceOrder,
  useUpdateServiceOrderStatus,
  useServiceOrderParts,
  useAddServiceOrderPart,
  useRemoveServiceOrderPart,
  isStockModelV2,
  useServiceOrderServices,
  useAddServiceOrderService,
  useRemoveServiceOrderService,
  useTimeEntries,
  useAddTimeEntry,
  useRemoveTimeEntry,
  STATUS_TRANSITIONS,
  useCancelServiceOrder,
  useReopenServiceOrder,
  useDuplicateServiceOrder,
  recalcTotals,
} from '@/hooks/use-service-orders';
import { useAppUsers, useCommissionableUsers } from '@/hooks/use-app-users';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { useCollectionsByOS } from '@/hooks/use-collections';
import { useReceivablesByServiceOrder, usePaymentsByServiceOrder, useCreateReceivable } from '@/hooks/use-financial';
import { PaymentDialog } from '@/components/PaymentDialog';
import { useVesselContacts, VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { QuickProductDialog } from '@/components/QuickProductDialog';
import { MarinaFormDialog } from '@/components/MarinaFormDialog';
import { QuickSupplierDialog } from '@/components/QuickSupplierDialog';
import { ServiceOrderFinancialSummary, type FinancialWaterfallLine } from '@/components/ServiceOrderFinancialSummary';
import { useSuppliers } from '@/hooks/use-suppliers';
import { useServiceOrderExpenses, useAddServiceOrderExpense, useUpdateServiceOrderExpense, useRemoveServiceOrderExpense } from '@/hooks/use-service-order-expenses';
import { useUpdateServiceOrderService } from '@/hooks/use-service-order-services';
import { useUpdateServiceOrderPart } from '@/hooks/use-service-order-parts';
import { PriceCalculatorDialog } from '@/components/PriceCalculatorDialog';
import { supabase } from '@/integrations/supabase/client';
import { usePDFData } from '@/hooks/use-pdf';
import { generatePDF, downloadPDF, DEFAULT_PDF_OPTIONS } from '@/lib/pdf-generator';
import type { PDFOptions } from '@/lib/pdf-generator';
import { PDFOptionsDialog } from '@/components/PDFOptionsDialog';
import { RegisterDepositDialog } from '@/components/RegisterDepositDialog';
import { CompletionSendDialog } from '@/components/CompletionSendDialog';
import { StockAlertDialog } from '@/components/StockAlertDialog';
import { ReceivePODialog } from '@/components/ReceivePODialog';
import { calculateDisplacement, calculateTravelCost, travelRatesFromSettings } from '@/lib/displacement';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { ServiceFormDialog } from '@/components/ServiceFormDialog';
import { ServiceOrderSignatures } from '@/components/ServiceOrderSignatures';
import { WhatsAppSendHistoryDialog } from '@/components/WhatsAppSendHistoryDialog';
import { SendViaWhatsAppDialog, type SendViaWhatsAppTarget } from '@/components/SendViaWhatsAppDialog';
import { useWhatsAppSendHistory } from '@/hooks/use-whatsapp-send-log';
import { CheckCircle2, XCircle, History as HistoryIcon, Send, Sparkles } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowLeft, Plus, Trash2, AlertTriangle, Receipt, Lock, RotateCcw, Ban, FileText, Printer, ChevronDown, MessageCircle, Copy, Download, Loader2, DollarSign, Percent, Hash } from 'lucide-react';
import { toast } from 'sonner';
import { normalizePhoneE164 } from '@/lib/masks';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { recordWhatsAppEvent } from '@/lib/diagnostics';
import { useAITextOptimizer } from '@/hooks/use-ai-text-optimizer';
import {
  useDescriptionAnalysis, type DescriptionAnalysis,
} from '@/hooks/use-description-analysis';
import { DescriptionAnalysisDialog } from '@/components/service-orders/DescriptionAnalysisDialog';
import { RelatedMaterialsPanel } from '@/components/service-orders/RelatedMaterialsPanel';

interface Props {
  orderId?: string;
  orderData?: any;
  isLoading?: boolean;
}

import { GeneralSections } from './service-order/general-sections';
import { SummarySections } from './service-order/summary-sections';
import { PartsSection } from './service-order/parts-section';
import { ExpensesTimeDialogs } from './service-order/expenses-time-dialogs';
import { ServicesSection } from './service-order/services-section';
import { TravelDialog } from './service-order/travel-dialog';
import { FinancialSection } from './service-order/financial-section';
export function ServiceOrderForm({ orderId, orderData, isLoading }: Props) {
  const navigate = useNavigate();
  const { t, formatCurrency, formatDateTime, formatDate } = useI18n();
  const isNew = !orderId;

  const { data: clients } = useClients();
  const { data: allVessels } = useVessels();
  const { data: marinas } = useMarinas();
  const { data: products } = useProducts();
  const { data: suppliers } = useSuppliers();
  const { data: appUsers } = useAppUsers();
  const { data: commissionableUsers } = useCommissionableUsers();
  const { data: services } = useServices();
  const { data: cardFees } = useCardFees();
  const { data: appSettings } = useAppSettings();
  const issRatePct = Number(appSettings?.iss_rate_pct ?? 5) || 0;
  const defaultQuoteValidityDays = Number(appSettings?.quote_validity_days ?? 15) || 15;
  const travelRates = travelRatesFromSettings(appSettings);
  // Wrapper que injeta as tarifas configuráveis em todas as chamadas de cálculo de deslocamento
  const calcTravelCost = (p: Parameters<typeof calculateTravelCost>[0]) => calculateTravelCost(p, travelRates);
  const { data: paymentPresets } = usePaymentConditionPresets();
  const { data: pdfData } = usePDFData(isNew ? undefined : orderId);
  const queryClient = useQueryClient();
  const openPdfDialog = (type: 'quote' | 'service_order' | 'invoice') => {
    if (orderId) {
      queryClient.invalidateQueries({ queryKey: ['pdf-data', orderId] });
    }
    setPdfDialogType(type);
  };

  const handleDirectDownload = async (type: 'quote' | 'service_order' | 'invoice') => {
    if (!pdfData || !orderId) return;
    setDownloadingType(type);
    try {
      await downloadPDF({ ...pdfData, documentType: type }, DEFAULT_PDF_OPTIONS);
      toast.success('PDF baixado com sucesso');
    } catch (e: any) {
      console.error('PDF download failed:', e);
      toast.error('Erro ao gerar o PDF para download');
    } finally {
      setDownloadingType(null);
    }
  };

  const createSO = useCreateServiceOrder();
  const updateSO = useUpdateServiceOrder();
  const updateStatus = useUpdateServiceOrderStatus();
  const cancelSO = useCancelServiceOrder();
  const reopenSO = useReopenServiceOrder();
  const duplicate = useDuplicateServiceOrder();

  const { data: parts } = useServiceOrderParts(orderId);
  const addPart = useAddServiceOrderPart();
  const removePart = useRemoveServiceOrderPart();
  const { data: linkedPOs } = useSOLinkedPOs(orderId);
  const updatePO = useUpdatePurchaseOrder();
  const [stockAlert, setStockAlert] = useState<{ cardKey: string; productId: string; productName: string; needed: number; available: number; unitCost: number; unitSale: number; notes?: string; suppliers: { id: string; name: string }[]; leadTimeDays?: number; } | null>(null);
  const [receivePOTarget, setReceivePOTarget] = useState<any>(null);

  const { data: soServices } = useServiceOrderServices(orderId);
  const addService = useAddServiceOrderService();
  const removeService = useRemoveServiceOrderService();

  const { data: timeEntries } = useTimeEntries(orderId);
  const addTime = useAddTimeEntry();
  const removeTime = useRemoveTimeEntry();

  const { data: soExpenses } = useServiceOrderExpenses(orderId);
  const addExpense = useAddServiceOrderExpense();
  const updateExpense = useUpdateServiceOrderExpense();
  const removeExpense = useRemoveServiceOrderExpense();
  
  const { isOptimizing, optimizeText } = useAITextOptimizer();

  /* A descrição vira levantamento meio pronto.
     O texto do orçamento já diz o verbo, o sistema e metade das respostas —
     até aqui o único botão de IA sobre ele reescrevia a redação. */
  const { analisar, analisando } = useDescriptionAnalysis();
  const [analise, setAnalise] = useState<DescriptionAnalysis | null>(null);
  const [analiseAberta, setAnaliseAberta] = useState(false);
  const [gravandoAnalise, setGravandoAnalise] = useState(false);

  async function analisarDescricao(texto: string) {
    const r = await analisar(texto);
    if (!r) {
      toast.error('Não deu para ler a descrição. Tente com mais detalhes.');
      return;
    }
    setAnalise(r);
    setAnaliseAberta(true);
  }

  async function gravarAnaliseComoLevantamento(
    respostas: Array<{ id: string; question: string; answer: string }>,
  ) {
    if (!orderId) {
      toast.error('Salve o orçamento antes — o levantamento precisa estar preso a ele.');
      return;
    }
    setGravandoAnalise(true);
    try {
      const { data: survey, error } = await supabase
        .from('service_surveys')
        .insert({
          service_order_id: orderId,
          client_id: form.client_id || null,
          vessel_id: form.vessel_id || null,
          // Sem serviço escolhido ainda: a descrição vem antes dessa decisão,
          // e a coluna aceita nulo justamente para permitir este caminho.
          service_id: null,
          trigger_reason: 'Lido da descrição do orçamento',
          mode: 'local',
          status: 'draft',
          questions_planned: respostas.length + (analise?.faltam.length ?? 0),
        })
        .select('id')
        .single();
      if (error) throw error;

      if (respostas.length) {
        const { error: e2 } = await supabase.from('service_survey_answers').insert(
          respostas.map((r, i) => ({
            survey_id: survey.id,
            template_id: r.id,
            seq: i + 1,
            question_snapshot: r.question,
            answer_value: r.answer,
          })),
        );
        if (e2) throw e2;
      }

      setAnaliseAberta(false);
      toast.success(
        `Levantamento aberto com ${respostas.length} resposta(s). Abra a aba Levantamento para continuar.`,
      );
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao abrir o levantamento');
    } finally {
      setGravandoAnalise(false);
    }
  }

  // Form state
  const [form, setForm] = useState<Record<string, any>>({
    status: 'draft',
    priority: 'normal',
    service_type: 'repair',
    client_id: '',
    vessel_id: '',
    marina_id: '',
    requested_by_name: '',
    customer_po_number: '',
    customer_buyer_name: '',
    requested_by_contact_id: '',
    scheduled_start_at: '',
    scheduled_end_at: '',
    problem_description: '',
    initial_findings: '',
    diagnosis: '',
    solution_applied: '',
    technician_notes: '',
    extra_notes: '',
    internal_notes: '',
    customer_visible_report: '',
    travel_distance_km: 0,
    travel_cost_per_km: 3.5,
    technician_count_for_travel: 1,
    travel_cost_total: 0,
    travel_hours: 0,
    ferry_cost: 0,
    travel_type: 'comercial' as 'comercial' | 'urgencia' | 'fds_feriado',
    is_travel_billable: true,
    discount_amount: 0,
    tax_amount: 0,
    subcontract_cost_total: 0,
    commission_rate: 0,
    commission_amount: 0,
    commissioned_person: '',
    commissioned_user_id: '',
    payment_conditions: '',
    payment_condition_preset_id: '',
    custom_payment_installments: null as any[] | null,
    financial_notes: '',
    payment_method_preferred: '',
    quote_validity_days: defaultQuoteValidityDays,
    card_installments: 1,
    card_fee_passthrough_enabled: false,
    signed_at: '' as string,
  });

  // Em orçamento NOVO, o valor inicial de quote_validity_days acima pode ter usado o
  // fallback (15) se app_settings ainda não tinha carregado no primeiro render (useState
  // só aplica o valor inicial uma vez). Este efeito corrige assim que a configuração
  // chegar — mas só uma vez (ref), pra nunca sobrescrever uma edição manual do usuário.
  const appliedDefaultValidityRef = useRef(false);
  useEffect(() => {
    if (isNew && appSettings && !appliedDefaultValidityRef.current) {
      appliedDefaultValidityRef.current = true;
      setForm(f => ({ ...f, quote_validity_days: defaultQuoteValidityDays }));
    }
  }, [isNew, appSettings, defaultQuoteValidityDays]);

  const [manualTravel, setManualTravel] = useState(false);
  const [selectedTechnicians, setSelectedTechnicians] = useState<string[]>([]);
  const [extraFieldsOpen, setExtraFieldsOpen] = useState(false);
  const [discountServicesPct, setDiscountServicesPct] = useState(0);
  const [discountPartsPct, setDiscountPartsPct] = useState(0);
  const [showTravelDialog, setShowTravelDialog] = useState(false);
  const [showExpensesDialog, setShowExpensesDialog] = useState(false);
  const [showTimeDialog, setShowTimeDialog] = useState(false);
  // Onda 4: agora controla a expansão da seção Financeiro inline (não mais um modal) — começa expandida.
  const [showFinancialDialog, setShowFinancialDialog] = useState(true);
  const [depositDialogOpen, setDepositDialogOpen] = useState(false);
  const [depositFromFinancial, setDepositFromFinancial] = useState(false);
  // Prompt opt-in de conclusão (avisar cliente + saldo) — aberto ao concluir a OS.
  const [completionSend, setCompletionSend] = useState<{
    open: boolean; balance: number; dueDate: string | null; clientName: string | null; clientPhone: string | null;
  }>({ open: false, balance: 0, dueDate: null, clientName: null, clientPhone: null });
  const { data: vesselContacts } = useVesselContacts(form.vessel_id || undefined);

  // Part inline-card state (matches the services pattern)
  type PartCardDraft = {
    product_id: string;
    name: string;
    unit: string;
    quantity: number;
    unit_cost: number;
    unit_sale: number;
    notes: string;
    image_url?: string | null;
    discount_pct?: number;
    discount_amount?: number;
  };
  const emptyPartCard = (): PartCardDraft => ({
    product_id: '',
    name: '',
    unit: 'un',
    quantity: 1,
    unit_cost: 0,
    unit_sale: 0,
    notes: '',
    image_url: null,
  });
  const [editingPart, setEditingPart] = useState<Record<string, PartCardDraft>>({});
  const [openNewPartCards, setOpenNewPartCards] = useState<string[]>([]);
  const [priceCalcCardKey, setPriceCalcCardKey] = useState<string | null>(null);
  const updatePartLine = useUpdateServiceOrderPart();
  // Kept for backwards compatibility (no longer opened from the parts row)
  const [quickProductOpen, setQuickProductOpen] = useState(false);
  const [quickProductName, setQuickProductName] = useState('');
  const [quickMarinaOpen, setQuickMarinaOpen] = useState(false);
  const [quickMarinaName, setQuickMarinaName] = useState('');
  const [quickSupplierOpen, setQuickSupplierOpen] = useState(false);
  const [quickSupplierName, setQuickSupplierName] = useState('');

  // Service line cards (inline expanding cards)
  type SvcCardDraft = {
    service_id: string;
    name_snapshot: string;
    description_snapshot: string;
    billing_unit_snapshot: string;
    quantity: number;
    unit_price: number;
    notes: string;
    technician_user_id: string;
    warranty_months?: number;
    discount_pct?: number;
    discount_amount?: number;
  };
  const emptySvcCard = (): SvcCardDraft => ({
    service_id: '',
    name_snapshot: '',
    description_snapshot: '',
    billing_unit_snapshot: 'hour',
    quantity: 1,
    unit_price: 0,
    notes: '',
    technician_user_id: '',
    warranty_months: 0,
  });
  // Editing state per row id (persisted: row.id, draft: tempId, new: 'new-N')
  const [editingSvc, setEditingSvc] = useState<Record<string, SvcCardDraft>>({});
  const [openNewSvcCards, setOpenNewSvcCards] = useState<string[]>([]);
  const [showNewServiceDialog, setShowNewServiceDialog] = useState(false);
  const updateSvcLine = useUpdateServiceOrderService();

  // Draft items used while OS is new (no orderId yet) — persisted on save
  type DraftPart = {
    tempId: string;
    product_id: string;
    name: string;
    quantity: number;
    unit_cost: number;
    unit_sale: number;
    warranty_months?: number;
    serial_number?: string;
    discount_pct?: number;
    discount_amount?: number;
  };
  type DraftService = {
    tempId: string;
    service_id?: string;
    name_snapshot: string;
    description_snapshot?: string;
    billing_unit_snapshot: string;
    quantity: number;
    unit_price_snapshot: number;
    notes?: string;
    warranty_months?: number;
    discount_pct?: number;
    discount_amount?: number;
  };
  const [draftParts, setDraftParts] = useState<DraftPart[]>([]);
  const [draftServices, setDraftServices] = useState<DraftService[]>([]);

  // Time form
  const [timeForm, setTimeForm] = useState({
    technician_user_id: '', started_at: '', ended_at: '', duration_minutes: 0, billable: true, notes: '',
  });
  const [showTimeForm, setShowTimeForm] = useState(false);

  // Expense form
  const [expForm, setExpForm] = useState({
    category: '', description: '', amount: 0, currency: 'BRL',
    expense_date: new Date().toISOString().slice(0, 10),
    paid_by: 'company' as 'company' | 'technician',
    technician_user_id: '', receipt_url: '', receipt_storage_path: '', notes: '',
    also_create_payable: false,
    supplier_id: '',
    billable_to_client: true,
  });
  const [showExpForm, setShowExpForm] = useState(false);
  const [editingExpenseId, setEditingExpenseId] = useState<string | null>(null);
  const [uploadingReceipt, setUploadingReceipt] = useState(false);
  const receiptInputRef = useRef<HTMLInputElement | null>(null);

  // Card installments
  const [selectedInstallments, setSelectedInstallments] = useState(1);
  const [showCancelDialog, setShowCancelDialog] = useState(false);
  const [showReopenDialog, setShowReopenDialog] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [reopenReason, setReopenReason] = useState('');
  const [showZapiHistory, setShowZapiHistory] = useState(false);
  const [whatsAppTarget, setWhatsAppTarget] = useState<SendViaWhatsAppTarget | null>(null);
  const { data: waHistory } = useWhatsAppSendHistory(orderId || null);
  const lastWaSend = waHistory?.[0];
  const [pdfDialogType, setPdfDialogType] = useState<'quote' | 'service_order' | 'invoice' | null>(null);
  const [downloadingType, setDownloadingType] = useState<'quote' | 'service_order' | 'invoice' | null>(null);
  const [waPreview, setWaPreview] = useState<{ phone: string; message: string; url: string; clientName: string } | null>(null);
  const [waEditMessage, setWaEditMessage] = useState('');
  const [waEditPhone, setWaEditPhone] = useState('');

  const [generatingCollections, setGeneratingCollections] = useState(false);
  const prevSignedAt = useRef<string | null>(null);
  const topActionsRef = useRef<HTMLDivElement | null>(null);
  const bottomSaveRef = useRef<HTMLDivElement | null>(null);
  const [topVisible, setTopVisible] = useState(true);
  const [bottomVisible, setBottomVisible] = useState(false);
  const { data: osCollections } = useCollectionsByOS(orderId);
  // M1: recebíveis desta OS para resumo financeiro e ações de pagamento
  const { data: soReceivables } = useReceivablesByServiceOrder(orderId);
  // M2: histórico de pagamentos desta OS
  const { data: soPayments } = usePaymentsByServiceOrder(orderId);
  const [showPaymentHistory, setShowPaymentHistory] = useState(false);
  // Recebível selecionado para abrir o PaymentDialog
  const [paymentDialogReceivable, setPaymentDialogReceivable] = useState<any>(null);
  const createReceivable = useCreateReceivable();
  // Onda 3: Modo de visão — 'internal' mostra custo/margem/comissão; 'client' esconde
  const [clientView, setClientView] = useState(false);

  useEffect(() => {
    const targets: Array<{ el: HTMLElement | null; setter: (v: boolean) => void }> = [
      { el: topActionsRef.current, setter: setTopVisible },
      { el: bottomSaveRef.current, setter: setBottomVisible },
    ];
    const observers: IntersectionObserver[] = [];
    for (const { el, setter } of targets) {
      if (!el) continue;
      const io = new IntersectionObserver(
        ([entry]) => setter(entry.isIntersecting),
        { rootMargin: '0px', threshold: 0.01 },
      );
      io.observe(el);
      observers.push(io);
    }
    return () => observers.forEach((o) => o.disconnect());
  }, [isLoading, orderId]);

  const handleGenerateCollections = useCallback(async () => {
    if (!orderId) return;
    setGeneratingCollections(true);
    try {
      const { generateCollectionsFromOS } = await import('@/lib/generate-collections');
      const approvalDate = form.signed_at
        ? form.signed_at.slice(0, 10)
        : new Date().toISOString().slice(0, 10);
      const result = await generateCollectionsFromOS({
        serviceOrderId: orderId,
        approvalDate,
        trigger: 'status_change',
      });
      if (result.skipped) {
        toast.info('Cobranças já existem para esta OS ou valor é zero.');
      } else {
        toast.success(`${result.created} cobrança(s) gerada(s) e enviadas por WhatsApp!`);
      }
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao gerar cobranças');
    } finally {
      setGeneratingCollections(false);
    }
  }, [orderId, form.signed_at]);

  // Auto-generate collections when OS is signed
  useEffect(() => {
    if (!orderId || !form.signed_at) return;
    if (prevSignedAt.current === form.signed_at) return;
    if (prevSignedAt.current === null) {
      // first observation — only trigger on transition, not on initial load
      prevSignedAt.current = form.signed_at;
      return;
    }
    prevSignedAt.current = form.signed_at;
    handleGenerateCollections();
  }, [form.signed_at, orderId, handleGenerateCollections]);

  useEffect(() => {
    if (orderData) {
      const d = orderData;
      setForm({
        status: d.status || 'draft',
        priority: d.priority || 'normal',
        service_type: d.service_type || 'repair',
        client_id: d.client_id || '',
        vessel_id: d.vessel_id || '',
        marina_id: d.marina_id || '',
        requested_by_name: d.requested_by_name || '',
        customer_po_number: d.customer_po_number || '',
        customer_buyer_name: d.customer_buyer_name || '',
        requested_by_contact_id: d.requested_by_contact_id || '',
        scheduled_start_at: d.scheduled_start_at ? d.scheduled_start_at.slice(0, 16) : '',
        scheduled_end_at: d.scheduled_end_at ? d.scheduled_end_at.slice(0, 16) : '',
        problem_description: d.problem_description || '',
        initial_findings: d.initial_findings || '',
        diagnosis: d.diagnosis || '',
        solution_applied: d.solution_applied || '',
        technician_notes: d.technician_notes || '',
        extra_notes: d.extra_notes || '',
        internal_notes: d.internal_notes || '',
        customer_visible_report: d.customer_visible_report || '',
        travel_distance_km: d.travel_distance_km || 0,
        travel_cost_per_km: d.travel_cost_per_km || 3.5,
        technician_count_for_travel: d.technician_count_for_travel || 1,
        travel_cost_total: d.travel_cost_total || 0,
        travel_hours: d.travel_hours || 0,
        ferry_cost: d.ferry_cost || 0,
        travel_type: (d.travel_type as any) || 'comercial',
        is_travel_billable: (d as any).is_travel_billable !== false,
        discount_amount: d.discount_amount || 0,
        tax_amount: d.tax_amount || 0,
        subcontract_cost_total: d.subcontract_cost_total || 0,
        commission_rate: d.commission_rate || 0,
        commission_amount: d.commission_amount || 0,
        commissioned_person: d.commissioned_person || '',
        commissioned_user_id: d.commissioned_user_id || '',
        payment_conditions: d.payment_conditions || '',
        payment_condition_preset_id: d.payment_condition_preset_id || '',
        custom_payment_installments: (d as any).custom_payment_installments || null,
        financial_notes: d.financial_notes || '',
        payment_method_preferred: d.payment_method_preferred || '',
        quote_validity_days: d.quote_validity_days ?? defaultQuoteValidityDays,
        card_installments: (d as any).card_installments || 1,
        card_fee_passthrough_enabled: (d as any).card_fee_passthrough_enabled || false,
        signed_at: d.signed_at || '',
      });
      if ((d as any).card_installments) setSelectedInstallments((d as any).card_installments);
      if (d.service_order_technicians) {
        setSelectedTechnicians(d.service_order_technicians.map((t: any) => t.user_id));
      }
      setDiscountServicesPct(Number(d.discount_services_pct) || 0);
      setDiscountPartsPct(Number(d.discount_parts_pct) || 0);
      // Open extra fields if any has content
      if (d.initial_findings || d.diagnosis || d.solution_applied || d.internal_notes || d.customer_visible_report || d.extra_notes) {
        setExtraFieldsOpen(true);
      }
    }
  }, [orderData]);

  const set = (field: string, value: any) => setForm((p) => ({ ...p, [field]: value }));

  // Filter vessels by client
  const clientVessels = allVessels?.filter((v) => v.client_id === form.client_id) || [];

  // Auto-select single vessel
  useEffect(() => {
    if (form.client_id && clientVessels.length === 1 && !form.vessel_id) {
      set('vessel_id', clientVessels[0].id);
      if (clientVessels[0].marina_id) set('marina_id', clientVessels[0].marina_id);
    }
  }, [form.client_id, clientVessels.length]);

  // Auto displacement
  const runDisplacement = useCallback(async () => {
    const marina = marinas?.find((m) => m.id === form.marina_id);
    if (!marina?.latitude || !marina?.longitude) return;
    try {
      const result = await calculateDisplacement(
        Number(marina.latitude),
        Number(marina.longitude),
        form.technician_count_for_travel
      );
      set('travel_distance_km', result.distance_km);
      set('travel_cost_per_km', result.cost_per_km);
      set('travel_cost_total', result.total_cost);
    } catch (e) {
      console.error('Displacement calc failed', e);
    }
  }, [form.marina_id, form.technician_count_for_travel, marinas]);

  // Financial summary — matemática extraída para o módulo puro os-financials
  // (Fase 3 UI v2: os testes de paridade pinam este comportamento).
  const laborCost = orderData?.labor_cost_total || 0;
  const partsCost = orderData?.parts_cost_total || 0;
  const operationalCost = orderData?.operational_cost_total || 0;
  const selectedPreset = (paymentPresets || []).find(
    (p: any) =>
      p.id === form.payment_condition_preset_id ||
      (p.label === form.payment_conditions && !form.payment_condition_preset_id)
  );
  const customInstallments = (form as any).custom_payment_installments;
  // Fonte CRUA (preset ou custom) — o diálogo de sinal recebe sem normalizar.
  const installmentSource = Array.isArray(selectedPreset?.installments)
    ? selectedPreset!.installments
    : (Array.isArray(customInstallments) ? customInstallments : null);
  const installmentRows = normalizeInstallmentRows(installmentSource);
  const {
    billableTravelCost, expensesTotal, subtotal, base,
    passthroughFeePercent, passthroughCardFeeAmount, grandTotal, discountRatio,
  } = computeOsFinancials({
    laborCost,
    partsCost,
    operationalCost,
    travelCost: form.travel_cost_total || 0,
    isTravelBillable: form.is_travel_billable !== false,
    subcontractCost: form.subcontract_cost_total || 0,
    discountAmount: form.discount_amount || 0,
    taxAmount: form.tax_amount || 0,
    cardFeePassthroughEnabled: !!form.card_fee_passthrough_enabled,
    cardInstallments: form.card_installments,
    cardFees,
  });

  const calcInstallmentAmount = (row: typeof installmentRows[0]) =>
    calcInstallmentAmountPure(row, { laborCost, partsCost, expensesTotal, discountRatio });

  // Sinal (deposit) row from preset — first installment with tipo='aprovacao' or days=0
  const signalRow = findSignalRow(installmentRows);
  const signalAmount = signalRow ? calcInstallmentAmount(signalRow) : null;

  // Simulador de Recebimento — preview livre de qualquer parcelamento, independente do que
  // está de fato marcado para repasse (form.card_installments/card_fee_passthrough_enabled).
  const selectedFee = cardFees?.find((f) => f.installments === selectedInstallments);
  const feePercent = selectedFee?.fee_percent || 0;
  const { cardGross, cardFeeAmount, installmentValue } = simulateCardReceipt(base, Number(feePercent), selectedInstallments);

  // Desconto aplicado por item (serviço/peça) — separado do desconto de categoria.
  const itemDiscountTotal = computeItemDiscountTotal(soServices as any, parts as any);

  // Parts profit (edit-mode only, never in PDF)
  const { partsRevenue, partsProfit, partsMarginPct } = computePartsProfit(parts as any);

  // Section subtotals
  const servicesItemCount = (soServices || []).length;
  const billableHours = orderData?.labor_hours_total || 0;
  const partsItemCount = (parts || []).length;

  // M1: Totais financeiros da OS a partir dos recebíveis reais
  const {
    totalCharged: soTotalCharged, totalPaid: soTotalPaid,
    balance: soBalance, payStatus: soPayStatus,
  } = computeReceivablesStatus(soReceivables as any);

  const handleSave = async () => {
    if (!form.client_id || !form.vessel_id || !form.problem_description) {
      toast.error('Preencha cliente, embarcação e descrição do problema');
      return;
    }
    try {
      const { signed_at: _signedAt, ...formForSave } = form;
      // Helper: convert empty string to null for UUID fields
      const uuidOrNull = (v: string | null | undefined) => (v && v.trim() !== '' ? v : null);

      const payload = {
        ...formForSave,
        scheduled_start_at: form.scheduled_start_at || null,
        scheduled_end_at: form.scheduled_end_at || null,
        commissioned_user_id: uuidOrNull(form.commissioned_user_id),
        requested_by_contact_id: uuidOrNull(form.requested_by_contact_id),
        marina_id: uuidOrNull(form.marina_id),
        payment_conditions: form.payment_conditions || null,
        payment_condition_preset_id: uuidOrNull(form.payment_condition_preset_id),
        // Always persist the computed grand_total so the PDF and receivables
        // always reflect the current discount/tax/travel/card fee values.
        grand_total: Math.round(grandTotal * 100) / 100,
        card_fee_amount: passthroughCardFeeAmount,
        discount_services_pct: discountServicesPct,
        discount_parts_pct: discountPartsPct,
        financial_notes: form.financial_notes || null,
        payment_method_preferred: form.payment_method_preferred || null,
        quote_validity_days: form.quote_validity_days || defaultQuoteValidityDays,
      };

      if (isNew) {
        const result = await createSO.mutateAsync(payload);
        const { supabase } = await import('@/integrations/supabase/client');
        const validTechs = selectedTechnicians.filter(uid => uid && uid.trim() !== '');
        if (validTechs.length > 0) {
          await supabase.from('service_order_technicians').insert(
            validTechs.map((uid) => ({ service_order_id: result.id, user_id: uid }))
          );
        }
        if (selectedTechnicians.length > 0) {
          for (const uid of selectedTechnicians) {
            if (!uid || uid.trim() === '') continue;
            supabase.functions.invoke('send-push-notification', {
              body: {
                user_id: uid,
                title: 'Nova OS atribuída',
                body: `Você foi atribuído à OS ${result.service_order_number ?? ''}`,
                url: `/service-orders/${result.id}`,
              },
            }).catch((e) => console.warn('push notify failed', e));
          }
        }
        // Persist any draft parts entered before the OS existed
        for (const dp of draftParts) {
          try {
            await addPart.mutateAsync({
              service_order_id: result.id,
              product_id: dp.product_id,
              quantity: dp.quantity,
              unit_cost_snapshot: dp.unit_cost,
              unit_sale_snapshot: dp.unit_sale,
              discount_pct: (dp as any).discount_pct || 0,
              discount_amount: (dp as any).discount_amount || 0,
            });
          } catch (err) {
            console.error('Failed to persist draft part', err);
          }
        }
        for (const ds of draftServices) {
          try {
            await addService.mutateAsync({
              service_order_id: result.id,
              service_id: ds.service_id || undefined,
              name_snapshot: ds.name_snapshot,
              description_snapshot: ds.description_snapshot || undefined,
              billing_unit_snapshot: ds.billing_unit_snapshot,
              quantity: ds.quantity,
              unit_price_snapshot: ds.unit_price_snapshot,
              notes: ds.notes || undefined,
              technician_user_id: (ds as any).technician_user_id || null,
              discount_pct: (ds as any).discount_pct || 0,
              discount_amount: (ds as any).discount_amount || 0,
            });
          } catch (err) {
            console.error('Failed to persist draft service', err);
          }
        }
        toast.success('Ordem de serviço criada com sucesso');
        navigate(`/service-orders/${result.id}`);
      } else {
        await updateSO.mutateAsync({ id: orderId!, ...payload });
        const { supabase } = await import('@/integrations/supabase/client');
        const { data: existingTechs } = await supabase
          .from('service_order_technicians')
          .select('user_id')
          .eq('service_order_id', orderId!);
        const existingIds = new Set((existingTechs ?? []).map((t: any) => t.user_id));
        await supabase.from('service_order_technicians').delete().eq('service_order_id', orderId!);
        const validTechs = selectedTechnicians.filter(uid => uid && uid.trim() !== '');
        if (validTechs.length > 0) {
          await supabase.from('service_order_technicians').insert(
            validTechs.map((uid) => ({ service_order_id: orderId!, user_id: uid }))
          );
        }
        if (selectedTechnicians.length > 0) {
          const newlyAssigned = selectedTechnicians.filter((uid) => !existingIds.has(uid));
          for (const uid of newlyAssigned) {
            if (!uid || uid.trim() === '') continue;
            supabase.functions.invoke('send-push-notification', {
              body: {
                user_id: uid,
                title: 'Nova OS atribuída',
                body: `Você foi atribuído à OS ${form.service_order_number ?? ''}`,
                url: `/service-orders/${orderId}`,
              },
            }).catch((e) => console.warn('push notify failed', e));
          }
        }
        toast.success('Ordem de serviço atualizada');

        // Audit log for financial field changes
        if (orderData) {
          const financialFields = ['discount_amount', 'tax_amount', 'grand_total', 'commission_rate', 'commission_amount'] as const;
          const changed: Record<string, { before: any; after: any }> = {};
          for (const f of financialFields) {
            const before = (orderData as any)[f];
            const after = (payload as any)[f] ?? (form as any)[f];
            if (before !== undefined && after !== undefined && Number(before) !== Number(after)) {
              changed[f] = { before, after };
            }
          }
          if (Object.keys(changed).length > 0) {
            writeAuditLog({
              table_name: 'service_orders',
              record_id: orderId!,
              action: 'update' as any,
              new_value: { financial_changes: changed },
              reason: 'Campos financeiros alterados manualmente',
            }).catch(() => {});
          }
        }

        // M4: gerar cobranças do saldo ao concluir (preset de parcelamento) — SEM auto-envio.
        // Na conclusão o aviso ao cliente é OPT-IN (prompt abaixo), nunca WhatsApp automático.
        if (form.status === 'completed' && form.payment_condition_preset_id) {
          const { generateCollectionsFromOS } = await import('@/lib/generate-collections');
          generateCollectionsFromOS({
            serviceOrderId: orderId!,
            approvalDate: new Date().toISOString().slice(0, 10),
            trigger: 'status_change',
            autoSend: false,
          })
            .then((res) => {
              if (res.created > 0) {
                toast.success(`${res.created} cobrança(s) do saldo registrada(s).`);
              }
            })
            .catch((err) => console.error('auto-generate-collections (completed) failed', err));
        }

        // (O prompt opt-in de conclusão fica no handleStatusChange — onde a conclusão realmente
        // acontece via o seletor de status. Aqui, no salvar, ele não caberia.)

        // Auto-trigger collection generation when status becomes 'invoiced'
        if (form.status === 'invoiced') {
          const { generateCollectionsFromOS } = await import('@/lib/generate-collections');
          generateCollectionsFromOS({
            serviceOrderId: orderId!,
            approvalDate: new Date().toISOString().slice(0, 10),
            trigger: 'invoice',
          })
            .then((res) => {
              if (res.created > 0) {
                toast.success(`${res.created} cobrança(s) gerada(s) automaticamente.`);
              }
            })
            .catch((err) => console.error('auto-generate-collections (invoice) failed', err));
        }
      }
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar');
    }
  };

  // Onda 2 — aplica um desconto % em lote a todas as linhas de serviço e/ou peça
  // existentes na OS, escrevendo discount_pct diretamente em cada linha (que já
  // recalcula seu line_total). Atualiza todas as linhas primeiro e só então chama
  // recalcTotals uma única vez, evitando corrida de múltiplos recalcs em paralelo.
  const applyBulkLineDiscount = async (target: 'services' | 'parts' | 'both', pct: number) => {
    setDiscountServicesPct(target === 'services' || target === 'both' ? pct : discountServicesPct);
    setDiscountPartsPct(target === 'parts' || target === 'both' ? pct : discountPartsPct);

    // Linhas ainda não salvas (OS nova) — só ajusta o estado local.
    if (target === 'services' || target === 'both') {
      setDraftServices((prev) => prev.map((s) => ({
        ...s,
        discount_pct: pct,
        discount_amount: Math.round(s.quantity * s.unit_price_snapshot * pct / 100 * 100) / 100,
      })));
    }
    if (target === 'parts' || target === 'both') {
      setDraftParts((prev) => prev.map((p) => ({
        ...p,
        discount_pct: pct,
        discount_amount: Math.round(p.quantity * p.unit_sale * pct / 100 * 100) / 100,
      })));
    }

    if (!orderId) return; // OS ainda não existe — nada para persistir no banco

    // Snapshot dos campos alterados antes de gravar — necessário para
    // reverter todas as linhas caso o novo total fique abaixo do já pago.
    const svcBefore = (target === 'services' || target === 'both') && soServices
      ? soServices.map((s: any) => ({ id: s.id, discount_pct: s.discount_pct, discount_amount: s.discount_amount, line_total: s.line_total }))
      : [];
    const partBefore = (target === 'parts' || target === 'both') && parts
      ? parts.map((p: any) => ({ id: p.id, discount_pct: p.discount_pct, discount_amount: p.discount_amount, line_total_sale: p.line_total_sale }))
      : [];

    try {
      if ((target === 'services' || target === 'both') && soServices && soServices.length > 0) {
        await Promise.all(soServices.map((s: any) => {
          const raw = Number(s.quantity) * Number(s.unit_price_snapshot);
          const discount_amount = Math.round(raw * pct / 100 * 100) / 100;
          const line_total = Math.round((raw - discount_amount) * 100) / 100;
          return supabase.from('service_order_services')
            .update({ discount_pct: pct, discount_amount, line_total } as any)
            .eq('id', s.id);
        }));
      }
      if ((target === 'parts' || target === 'both') && parts && parts.length > 0) {
        await Promise.all(parts.map((p: any) => {
          const raw = Number(p.quantity) * Number(p.unit_sale_snapshot);
          const discount_amount = Math.round(raw * pct / 100 * 100) / 100;
          const line_total_sale = Math.round((raw - discount_amount) * 100) / 100;
          return supabase.from('service_order_parts')
            .update({ discount_pct: pct, discount_amount, line_total_sale } as any)
            .eq('id', p.id);
        }));
      }
      try {
        await recalcTotals(orderId);
      } catch (e) {
        await Promise.all([
          ...svcBefore.map((b) => supabase.from('service_order_services').update(b).eq('id', b.id)),
          ...partBefore.map((b) => supabase.from('service_order_parts').update(b).eq('id', b.id)),
        ]);
        await recalcTotals(orderId).catch(() => {});
        throw e;
      }
      queryClient.invalidateQueries({ queryKey: ['so-services', orderId] });
      queryClient.invalidateQueries({ queryKey: ['so-parts', orderId] });
      queryClient.invalidateQueries({ queryKey: ['service-orders', orderId] });
      queryClient.invalidateQueries({ queryKey: ['pdf-data'] });
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao aplicar desconto em lote');
    }
  };

  const handleStatusChange = async (newStatus: string) => {
    if (!orderId) return;
    try {
      await updateStatus.mutateAsync({ id: orderId, status: newStatus });
      toast.success(`Status alterado para ${(t.status as Record<string, string>)[newStatus]}`);

      // Deposit alert: when completing/invoicing, check if a deposit was already paid
      if (newStatus === 'completed' || newStatus === 'invoiced') {
        const { data: deposits } = await (await import('@/integrations/supabase/client')).supabase
          .from('receivables')
          .select('paid_amount')
          .eq('service_order_id', orderId)
          .eq('is_deposit', true)
          .eq('status', 'paid');

        const totalDeposit = (deposits || []).reduce((sum, r) => sum + (r.paid_amount || 0), 0);
        if (totalDeposit > 0) {
          const fmt = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(totalDeposit);
          toast.info(`Sinal de ${fmt} já foi recebido. Lembre-se de descontar no valor da cobrança final.`, { duration: 8000 });
        }
      }

      // Conclusão → prompt OPT-IN para avisar o cliente (serviço concluído + saldo). A mutation
      // acima já criou os recebíveis da conclusão e o trigger ajustou os vencimentos "na entrega",
      // então o saldo/vencimento lidos aqui já vêm certos. Só abre quando há saldo em aberto.
      if (newStatus === 'completed') {
        try {
          const [{ data: recRows }, cliRes] = await Promise.all([
            supabase.from('receivables')
              .select('balance_amount, due_date, is_deposit, status')
              .eq('service_order_id', orderId)
              .neq('status', 'cancelled'),
            form.client_id
              ? supabase.from('clients').select('name, whatsapp, phone').eq('id', form.client_id).maybeSingle()
              : Promise.resolve({ data: null } as { data: any }),
          ]);
          const pend = (recRows || []).filter((r: any) => !r.is_deposit && r.status !== 'paid');
          const outstanding = pend.reduce((s: number, r: any) => s + Number(r.balance_amount || 0), 0);
          if (outstanding > 0.009) {
            const dueRow = pend.slice().sort((a: any, b: any) =>
              String(a.due_date).localeCompare(String(b.due_date)))[0];
            const cli = (cliRes as any).data;
            setCompletionSend({
              open: true,
              balance: Math.round(outstanding * 100) / 100,
              dueDate: dueRow?.due_date ?? null,
              clientName: cli?.name ?? null,
              clientPhone: cli?.whatsapp || cli?.phone || null,
            });
          }
        } catch (err) {
          console.error('completion prompt prep failed', err);
        }
      }
    } catch (e: any) {
      toast.error(e.message || 'Erro ao alterar status');
    }
  };

  const handleDuplicate = async () => {
    if (!orderId) return;
    try {
      // In the form context, replicate the same type as the source:
      // draft → quote (ORÇ), anything else → order (OS)
      const mode = orderData?.status === 'draft' ? 'quote' : 'order';
      const newSO = await duplicate.mutateAsync({ sourceId: orderId, mode });
      toast.success(mode === 'quote' ? 'Orçamento duplicado!' : 'OS duplicada com sucesso!');
      navigate(`/service-orders/${(newSO as any).id}`);
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao duplicar');
    }
  };

  // Ensure the product exists in the catalog. If product_id is empty,
  // create a new entry in `products` and return the new id.
  const ensureProductInCatalog = async (draft: PartCardDraft): Promise<string> => {
    if (draft.product_id) return draft.product_id;
    const { data, error } = await supabase
      .from('products')
      .insert({
        name: draft.name,
        cost_price: draft.unit_cost,
        sale_price: draft.unit_sale,
        unit: draft.unit || 'un',
        active: true,
        fiscal_complete: false,
        stock_quantity: 0,
        minimum_stock: 0,
        cost_currency: 'BRL',
        sale_currency: 'BRL',
      } as any)
      .select('id')
      .single();
    if (error) throw error;
    queryClient.invalidateQueries({ queryKey: ['products'] });
    return data.id as string;
  };

  const addNewPartCard = () => {
    const key = `new-${crypto.randomUUID()}`;
    setEditingPart((prev) => ({ ...prev, [key]: emptyPartCard() }));
    setOpenNewPartCards((prev) => [...prev, key]);
  };

  const cancelPartCard = (key: string, isNewCard: boolean) => {
    setEditingPart((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
    if (isNewCard) {
      setOpenNewPartCards((prev) => prev.filter((k) => k !== key));
    }
  };

  const startEditPersistedPart = (row: any) => {
    setEditingPart((prev) => ({
      ...prev,
      [row.id]: {
        product_id: row.product_id || '',
        name: row.products?.name || '',
        unit: row.products?.unit || 'un',
        quantity: Number(row.quantity) || 1,
        unit_cost: Number(row.unit_cost_snapshot) || 0,
        unit_sale: Number(row.unit_sale_snapshot) || 0,
        notes: row.notes || '',
        discount_pct: Number(row.discount_pct) || 0,
        discount_amount: Number(row.discount_amount) || 0,
      },
    }));
  };

  const handleConfirmNewPartCard = async (cardKey: string) => {
    const draft = editingPart[cardKey];
    if (!draft) return;
    if (!draft.name.trim() || draft.quantity <= 0) {
      toast.error('Preencha nome e quantidade');
      return;
    }
    try {
      const productId = await ensureProductInCatalog(draft);

      // Stock check: only for actual OS (non-draft). During the quote phase
      // the OS doesn't exist yet, so creating a PO at this point makes no sense —
      // the PO flow is triggered later at the moment of conversion (PurchaseNeedsDialog).
      if (!isNew && orderId && draft.quantity > 0 && orderData?.status !== 'draft') {
        // O embed é LEFT JOIN (sem `!inner`) de propósito: product_suppliers está vazia
        // em produção, e um `!inner` fazia o INNER JOIN eliminar o próprio produto do
        // resultado. prodData vinha null SEMPRE, available caía para 0 e o alerta de
        // falta disparava mesmo com o estoque cheio. Um embed só, trazendo lead_time_days
        // junto — os dois embeds da mesma relação também eram redundantes.
        const { data: prodData } = await (supabase as any)
          .from('products')
          .select('stock_quantity, reserved_quantity, minimum_stock, product_suppliers(supplier_id, lead_time_days, suppliers(id, name))')
          .eq('id', productId)
          .maybeSingle();
        // No modelo v2, disponível = físico − reservado (o físico não é pré-baixado por orçamentos).
        const v2 = await isStockModelV2();
        const available = v2
          ? ((prodData?.stock_quantity ?? 0) - ((prodData as any)?.reserved_quantity ?? 0))
          : (prodData?.stock_quantity ?? 0);
        if (available < draft.quantity) {
          const suppliers = ((prodData as any)?.product_suppliers ?? [])
            .map((ps: any) => ps.suppliers)
            .filter(Boolean)
            .map((s: any) => ({ id: s.id, name: s.name }));
          const leadTimeDays = (prodData as any)?.product_suppliers?.[0]?.lead_time_days ?? undefined;
          setStockAlert({
            cardKey: cardKey,
            productId,
            productName: draft.name,
            needed: draft.quantity,
            available: Math.max(0, available),
            unitCost: draft.unit_cost,
            unitSale: draft.unit_sale,
            notes: draft.notes,
            suppliers,
            leadTimeDays,
          });
          return; // pause — user chooses action in dialog
        }
      }

      if (isNew) {
        setDraftParts((prev) => [
          ...prev,
          {
            tempId: crypto.randomUUID(),
            product_id: productId,
            name: draft.name,
            quantity: draft.quantity,
            unit_cost: draft.unit_cost,
            unit_sale: draft.unit_sale,
            discount_pct: draft.discount_pct || 0,
            discount_amount: draft.discount_amount || 0,
          },
        ]);
        toast.success('Peça adicionada (será salva ao criar a OS)');
      } else {
        if (!orderId) return;
        await addPart.mutateAsync({
          service_order_id: orderId,
          product_id: productId,
          quantity: draft.quantity,
          unit_cost_snapshot: draft.unit_cost,
          unit_sale_snapshot: draft.unit_sale,
          notes: draft.notes || undefined,
          discount_pct: draft.discount_pct || 0,
          discount_amount: draft.discount_amount || 0,
        });
        toast.success('Peça adicionada');
      }
      setOpenNewPartCards((prev) => prev.filter((k) => k !== cardKey));
      setEditingPart((prev) => {
        const next = { ...prev };
        delete next[cardKey];
        return next;
      });
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar peça');
    }
  };

  const handleConfirmEditPart = async (rowId: string, originalRow: any) => {
    const draft = editingPart[rowId];
    if (!draft || !orderId) return;
    if (!draft.name.trim() || draft.quantity <= 0) {
      toast.error('Preencha nome e quantidade');
      return;
    }
    try {
      const productId = await ensureProductInCatalog(draft);
      await updatePartLine.mutateAsync({
        id: rowId,
        service_order_id: orderId,
        product_id: productId,
        previous_quantity: Number(originalRow.quantity) || 0,
        quantity: draft.quantity,
        unit_cost_snapshot: draft.unit_cost,
        unit_sale_snapshot: draft.unit_sale,
        notes: draft.notes || null,
        discount_pct: draft.discount_pct || 0,
        discount_amount: draft.discount_amount || 0,
      });
      setEditingPart((prev) => {
        const next = { ...prev };
        delete next[rowId];
        return next;
      });
      toast.success('Peça atualizada');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao atualizar peça');
    }
  };


  // Ensure the service exists in the catalog. If service_id is empty,
  // create a new entry in `services` and return the new id.
  const ensureServiceInCatalog = async (draft: SvcCardDraft): Promise<string> => {
    if (draft.service_id) return draft.service_id;
    const { data, error } = await supabase
      .from('services')
      .insert({
        name: draft.name_snapshot,
        default_price: draft.unit_price,
        billing_unit: draft.billing_unit_snapshot,
        active: true,
      } as any)
      .select('id')
      .single();
    if (error) throw error;
    queryClient.invalidateQueries({ queryKey: ['services'] });
    return data.id as string;
  };

  // Confirm a service card (insert new line on the OS)
  const handleConfirmNewSvcCard = async (cardKey: string) => {
    const draft = editingSvc[cardKey];
    if (!draft) return;
    if (!draft.name_snapshot.trim() || draft.quantity <= 0) {
      toast.error('Preencha descrição e quantidade');
      return;
    }
    try {
      let serviceId = draft.service_id;
      // For non-draft (persisted OS) we always sync catalog. For draft OS we
      // also create the catalog entry so it becomes reusable immediately.
      if (!serviceId) {
        serviceId = await ensureServiceInCatalog(draft);
      }
      if (isNew) {
        setDraftServices((prev) => [
          ...prev,
          {
            tempId: crypto.randomUUID(),
            service_id: serviceId || undefined,
            name_snapshot: draft.name_snapshot,
            description_snapshot: draft.description_snapshot || undefined,
            billing_unit_snapshot: draft.billing_unit_snapshot,
            quantity: draft.quantity,
            unit_price_snapshot: draft.unit_price,
            notes: draft.notes || undefined,
            warranty_months: draft.warranty_months || 0,
            discount_pct: draft.discount_pct || 0,
            discount_amount: draft.discount_amount || 0,
            // technician_user_id is held client-side until OS is created
            ...(draft.technician_user_id ? { technician_user_id: draft.technician_user_id } : {}),
          } as any,
        ]);
        toast.success('Serviço adicionado (será salvo ao criar a OS)');
      } else {
        if (!orderId) return;
        await addService.mutateAsync({
          service_order_id: orderId,
          service_id: serviceId || undefined,
          name_snapshot: draft.name_snapshot,
          description_snapshot: draft.description_snapshot || undefined,
          billing_unit_snapshot: draft.billing_unit_snapshot,
          quantity: draft.quantity,
          unit_price_snapshot: draft.unit_price,
          notes: draft.notes || undefined,
          technician_user_id: draft.technician_user_id || null,
          warranty_months: draft.warranty_months || 0,
          discount_pct: draft.discount_pct || 0,
          discount_amount: draft.discount_amount || 0,
        } as any);
        toast.success('Serviço adicionado');
      }
      // Close the card
      setOpenNewSvcCards((prev) => prev.filter((k) => k !== cardKey));
      setEditingSvc((prev) => {
        const next = { ...prev };
        delete next[cardKey];
        return next;
      });
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar serviço');
    }
  };

  // Confirm an edit on an existing persisted line
  const handleConfirmEditSvc = async (rowId: string) => {
    const draft = editingSvc[rowId];
    if (!draft || !orderId) return;
    if (!draft.name_snapshot.trim() || draft.quantity <= 0) {
      toast.error('Preencha descrição e quantidade');
      return;
    }
    try {
      let serviceId = draft.service_id;
      if (!serviceId) serviceId = await ensureServiceInCatalog(draft);
      await updateSvcLine.mutateAsync({
        id: rowId,
        service_order_id: orderId,
        service_id: serviceId || null,
        name_snapshot: draft.name_snapshot,
        description_snapshot: draft.description_snapshot || null,
        billing_unit_snapshot: draft.billing_unit_snapshot,
        quantity: draft.quantity,
        unit_price_snapshot: draft.unit_price,
        notes: draft.notes || null,
        technician_user_id: draft.technician_user_id || null,
        discount_pct: draft.discount_pct || 0,
        discount_amount: draft.discount_amount || 0,
      });
      setEditingSvc((prev) => {
        const next = { ...prev };
        delete next[rowId];
        return next;
      });
      toast.success('Serviço atualizado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao atualizar serviço');
    }
  };

  const addNewSvcCard = () => {
    const key = `new-${crypto.randomUUID()}`;
    setEditingSvc((prev) => ({ ...prev, [key]: emptySvcCard() }));
    setOpenNewSvcCards((prev) => [...prev, key]);
  };

  const cancelSvcCard = (key: string, isNewCard: boolean) => {
    setEditingSvc((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
    if (isNewCard) {
      setOpenNewSvcCards((prev) => prev.filter((k) => k !== key));
    }
  };

  const startEditPersisted = (row: any) => {
    setEditingSvc((prev) => ({
      ...prev,
      [row.id]: {
        service_id: row.service_id || '',
        name_snapshot: row.name_snapshot || '',
        description_snapshot: row.description_snapshot || '',
        billing_unit_snapshot: row.billing_unit_snapshot || 'hour',
        quantity: Number(row.quantity) || 1,
        unit_price: Number(row.unit_price_snapshot) || 0,
        notes: row.notes || '',
        technician_user_id: row.technician_user_id || '',
        discount_pct: Number(row.discount_pct) || 0,
        discount_amount: Number(row.discount_amount) || 0,
      },
    }));
  };

  // Atalho rápido de desconto na linha colapsada (sem abrir o card de edição inteiro).
  // Usa mutateAsync + try/catch para garantir que qualquer falha apareça pro usuário
  // (em vez de falhar silenciosamente, como aconteceu antes com o cache de schema desatualizado).
  const applyQuickDiscountToService = async (row: any, pct: number, discountAmount: number) => {
    if (!orderId) return;
    try {
      await updateSvcLine.mutateAsync({
        id: row.id,
        service_order_id: orderId,
        service_id: row.service_id || null,
        name_snapshot: row.name_snapshot,
        description_snapshot: row.description_snapshot || null,
        billing_unit_snapshot: row.billing_unit_snapshot,
        quantity: row.quantity,
        unit_price_snapshot: row.unit_price_snapshot,
        notes: row.notes || null,
        technician_user_id: row.technician_user_id || null,
        discount_pct: pct,
        discount_amount: discountAmount,
      });
      toast.success(pct > 0 ? `Desconto de ${pct}% aplicado` : 'Desconto removido');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao aplicar desconto');
    }
  };

  const applyQuickDiscountToPart = async (row: any, pct: number, discountAmount: number) => {
    if (!orderId) return;
    try {
      await updatePartLine.mutateAsync({
        id: row.id,
        service_order_id: orderId,
        product_id: row.product_id,
        previous_quantity: Number(row.quantity) || 0,
        quantity: row.quantity,
        unit_cost_snapshot: row.unit_cost_snapshot,
        unit_sale_snapshot: row.unit_sale_snapshot,
        notes: row.notes || null,
        discount_pct: pct,
        discount_amount: discountAmount,
      });
      toast.success(pct > 0 ? `Desconto de ${pct}% aplicado` : 'Desconto removido');
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao aplicar desconto');
    }
  };


  const handleAddTime = async () => {
    if (!orderId || !timeForm.technician_user_id || !timeForm.started_at) return;
    try {
      await addTime.mutateAsync({
        service_order_id: orderId,
        ...timeForm,
        ended_at: timeForm.ended_at || undefined,
      });
      setTimeForm({ technician_user_id: '', started_at: '', ended_at: '', duration_minutes: 0, billable: true, notes: '' });
      setShowTimeForm(false);
      toast.success('Registro de tempo adicionado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao registrar tempo');
    }
  };

  const resetExpForm = () => {
    setExpForm({
      category: '', description: '', amount: 0, currency: 'BRL',
      expense_date: new Date().toISOString().slice(0, 10),
      paid_by: 'company', technician_user_id: '', receipt_url: '', receipt_storage_path: '', notes: '',
      also_create_payable: false,
      supplier_id: '',
      billable_to_client: true,
    });
    setEditingExpenseId(null);
  };

  const handleEditExpense = (exp: any) => {
    setExpForm({
      category: exp.category || '',
      description: exp.description || '',
      amount: Number(exp.amount) || 0,
      currency: exp.currency || 'BRL',
      expense_date: exp.expense_date || new Date().toISOString().slice(0, 10),
      paid_by: (exp.paid_by as 'company' | 'technician') || 'company',
      technician_user_id: exp.technician_user_id || '',
      receipt_url: exp.receipt_url || '',
      receipt_storage_path: exp.receipt_storage_path || '',
      notes: exp.notes || '',
      also_create_payable: false,
      supplier_id: exp.supplier_id || '',
      billable_to_client: exp.billable_to_client !== false,
    });
    setEditingExpenseId(exp.id);
    setShowExpForm(true);
  };

  const handleUploadReceipt = async (file: File) => {
    if (!orderId) {
      toast.error('Salve a OS primeiro antes de anexar comprovantes');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      toast.error('Arquivo excede 5MB');
      return;
    }
    setUploadingReceipt(true);
    try {
      const ext = file.name.split('.').pop() || 'bin';
      const uuid = (crypto as any).randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const path = `expenses/${orderId}/${uuid}.${ext}`;
      const { error: upErr } = await supabase.storage
        .from('expense-receipts')
        .upload(path, file, { contentType: file.type, upsert: false });
      if (upErr) throw upErr;
      const { data: urlData } = supabase.storage.from('expense-receipts').getPublicUrl(path);
      setExpForm((prev) => ({ ...prev, receipt_url: urlData.publicUrl, receipt_storage_path: path }));
      toast.success('Comprovante anexado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao enviar comprovante');
    } finally {
      setUploadingReceipt(false);
      if (receiptInputRef.current) receiptInputRef.current.value = '';
    }
  };

  const handleRemoveReceipt = async () => {
    const path = expForm.receipt_storage_path;
    if (path) {
      try {
        await supabase.storage.from('expense-receipts').remove([path]);
      } catch {
        /* swallow — still clear form */
      }
    }
    setExpForm((prev) => ({ ...prev, receipt_url: '', receipt_storage_path: '' }));
  };

  const handleAddExpense = async () => {
    if (!orderId || !expForm.category || !expForm.description || expForm.amount <= 0) return;
    try {
      if (editingExpenseId) {
        await updateExpense.mutateAsync({
          id: editingExpenseId,
          service_order_id: orderId,
          category: expForm.category,
          description: expForm.description,
          amount: expForm.amount,
          currency: expForm.currency,
          expense_date: expForm.expense_date,
          paid_by: expForm.paid_by,
          technician_user_id: expForm.paid_by === 'technician' ? expForm.technician_user_id || null : null,
          receipt_url: expForm.receipt_url || null,
          receipt_storage_path: expForm.receipt_storage_path || null,
          supplier_id: expForm.supplier_id || null,
          notes: expForm.notes || null,
          billable_to_client: expForm.billable_to_client,
        });
        toast.success('Despesa atualizada');
      } else {
        await addExpense.mutateAsync({
          service_order_id: orderId,
          category: expForm.category,
          description: expForm.description,
          amount: expForm.amount,
          currency: expForm.currency,
          expense_date: expForm.expense_date,
          paid_by: expForm.paid_by,
          technician_user_id: expForm.paid_by === 'technician' ? expForm.technician_user_id || undefined : undefined,
          receipt_url: expForm.receipt_url || undefined,
          receipt_storage_path: expForm.receipt_storage_path || undefined,
          supplier_id: expForm.supplier_id || undefined,
          notes: expForm.notes || undefined,
          also_create_payable: expForm.also_create_payable,
          billable_to_client: expForm.billable_to_client,
        });
        toast.success('Despesa adicionada');
      }
      resetExpForm();
      setShowExpForm(false);
    } catch (e: any) {
      console.error('Erro ao salvar despesa:', e);
      toast.error(e?.message || e?.details || 'Erro ao salvar despesa');
    }
  };

  useEffect(() => {
    if (timeForm.started_at && timeForm.ended_at) {
      const start = new Date(timeForm.started_at).getTime();
      const end = new Date(timeForm.ended_at).getTime();
      if (end > start) {
        setTimeForm((p) => ({ ...p, duration_minutes: Math.round((end - start) / 60000) }));
      }
    }
  }, [timeForm.started_at, timeForm.ended_at]);

  if (isLoading) return <div className="space-y-4">{Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-20 w-full" />)}</div>;

  const currentStatus = form.status;
  const validTransitions = STATUS_TRANSITIONS[currentStatus] || [];
  const marina = marinas?.find((m) => m.id === form.marina_id);
  const isLocked = currentStatus === 'invoiced' || currentStatus === 'cancelled';

  const handleCancel = async () => {
    if (!orderId || cancelReason.length < 5) return;
    try {
      await cancelSO.mutateAsync({ id: orderId, reason: cancelReason });
      toast.success(t.serviceOrders.cancelSuccess);
      setShowCancelDialog(false);
      navigate('/service-orders');
    } catch (e: any) { toast.error(e.message); }
  };

  const handleReopen = async () => {
    if (!orderId || reopenReason.length < 5) return;
    try {
      await reopenSO.mutateAsync({ id: orderId, reason: reopenReason });
      toast.success(t.serviceOrders.reopenSuccess);
      setShowReopenDialog(false);
    } catch (e: any) { toast.error(e.message); }
  };

  return (
    <div className="space-y-6 animate-fade-in max-w-5xl">
      {/* Invoiced lock banner */}
      {isLocked && !isNew && (
        <div className="flex items-center justify-between rounded-lg border border-amber-200 bg-amber-50 p-4">
          <div className="flex items-center gap-2">
            <Lock className="h-5 w-5 text-amber-600" />
            <span className="text-sm font-medium text-amber-800">{t.serviceOrders.osLocked}</span>
          </div>
          {currentStatus === 'invoiced' && (
            <Button variant="outline" size="sm" onClick={() => setShowReopenDialog(true)}>
              <RotateCcw className="h-4 w-4 mr-1" /> {t.serviceOrders.reopenOS}
            </Button>
          )}
        </div>
      )}

      {/* Deposit pending banner */}
      {!isNew && (orderData as any)?.quote_status === 'awaiting_deposit' && form.status === 'draft' && (
        <div className="flex items-center justify-between rounded-lg border border-orange-200 bg-orange-50 p-4">
          <div className="flex items-center gap-2">
            <DollarSign className="h-5 w-5 text-orange-600 shrink-0" />
            <div>
              <p className="text-sm font-medium text-orange-800">Aguardando pagamento do sinal</p>
              <p className="text-xs text-orange-600 mt-0.5">O orçamento será convertido em OS automaticamente após o registro.</p>
            </div>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="border-orange-300 text-orange-700 hover:bg-orange-100 gap-1 shrink-0"
            onClick={() => setDepositDialogOpen(true)}
          >
            <DollarSign className="h-4 w-4" /> Registrar sinal
          </Button>
        </div>
      )}

      {/* Deposit dialog */}
      {!isNew && orderId && (
        <RegisterDepositDialog
          open={depositDialogOpen}
          onOpenChange={v => { setDepositDialogOpen(v); if (!v) setDepositFromFinancial(false); }}
          serviceOrderId={orderId}
          serviceOrderNumber={orderData?.service_order_number || ''}
          grandTotal={grandTotal}
          laborCost={laborCost}
          partsCost={partsCost}
          discountRatio={discountRatio}
          expensesTotal={expensesTotal}
          presetServicesPct={depositFromFinancial && signalRow ? signalRow.services_pct : undefined}
          presetPartsPct={depositFromFinancial && signalRow ? signalRow.parts_pct : undefined}
          presetExpensesPct={depositFromFinancial && signalRow ? signalRow.expenses_pct : undefined}
          appliedConditionLabel={form.payment_conditions || ''}
          installments={installmentSource ?? undefined}
          scheduledEndAt={form.scheduled_end_at || null}
        />
      )}

      {/* Prompt opt-in de conclusão (avisar cliente + saldo) */}
      {!isNew && orderId && (
        <CompletionSendDialog
          open={completionSend.open}
          onOpenChange={v => setCompletionSend(prev => ({ ...prev, open: v }))}
          serviceOrderId={orderId}
          osNumber={orderData?.service_order_number || ''}
          clientName={completionSend.clientName}
          clientPhone={completionSend.clientPhone}
          balance={completionSend.balance}
          dueDate={completionSend.dueDate}
        />
      )}

      {/* Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <Button variant="ghost" size="icon" onClick={() => navigate('/service-orders')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1 min-w-0">
          <h1 className="text-2xl font-bold truncate">
            {isNew ? t.serviceOrders.newOrder : orderData?.service_order_number}
          </h1>
          {!isNew && (
            <div className="flex items-center gap-2 mt-1">
              <StatusBadge className={statusConfig[currentStatus]?.className || ''}>
                {(t.status as Record<string, string>)[currentStatus]}
              </StatusBadge>
              <span className={priorityConfig[form.priority]?.className || ''}>
                {(t.priority as Record<string, string>)[form.priority]}
              </span>
              {lastWaSend && (
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        type="button"
                        onClick={() => setShowZapiHistory(true)}
                        className="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs hover:bg-muted transition-colors"
                        aria-label="Ver histórico de envios WhatsApp"
                      >
                        {lastWaSend.success ? (
                          <CheckCircle2 className="h-3.5 w-3.5 text-success" />
                        ) : (
                          <XCircle className="h-3.5 w-3.5 text-destructive" />
                        )}
                        <span className={lastWaSend.success ? 'text-success' : 'text-destructive'}>
                          WhatsApp: {lastWaSend.success ? 'enviado' : 'falhou'}
                        </span>
                        <HistoryIcon className="h-3 w-3 text-muted-foreground" />
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="bottom" className="max-w-xs">
                      <div className="text-xs space-y-1">
                        <div className="font-medium">
                          Último envio: {new Date(lastWaSend.changed_at).toLocaleString('pt-BR')}
                        </div>
                        {!lastWaSend.success && (
                          <div className="text-destructive">
                            {(lastWaSend.new_value as any)?.provider_result?.error
                              || (lastWaSend.new_value as any)?.zapi_response?.error
                              || lastWaSend.reason
                              || `HTTP ${(lastWaSend.new_value as any)?.http_status ?? '?'}`}
                          </div>
                        )}
                        <div className="text-muted-foreground italic">Clique para ver histórico completo</div>
                      </div>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              )}
            </div>
          )}
        </div>
        <div ref={topActionsRef} className="flex gap-2 flex-wrap">
          {!isNew && (
            <>
              <Button variant="outline" size="sm" onClick={() => openPdfDialog('quote')} className="gap-1">
                <FileText className="h-4 w-4" />
                {t.pdf.quote}
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => handleDirectDownload('quote')}
                disabled={!pdfData || downloadingType === 'quote'}
                title="Baixar Orçamento em PDF"
                className="gap-1"
              >
                {downloadingType === 'quote' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                Baixar
              </Button>
              <Button variant="outline" size="sm" onClick={() => openPdfDialog('service_order')} className="gap-1">
                <Printer className="h-4 w-4" />
                OS
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => handleDirectDownload('service_order')}
                disabled={!pdfData || downloadingType === 'service_order'}
                title="Baixar OS em PDF"
                className="gap-1"
              >
                {downloadingType === 'service_order' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                Baixar
              </Button>
              {(currentStatus === 'completed' || currentStatus === 'invoiced') && (
                <>
                  <Button variant="outline" size="sm" onClick={() => openPdfDialog('invoice')} className="gap-1">
                    <Receipt className="h-4 w-4" />
                    Fatura
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleDirectDownload('invoice')}
                    disabled={!pdfData || downloadingType === 'invoice'}
                    title="Baixar Fatura em PDF"
                    className="gap-1"
                  >
                    {downloadingType === 'invoice' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                    Baixar
                  </Button>
                </>
              )}
              {orderData?.share_token && (
                <Button
                  variant="outline"
                  size="sm"
                  className="gap-1 border-green-600 text-green-700 hover:bg-green-50 hover:text-green-800 dark:hover:bg-green-950"
                  onClick={() => {
                    const url = `${window.location.origin}/view/${orderData.share_token}`;
                    const phoneRaw = (orderData?.clients as any)?.whatsapp || (orderData?.clients as any)?.phone || '';
                    const phone = normalizePhoneE164(phoneRaw);
                    const clientName = (orderData?.clients as any)?.name || '';
                    const msg = `Olá${clientName ? ' ' + clientName : ''}, segue o link da Ordem de Serviço ${orderData.service_order_number}: ${url}`;
                    setWaEditPhone(phone);
                    setWaEditMessage(msg);
                    setWaPreview({ phone, message: msg, url, clientName });
                    void writeAuditLog({
                      table_name: 'service_orders',
                      record_id: orderData.id,
                      action: 'whatsapp_preview' as any,
                      new_value: {
                        share_token: orderData.share_token,
                        public_url: url,
                        phone_raw: String(phoneRaw),
                        phone_normalized: phone,
                        client_name: clientName,
                      },
                      reason: 'Abriu pré-visualização do WhatsApp',
                    });
                    recordWhatsAppEvent({
                      source: 'detail_dialog',
                      action: 'preview',
                      serviceOrderId: orderData.id,
                      serviceOrderNumber: orderData.service_order_number,
                      shareToken: orderData.share_token,
                      phoneRaw: String(phoneRaw),
                      phoneNormalized: phone,
                    });
                  }}
                >
                  <MessageCircle className="h-4 w-4" />
                  WhatsApp
                </Button>
              )}
              {orderData?.share_token && (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button
                      variant="outline"
                      size="sm"
                      className="gap-1 border-accent text-accent hover:bg-accent/10"
                    >
                      <Send className="h-4 w-4" />
                      Enviar WhatsApp
                      <ChevronDown className="h-3 w-3 opacity-60" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem
                      onClick={() => setWhatsAppTarget({
                        kind: 'service_order',
                        serviceOrderId: orderData.id,
                        serviceOrderNumber: orderData.service_order_number,
                        shareToken: orderData.share_token,
                        clientId: (orderData?.clients as any)?.id || (orderData as any)?.client_id || null,
                        clientName: (orderData?.clients as any)?.name || null,
                        clientPhone: (orderData?.clients as any)?.whatsapp || (orderData?.clients as any)?.phone || null,
                        documentType: 'service_order',
                      })}
                    >
                      <Printer className="h-4 w-4 mr-2" /> Enviar OS
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      onClick={() => setWhatsAppTarget({
                        kind: 'service_order',
                        serviceOrderId: orderData.id,
                        serviceOrderNumber: orderData.service_order_number,
                        shareToken: orderData.share_token,
                        clientId: (orderData?.clients as any)?.id || (orderData as any)?.client_id || null,
                        clientName: (orderData?.clients as any)?.name || null,
                        clientPhone: (orderData?.clients as any)?.whatsapp || (orderData?.clients as any)?.phone || null,
                        documentType: 'quote',
                      })}
                    >
                      <FileText className="h-4 w-4 mr-2" /> Enviar Orçamento
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
              <Button
                variant="outline"
                size="sm"
                onClick={handleDuplicate}
                disabled={isNew || duplicate.isPending}
                className="gap-1"
              >
                <Copy className="h-4 w-4" />
                Duplicar
              </Button>
            </>
          )}
          {!isNew && !isLocked && currentStatus !== 'cancelled' && (
            <Button variant="outline" size="sm" className="text-destructive" onClick={() => setShowCancelDialog(true)}>
              <Ban className="h-4 w-4 mr-1" /> {t.serviceOrders.cancelOS}
            </Button>
          )}
          {!isNew && !isLocked && validTransitions.length > 0 && (
            <Select value={currentStatus} onValueChange={handleStatusChange}>
              <SelectTrigger className="w-[200px]">
                <SelectValue>
                  <span className="text-muted-foreground text-xs mr-1">Status:</span>
                  <span className="font-medium">{(t.status as Record<string, string>)[currentStatus]}</span>
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={currentStatus} disabled className="opacity-60">
                  {(t.status as Record<string, string>)[currentStatus]} (atual)
                </SelectItem>
                {validTransitions.map((s) => (
                  <SelectItem key={s} value={s}>
                    → {(t.status as Record<string, string>)[s]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          {!isLocked && (
            <Button onClick={handleSave} disabled={createSO.isPending || updateSO.isPending}
              className="bg-accent text-accent-foreground hover:bg-accent/90">
              {t.common.save}
            </Button>
          )}
        </div>
      </div>

      {/* Cancel Dialog */}
      <Dialog open={showCancelDialog} onOpenChange={setShowCancelDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>{t.serviceOrders.cancelOS}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3">
              <AlertTriangle className="h-5 w-5 text-destructive shrink-0 mt-0.5" />
              <p className="text-sm">{t.serviceOrders.cancelWarning}</p>
            </div>
            <div>
              <Label>{t.serviceOrders.cancelReason}</Label>
              <Textarea value={cancelReason} onChange={e => setCancelReason(e.target.value)} placeholder="..." />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setShowCancelDialog(false)}>{t.common.cancel}</Button>
              <Button variant="destructive" onClick={handleCancel} disabled={cancelReason.length < 5 || cancelSO.isPending}>
                {t.serviceOrders.confirmCancel}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reopen Dialog */}
      <Dialog open={showReopenDialog} onOpenChange={setShowReopenDialog}>
        <DialogContent>
          <DialogHeader><DialogTitle>{t.serviceOrders.reopenOS}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3">
              <AlertTriangle className="h-5 w-5 text-amber-600 shrink-0 mt-0.5" />
              <p className="text-sm">{t.serviceOrders.reopenWarning}</p>
            </div>
            <div>
              <Label>{t.serviceOrders.reopenReason}</Label>
              <Textarea value={reopenReason} onChange={e => setReopenReason(e.target.value)} placeholder="..." />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setShowReopenDialog(false)}>{t.common.cancel}</Button>
              <Button onClick={handleReopen} disabled={reopenReason.length < 5 || reopenSO.isPending}>
                {t.serviceOrders.confirmReopen}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <GeneralSections
        isNew={isNew}
        isLocked={isLocked}
        orderData={orderData}
        form={form}
        set={set}
        setForm={setForm}
        clients={clients}
        allVessels={allVessels}
        clientVessels={clientVessels}
        marinas={marinas}
        appUsers={appUsers}
        vesselContacts={vesselContacts}
        selectedTechnicians={selectedTechnicians}
        setSelectedTechnicians={setSelectedTechnicians}
        setQuickMarinaOpen={setQuickMarinaOpen}
        setQuickMarinaName={setQuickMarinaName}
        isOptimizing={isOptimizing}
        optimizeText={optimizeText}
        onAnalisarDescricao={analisarDescricao}
        analisandoDescricao={analisando}
      />

      <DescriptionAnalysisDialog
        open={analiseAberta}
        onOpenChange={setAnaliseAberta}
        analise={analise}
        salvando={gravandoAnalise}
        onConfirmar={gravarAnaliseComoLevantamento}
      />

      <ServicesSection
        isNew={isNew}
        orderId={orderId}
        services={services}
        soServices={soServices}
        appUsers={appUsers}
        servicesItemCount={servicesItemCount}
        laborCost={laborCost}
        billableHours={billableHours}
        draftServices={draftServices}
        setDraftServices={setDraftServices}
        editingSvc={editingSvc}
        setEditingSvc={setEditingSvc}
        openNewSvcCards={openNewSvcCards}
        setOpenNewSvcCards={setOpenNewSvcCards}
        setShowNewServiceDialog={setShowNewServiceDialog}
        addNewSvcCard={addNewSvcCard}
        cancelSvcCard={cancelSvcCard}
        handleConfirmNewSvcCard={handleConfirmNewSvcCard}
        handleConfirmEditSvc={handleConfirmEditSvc}
        startEditPersisted={startEditPersisted}
        applyQuickDiscountToService={applyQuickDiscountToService}
        updateSvcLine={updateSvcLine}
        removeService={removeService}
        addService={addService}
      />

      {/* New Service Dialog */}
      <ServiceFormDialog open={showNewServiceDialog} onOpenChange={setShowNewServiceDialog} />

      <TravelDialog
        isNew={isNew}
        form={form}
        set={set}
        marina={marina}
        travelRates={travelRates}
        manualTravel={manualTravel}
        setManualTravel={setManualTravel}
        showTravelDialog={showTravelDialog}
        setShowTravelDialog={setShowTravelDialog}
        calcTravelCost={calcTravelCost}
        runDisplacement={runDisplacement}
      />

      <PartsSection
        isNew={isNew}
        orderId={orderId}
        orderData={orderData}
        parts={parts}
        products={products}
        partsItemCount={partsItemCount}
        partsRevenue={partsRevenue}
        partsProfit={partsProfit}
        partsMarginPct={partsMarginPct}
        draftParts={draftParts}
        setDraftParts={setDraftParts}
        editingPart={editingPart}
        setEditingPart={setEditingPart}
        openNewPartCards={openNewPartCards}
        setOpenNewPartCards={setOpenNewPartCards}
        setPriceCalcCardKey={setPriceCalcCardKey}
        addNewPartCard={addNewPartCard}
        cancelPartCard={cancelPartCard}
        handleConfirmNewPartCard={handleConfirmNewPartCard}
        handleConfirmEditPart={handleConfirmEditPart}
        startEditPersistedPart={startEditPersistedPart}
        applyQuickDiscountToPart={applyQuickDiscountToPart}
        updatePartLine={updatePartLine}
        removePart={removePart}
        addPart={addPart}
      />

      {/* O que costuma entrar junto com o que já foi lançado, medido no
          histórico da casa. Fica logo abaixo das peças porque é ali que se
          percebe a falta — proteção e acessório são o que mais sai do
          orçamento por descuido e volta como prejuízo. */}
      <RelatedMaterialsPanel serviceOrderId={orderId} />

      <ExpensesTimeDialogs
        isNew={isNew}
        orderId={orderId}
        showExpensesDialog={showExpensesDialog}
        setShowExpensesDialog={setShowExpensesDialog}
        showTimeDialog={showTimeDialog}
        setShowTimeDialog={setShowTimeDialog}
        showExpForm={showExpForm}
        setShowExpForm={setShowExpForm}
        showTimeForm={showTimeForm}
        setShowTimeForm={setShowTimeForm}
        expForm={expForm}
        setExpForm={setExpForm}
        timeForm={timeForm}
        setTimeForm={setTimeForm}
        editingExpenseId={editingExpenseId}
        resetExpForm={resetExpForm}
        handleAddExpense={handleAddExpense}
        handleAddTime={handleAddTime}
        handleEditExpense={handleEditExpense}
        handleUploadReceipt={handleUploadReceipt}
        handleRemoveReceipt={handleRemoveReceipt}
        uploadingReceipt={uploadingReceipt}
        receiptInputRef={receiptInputRef}
        soExpenses={soExpenses}
        timeEntries={timeEntries}
        suppliers={suppliers}
        appUsers={appUsers}
        addExpense={addExpense}
        addTime={addTime}
        removeExpense={removeExpense}
        removeTime={removeTime}
        updateExpense={updateExpense}
        setQuickSupplierOpen={setQuickSupplierOpen}
        setQuickSupplierName={setQuickSupplierName}
      />

      <SummarySections
        isNew={isNew}
        orderId={orderId}
        orderData={orderData}
        form={form}
        clientView={clientView}
        setClientView={setClientView}
        linkedPOs={linkedPOs}
        updatePO={updatePO}
        setReceivePOTarget={setReceivePOTarget}
        laborCost={laborCost}
        partsCost={partsCost}
        subtotal={subtotal}
        grandTotal={grandTotal}
        partsRevenue={partsRevenue}
        partsProfit={partsProfit}
        partsMarginPct={partsMarginPct}
        soReceivables={soReceivables}
        soPayments={soPayments}
        soTotalCharged={soTotalCharged}
        soTotalPaid={soTotalPaid}
        soBalance={soBalance}
        soPayStatus={soPayStatus}
        showPaymentHistory={showPaymentHistory}
        setShowPaymentHistory={setShowPaymentHistory}
        setPaymentDialogReceivable={setPaymentDialogReceivable}
        createReceivable={createReceivable}
        showFinancialDialog={showFinancialDialog}
        setShowFinancialDialog={setShowFinancialDialog}
        setShowExpensesDialog={setShowExpensesDialog}
        setShowTimeDialog={setShowTimeDialog}
        setShowTravelDialog={setShowTravelDialog}
      />

      {/* Onda 4: seção Financeiro inline (não mais modal) — showFinancialDialog agora controla expandido/colapsado */}
      <FinancialSection
        showFinancialDialog={showFinancialDialog}
        setShowFinancialDialog={setShowFinancialDialog}
        form={form}
        set={set}
        setForm={setForm}
        orderId={orderId}
        orderData={orderData}
        isNew={isNew}
        isLocked={isLocked}
        clientView={clientView}
        laborCost={laborCost}
        partsCost={partsCost}
        operationalCost={operationalCost}
        expensesTotal={expensesTotal}
        subtotal={subtotal}
        base={base}
        grandTotal={grandTotal}
        discountRatio={discountRatio}
        cardFeeAmount={cardFeeAmount}
        signalAmount={signalAmount}
        discountServicesPct={discountServicesPct}
        discountPartsPct={discountPartsPct}
        applyBulkLineDiscount={applyBulkLineDiscount}
        issRatePct={issRatePct}
        defaultQuoteValidityDays={defaultQuoteValidityDays}
        paymentPresets={paymentPresets}
        selectedPreset={selectedPreset}
        installmentRows={installmentRows}
        calcInstallmentAmount={calcInstallmentAmount}
        cardFees={cardFees}
        selectedInstallments={selectedInstallments}
        setSelectedInstallments={setSelectedInstallments}
        setDepositFromFinancial={setDepositFromFinancial}
        setDepositDialogOpen={setDepositDialogOpen}
        handleGenerateCollections={handleGenerateCollections}
        generatingCollections={generatingCollections}
        osCollections={osCollections}
        commissionableUsers={commissionableUsers}
      />

      {/* Stock Alert Dialog — shown when part has insufficient stock */}
      {stockAlert && orderId && (
        <StockAlertDialog
          open={!!stockAlert}
          onOpenChange={v => { if (!v) setStockAlert(null); }}
          serviceOrderId={orderId}
          productId={stockAlert.productId}
          productName={stockAlert.productName}
          needed={stockAlert.needed}
          available={stockAlert.available}
          unitCost={stockAlert.unitCost}
          suppliers={stockAlert.suppliers}
          leadTimeDays={stockAlert.leadTimeDays}
          onAddAnyway={async () => {
            if (!orderId) return;
            await addPart.mutateAsync({
              service_order_id: orderId,
              product_id: stockAlert.productId,
              quantity: stockAlert.needed,
              unit_cost_snapshot: stockAlert.unitCost,
              unit_sale_snapshot: stockAlert.unitSale,
              notes: stockAlert.notes,
            });
            setOpenNewPartCards(prev => prev.filter(k => k !== stockAlert.cardKey));
            setEditingPart(prev => { const n = { ...prev }; delete n[stockAlert.cardKey]; return n; });
            setStockAlert(null);
            toast.success('Peça adicionada (estoque negativo)');
          }}
        />
      )}

      {/* Receive PO Dialog */}
      {receivePOTarget && (
        <ReceivePODialog
          open={!!receivePOTarget}
          onOpenChange={v => { if (!v) setReceivePOTarget(null); }}
          po={receivePOTarget}
        />
      )}

      {/* Notes & Technical Reports */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">Observações e Laudos Técnicos</h2>
        <Collapsible open={extraFieldsOpen} onOpenChange={setExtraFieldsOpen}>
          <CollapsibleTrigger asChild>
            <Button variant="ghost" size="sm" className="gap-2 text-muted-foreground hover:text-foreground">
              <ChevronDown className={`h-4 w-4 transition-transform ${extraFieldsOpen ? 'rotate-180' : ''}`} />
              Campos adicionais (diagnóstico, laudo...)
            </Button>
          </CollapsibleTrigger>
          <CollapsibleContent className="space-y-4 pt-3">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.technicianNotes}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('technician_notes', await optimizeText(form.technician_notes))} disabled={isOptimizing || !form.technician_notes || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.technician_notes} onChange={(e) => set('technician_notes', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.initialFindings}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('initial_findings', await optimizeText(form.initial_findings))} disabled={isOptimizing || !form.initial_findings || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.initial_findings} onChange={(e) => set('initial_findings', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.diagnosis}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('diagnosis', await optimizeText(form.diagnosis))} disabled={isOptimizing || !form.diagnosis || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.diagnosis} onChange={(e) => set('diagnosis', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.solutionApplied}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('solution_applied', await optimizeText(form.solution_applied))} disabled={isOptimizing || !form.solution_applied || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.solution_applied} onChange={(e) => set('solution_applied', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.internalNotes}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('internal_notes', await optimizeText(form.internal_notes))} disabled={isOptimizing || !form.internal_notes || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.internal_notes} onChange={(e) => set('internal_notes', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1">
                  <Label>{t.serviceOrders.customerReport}</Label>
                  <Button type="button" variant="ghost" size="sm" className="h-6 px-2 text-xs text-primary hover:text-primary hover:bg-primary/10"
                    onClick={async () => set('customer_visible_report', await optimizeText(form.customer_visible_report))} disabled={isOptimizing || !form.customer_visible_report || isLocked}>
                    <Sparkles className="h-3 w-3 mr-1" /> IA
                  </Button>
                </div>
                <Textarea value={form.customer_visible_report} onChange={(e) => set('customer_visible_report', e.target.value)} rows={2} disabled={isLocked} />
              </div>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </section>

      {/* Signatures */}
      {!isNew && orderId && (
        <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold text-sm flex items-center gap-2">
              <FileText className="h-4 w-4" />
              Assinaturas do Cliente
            </h2>
          </div>
          <ServiceOrderSignatures serviceOrderId={orderId} />
        </section>
      )}

      {/* Bottom Save bar (mirrors top action) */}
      {!isLocked && (
        <div ref={bottomSaveRef} className="flex justify-end pt-2">
          <Button
            onClick={handleSave}
            disabled={createSO.isPending || updateSO.isPending}
            size="lg"
            className="bg-accent text-accent-foreground hover:bg-accent/90 min-w-[180px]"
          >
            {t.common.save}
          </Button>
        </div>
      )}

      {/* PDF Options Dialog */}
      <PDFOptionsDialog
        open={!!pdfDialogType && !!pdfData}
        onOpenChange={v => { if (!v) setPdfDialogType(null); }}
        documentType={pdfDialogType || 'quote'}
        initialValidityDays={form.quote_validity_days || defaultQuoteValidityDays}
        hasProductImages={pdfData?.parts?.some((p: any) => !!p.image_url) ?? false}
        onGenerate={async (action, options, validity, dueDate) => {
          if (!pdfData || !pdfDialogType) return;
          const payload = { ...pdfData, documentType: pdfDialogType };
          const opts = { ...options, validity, dueDate };
          if (action === 'download') {
            try {
              await downloadPDF(payload, opts);
              toast.success('PDF baixado com sucesso');
              setPdfDialogType(null);
            } catch (e: any) {
              console.error('PDF download failed:', e);
              toast.error('Erro ao gerar o PDF para download');
            }
          } else {
            generatePDF(payload, opts);
            setPdfDialogType(null);
          }
        }}
      />

      {/* WhatsApp Preview Dialog */}
      <Dialog open={!!waPreview} onOpenChange={v => { if (!v) setWaPreview(null); }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MessageCircle className="h-5 w-5 text-green-600" />
              Enviar via WhatsApp
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            {waPreview?.clientName && (
              <div className="text-sm text-muted-foreground">
                Cliente: <span className="font-medium text-foreground">{waPreview.clientName}</span>
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="wa-phone">Número (com DDI + DDD)</Label>
              <Input
                id="wa-phone"
                value={waEditPhone}
                onChange={e => setWaEditPhone(e.target.value.replace(/\D/g, ''))}
                placeholder="Ex: 5521999999999"
              />
              {!waEditPhone && (
                <p className="text-xs text-muted-foreground">
                  Sem número: o WhatsApp pedirá para você escolher o contato.
                </p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="wa-message">Mensagem</Label>
              <Textarea
                id="wa-message"
                value={waEditMessage}
                onChange={e => setWaEditMessage(e.target.value)}
                rows={5}
              />
            </div>
            <div className="rounded-md border bg-muted/40 p-3 text-xs break-all">
              <div className="font-medium text-foreground mb-1">Link público:</div>
              {waPreview?.url}
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={() => setWaPreview(null)}>
                Cancelar
              </Button>
              <Button
                className="bg-green-600 hover:bg-green-700 text-white gap-1"
                onClick={() => {
                  const waUrl = waEditPhone
                    ? `https://wa.me/${waEditPhone}?text=${encodeURIComponent(waEditMessage)}`
                    : `https://wa.me/?text=${encodeURIComponent(waEditMessage)}`;
                  let opened = false;
                  try {
                    const w = window.open(waUrl, '_blank', 'noopener,noreferrer');
                    opened = !!w;
                  } catch {
                    opened = false;
                  }
                  if (orderData?.id) {
                    void writeAuditLog({
                      table_name: 'service_orders',
                      record_id: orderData.id,
                      action: 'whatsapp_send' as any,
                      new_value: {
                        share_token: orderData.share_token,
                        public_url: waPreview?.url,
                        phone_used: waEditPhone || null,
                        had_phone: !!waEditPhone,
                        wa_url: waUrl,
                        window_opened: opened,
                      },
                      reason: opened
                        ? 'Link do WhatsApp aberto'
                        : 'Falha ao abrir janela do WhatsApp (provável bloqueio de pop-up)',
                    });
                  }
                  recordWhatsAppEvent({
                    source: 'detail_dialog',
                    action: 'send',
                    serviceOrderId: orderData?.id,
                    serviceOrderNumber: orderData?.service_order_number,
                    shareToken: orderData?.share_token,
                    phoneNormalized: waEditPhone || undefined,
                    opened,
                    popupBlocked: !opened,
                    errorMessage: !opened ? 'window.open returned null (likely popup blocker)' : undefined,
                  });
                  setWaPreview(null);
                }}
              >
                <MessageCircle className="h-4 w-4" />
                Abrir WhatsApp
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <WhatsAppSendHistoryDialog
        open={showZapiHistory}
        onOpenChange={setShowZapiHistory}
        serviceOrderId={showZapiHistory ? (orderId || null) : null}
        serviceOrderNumber={orderData?.service_order_number}
      />

      <SendViaWhatsAppDialog
        open={!!whatsAppTarget}
        onOpenChange={v => { if (!v) setWhatsAppTarget(null); }}
        target={whatsAppTarget}
      />

      {/* M1: PaymentDialog integrado na OS — abre ao clicar "Registrar pagamento" */}
      <PaymentDialog
        open={!!paymentDialogReceivable}
        onOpenChange={v => { if (!v) setPaymentDialogReceivable(null); }}
        receivable={paymentDialogReceivable}
      />

      <QuickProductDialog
        open={quickProductOpen}
        onOpenChange={setQuickProductOpen}
        initialName={quickProductName}
        onCreated={() => {
          // Kept for backwards compatibility; new flow uses inline part cards.
        }}
      />

      <PriceCalculatorDialog
        open={!!priceCalcCardKey}
        onOpenChange={(v) => { if (!v) setPriceCalcCardKey(null); }}
        initialCost={priceCalcCardKey ? (editingPart[priceCalcCardKey]?.unit_cost || 0) : 0}
        initialPrice={priceCalcCardKey ? (editingPart[priceCalcCardKey]?.unit_sale || 0) : 0}
        onConfirm={(price) => {
          if (!priceCalcCardKey) return;
          setEditingPart((prev) => ({
            ...prev,
            [priceCalcCardKey]: { ...prev[priceCalcCardKey], unit_sale: price },
          }));
        }}
      />

      <MarinaFormDialog
        open={quickMarinaOpen}
        onOpenChange={setQuickMarinaOpen}
        marina={null}
        onSaved={(marina) => {
          set('marina_id', marina.id);
          setQuickMarinaOpen(false);
        }}
      />

      <QuickSupplierDialog
        open={quickSupplierOpen}
        onOpenChange={setQuickSupplierOpen}
        initialName={quickSupplierName}
        onCreated={(s) => setExpForm((prev) => ({ ...prev, supplier_id: s.id }))}
      />

      {/* Onda 4: resumo financeiro fixo (sticky) — mesmo waterfall exibido ao cliente */}
      <ServiceOrderFinancialSummary
        grandTotal={grandTotal}
        balance={!isNew ? soBalance : null}
        formatCurrency={formatCurrency}
        onOpenFinancial={() => setShowFinancialDialog(true)}
        onSave={handleSave}
        saving={createSO.isPending || updateSO.isPending}
        showSave={!isLocked && !topVisible && !bottomVisible}
        waterfall={([
          { label: t.serviceOrders.labor, value: laborCost },
          { label: t.serviceOrders.parts, value: partsCost },
          { label: t.serviceOrders.travel, value: billableTravelCost },
          { label: t.serviceOrders.operationalCost, value: operationalCost },
          { label: t.serviceOrders.subcontract, value: form.subcontract_cost_total || 0 },
          { label: 'Desconto por item', value: itemDiscountTotal, negative: true },
          { label: 'Desconto', value: form.discount_amount || 0, negative: true },
          { label: 'Impostos', value: form.tax_amount || 0 },
          { label: 'Taxa de cartão', value: passthroughCardFeeAmount },
        ] as FinancialWaterfallLine[])}
      />
    </div>
  );
}

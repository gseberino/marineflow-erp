import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useI18n } from '@/i18n';
import { useClients } from '@/hooks/use-clients';
import { useVessels } from '@/hooks/use-vessels';
import { useMarinas } from '@/hooks/use-marinas';
import { useProducts } from '@/hooks/use-products';
import { useServices } from '@/hooks/use-services';
import { useCardFees } from '@/hooks/use-card-fees';
import {
  useCreateServiceOrder,
  useUpdateServiceOrder,
  useUpdateServiceOrderStatus,
  useServiceOrderParts,
  useAddServiceOrderPart,
  useRemoveServiceOrderPart,
  useServiceOrderServices,
  useAddServiceOrderService,
  useRemoveServiceOrderService,
  useTimeEntries,
  useAddTimeEntry,
  useRemoveTimeEntry,
  STATUS_TRANSITIONS,
  useCancelServiceOrder,
  useReopenServiceOrder,
} from '@/hooks/use-service-orders';
import { useAppUsers, useCommissionableUsers, USER_ROLES } from '@/hooks/use-app-users';
import { usePaymentConditionPresets } from '@/hooks/use-payment-conditions';
import { useVesselContacts, VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import { ClientCombobox } from '@/components/ClientCombobox';
import { VesselSelect } from '@/components/VesselSelect';
import { useServiceOrderExpenses, useAddServiceOrderExpense, useRemoveServiceOrderExpense } from '@/hooks/use-service-order-expenses';
import { usePDFData } from '@/hooks/use-pdf';
import { generatePDF, DEFAULT_PDF_OPTIONS } from '@/lib/pdf-generator';
import type { PDFOptions } from '@/lib/pdf-generator';
import { PDFOptionsDialog } from '@/components/PDFOptionsDialog';
import { OPERATIONAL_EXPENSE_CATEGORIES } from '@/lib/expense-categories';
import { calculateDisplacement } from '@/lib/displacement';
import { statusConfig, priorityConfig } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';
import { ServiceFormDialog } from '@/components/ServiceFormDialog';
import { RecordHistory } from '@/components/RecordHistory';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowLeft, Plus, Trash2, RefreshCw, AlertTriangle, Calculator, CreditCard, Receipt, Lock, RotateCcw, Ban, FileText, Printer, ChevronDown, MessageCircle } from 'lucide-react';
import { toast } from 'sonner';

interface Props {
  orderId?: string;
  orderData?: any;
  isLoading?: boolean;
}

const SERVICE_TYPES = [
  'diagnosis', 'repair', 'installation', 'preventive_maintenance',
  'consulting', 'engineering_project', 'commissioning', 'inspection',
] as const;

const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const;
const STATUSES = [
  'draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts',
  'awaiting_client', 'completed', 'invoiced', 'cancelled',
] as const;

const BILLING_UNIT_LABELS: Record<string, string> = {
  hour: 'h',
  visit: 'visita(s)',
  day: 'dia(s)',
  unit: 'un.',
};

export function ServiceOrderForm({ orderId, orderData, isLoading }: Props) {
  const navigate = useNavigate();
  const { t, formatCurrency, formatDateTime, formatDate } = useI18n();
  const isNew = !orderId;

  const { data: clients } = useClients();
  const { data: allVessels } = useVessels();
  const { data: marinas } = useMarinas();
  const { data: products } = useProducts();
  const { data: appUsers } = useAppUsers();
  const { data: commissionableUsers } = useCommissionableUsers();
  const { data: services } = useServices();
  const { data: cardFees } = useCardFees();
  const { data: paymentPresets } = usePaymentConditionPresets();
  const { data: pdfData } = usePDFData(isNew ? undefined : orderId);

  const createSO = useCreateServiceOrder();
  const updateSO = useUpdateServiceOrder();
  const updateStatus = useUpdateServiceOrderStatus();
  const cancelSO = useCancelServiceOrder();
  const reopenSO = useReopenServiceOrder();

  const { data: parts } = useServiceOrderParts(orderId);
  const addPart = useAddServiceOrderPart();
  const removePart = useRemoveServiceOrderPart();

  const { data: soServices } = useServiceOrderServices(orderId);
  const addService = useAddServiceOrderService();
  const removeService = useRemoveServiceOrderService();

  const { data: timeEntries } = useTimeEntries(orderId);
  const addTime = useAddTimeEntry();
  const removeTime = useRemoveTimeEntry();

  const { data: soExpenses } = useServiceOrderExpenses(orderId);
  const addExpense = useAddServiceOrderExpense();
  const removeExpense = useRemoveServiceOrderExpense();

  // Form state
  const [form, setForm] = useState<Record<string, any>>({
    status: 'draft',
    priority: 'normal',
    service_type: 'repair',
    client_id: '',
    vessel_id: '',
    marina_id: '',
    requested_by_name: '',
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
    hourly_rate: 150,
    estimated_hours: 0,
    travel_distance_km: 0,
    travel_cost_per_km: 3.5,
    technician_count_for_travel: 1,
    travel_cost_total: 0,
    discount_amount: 0,
    tax_amount: 0,
    subcontract_cost_total: 0,
    commission_rate: 0,
    commission_amount: 0,
    commissioned_person: '',
    commissioned_user_id: '',
    payment_conditions: '',
  });

  const [manualTravel, setManualTravel] = useState(false);
  const [selectedTechnicians, setSelectedTechnicians] = useState<string[]>([]);
  const [extraFieldsOpen, setExtraFieldsOpen] = useState(false);
  const { data: vesselContacts } = useVesselContacts(form.vessel_id || undefined);

  // Part form
  const [partForm, setPartForm] = useState({ product_id: '', quantity: 1, unit_cost: 0, unit_sale: 0 });
  const [showPartForm, setShowPartForm] = useState(false);

  // Service line form
  const [svcForm, setSvcForm] = useState({ service_id: '', quantity: 1, unit_price: 0, notes: '', service_name_snapshot: '', description_snapshot: '', billing_unit_snapshot: 'hour' });
  const [showSvcForm, setShowSvcForm] = useState(false);
  const [showNewServiceDialog, setShowNewServiceDialog] = useState(false);

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
    technician_user_id: '', receipt_url: '', notes: '',
    also_create_payable: false,
  });
  const [showExpForm, setShowExpForm] = useState(false);

  // Card installments
  const [selectedInstallments, setSelectedInstallments] = useState(1);
  const [showCancelDialog, setShowCancelDialog] = useState(false);
  const [showReopenDialog, setShowReopenDialog] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [reopenReason, setReopenReason] = useState('');
  const [pdfDialogType, setPdfDialogType] = useState<'quote' | 'service_order' | 'invoice' | null>(null);
  const [waPreview, setWaPreview] = useState<{ phone: string; message: string; url: string; clientName: string } | null>(null);
  const [waEditMessage, setWaEditMessage] = useState('');
  const [waEditPhone, setWaEditPhone] = useState('');
  const [presetKey, setPresetKey] = useState(0);

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
        hourly_rate: d.hourly_rate || 150,
        estimated_hours: d.estimated_hours || 0,
        travel_distance_km: d.travel_distance_km || 0,
        travel_cost_per_km: d.travel_cost_per_km || 3.5,
        technician_count_for_travel: d.technician_count_for_travel || 1,
        travel_cost_total: d.travel_cost_total || 0,
        discount_amount: d.discount_amount || 0,
        tax_amount: d.tax_amount || 0,
        subcontract_cost_total: d.subcontract_cost_total || 0,
        commission_rate: d.commission_rate || 0,
        commission_amount: d.commission_amount || 0,
        commissioned_person: d.commissioned_person || '',
        commissioned_user_id: d.commissioned_user_id || '',
        payment_conditions: d.payment_conditions || '',
      });
      if (d.service_order_technicians) {
        setSelectedTechnicians(d.service_order_technicians.map((t: any) => t.user_id));
      }
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

  // Financial summary
  const laborCost = orderData?.labor_cost_total || 0;
  const partsCost = orderData?.parts_cost_total || 0;
  const operationalCost = orderData?.operational_cost_total || 0;
  const subtotal = laborCost + partsCost + operationalCost + form.travel_cost_total + form.subcontract_cost_total;
  const grandTotal = subtotal - form.discount_amount + form.tax_amount;

  // Card fee calculation
  const selectedFee = cardFees?.find((f) => f.installments === selectedInstallments);
  const feePercent = selectedFee?.fee_percent || 0;
  const cardGross = feePercent > 0 ? grandTotal / (1 - Number(feePercent) / 100) : grandTotal;
  const cardFeeAmount = cardGross - grandTotal;
  const installmentValue = selectedInstallments > 0 ? cardGross / selectedInstallments : cardGross;

  const handleSave = async () => {
    if (!form.client_id || !form.vessel_id || !form.problem_description) {
      toast.error('Preencha cliente, embarcação e descrição do problema');
      return;
    }
    try {
      const payload = {
        ...form,
        scheduled_start_at: form.scheduled_start_at || null,
        scheduled_end_at: form.scheduled_end_at || null,
        commissioned_user_id: form.commissioned_user_id || null,
        requested_by_contact_id: form.requested_by_contact_id || null,
        payment_conditions: form.payment_conditions || null,
      };
      if (isNew) {
        const result = await createSO.mutateAsync(payload);
        if (selectedTechnicians.length > 0) {
          const { supabase } = await import('@/integrations/supabase/client');
          await supabase.from('service_order_technicians').insert(
            selectedTechnicians.map((uid) => ({ service_order_id: result.id, user_id: uid }))
          );
        }
        toast.success('Ordem de serviço criada com sucesso');
        navigate(`/service-orders/${result.id}`);
      } else {
        await updateSO.mutateAsync({ id: orderId!, ...payload });
        const { supabase } = await import('@/integrations/supabase/client');
        await supabase.from('service_order_technicians').delete().eq('service_order_id', orderId!);
        if (selectedTechnicians.length > 0) {
          await supabase.from('service_order_technicians').insert(
            selectedTechnicians.map((uid) => ({ service_order_id: orderId!, user_id: uid }))
          );
        }
        toast.success('Ordem de serviço atualizada');
      }
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar');
    }
  };

  const handleStatusChange = async (newStatus: string) => {
    if (!orderId) return;
    try {
      await updateStatus.mutateAsync({ id: orderId, status: newStatus });
      toast.success(`Status alterado para ${(t.status as Record<string, string>)[newStatus]}`);
    } catch (e: any) {
      toast.error(e.message || 'Erro ao alterar status');
    }
  };

  const handleAddPart = async () => {
    if (!orderId || !partForm.product_id || partForm.quantity <= 0) return;
    try {
      await addPart.mutateAsync({
        service_order_id: orderId,
        product_id: partForm.product_id,
        quantity: partForm.quantity,
        unit_cost_snapshot: partForm.unit_cost,
        unit_sale_snapshot: partForm.unit_sale,
      });
      setPartForm({ product_id: '', quantity: 1, unit_cost: 0, unit_sale: 0 });
      setShowPartForm(false);
      toast.success('Peça adicionada');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar peça');
    }
  };

  const handleAddService = async () => {
    if (!orderId || !svcForm.service_name_snapshot || svcForm.quantity <= 0) return;
    try {
      await addService.mutateAsync({
        service_order_id: orderId,
        service_id: svcForm.service_id || undefined,
        service_name_snapshot: svcForm.service_name_snapshot,
        description_snapshot: svcForm.description_snapshot || undefined,
        billing_unit_snapshot: svcForm.billing_unit_snapshot,
        quantity: svcForm.quantity,
        unit_price_snapshot: svcForm.unit_price,
        notes: svcForm.notes || undefined,
      });
      setSvcForm({ service_id: '', quantity: 1, unit_price: 0, notes: '', service_name_snapshot: '', description_snapshot: '', billing_unit_snapshot: 'hour' });
      setShowSvcForm(false);
      toast.success('Serviço adicionado');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar serviço');
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

  const handleAddExpense = async () => {
    if (!orderId || !expForm.category || !expForm.description || expForm.amount <= 0) return;
    try {
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
        notes: expForm.notes || undefined,
        also_create_payable: expForm.also_create_payable,
      });
      setExpForm({
        category: '', description: '', amount: 0, currency: 'BRL',
        expense_date: new Date().toISOString().slice(0, 10),
        paid_by: 'company', technician_user_id: '', receipt_url: '', notes: '',
        also_create_payable: false,
      });
      setShowExpForm(false);
      toast.success('Despesa adicionada');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao adicionar despesa');
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

      {/* Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <Button variant="ghost" size="icon" onClick={() => navigate('/service-orders')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold">
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
            </div>
          )}
        </div>
        <div className="flex gap-2 flex-wrap">
          {!isNew && (
            <>
              <Button variant="outline" size="sm" onClick={() => setPdfDialogType('quote')} className="gap-1">
                <FileText className="h-4 w-4" />
                {t.pdf.quote}
              </Button>
              <Button variant="outline" size="sm" onClick={() => setPdfDialogType('service_order')} className="gap-1">
                <Printer className="h-4 w-4" />
                OS
              </Button>
              {(currentStatus === 'completed' || currentStatus === 'invoiced') && (
                <Button variant="outline" size="sm" onClick={() => setPdfDialogType('invoice')} className="gap-1">
                  <Receipt className="h-4 w-4" />
                  Fatura
                </Button>
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
                    const clientName = (orderData?.clients as any)?.full_name_or_company_name || '';
                    const msg = `Olá${clientName ? ' ' + clientName : ''}, segue o link da Ordem de Serviço ${orderData.service_order_number}: ${url}`;
                    setWaEditPhone(phone);
                    setWaEditMessage(msg);
                    setWaPreview({ phone, message: msg, url, clientName });
                  }}
                >
                  <MessageCircle className="h-4 w-4" />
                  WhatsApp
                </Button>
              )}
            </>
          )}
          {!isNew && !isLocked && currentStatus !== 'cancelled' && (
            <Button variant="outline" size="sm" className="text-destructive" onClick={() => setShowCancelDialog(true)}>
              <Ban className="h-4 w-4 mr-1" /> {t.serviceOrders.cancelOS}
            </Button>
          )}
          {!isNew && !isLocked && validTransitions.length > 0 && (
            <Select onValueChange={handleStatusChange}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder={t.serviceOrders.alterStatus} />
              </SelectTrigger>
              <SelectContent>
                {validTransitions.map((s) => (
                  <SelectItem key={s} value={s}>
                    {(t.status as Record<string, string>)[s]}
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

      {/* A - Identification */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.tabOverview}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <Label>{t.common.status}</Label>
            <Select value={form.status} onValueChange={(v) => set('status', v)} disabled={!isNew}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {STATUSES.map((s) => (
                  <SelectItem key={s} value={s}>{(t.status as Record<string, string>)[s]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.serviceOrders.priority}</Label>
            <Select value={form.priority} onValueChange={(v) => set('priority', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {PRIORITIES.map((p) => (
                  <SelectItem key={p} value={p}>{(t.priority as Record<string, string>)[p]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.common.type}</Label>
            <Select value={form.service_type} onValueChange={(v) => set('service_type', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {SERVICE_TYPES.map((st) => (
                  <SelectItem key={st} value={st}>{(t.serviceType as Record<string, string>)[st]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
      </section>

      {/* B - Client & Vessel */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.clientAndVessel}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.client} *</Label>
            <ClientCombobox
              value={form.client_id}
              onChange={(clientId) => {
                set('client_id', clientId);
                set('vessel_id', '');
                set('requested_by_contact_id', '');
                set('requested_by_name', '');
              }}
              clients={clients}
              disabled={isLocked}
            />
          </div>
          <div>
            <Label>{t.serviceOrders.vessel} *</Label>
            <VesselSelect
              value={form.vessel_id}
              clientId={form.client_id}
              vessels={clientVessels}
              disabled={!form.client_id || isLocked}
              onChange={(vesselId) => {
                set('vessel_id', vesselId);
                set('requested_by_contact_id', '');
                const vessel = allVessels?.find(v => v.id === vesselId);
                if (vessel?.marina_id) set('marina_id', vessel.marina_id);
              }}
              onVesselCreated={(vessel) => {
                set('vessel_id', vessel.id);
                if (vessel.marina_id) set('marina_id', vessel.marina_id);
              }}
            />
          </div>
          <div>
            <Label>{t.serviceOrders.marina}</Label>
            <Select value={form.marina_id || 'none'} onValueChange={(v) => set('marina_id', v === 'none' ? '' : v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">—</SelectItem>
                {marinas?.filter((m) => m.active).map((m) => (
                  <SelectItem key={m.id} value={m.id}>{m.marina_name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>{t.serviceOrders.requestedBy}</Label>
            {vesselContacts && vesselContacts.length > 0 ? (
              <Select
                value={form.requested_by_contact_id || 'none'}
                onValueChange={(v) => {
                  const contact = vesselContacts.find(c => c.id === v);
                  setForm(f => ({
                    ...f,
                    requested_by_contact_id: v === 'none' ? '' : v,
                    requested_by_name: contact?.full_name || '',
                  }));
                }}
                disabled={isLocked}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Selecionar contato" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">—</SelectItem>
                  {vesselContacts.map(c => (
                    <SelectItem key={c.id} value={c.id}>
                      <span className="flex items-center gap-1">
                        {c.full_name}
                        <span className="text-xs text-muted-foreground">
                          ({VESSEL_CONTACT_ROLES.find(r => r.value === c.role)?.label || c.role})
                        </span>
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <div>
                <Input
                  value={form.requested_by_name}
                  onChange={e => set('requested_by_name', e.target.value)}
                  placeholder="Nome do solicitante"
                  disabled={isLocked}
                />
                {form.vessel_id && (
                  <p className="text-xs text-muted-foreground mt-1">
                    Cadastre contatos na embarcação para aparecerem aqui
                  </p>
                )}
              </div>
            )}
          </div>
        </div>
      </section>

      {/* C - Scheduling + Technicians (merged) */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.schedule}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <Label>{t.serviceOrders.scheduledStart}</Label>
            <Input type="datetime-local" value={form.scheduled_start_at} onChange={(e) => set('scheduled_start_at', e.target.value)} />
          </div>
          <div>
            <Label>{t.serviceOrders.scheduledEnd}</Label>
            <Input type="datetime-local" value={form.scheduled_end_at} onChange={(e) => set('scheduled_end_at', e.target.value)} />
          </div>
        </div>
        {/* Technicians */}
        <div>
          <Label>{t.serviceOrders.technicians}</Label>
          <div className="flex flex-wrap gap-2 mt-1">
            {appUsers?.map((u) => (
              <label key={u.id} className="flex items-center gap-1.5 text-sm border rounded-lg px-3 py-1.5 cursor-pointer hover:bg-muted transition-colors">
                <input
                  type="checkbox"
                  checked={selectedTechnicians.includes(u.id)}
                  onChange={(e) => {
                    const next = e.target.checked
                      ? [...selectedTechnicians, u.id]
                      : selectedTechnicians.filter((id) => id !== u.id);
                    setSelectedTechnicians(next);
                    set('technician_count_for_travel', next.length || 1);
                  }}
                />
                {u.full_name}
              </label>
            ))}
          </div>
        </div>
      </section>

      {/* D - Problem & Technical (compact with collapsible) */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.problemDescription}</h2>
        <div>
          <Label>{t.serviceOrders.problemDescription} *</Label>
          <Textarea value={form.problem_description} onChange={(e) => set('problem_description', e.target.value)} rows={3} />
        </div>
        <div className="space-y-2">
          <Label className="flex items-center gap-2 text-sm font-medium">
            Observações Adicionais para Impressão
            <span className="text-xs text-muted-foreground font-normal">
              (aparece no PDF deste documento)
            </span>
          </Label>
          <Textarea
            value={form.extra_notes || ''}
            onChange={e => set('extra_notes', e.target.value)}
            placeholder="Informações específicas para este cliente, condições especiais, garantias, prazos..."
            rows={2}
            disabled={isLocked}
          />
        </div>

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
                <Label>{t.serviceOrders.technicianNotes}</Label>
                <Textarea value={form.technician_notes} onChange={(e) => set('technician_notes', e.target.value)} rows={2} disabled={isLocked} />
              </div>
              <div>
                <Label>{t.serviceOrders.initialFindings}</Label>
                <Textarea value={form.initial_findings} onChange={(e) => set('initial_findings', e.target.value)} rows={2} />
              </div>
              <div>
                <Label>{t.serviceOrders.diagnosis}</Label>
                <Textarea value={form.diagnosis} onChange={(e) => set('diagnosis', e.target.value)} rows={2} />
              </div>
              <div>
                <Label>{t.serviceOrders.solutionApplied}</Label>
                <Textarea value={form.solution_applied} onChange={(e) => set('solution_applied', e.target.value)} rows={2} />
              </div>
              <div>
                <Label>{t.serviceOrders.internalNotes}</Label>
                <Textarea value={form.internal_notes} onChange={(e) => set('internal_notes', e.target.value)} rows={2} />
              </div>
              <div>
                <Label>{t.serviceOrders.customerReport}</Label>
                <Textarea value={form.customer_visible_report} onChange={(e) => set('customer_visible_report', e.target.value)} rows={2} />
              </div>
            </div>
          </CollapsibleContent>
        </Collapsible>
      </section>

      {/* E - Labor Services (edit only) */}
      {!isNew && (
        <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-5 border-b flex items-center justify-between">
            <h2 className="font-semibold text-sm">{t.services.laborSection}</h2>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowSvcForm(!showSvcForm)}>
              <Plus className="h-3 w-3" /> {t.services.selectService}
            </Button>
          </div>
          {showSvcForm && (
            <div className="p-4 border-b bg-muted/30 space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <Label>{t.services.selectService}</Label>
                  <Select value={svcForm.service_id} onValueChange={(v) => {
                    const svc = services?.find((s) => s.id === v);
                    if (svc) {
                      setSvcForm({
                        ...svcForm,
                        service_id: v,
                        service_name_snapshot: svc.service_name,
                        description_snapshot: svc.description || '',
                        billing_unit_snapshot: svc.billing_unit,
                        unit_price: svc.default_price || 0,
                      });
                    }
                  }}>
                    <SelectTrigger><SelectValue placeholder={t.services.selectService} /></SelectTrigger>
                    <SelectContent>
                      {services?.filter((s) => s.active).map((s) => (
                        <SelectItem key={s.id} value={s.id}>
                          {s.service_name} ({BILLING_UNIT_LABELS[s.billing_unit] || s.billing_unit} — {formatCurrency(s.default_price || 0)})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <button type="button" className="text-xs text-primary mt-1 hover:underline"
                    onClick={() => setShowNewServiceDialog(true)}>
                    {t.services.registerNew}
                  </button>
                </div>
                <div className="grid grid-cols-3 gap-3">
                  <div>
                    <Label>{t.serviceOrders.qty}</Label>
                    <Input type="number" min={0.001} step="any" value={svcForm.quantity}
                      onChange={(e) => setSvcForm({ ...svcForm, quantity: parseFloat(e.target.value) || 1 })} />
                  </div>
                  <div>
                    <Label>{t.serviceOrders.unitPrice}</Label>
                    <Input type="number" value={svcForm.unit_price}
                      onChange={(e) => setSvcForm({ ...svcForm, unit_price: parseFloat(e.target.value) || 0 })} />
                  </div>
                  <div>
                    <Label>{t.common.total}</Label>
                    <Input readOnly value={formatCurrency(svcForm.quantity * svcForm.unit_price)} className="bg-muted" />
                  </div>
                </div>
              </div>
              <div>
                <Label>{t.common.notes}</Label>
                <Input value={svcForm.notes} onChange={(e) => setSvcForm({ ...svcForm, notes: e.target.value })} />
              </div>
              <div className="flex gap-2">
                <Button size="sm" onClick={handleAddService} disabled={addService.isPending}>{t.common.save}</Button>
                <Button size="sm" variant="outline" onClick={() => setShowSvcForm(false)}>{t.common.cancel}</Button>
              </div>
            </div>
          )}
          {(!soServices || soServices.length === 0) ? (
            <p className="text-sm text-muted-foreground p-5">{t.services.noServicesLinked}</p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.services.serviceName}</th>
                  <th className="px-4 py-2 text-center font-medium text-muted-foreground">{t.services.billingUnit}</th>
                  <th className="px-4 py-2 text-center font-medium text-muted-foreground">{t.serviceOrders.qty}</th>
                  <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.serviceOrders.unitPrice}</th>
                  <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.common.total}</th>
                  <th className="px-4 py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {soServices.map((s: any) => (
                  <tr key={s.id} className="border-b last:border-0">
                    <td className="px-4 py-3 font-medium">
                      {s.service_name_snapshot}
                      {s.description_snapshot && <span className="block text-xs text-muted-foreground">{s.description_snapshot}</span>}
                    </td>
                    <td className="px-4 py-3 text-center text-muted-foreground">{BILLING_UNIT_LABELS[s.billing_unit_snapshot] || s.billing_unit_snapshot}</td>
                    <td className="px-4 py-3 text-center">{s.quantity}</td>
                    <td className="px-4 py-3 text-right">{formatCurrency(s.unit_price_snapshot)}</td>
                    <td className="px-4 py-3 text-right font-semibold">{formatCurrency(s.line_total)}</td>
                    <td className="px-4 py-3">
                      <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                        onClick={() => removeService.mutate({ id: s.id, service_order_id: orderId! })}>
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}

      {/* New Service Dialog */}
      <ServiceFormDialog open={showNewServiceDialog} onOpenChange={setShowNewServiceDialog} />

      {/* Travel Section */}
      {!isNew && (
        <section className="rounded-xl border bg-card p-5 shadow-sm space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold text-sm">{t.serviceOrders.travel}</h2>
            {marina?.latitude && (
              <Button variant="outline" size="sm" onClick={runDisplacement} className="gap-1">
                <RefreshCw className="h-3 w-3" />
                {t.serviceOrders.recalculate}
              </Button>
            )}
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div>
              <Label>{t.serviceOrders.distance}</Label>
              <Input type="number" value={form.travel_distance_km}
                onChange={(e) => {
                  const km = parseFloat(e.target.value) || 0;
                  set('travel_distance_km', km);
                  if (!manualTravel) {
                    set('travel_cost_total', km * form.travel_cost_per_km * form.technician_count_for_travel);
                  }
                }} />
            </div>
            <div>
              <Label>Custo/km</Label>
              <Input type="number" value={form.travel_cost_per_km}
                onChange={(e) => {
                  const cpk = parseFloat(e.target.value) || 0;
                  set('travel_cost_per_km', cpk);
                  if (!manualTravel) {
                    set('travel_cost_total', form.travel_distance_km * cpk * form.technician_count_for_travel);
                  }
                }} />
            </div>
            <div>
              <Label>{t.serviceOrders.technicians}</Label>
              <Input type="number" min={1} value={form.technician_count_for_travel}
                onChange={(e) => {
                  const count = parseInt(e.target.value) || 1;
                  set('technician_count_for_travel', count);
                  if (!manualTravel) {
                    set('travel_cost_total', form.travel_distance_km * form.travel_cost_per_km * count);
                  }
                }} />
            </div>
            <div>
              <Label className="flex items-center gap-2">
                {t.serviceOrders.travel} total
                <label className="flex items-center gap-1 text-xs text-muted-foreground font-normal cursor-pointer">
                  <input type="checkbox" checked={manualTravel} onChange={(e) => setManualTravel(e.target.checked)} />
                  Manual
                </label>
              </Label>
              <Input type="number" value={form.travel_cost_total}
                onChange={(e) => set('travel_cost_total', parseFloat(e.target.value) || 0)}
                disabled={!manualTravel} className={!manualTravel ? 'bg-muted' : ''} />
            </div>
          </div>
        </section>
      )}

      {/* F - Parts (edit only) */}
      {!isNew && (
        <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-5 border-b flex items-center justify-between">
            <h2 className="font-semibold text-sm">{t.serviceOrders.parts}</h2>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowPartForm(!showPartForm)}>
              <Plus className="h-3 w-3" /> {t.serviceOrders.addPart}
            </Button>
          </div>
          {showPartForm && (
            <div className="p-4 border-b bg-muted/30 space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
                <div className="sm:col-span-2">
                  <Label>{t.serviceOrders.product}</Label>
                  <Select value={partForm.product_id} onValueChange={(v) => {
                    const prod = products?.find((p) => p.id === v);
                    setPartForm({
                      ...partForm, product_id: v,
                      unit_cost: prod?.cost_price || 0,
                      unit_sale: prod?.sale_price || 0,
                    });
                  }}>
                    <SelectTrigger><SelectValue placeholder="Selecionar produto" /></SelectTrigger>
                    <SelectContent>
                      {products?.filter((p) => p.active).map((p) => (
                        <SelectItem key={p.id} value={p.id}>
                          {p.product_name} (estoque: {p.stock_quantity})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>{t.serviceOrders.qty}</Label>
                  <Input type="number" min={1} value={partForm.quantity}
                    onChange={(e) => setPartForm({ ...partForm, quantity: parseInt(e.target.value) || 1 })} />
                </div>
                <div>
                  <Label>{t.serviceOrders.unitPrice}</Label>
                  <Input type="number" value={partForm.unit_sale}
                    onChange={(e) => setPartForm({ ...partForm, unit_sale: parseFloat(e.target.value) || 0 })} />
                </div>
              </div>
              <div className="flex gap-2">
                <Button size="sm" onClick={handleAddPart} disabled={addPart.isPending}>{t.common.save}</Button>
                <Button size="sm" variant="outline" onClick={() => setShowPartForm(false)}>{t.common.cancel}</Button>
              </div>
            </div>
          )}
          {(!parts || parts.length === 0) ? (
            <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noPartsYet}</p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.serviceOrders.product}</th>
                  <th className="px-4 py-2 text-center font-medium text-muted-foreground">{t.serviceOrders.qty}</th>
                  <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.serviceOrders.unitPrice}</th>
                  <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.common.total}</th>
                  <th className="px-4 py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {parts.map((p: any) => (
                  <tr key={p.id} className="border-b last:border-0">
                    <td className="px-4 py-3 font-medium">{p.products?.product_name}</td>
                    <td className="px-4 py-3 text-center">{p.quantity}</td>
                    <td className="px-4 py-3 text-right">{formatCurrency(p.unit_sale_snapshot)}</td>
                    <td className="px-4 py-3 text-right font-semibold">{formatCurrency(p.line_total_sale)}</td>
                    <td className="px-4 py-3">
                      <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                        onClick={() => removePart.mutate({
                          id: p.id, service_order_id: orderId!, product_id: p.product_id,
                          quantity: p.quantity, unit_cost_snapshot: p.unit_cost_snapshot,
                        })}>
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}

      {/* Expenses section (edit only) */}
      {!isNew && (
        <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-5 border-b flex items-center justify-between">
            <h2 className="font-semibold text-sm">{t.serviceOrders.operationalExpenses}</h2>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowExpForm(!showExpForm)}>
              <Plus className="h-3 w-3" /> {t.serviceOrders.addExpense}
            </Button>
          </div>
          {showExpForm && (
            <div className="p-4 border-b bg-muted/30 space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <Label>{t.products.category}</Label>
                  <Select value={expForm.category} onValueChange={(v) => setExpForm({ ...expForm, category: v })}>
                    <SelectTrigger><SelectValue placeholder={t.products.category} /></SelectTrigger>
                    <SelectContent>
                      {OPERATIONAL_EXPENSE_CATEGORIES.map((c) => (
                        <SelectItem key={c} value={c}>{c}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>{t.serviceOrders.expenseDate}</Label>
                  <Input type="date" value={expForm.expense_date} onChange={(e) => setExpForm({ ...expForm, expense_date: e.target.value })} />
                </div>
                <div>
                  <Label>{t.common.amount}</Label>
                  <Input type="number" min={0} step="0.01" value={expForm.amount}
                    onChange={(e) => setExpForm({ ...expForm, amount: parseFloat(e.target.value) || 0 })} />
                </div>
              </div>
              <div>
                <Label>{t.common.description}</Label>
                <Input value={expForm.description} onChange={(e) => setExpForm({ ...expForm, description: e.target.value })} />
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <Label>{t.serviceOrders.paidBy}</Label>
                  <Select value={expForm.paid_by} onValueChange={(v: 'company' | 'technician') => setExpForm({ ...expForm, paid_by: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="company">{t.serviceOrders.paidByCompany}</SelectItem>
                      <SelectItem value="technician">{t.serviceOrders.paidByTechnician}</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {expForm.paid_by === 'technician' && (
                  <div>
                    <Label>{t.serviceOrders.technicians}</Label>
                    <Select value={expForm.technician_user_id} onValueChange={(v) => setExpForm({ ...expForm, technician_user_id: v })}>
                      <SelectTrigger><SelectValue placeholder={t.serviceOrders.technicians} /></SelectTrigger>
                      <SelectContent>
                        {appUsers?.map((u) => (
                          <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-warning mt-1">{t.serviceOrders.pendingReimbursement}</p>
                  </div>
                )}
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <Label>{t.serviceOrders.receiptUrl}</Label>
                  <Input value={expForm.receipt_url} onChange={(e) => setExpForm({ ...expForm, receipt_url: e.target.value })} placeholder="https://..." />
                </div>
                <div>
                  <Label>{t.common.notes}</Label>
                  <Input value={expForm.notes} onChange={(e) => setExpForm({ ...expForm, notes: e.target.value })} />
                </div>
              </div>
              <label className="flex items-center gap-2 text-sm cursor-pointer">
                <input type="checkbox" checked={expForm.also_create_payable}
                  onChange={(e) => setExpForm({ ...expForm, also_create_payable: e.target.checked })} />
                {t.serviceOrders.alsoCreatePayable}
              </label>
              <div className="flex gap-2">
                <Button size="sm" onClick={handleAddExpense} disabled={addExpense.isPending}>{t.common.save}</Button>
                <Button size="sm" variant="outline" onClick={() => setShowExpForm(false)}>{t.common.cancel}</Button>
              </div>
            </div>
          )}
          {(!soExpenses || soExpenses.length === 0) ? (
            <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noExpensesYet}</p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b bg-muted/50">
                  <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.common.date}</th>
                  <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.products.category}</th>
                  <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.common.description}</th>
                  <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.serviceOrders.paidBy}</th>
                  <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                  <th className="px-4 py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {soExpenses.map((exp: any) => (
                  <tr key={exp.id} className="border-b last:border-0">
                    <td className="px-4 py-3 text-muted-foreground">{formatDate(exp.expense_date)}</td>
                    <td className="px-4 py-3"><StatusBadge className="bg-secondary text-secondary-foreground">{exp.category}</StatusBadge></td>
                    <td className="px-4 py-3 font-medium">{exp.description}</td>
                    <td className="px-4 py-3">
                      {exp.paid_by === 'technician' ? (
                        <span className="text-warning">{exp.app_users?.full_name || t.serviceOrders.paidByTechnician}
                          {!exp.reimbursed && <StatusBadge className="bg-warning/15 text-warning ml-1">{t.serviceOrders.pendingReimbursement}</StatusBadge>}
                          {exp.reimbursed && <StatusBadge className="bg-success/15 text-success ml-1">{t.serviceOrders.reimbursed}</StatusBadge>}
                        </span>
                      ) : t.serviceOrders.paidByCompany}
                    </td>
                    <td className="px-4 py-3 text-right font-semibold">{formatCurrency(Number(exp.amount))}</td>
                    <td className="px-4 py-3">
                      <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                        onClick={() => removeExpense.mutate({ id: exp.id, service_order_id: orderId! })}>
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}

      {/* G - Time Entries (edit only) — internal control */}
      {!isNew && (
        <section className="rounded-xl border bg-card shadow-sm overflow-hidden">
          <div className="p-5 border-b flex items-center justify-between">
            <div>
              <h2 className="font-semibold text-sm">{t.services.timeSection}</h2>
              <p className="text-xs text-muted-foreground mt-0.5">{t.services.timeNote}</p>
            </div>
            <Button variant="outline" size="sm" className="gap-1" onClick={() => setShowTimeForm(!showTimeForm)}>
              <Plus className="h-3 w-3" /> {t.serviceOrders.addTimeEntry}
            </Button>
          </div>
          {showTimeForm && (
            <div className="p-4 border-b bg-muted/30 space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <Label>{t.serviceOrders.technicians}</Label>
                  <Select value={timeForm.technician_user_id}
                    onValueChange={(v) => setTimeForm({ ...timeForm, technician_user_id: v })}>
                    <SelectTrigger><SelectValue placeholder="Selecionar técnico" /></SelectTrigger>
                    <SelectContent>
                      {appUsers?.map((u) => (
                        <SelectItem key={u.id} value={u.id}>{u.full_name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>{t.serviceOrders.scheduledStart}</Label>
                  <Input type="datetime-local" value={timeForm.started_at}
                    onChange={(e) => setTimeForm({ ...timeForm, started_at: e.target.value })} />
                </div>
                <div>
                  <Label>{t.serviceOrders.scheduledEnd}</Label>
                  <Input type="datetime-local" value={timeForm.ended_at}
                    onChange={(e) => setTimeForm({ ...timeForm, ended_at: e.target.value })} />
                </div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <Label>Duração (min)</Label>
                  <Input type="number" value={timeForm.duration_minutes}
                    onChange={(e) => setTimeForm({ ...timeForm, duration_minutes: parseInt(e.target.value) || 0 })} />
                </div>
                <div className="flex items-end gap-2">
                  <label className="flex items-center gap-1.5 text-sm">
                    <Switch checked={timeForm.billable}
                      onCheckedChange={(v) => setTimeForm({ ...timeForm, billable: v })} />
                    {t.serviceOrders.billable}
                  </label>
                </div>
                <div>
                  <Label>{t.common.notes}</Label>
                  <Input value={timeForm.notes}
                    onChange={(e) => setTimeForm({ ...timeForm, notes: e.target.value })} />
                </div>
              </div>
              <div className="flex gap-2">
                <Button size="sm" onClick={handleAddTime} disabled={addTime.isPending}>{t.common.save}</Button>
                <Button size="sm" variant="outline" onClick={() => setShowTimeForm(false)}>{t.common.cancel}</Button>
              </div>
            </div>
          )}
          {(!timeEntries || timeEntries.length === 0) ? (
            <p className="text-sm text-muted-foreground p-5">{t.serviceOrders.noTimeEntries}</p>
          ) : (
            <div className="divide-y">
              {timeEntries.map((te: any) => (
                <div key={te.id} className="flex items-start justify-between p-4">
                  <div>
                    <p className="text-sm font-medium">{te.app_users?.full_name}</p>
                    {te.notes && <p className="text-xs text-muted-foreground">{te.notes}</p>}
                    <p className="text-xs text-muted-foreground mt-1">
                      {formatDateTime(te.started_at)} → {te.ended_at ? formatDateTime(te.ended_at) : '...'}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="text-right">
                      <p className="text-sm font-semibold">{((te.duration_minutes || 0) / 60).toFixed(1)}h</p>
                      <StatusBadge className={te.billable ? 'bg-success/15 text-success' : 'bg-muted text-muted-foreground'}>
                        {te.billable ? t.serviceOrders.billable : t.serviceOrders.nonBillable}
                      </StatusBadge>
                    </div>
                    <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive"
                      onClick={() => removeTime.mutate({ id: te.id, service_order_id: orderId! })}>
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      {/* H - Financial Summary */}
      <section className="rounded-xl border bg-card p-5 shadow-sm space-y-4">
        <h2 className="font-semibold text-sm">{t.serviceOrders.costBreakdown}</h2>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.labor}</span>
              <span>{formatCurrency(laborCost)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.parts}</span>
              <span>{formatCurrency(partsCost)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.operationalCost}</span>
              <span>{formatCurrency(operationalCost)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">{t.serviceOrders.travel}</span>
              <span>{formatCurrency(form.travel_cost_total)}</span>
            </div>
            <div className="flex justify-between text-sm items-center">
              <span className="text-muted-foreground">{t.serviceOrders.subcontract}</span>
              <Input type="number" className="w-28 h-7 text-right text-sm" value={form.subcontract_cost_total}
                onChange={(e) => set('subcontract_cost_total', parseFloat(e.target.value) || 0)} />
            </div>
            <div className="flex justify-between text-sm items-center">
              <span className="text-muted-foreground">{t.serviceOrders.discount}</span>
              <Input type="number" className="w-28 h-7 text-right text-sm" value={form.discount_amount}
                onChange={(e) => set('discount_amount', parseFloat(e.target.value) || 0)} disabled={isLocked} />
            </div>
            <div className="flex justify-between text-sm items-center">
              <span className="text-muted-foreground">{t.serviceOrders.tax}</span>
              <Input type="number" className="w-28 h-7 text-right text-sm" value={form.tax_amount}
                onChange={(e) => set('tax_amount', parseFloat(e.target.value) || 0)} disabled={isLocked} />
            </div>

            {/* Commission */}
            <div className="space-y-2 pt-2 border-t border-dashed">
              <div className="flex justify-between text-sm items-center">
                <span className="text-muted-foreground">{(t.serviceOrders as any).commissionedPerson || 'Comissionado'}</span>
                <Select
                  value={form.commissioned_user_id || 'none'}
                  onValueChange={(v) => {
                    const user = commissionableUsers?.find(u => u.id === v);
                    setForm(f => ({
                      ...f,
                      commissioned_user_id: v === 'none' ? '' : v,
                      commissioned_person: user?.full_name || '',
                    }));
                  }}
                  disabled={isLocked}
                >
                  <SelectTrigger className="w-52 h-7 text-sm">
                    <SelectValue placeholder="Selecionar" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">—</SelectItem>
                    {(commissionableUsers || []).map(u => (
                      <SelectItem key={u.id} value={u.id}>
                        {u.full_name} ({USER_ROLES.find(r => r.value === u.role)?.label || u.role})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex justify-between text-sm items-center">
                <span className="text-muted-foreground">{(t.serviceOrders as any).commissionAmount || 'Comissão'} (%)</span>
                <div className="flex items-center gap-2">
                  <Input type="number" step="0.01" className="w-20 h-7 text-right text-sm" value={form.commission_rate}
                    onChange={(e) => {
                      const rate = parseFloat(e.target.value) || 0;
                      const amount = Math.round(grandTotal * rate / 100 * 100) / 100;
                      setForm(f => ({ ...f, commission_rate: rate, commission_amount: amount }));
                    }}
                    disabled={isLocked} />
                  {(form.commission_rate || 0) > 0 && (
                    <span className="text-xs text-muted-foreground whitespace-nowrap">
                      = {formatCurrency(grandTotal * (form.commission_rate || 0) / 100)}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Payment conditions */}
            <div className="space-y-2 pt-2 border-t border-dashed">
              <div className="flex items-center justify-between">
                <Label className="text-sm">Condições de Pagamento</Label>
                <span className="text-xs text-muted-foreground">(aparece no PDF)</span>
              </div>
              <div className="flex gap-2 items-center">
                <Select
                  key={presetKey}
                  onValueChange={(v) => {
                    set('payment_conditions', v);
                    setPresetKey((k) => k + 1);
                  }}
                  disabled={isLocked}
                >
                  <SelectTrigger className="w-44 h-8 text-sm">
                    <SelectValue placeholder="Pré-definidas..." />
                  </SelectTrigger>
                  <SelectContent>
                    {(paymentPresets || []).map((p: any) => (
                      <SelectItem key={p.id} value={p.label}>
                        {p.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Input
                  value={form.payment_conditions || ''}
                  onChange={(e) => set('payment_conditions', e.target.value)}
                  placeholder="Ou descreva livremente..."
                  disabled={isLocked}
                  className="flex-1 h-8 text-sm"
                />
              </div>
            </div>

            <div className="flex justify-between pt-3 border-t-2">
              <span className="font-bold text-lg">{t.serviceOrders.grandTotal}</span>
              <span className="font-bold text-lg text-accent">{formatCurrency(grandTotal)}</span>
            </div>
            {(form.commission_amount || 0) > 0 && (
              <>
                <div className="flex justify-between text-sm text-muted-foreground">
                  <span>{(t.serviceOrders as any).commissionAmount || 'Comissão'} ({form.commission_rate}%)</span>
                  <span>− {formatCurrency(form.commission_amount || 0)}</span>
                </div>
                <div className="flex justify-between text-sm font-medium">
                  <span>{(t.serviceOrders as any).netTotal || 'Total líquido'}</span>
                  <span>{formatCurrency(grandTotal - (form.commission_amount || 0))}</span>
                </div>
              </>
            )}
          </div>

          {/* Payment info */}
          <div className="space-y-3">
            <div className="rounded-lg border p-3 bg-muted/30">
              <div className="flex items-center gap-2 mb-1">
                <Calculator className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm font-medium">{t.serviceOrders.paymentMethodPix}</span>
              </div>
              <p className="text-sm font-semibold">{formatCurrency(grandTotal)}</p>
            </div>
            <div className="rounded-lg border p-3 bg-muted/30 space-y-3">
              <div className="flex items-center gap-2">
                <CreditCard className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm font-medium">{t.serviceOrders.paymentMethodCard}</span>
              </div>
              {/* Installment selector */}
              <div className="flex gap-1.5">
                {[1, 2, 3, 4, 5, 6].map((n) => (
                  <button key={n} type="button"
                    className={`px-3 py-1.5 rounded-md text-xs font-medium border transition-colors ${
                      selectedInstallments === n
                        ? 'bg-primary text-primary-foreground border-primary'
                        : 'bg-background text-foreground border-border hover:bg-muted'
                    }`}
                    onClick={() => setSelectedInstallments(n)}>
                    {n}x
                  </button>
                ))}
              </div>
              <div className="space-y-1 text-sm">
                <div className="flex justify-between">
                  <span className="font-medium">{t.serviceOrders.cardGrossAmount}:</span>
                  <span className="font-bold">{formatCurrency(cardGross)}</span>
                </div>
                {selectedInstallments > 1 && (
                  <div className="flex justify-between text-muted-foreground">
                    <span>{t.serviceOrders.cardInstallmentValue}:</span>
                    <span>{selectedInstallments}x {formatCurrency(installmentValue)}</span>
                  </div>
                )}
                <div className="flex justify-between text-muted-foreground">
                  <span>{t.serviceOrders.cardFeeAmount} ({Number(feePercent).toFixed(2)}%):</span>
                  <span>{formatCurrency(cardFeeAmount)}</span>
                </div>
                <div className="flex justify-between text-success pt-1 border-t">
                  <span className="font-medium">{t.serviceOrders.cardNetAmount}:</span>
                  <span className="font-semibold">{formatCurrency(grandTotal)}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Record History */}
      {!isNew && (
        <section className="rounded-xl border bg-card p-5 shadow-sm">
          <RecordHistory tableName="service_orders" recordId={orderId} />
        </section>
      )}

      {/* PDF Options Dialog */}
      <PDFOptionsDialog
        open={!!pdfDialogType}
        onOpenChange={v => { if (!v) setPdfDialogType(null); }}
        documentType={pdfDialogType || 'quote'}
        onGenerate={(options, validity, dueDate) => {
          if (!pdfData || !pdfDialogType) return;
          generatePDF({ ...pdfData, documentType: pdfDialogType }, { ...options, validity, dueDate });
          setPdfDialogType(null);
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
                  window.open(waUrl, '_blank', 'noopener,noreferrer');
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
    </div>
  );
}
